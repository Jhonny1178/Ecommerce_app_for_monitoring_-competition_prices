from flask import Blueprint, jsonify, session, request
from webapp.database import get_db
from webapp.utils.security import login_required
import requests  # Do wysłania zapytania do Twojego kontenera z rekomendacjami

actions_bp = Blueprint('actions', __name__)


@actions_bp.route("/api/products/<int:product_id>/recommendation", methods=["POST"])
@login_required
def generate_recommendation(product_id):
    """
    Endpoint wywoływany po kliknięciu przycisku "Wygeneruj rekomendację"
    na karcie pojedynczego produktu.
    """
    prefix = session.get('store_prefix', 'default')
    table_products = f"{prefix}_products"

    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # 1. Pobierz dane o Twoim produkcie
        cur.execute(f"SELECT * FROM {table_products} WHERE id = %s", (product_id,))
        product = cur.fetchone()

        if not product:
            return jsonify({"ok": False, "error": "Nie znaleziono produktu"}), 404

        # 2. Pobierz dane o konkurencji (korzystając z tabeli mapowań)
        table_mappings = f"{prefix}_product_mappings"
        competitor_table = f"{prefix}_competitors"

        cur.execute(f"""
            SELECT c.* FROM {table_mappings} m
            JOIN {competitor_table} c ON m.competitor_id = c.id
            WHERE m.our_product_id = %s AND m.competitor_table = %s
        """, (product_id, competitor_table))

        competitors = cur.fetchall()
        cur.close()
        conn.close()

        # 3. Zbuduj payload do Twojego kontenera z modelem LLM
        # Dostosuj ten słownik do tego, czego oczekuje Twój moduł rekomendacji
        payload = {
            "our_product": dict(product),
            "competitors": [dict(c) for c in competitors],
            "rules": {
                "min_margin_pct": 10,  # Przykładowe twarde reguły - możesz je pobrać z bazy
                "max_price_drop": 50
            }
        }

        # 4. Wyślij zapytanie do serwisu rekomendacji (w Dockerze)
        # UWAGA: 'recommendation_service' to nazwa kontenera w docker-compose, port to np. 8000
        LLM_SERVICE_URL = "http://recommendation_service:8000/generate"

        response = requests.post(LLM_SERVICE_URL, json=payload, timeout=10)

        if response.status_code == 200:
            recommendation_data = response.json()

            # Opcjonalnie: Zapisz wygenerowaną rekomendację do bazy danych,
            # aby użytkownik miał do niej dostęp w przyszłości (historia rekomendacji)

            return jsonify({
                "ok": True,
                "recommendation": recommendation_data.get("suggested_price"),
                "reasoning": recommendation_data.get("llm_reasoning")
            })
        else:
            return jsonify({"ok": False, "error": f"Błąd silnika AI: {response.text}"}), 502

    except requests.exceptions.RequestException as e:
        return jsonify({"ok": False, "error": f"Brak komunikacji z modułem rekomendacji: {str(e)}"}), 503
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
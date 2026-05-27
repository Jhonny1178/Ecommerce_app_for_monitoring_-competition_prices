# webapp/routes/products.py
from flask import Blueprint, jsonify, session, request
import psycopg2
import psycopg2.extras
import requests
import math
# ZMIENIONO: Teraz pobieramy funkcje z utils
from utils import get_db, login_required

products_bp = Blueprint('products', __name__)


@products_bp.route("/api/products")
@login_required
def api_products():
    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak sesji sklepu"}), 401

    # 1. Pobieranie parametrów z zapytania frontendu (z wartościami domyślnymi)
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    sort_by = request.args.get('sort', 'id')
    order = request.args.get('order', 'asc').upper()

    # 2. Zabezpieczenie (Biała lista) - pozwala sortować tylko po dozwolonych kolumnach
    allowed_sort_columns = ['id', 'sku', 'name', 'price_normal', 'competitors_count']
    if sort_by not in allowed_sort_columns:
        sort_by = 'id'
    if order not in ['ASC', 'DESC']:
        order = 'ASC'

    # Obliczanie przesunięcia dla bazy danych (OFFSET)
    offset = (page - 1) * per_page

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # 3. Zliczanie CAŁKOWITEJ liczby produktów (tylko tych z konkurencją) dla frontendu
        count_query = f"""
            SELECT COUNT(DISTINCT p.id) as total
            FROM {prefix}_products p
            INNER JOIN {prefix}_product_mappings m ON p.id = m.our_product_id
        """
        cursor.execute(count_query)
        total_items = cursor.fetchone()['total']

        # 4. Właściwe zapytanie z sortowaniem, stronicowaniem i zliczaniem konkurencji
        query = f"""
            SELECT 
                p.id, 
                p.sku, 
                p.name, 
                p.price_normal, 
                p.category,
                COUNT(m.id) as competitors_count
            FROM {prefix}_products p
            INNER JOIN {prefix}_product_mappings m ON p.id = m.our_product_id
            GROUP BY p.id
            ORDER BY {sort_by} {order}
            LIMIT %s OFFSET %s
        """
        cursor.execute(query, (per_page, offset))
        products = cursor.fetchall()

        # 5. Zwracamy piękny obiekt JSON dla Dashboardu
        return jsonify({
            "ok": True,
            "data": products,
            "pagination": {
                "total_items": total_items,
                "current_page": page,
                "per_page": per_page,
                "total_pages": math.ceil(total_items / per_page) if total_items > 0 else 1
            }
        })

    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    finally:
        if 'conn' in locals():
            cursor.close()
            conn.close()
from flask import Blueprint, jsonify, session, request
import psycopg2
import psycopg2.extras
import math

# Pobieranie funkcji z utils
from utils import get_db, login_required

products_bp = Blueprint('products', __name__)


@products_bp.route("/api/products")
@login_required
def api_products():
    # Dynamiczne pobieranie prefiksu z sesji zalogowanego użytkownika
    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak zdefiniowanego sklepu w sesji użytkownika"}), 401

    # Pobieranie parametrów z zapytania frontendu (z wartościami domyślnymi)
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    sort_by = request.args.get('sort', 'id')
    order = request.args.get('order', 'asc').upper()

    # Zabezpieczenie (Biała lista) - pozwala sortować tylko po dozwolonych kolumnach
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

        # Zliczanie CAŁKOWITEJ liczby produktów (tylko tych z konkurencją) dla frontendu
        count_query = f"""
            SELECT COUNT(DISTINCT p.id) as total
            FROM {prefix}_products p
            INNER JOIN {prefix}_product_mappings m ON p.id = m.our_product_id
        """
        cursor.execute(count_query)
        total_items = cursor.fetchone()['total']

        # Właściwe zapytanie z sortowaniem, stronicowaniem i detalami
        query = f"""
            SELECT 
                p.id, 
                p.sku, 
                p.name, 
                p.price_normal, 
                p.price_special,
                p.category,
                p.store,
                p.availability,
                COUNT(m.id) as competitors_count
            FROM {prefix}_products p
            INNER JOIN {prefix}_product_mappings m ON p.id = m.our_product_id
            GROUP BY p.id
            ORDER BY {sort_by} {order}
            LIMIT %s OFFSET %s
        """
        cursor.execute(query, (per_page, offset))
        products = cursor.fetchall()

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


@products_bp.route("/api/stats")
@login_required
def api_stats():
    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak zdefiniowanego sklepu w sesji"}), 401

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Główne KPI
        cursor.execute(f"""
            SELECT COUNT(*) as total, 
                   AVG(price_normal) as avg_price_normal, 
                   AVG(price_special) as avg_price_special, 
                   COUNT(DISTINCT category) as total_categories, 
                   COUNT(DISTINCT store) as total_stores, 
                   COUNT(DISTINCT manufacturer) as total_manufacturers 
            FROM {prefix}_products
        """)
        summary = cursor.fetchone()

        # Dane do wykresów
        cursor.execute(
            f"SELECT category, COUNT(*) as count, AVG(price_normal) as avg_price FROM {prefix}_products GROUP BY category")
        by_category = cursor.fetchall()

        cursor.execute(f"SELECT store, COUNT(*) as count FROM {prefix}_products GROUP BY store")
        by_store = cursor.fetchall()

        cursor.execute(f"SELECT availability, COUNT(*) as count FROM {prefix}_products GROUP BY availability")
        by_availability = cursor.fetchall()

        return jsonify({
            "ok": True,
            "summary": summary,
            "by_category": by_category,
            "by_store": by_store,
            "by_availability": by_availability
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    finally:
        if 'conn' in locals():
            cursor.close()
            conn.close()


@products_bp.route("/api/categories")
@login_required
def api_categories():
    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak zdefiniowanego sklepu w sesji"}), 401

    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute(f"SELECT DISTINCT category FROM {prefix}_products WHERE category IS NOT NULL")
        return jsonify({"ok": True, "data": [r[0] for r in cursor.fetchall()]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    finally:
        if 'conn' in locals(): cursor.close(); conn.close()


@products_bp.route("/api/stores")
@login_required
def api_stores():
    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak zdefiniowanego sklepu w sesji"}), 401

    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute(f"SELECT DISTINCT store FROM {prefix}_products WHERE store IS NOT NULL")
        return jsonify({"ok": True, "data": [r[0] for r in cursor.fetchall()]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    finally:
        if 'conn' in locals(): cursor.close(); conn.close()
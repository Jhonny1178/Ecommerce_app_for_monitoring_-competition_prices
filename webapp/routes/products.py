from flask import Blueprint, jsonify, session, request
import psycopg2
import psycopg2.extras
import math


from utils import get_db, login_required

products_bp = Blueprint('products', __name__)


@products_bp.route("/api/products")
@login_required
def api_products():

    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak zdefiniowanego sklepu w sesji użytkownika"}), 401


    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    sort_by = request.args.get('sort', 'id')
    order = request.args.get('order', 'asc').upper()

    search_query = request.args.get('search', '').strip()


    allowed_sort_columns = ['id', 'sku', 'name', 'price_normal', 'competitors_count']
    if sort_by not in allowed_sort_columns:
        sort_by = 'id'
    if order not in ['ASC', 'DESC']:
        order = 'ASC'


    offset = (page - 1) * per_page

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


        where_clause = ""
        params = []
        
        if search_query:
            where_clause = "WHERE name ILIKE %s OR sku ILIKE %s"
            params.extend([f"%{search_query}%", f"%{search_query}%"])


        count_query = f"""
            SELECT COUNT(id) as total
            FROM {prefix}_competitors
            {where_clause}
        """
        cursor.execute(count_query, params)
        total_items = cursor.fetchone()['total']


        query = f"""
            SELECT 
                id, 
                sku, 
                name, 
                price_normal, 
                price_special,
                category,
                store,
                availability,
                image,
                0 as competitors_count
            FROM {prefix}_competitors
            {where_clause}
            ORDER BY {sort_by} {order}
            LIMIT %s OFFSET %s
        """
        params.extend([per_page, offset])
        cursor.execute(query, params)
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


@products_bp.route("/api/products/<int:product_id>")
@login_required
def api_product_detail(product_id):
    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak zdefiniowanego sklepu w sesji użytkownika"}), 401

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        query = f"""
            SELECT 
                id, sku, name, size, color, manufacturer, category,
                price_normal, price_special, store, availability, url, image, description
            FROM {prefix}_competitors
            WHERE id = %s
        """
        cursor.execute(query, (product_id,))
        product = cursor.fetchone()

        if not product:
            return jsonify({"ok": False, "error": "Produkt nie został znaleziony"}), 404


        competitors = []

        return jsonify({
            "ok": True,
            "data": product,
            "competitors": competitors
        })

    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    finally:
        if 'conn' in locals():
            cursor.close()
            conn.close()

@products_bp.route("/api/products/<int:product_id>/recommend", methods=["POST"])
@login_required
def api_product_recommend(product_id):
    # Mock AI recommendation for now
    import random
    suggested = round(random.uniform(50.0, 300.0), 2)
    return jsonify({
        "ok": True,
        "recommendation": suggested,
        "reason": "Sztuczna Inteligencja przeanalizowała historię cen konkurencji i uznała, że jest to optymalna kwota maksymalizująca zysk."
    })

@products_bp.route("/api/stats")
@login_required
def api_stats():
    prefix = session.get("store_prefix")
    if not prefix:
        return jsonify({"ok": False, "error": "Brak zdefiniowanego sklepu w sesji"}), 401

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


        cursor.execute(f"""
            SELECT COUNT(*) as total, 
                   AVG(price_normal) as avg_price_normal, 
                   AVG(price_special) as avg_price_special, 
                   COUNT(DISTINCT category) as total_categories, 
                   COUNT(DISTINCT store) as total_stores, 
                   COUNT(DISTINCT manufacturer) as total_manufacturers 
            FROM {prefix}_competitors
        """)
        summary = cursor.fetchone()


        cursor.execute(
            f"SELECT category, COUNT(*) as count, AVG(price_normal) as avg_price FROM {prefix}_competitors GROUP BY category")
        by_category = cursor.fetchall()

        cursor.execute(f"SELECT store, COUNT(*) as count FROM {prefix}_competitors GROUP BY store")
        by_store = cursor.fetchall()

        cursor.execute(f"SELECT availability, COUNT(*) as count FROM {prefix}_competitors GROUP BY availability")
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
        cursor.execute(f"SELECT DISTINCT category FROM {prefix}_competitors WHERE category IS NOT NULL")
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
        cursor.execute(f"SELECT DISTINCT store FROM {prefix}_competitors WHERE store IS NOT NULL")
        return jsonify({"ok": True, "data": [r[0] for r in cursor.fetchall()]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    finally:
        if 'conn' in locals(): cursor.close(); conn.close()
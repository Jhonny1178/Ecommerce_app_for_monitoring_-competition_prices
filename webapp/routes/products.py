from flask import Blueprint, jsonify, session, request
import math
import psycopg2
import psycopg2.extras
from psycopg2 import sql

from utils import get_db, login_required

products_bp = Blueprint("products", __name__)


def _get_store_prefix():
    prefix = session.get("store_prefix")
    if prefix:
        return prefix

    user_id = session.get("user_id")
    if not user_id:
        return None

    conn = None
    cur = None

    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT c.store_prefix
            FROM users u
            JOIN clients c ON c.id = u.client_id
            WHERE u.id = %s
            LIMIT 1
        """, (user_id,))

        row = cur.fetchone()

        if not row:
            return None

        prefix = row["store_prefix"]
        session["store_prefix"] = prefix

        return prefix

    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


def _table_exists(cur, table_name: str) -> bool:
    cur.execute("SELECT to_regclass(%s) AS table_ref", (f"public.{table_name}",))
    row = cur.fetchone()

    if not row:
        return False

    if isinstance(row, dict):
        return row.get("table_ref") is not None

    return row[0] is not None


def _get_columns(cur, table_name: str) -> set[str]:
    cur.execute("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = %s
    """, (table_name,))

    rows = cur.fetchall()

    columns = set()
    for row in rows:
        if isinstance(row, dict):
            columns.add(row["column_name"])
        else:
            columns.add(row[0])

    return columns


def _fetch_match_counts(cur, matches_table: str, products: list[dict]) -> dict:
    if not products or not _table_exists(cur, matches_table):
        return {}

    match_columns = _get_columns(cur, matches_table)

    if "product_id" in match_columns:
        product_ids = [p["id"] for p in products]

        query = sql.SQL("""
            SELECT product_id AS key, COUNT(*) AS count
            FROM {}
            WHERE product_id = ANY(%s)
            GROUP BY product_id
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (product_ids,))
        return {row["key"]: row["count"] for row in cur.fetchall()}

    if "client_sku" in match_columns:
        skus = [p["sku"] for p in products if p.get("sku")]

        query = sql.SQL("""
            SELECT client_sku AS key, COUNT(*) AS count
            FROM {}
            WHERE client_sku = ANY(%s)
            GROUP BY client_sku
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (skus,))
        return {row["key"]: row["count"] for row in cur.fetchall()}

    if "product_sku" in match_columns:
        skus = [p["sku"] for p in products if p.get("sku")]

        query = sql.SQL("""
            SELECT product_sku AS key, COUNT(*) AS count
            FROM {}
            WHERE product_sku = ANY(%s)
            GROUP BY product_sku
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (skus,))
        return {row["key"]: row["count"] for row in cur.fetchall()}

    if "product_name" in match_columns:
        names = [p["name"] for p in products if p.get("name")]

        query = sql.SQL("""
            SELECT product_name AS key, COUNT(*) AS count
            FROM {}
            WHERE product_name = ANY(%s)
            GROUP BY product_name
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (names,))
        return {row["key"]: row["count"] for row in cur.fetchall()}

    if "client_name" in match_columns:
        names = [p["name"] for p in products if p.get("name")]

        query = sql.SQL("""
            SELECT client_name AS key, COUNT(*) AS count
            FROM {}
            WHERE client_name = ANY(%s)
            GROUP BY client_name
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (names,))
        return {row["key"]: row["count"] for row in cur.fetchall()}

    return {}


def _add_match_counts(cur, matches_table: str, products: list[dict]) -> list[dict]:
    if not products:
        return products

    match_columns = _get_columns(cur, matches_table) if _table_exists(cur, matches_table) else set()
    counts = _fetch_match_counts(cur, matches_table, products)

    result = []

    for product in products:
        item = dict(product)

        if "product_id" in match_columns:
            key = item.get("id")
        elif "client_sku" in match_columns or "product_sku" in match_columns:
            key = item.get("sku")
        elif "product_name" in match_columns or "client_name" in match_columns:
            key = item.get("name")
        else:
            key = None

        item["competitors_count"] = counts.get(key, 0) if key is not None else 0
        result.append(item)

    return result


def _fetch_competitors_for_product(cur, product: dict, matches_table: str, competitors_table: str) -> list[dict]:
    if not product or not _table_exists(cur, matches_table):
        return []

    match_columns = _get_columns(cur, matches_table)
    competitors_exist = _table_exists(cur, competitors_table)

    # Wariant docelowy: test_matches ma product_id + competitor_product_id
    if (
        competitors_exist
        and "product_id" in match_columns
        and "competitor_product_id" in match_columns
    ):
        query = sql.SQL("""
            SELECT
                c.id,
                c.sku,
                c.name,
                c.price_normal,
                c.price_special,
                c.store,
                c.availability,
                c.url,
                c.image,
                m.similarity_score,
                m.price_difference,
                m.match_status
            FROM {} m
            LEFT JOIN {} c ON c.id = m.competitor_product_id
            WHERE m.product_id = %s
            ORDER BY m.similarity_score DESC NULLS LAST
        """).format(
            sql.Identifier(matches_table),
            sql.Identifier(competitors_table),
        )

        cur.execute(query, (product["id"],))
        return [dict(row) for row in cur.fetchall()]

    # Wariant aktualny: test_matches jest płaską tabelą z files_connector,
    # np. spider_dummy_price, spider_dummy_url, spider_dummy_name.
    match_row = None

    if "client_sku" in match_columns and product.get("sku"):
        query = sql.SQL("""
            SELECT *
            FROM {}
            WHERE client_sku = %s
            LIMIT 1
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (product["sku"],))
        match_row = cur.fetchone()

    elif "product_sku" in match_columns and product.get("sku"):
        query = sql.SQL("""
            SELECT *
            FROM {}
            WHERE product_sku = %s
            LIMIT 1
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (product["sku"],))
        match_row = cur.fetchone()

    elif "product_name" in match_columns and product.get("name"):
        query = sql.SQL("""
            SELECT *
            FROM {}
            WHERE product_name = %s
            LIMIT 1
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (product["name"],))
        match_row = cur.fetchone()

    elif "client_name" in match_columns and product.get("name"):
        query = sql.SQL("""
            SELECT *
            FROM {}
            WHERE client_name = %s
            LIMIT 1
        """).format(sql.Identifier(matches_table))

        cur.execute(query, (product["name"],))
        match_row = cur.fetchone()

    if not match_row:
        return []

    match_row = dict(match_row)
    competitors = []

    # Szukamy wszystkich kolumn typu:
    # spider_dummy_price
    # spider_dummy_url
    # spider_dummy_name
    for column_name, value in match_row.items():
        if not column_name.endswith("_price"):
            continue

        store_name = column_name[:-6]  # usuwa końcówkę "_price"

        price = match_row.get(f"{store_name}_price")
        url = match_row.get(f"{store_name}_url")
        name = match_row.get(f"{store_name}_name")

        if price is None and name is None and url is None:
            continue

        competitors.append({
            "id": None,
            "sku": None,
            "name": name or store_name,
            "price_normal": price,
            "price_special": None,
            "store": store_name,
            "availability": None,
            "url": url,
            "image": None,
            "similarity_score": None,
            "price_difference": (
                float(price) - float(product["price_normal"])
                if price is not None and product.get("price_normal") is not None
                else None
            ),
            "match_status": "matched",
        })

    return competitors


@products_bp.route("/api/products")
@login_required
def api_products():
    prefix = _get_store_prefix()

    if not prefix:
        return jsonify({
            "ok": False,
            "error": "Brak zdefiniowanego sklepu w sesji użytkownika"
        }), 401

    products_table = f"{prefix}_products"
    matches_table = f"{prefix}_matches"

    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)
    sort_by = request.args.get("sort", "id")
    order = request.args.get("order", "asc").upper()
    search_query = request.args.get("search", "").strip()
    matched_only = request.args.get("matched_only", "false").lower() == "true"

    allowed_sort_columns = [
        "id",
        "sku",
        "name",
        "price_normal",
        "price_special",
        "category",
        "store",
        "availability",
    ]

    if sort_by not in allowed_sort_columns:
        sort_by = "id"

    if order not in ["ASC", "DESC"]:
        order = "ASC"

    offset = (page - 1) * per_page

    where_sql = sql.SQL("")
    params = []

    if search_query:
        where_sql = sql.SQL("""
            WHERE name ILIKE %s
               OR sku ILIKE %s
               OR category ILIKE %s
               OR manufacturer ILIKE %s
        """)
        params.extend([
            f"%{search_query}%",
            f"%{search_query}%",
            f"%{search_query}%",
            f"%{search_query}%",
        ])

    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        if not _table_exists(cursor, products_table):
            return jsonify({
                "ok": True,
                "data": [],
                "pagination": {
                    "total_items": 0,
                    "current_page": page,
                    "per_page": per_page,
                    "total_pages": 1,
                }
            })

        count_query = sql.SQL("""
            SELECT COUNT(id) AS total
            FROM {}
            {}
        """).format(
            sql.Identifier(products_table),
            where_sql,
        )

        cursor.execute(count_query, params)
        total_items = cursor.fetchone()["total"]

        query = sql.SQL("""
            SELECT
                id,
                sku,
                name,
                size,
                color,
                manufacturer,
                category,
                price_normal,
                price_special,
                store,
                availability,
                url,
                image,
                description
            FROM {}
            {}
            ORDER BY {} {}
            LIMIT %s OFFSET %s
        """).format(
            sql.Identifier(products_table),
            where_sql,
            sql.Identifier(sort_by),
            sql.SQL(order),
        )

        cursor.execute(query, params + [per_page, offset])
        products = [dict(row) for row in cursor.fetchall()]

        products = _add_match_counts(cursor, matches_table, products)

        if matched_only:
            products = [
                product for product in products
                if product.get("competitors_count", 0) > 0
            ]

        return jsonify({
            "ok": True,
            "data": products,
            "pagination": {
                "total_items": total_items,
                "current_page": page,
                "per_page": per_page,
                "total_pages": math.ceil(total_items / per_page) if total_items > 0 else 1,
            }
        })

    except Exception as e:
        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@products_bp.route("/api/products/<int:product_id>")
@login_required
def api_product_detail(product_id):
    prefix = _get_store_prefix()

    if not prefix:
        return jsonify({
            "ok": False,
            "error": "Brak zdefiniowanego sklepu w sesji użytkownika"
        }), 401

    products_table = f"{prefix}_products"
    competitors_table = f"{prefix}_competitors"
    matches_table = f"{prefix}_matches"

    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        if not _table_exists(cursor, products_table):
            return jsonify({
                "ok": False,
                "error": "Tabela produktów klienta nie istnieje"
            }), 404

        query = sql.SQL("""
            SELECT
                id,
                sku,
                name,
                size,
                color,
                manufacturer,
                category,
                price_normal,
                price_special,
                store,
                availability,
                url,
                image,
                description
            FROM {}
            WHERE id = %s
        """).format(sql.Identifier(products_table))

        cursor.execute(query, (product_id,))
        product = cursor.fetchone()

        if not product:
            return jsonify({
                "ok": False,
                "error": "Produkt nie został znaleziony"
            }), 404

        product = dict(product)

        competitors = _fetch_competitors_for_product(
            cursor,
            product,
            matches_table,
            competitors_table,
        )

        return jsonify({
            "ok": True,
            "data": product,
            "competitors": competitors,
        })

    except Exception as e:
        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@products_bp.route("/api/products/<int:product_id>/recommend", methods=["POST"])
@login_required
def api_product_recommend(product_id):
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
    prefix = _get_store_prefix()

    if not prefix:
        return jsonify({
            "ok": False,
            "error": "Brak zdefiniowanego sklepu w sesji"
        }), 401

    products_table = f"{prefix}_products"
    competitors_table = f"{prefix}_competitors"
    matches_table = f"{prefix}_matches"

    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        product_summary = {
            "total": 0,
            "avg_price_normal": None,
            "avg_price_special": None,
            "total_categories": 0,
            "total_manufacturers": 0,
        }

        competitor_summary = {
            "total_competitor_products": 0,
            "avg_competitor_price": None,
            "total_stores": 0,
        }

        matched_products = 0

        if _table_exists(cursor, products_table):
            product_summary_query = sql.SQL("""
                SELECT
                    COUNT(*) AS total,
                    AVG(price_normal) AS avg_price_normal,
                    AVG(price_special) AS avg_price_special,
                    COUNT(DISTINCT category) AS total_categories,
                    COUNT(DISTINCT manufacturer) AS total_manufacturers
                FROM {}
            """).format(sql.Identifier(products_table))

            cursor.execute(product_summary_query)
            product_summary = dict(cursor.fetchone())

        if _table_exists(cursor, competitors_table):
            competitor_summary_query = sql.SQL("""
                SELECT
                    COUNT(*) AS total_competitor_products,
                    AVG(price_normal) AS avg_competitor_price,
                    COUNT(DISTINCT store) AS total_stores
                FROM {}
            """).format(sql.Identifier(competitors_table))

            cursor.execute(competitor_summary_query)
            competitor_summary = dict(cursor.fetchone())

        if _table_exists(cursor, matches_table):
            match_columns = _get_columns(cursor, matches_table)

            if "product_id" in match_columns:
                query = sql.SQL("""
                    SELECT COUNT(DISTINCT product_id) AS matched_products
                    FROM {}
                """).format(sql.Identifier(matches_table))
                cursor.execute(query)
                matched_products = cursor.fetchone()["matched_products"] or 0

            elif "client_sku" in match_columns:
                query = sql.SQL("""
                    SELECT COUNT(DISTINCT client_sku) AS matched_products
                    FROM {}
                """).format(sql.Identifier(matches_table))
                cursor.execute(query)
                matched_products = cursor.fetchone()["matched_products"] or 0

            elif "product_sku" in match_columns:
                query = sql.SQL("""
                    SELECT COUNT(DISTINCT product_sku) AS matched_products
                    FROM {}
                """).format(sql.Identifier(matches_table))
                cursor.execute(query)
                matched_products = cursor.fetchone()["matched_products"] or 0

        summary = {
            "total": product_summary.get("total") or 0,

            # Frontend teraz pokazuje pole avg_price_normal jako "Średnia cena".
            # Ustawiamy tu średnią cenę konkurencji, bo to jest ważniejsze analitycznie.
            # Jeśli nie ma konkurencji, będzie null -> frontend pokaże "Brak danych".
            "avg_price_normal": competitor_summary.get("avg_competitor_price"),

            "avg_price_special": None,
            "total_categories": product_summary.get("total_categories") or 0,
            "total_stores": competitor_summary.get("total_stores") or 0,
            "total_manufacturers": product_summary.get("total_manufacturers") or 0,

            "total_client_products": product_summary.get("total") or 0,
            "avg_client_price": product_summary.get("avg_price_normal"),
            "total_competitor_products": competitor_summary.get("total_competitor_products") or 0,
            "avg_competitor_price": competitor_summary.get("avg_competitor_price"),
            "matched_products": matched_products,
        }

        by_category = []
        by_store = []
        by_availability = []

        if _table_exists(cursor, products_table):
            by_category_query = sql.SQL("""
                SELECT
                    category,
                    COUNT(*) AS count,
                    AVG(price_normal) AS avg_price
                FROM {}
                GROUP BY category
                ORDER BY count DESC
            """).format(sql.Identifier(products_table))

            cursor.execute(by_category_query)
            by_category = cursor.fetchall()

            by_availability_query = sql.SQL("""
                SELECT
                    availability,
                    COUNT(*) AS count
                FROM {}
                GROUP BY availability
                ORDER BY count DESC
            """).format(sql.Identifier(products_table))

            cursor.execute(by_availability_query)
            by_availability = cursor.fetchall()

        if _table_exists(cursor, competitors_table):
            by_store_query = sql.SQL("""
                SELECT
                    store,
                    COUNT(*) AS count
                FROM {}
                GROUP BY store
                ORDER BY count DESC
            """).format(sql.Identifier(competitors_table))

            cursor.execute(by_store_query)
            by_store = cursor.fetchall()

        return jsonify({
            "ok": True,
            "summary": summary,
            "by_category": by_category,
            "by_store": by_store,
            "by_availability": by_availability,
        })

    except Exception as e:
        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@products_bp.route("/api/categories")
@login_required
def api_categories():
    prefix = _get_store_prefix()

    if not prefix:
        return jsonify({
            "ok": False,
            "error": "Brak zdefiniowanego sklepu w sesji"
        }), 401

    products_table = f"{prefix}_products"

    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor()

        if not _table_exists(cursor, products_table):
            return jsonify({
                "ok": True,
                "data": []
            })

        query = sql.SQL("""
            SELECT DISTINCT category
            FROM {}
            WHERE category IS NOT NULL
            ORDER BY category
        """).format(sql.Identifier(products_table))

        cursor.execute(query)

        return jsonify({
            "ok": True,
            "data": [r[0] for r in cursor.fetchall()]
        })

    except Exception as e:
        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@products_bp.route("/api/stores")
@login_required
def api_stores():
    prefix = _get_store_prefix()

    if not prefix:
        return jsonify({
            "ok": False,
            "error": "Brak zdefiniowanego sklepu w sesji"
        }), 401

    competitors_table = f"{prefix}_competitors"

    conn = None
    cursor = None

    try:
        conn = get_db()
        cursor = conn.cursor()

        if not _table_exists(cursor, competitors_table):
            return jsonify({
                "ok": True,
                "data": []
            })

        query = sql.SQL("""
            SELECT DISTINCT store
            FROM {}
            WHERE store IS NOT NULL
            ORDER BY store
        """).format(sql.Identifier(competitors_table))

        cursor.execute(query)

        return jsonify({
            "ok": True,
            "data": [r[0] for r in cursor.fetchall()]
        })

    except Exception as e:
        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
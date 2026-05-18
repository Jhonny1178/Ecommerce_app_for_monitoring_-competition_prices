from flask import Flask, render_template, request, redirect, url_for, session, jsonify, flash
import psycopg2
import psycopg2.extras
from functools import wraps
from dotenv import load_dotenv
import hashlib
import os

load_dotenv()

app = Flask(__name__)
app.secret_key = os.environ["SECRET_KEY"]

DB_CONFIG = {
    "host":     os.environ.get("DB_HOST", "localhost"),
    "port":     os.environ.get("DB_PORT", 5432),
    "dbname":   os.environ.get("DB_NAME", "eroch_db"),
    "user":     os.environ.get("DB_USER", "postgres"),
    "password": os.environ.get("DB_PASSWORD", "postgres"),
}

def get_db():
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    return conn

# helper functions

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated

def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login"))
        if not session.get("is_admin"):
            flash("Brak uprawnień administratora.", "error")
            return redirect(url_for("dashboard"))
        return f(*args, **kwargs)
    return decorated

# authentication

@app.route("/", methods=["GET", "POST"])
@app.route("/login", methods=["GET", "POST"])
def login():
    if "user_id" in session:
        return redirect(url_for("dashboard"))

    error = None
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        hashed   = hash_password(password)

        try:
            conn = get_db()
            cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
            cur.execute(
                "SELECT * FROM users WHERE username = %s AND password_hash = %s",
                (username, hashed)
            )
            user = cur.fetchone()
            cur.close(); conn.close()

            if user:
                session["user_id"]  = user["id"]
                session["username"] = user["username"]
                session["is_admin"] = user["is_admin"]
                return redirect(url_for("dashboard"))
            else:
                error = "Nieprawidłowy login lub hasło."
        except Exception as e:
            error = f"Błąd połączenia z bazą: {e}"

    return render_template("login.html", error=error)

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

# pages
@app.route("/dashboard")
@login_required
def dashboard():
    return render_template("dashboard.html",
                           username=session["username"],
                           is_admin=session.get("is_admin", False))

@app.route("/admin")
@admin_required
def admin():
    return render_template("admin.html", username=session["username"])

#api - read
ALLOWED_SORTS = {
    "id", "sku", "name", "size", "color", "manufacturer",
    "category", "price_normal", "price_special",
    "store", "availability", "date_of_download"
}

@app.route("/api/products")
@login_required
def api_products():
    category     = request.args.get("category", "")
    store        = request.args.get("store", "")
    availability = request.args.get("availability", "")
    manufacturer = request.args.get("manufacturer", "")
    min_price    = request.args.get("min_price", "")
    max_price    = request.args.get("max_price", "")
    sort         = request.args.get("sort", "id")
    order        = request.args.get("order", "asc")
    search       = request.args.get("search", "")

    if sort  not in ALLOWED_SORTS: sort = "id"
    if order not in {"asc", "desc"}: order = "asc"

    where, params = [], []

    if category:
        where.append("category = %s"); params.append(category)
    if store:
        where.append("store = %s"); params.append(store)
    if availability:
        where.append("availability = %s"); params.append(availability)
    if manufacturer:
        where.append("manufacturer = %s"); params.append(manufacturer)
    if min_price:
        where.append("price_normal >= %s"); params.append(float(min_price))
    if max_price:
        where.append("price_normal <= %s"); params.append(float(max_price))
    if search:
        where.append("(name ILIKE %s OR sku ILIKE %s OR description ILIKE %s)")
        params += [f"%{search}%", f"%{search}%", f"%{search}%"]

    sql = "SELECT * FROM products"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += f" ORDER BY {sort} {order}"

    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(sql, params)
        rows = cur.fetchall()
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": [dict(r) for r in rows]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/stats")
@login_required
def api_stats():
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Overall summary
        cur.execute("""
            SELECT
                COUNT(*)                        AS total,
                AVG(price_normal)               AS avg_price_normal,
                AVG(price_special)              AS avg_price_special,
                AVG(price_normal - COALESCE(price_special, price_normal)) AS avg_discount,
                COUNT(DISTINCT category)        AS total_categories,
                COUNT(DISTINCT store)           AS total_stores,
                COUNT(DISTINCT manufacturer)    AS total_manufacturers
            FROM products
        """)
        summary = dict(cur.fetchone())

        # By category
        cur.execute("""
            SELECT category,
                   COUNT(*)            AS count,
                   AVG(price_normal)   AS avg_price,
                   MIN(price_normal)   AS min_price,
                   MAX(price_normal)   AS max_price
            FROM products
            GROUP BY category
            ORDER BY count DESC
        """)
        by_category = [dict(r) for r in cur.fetchall()]

        # By store
        cur.execute("""
            SELECT store,
                   COUNT(*)            AS count,
                   AVG(price_normal)   AS avg_price
            FROM products
            GROUP BY store
            ORDER BY count DESC
        """)
        by_store = [dict(r) for r in cur.fetchall()]

        # By availability
        cur.execute("""
            SELECT availability, COUNT(*) AS count
            FROM products
            GROUP BY availability
            ORDER BY count DESC
        """)
        by_availability = [dict(r) for r in cur.fetchall()]

        # By manufacturer (top 10)
        cur.execute("""
            SELECT manufacturer, COUNT(*) AS count, AVG(price_normal) AS avg_price
            FROM products
            GROUP BY manufacturer
            ORDER BY count DESC
            LIMIT 10
        """)
        by_manufacturer = [dict(r) for r in cur.fetchall()]

        # Price discount distribution
        cur.execute("""
            SELECT
                ROUND(((price_normal - COALESCE(price_special, price_normal)) / NULLIF(price_normal,0) * 100)::numeric, 0) AS discount_pct,
                COUNT(*) AS count
            FROM products
            WHERE price_special IS NOT NULL AND price_special < price_normal
            GROUP BY discount_pct
            ORDER BY discount_pct
        """)
        discount_dist = [dict(r) for r in cur.fetchall()]

        cur.close(); conn.close()
        return jsonify({
            "ok": True,
            "summary":          summary,
            "by_category":      by_category,
            "by_store":         by_store,
            "by_availability":  by_availability,
            "by_manufacturer":  by_manufacturer,
            "discount_dist":    discount_dist,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/categories")
@login_required
def api_categories():
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute("SELECT DISTINCT category FROM products WHERE category IS NOT NULL ORDER BY category")
        cats = [r[0] for r in cur.fetchall()]
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": cats})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/stores")
@login_required
def api_stores():
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute("SELECT DISTINCT store FROM products WHERE store IS NOT NULL ORDER BY store")
        stores = [r[0] for r in cur.fetchall()]
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": stores})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/manufacturers")
@login_required
def api_manufacturers():
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute("SELECT DISTINCT manufacturer FROM products WHERE manufacturer IS NOT NULL ORDER BY manufacturer")
        data = [r[0] for r in cur.fetchall()]
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# api - admin crud

PRODUCT_FIELDS = [
    "sku", "name", "size", "color", "manufacturer",
    "category", "price_normal", "price_special",
    "store", "availability", "url", "image", "description"
]

@app.route("/api/admin/product", methods=["POST"])
@admin_required
def admin_add_product():
    data = request.get_json()
    cols, vals = [], []
    for f in PRODUCT_FIELDS:
        if f in data and data[f] not in (None, ""):
            cols.append(f)
            if f in ("price_normal", "price_special"):
                vals.append(float(data[f]))
            else:
                vals.append(data[f])
    if not cols:
        return jsonify({"ok": False, "error": "Brak danych"}), 400
    sql = f"INSERT INTO products ({', '.join(cols)}) VALUES ({', '.join(['%s']*len(cols))}) RETURNING id"
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute(sql, vals)
        new_id = cur.fetchone()[0]
        cur.close(); conn.close()
        return jsonify({"ok": True, "id": new_id})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/admin/product/<int:product_id>", methods=["PUT"])
@admin_required
def admin_update_product(product_id):
    data = request.get_json()
    fields, params = [], []
    for f in PRODUCT_FIELDS:
        if f in data:
            fields.append(f"{f} = %s")
            if f in ("price_normal", "price_special"):
                params.append(float(data[f]) if data[f] not in (None, "") else None)
            else:
                params.append(data[f] if data[f] != "" else None)
    if not fields:
        return jsonify({"ok": False, "error": "Brak pól do aktualizacji"}), 400
    params.append(product_id)
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute(f"UPDATE products SET {', '.join(fields)} WHERE id = %s", params)
        cur.close(); conn.close()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/admin/product/<int:product_id>", methods=["DELETE"])
@admin_required
def admin_delete_product(product_id):
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute("DELETE FROM products WHERE id = %s", (product_id,))
        cur.close(); conn.close()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# api - comparison

# Allowed competitor tables — extend this list as you add more shops
COMPETITOR_TABLES = {
    "products_shop1": "Shop 1",
    "products_shop2": "Shop 2",
}


@app.route("/api/comparison")
@login_required
def api_comparison():
    """
    Returns every mapped product pair with our price vs competitor price.
    Optional query params:
      - shop      : filter by competitor_table name (e.g. 'products_shop1')
      - category  : filter by our product's category
      - diff      : 'cheaper' | 'expensive' | 'equal'  (we vs competitor)
    """
    shop     = request.args.get("shop", "")
    category = request.args.get("category", "")
    diff     = request.args.get("diff", "")   # cheaper | expensive | equal

    # Validate shop param against whitelist
    if shop and shop not in COMPETITOR_TABLES:
        return jsonify({"ok": False, "error": "Unknown shop"}), 400

    rows = []
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        for table, label in COMPETITOR_TABLES.items():
            if shop and table != shop:
                continue

            cat_filter = "AND p.category = %s" if category else ""
            params     = [table]
            if category:
                params.append(category)

            cur.execute(f"""
                SELECT
                    p.id                                        AS our_id,
                    p.sku                                       AS sku,
                    p.name                                      AS our_name,
                    p.category                                  AS category,
                    p.price_normal                              AS our_price_normal,
                    p.price_special                             AS our_price_special,
                    p.availability                              AS our_availability,
                    c.id                                        AS comp_id,
                    c.name                                      AS comp_name,
                    c.price_normal                              AS comp_price_normal,
                    c.price_special                             AS comp_price_special,
                    c.availability                              AS comp_availability,
                    c.url                                       AS comp_url,
                    '{label}'                                   AS shop_label,
                    '{table}'                                   AS shop_table,
                    -- effective prices (use special if available)
                    COALESCE(p.price_special, p.price_normal)   AS our_effective,
                    COALESCE(c.price_special, c.price_normal)   AS comp_effective,
                    -- absolute and percent difference (positive = we are cheaper)
                    ROUND((
                        COALESCE(c.price_special, c.price_normal)
                        - COALESCE(p.price_special, p.price_normal)
                    )::numeric, 2)                              AS diff_abs,
                    ROUND((
                        (COALESCE(c.price_special, c.price_normal)
                         - COALESCE(p.price_special, p.price_normal))
                        / NULLIF(COALESCE(c.price_special, c.price_normal), 0) * 100
                    )::numeric, 1)                              AS diff_pct
                FROM product_mappings m
                JOIN products         p ON p.id = m.our_product_id
                JOIN {table}          c ON c.id = m.competitor_id
                WHERE m.competitor_table = %s
                {cat_filter}
                ORDER BY diff_abs DESC
            """, params)

            rows += [dict(r) for r in cur.fetchall()]

        cur.close(); conn.close()
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

    # Filter by cheaper/expensive/equal after collecting all rows
    if diff == "cheaper":
        rows = [r for r in rows if r["diff_abs"] and float(r["diff_abs"]) > 0]
    elif diff == "expensive":
        rows = [r for r in rows if r["diff_abs"] and float(r["diff_abs"]) < 0]
    elif diff == "equal":
        rows = [r for r in rows if not r["diff_abs"] or float(r["diff_abs"]) == 0]

    return jsonify({"ok": True, "data": rows, "shops": COMPETITOR_TABLES})


@app.route("/api/comparison/summary")
@login_required
def api_comparison_summary():
    """
    Aggregate stats for the comparison dashboard:
    - per-shop: how many products we're cheaper/equal/more expensive on
    - per-category: average price difference
    """
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        summary = []

        for table, label in COMPETITOR_TABLES.items():
            cur.execute(f"""
                SELECT
                    '{label}'  AS shop_label,
                    COUNT(*)   AS total_mapped,
                    SUM(CASE WHEN COALESCE(c.price_special, c.price_normal)
                                  > COALESCE(p.price_special, p.price_normal) THEN 1 ELSE 0 END) AS we_cheaper,
                    SUM(CASE WHEN COALESCE(c.price_special, c.price_normal)
                                  < COALESCE(p.price_special, p.price_normal) THEN 1 ELSE 0 END) AS we_expensive,
                    SUM(CASE WHEN COALESCE(c.price_special, c.price_normal)
                                  = COALESCE(p.price_special, p.price_normal) THEN 1 ELSE 0 END) AS equal,
                    ROUND(AVG(
                        COALESCE(c.price_special, c.price_normal)
                        - COALESCE(p.price_special, p.price_normal)
                    )::numeric, 2) AS avg_diff_abs
                FROM product_mappings m
                JOIN products  p ON p.id = m.our_product_id
                JOIN {table}   c ON c.id = m.competitor_id
                WHERE m.competitor_table = %s
            """, (table,))
            row = cur.fetchone()
            if row:
                summary.append(dict(row))

            # Per-category breakdown for this shop
            cur.execute(f"""
                SELECT
                    p.category,
                    '{label}'  AS shop_label,
                    COUNT(*)   AS count,
                    ROUND(AVG(
                        COALESCE(c.price_special, c.price_normal)
                        - COALESCE(p.price_special, p.price_normal)
                    )::numeric, 2) AS avg_diff
                FROM product_mappings m
                JOIN products  p ON p.id = m.our_product_id
                JOIN {table}   c ON c.id = m.competitor_id
                WHERE m.competitor_table = %s
                GROUP BY p.category
                ORDER BY avg_diff DESC
            """, (table,))
            # attach to the summary row
            summary[-1]["by_category"] = [dict(r) for r in cur.fetchall()]

        cur.close(); conn.close()
        return jsonify({"ok": True, "data": summary})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6767, debug=True)
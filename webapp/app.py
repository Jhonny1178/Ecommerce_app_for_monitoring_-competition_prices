from flask import Flask, render_template, request, redirect, url_for, session, jsonify, flash
import psycopg2
import psycopg2.extras
from functools import wraps
from dotenv import load_dotenv
import hashlib
import os
import csv
import io
import xml.etree.ElementTree as ET
import re
import unicodedata

load_dotenv()

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "super-tajny-klucz")

DB_CONFIG = {
    "host": os.environ.get("localhost"),
    "port": os.environ.get("APP_DB_PORT", 5434),
    "dbname": os.environ.get("APP_DB_NAME", "ecommerce_data"),
    "user": os.environ.get("APP_DB_USER", "postgres"),
    "password": os.environ.get("APP_DB_PASSWORD", "Ecom1233!"),
}


def get_db():
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    return conn


# -----------------
# POMOCNICZE
# -----------------

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def generate_store_prefix(name: str) -> str:
    """Tworzy bezpieczny prefiks dla tabel (np. 'Mój Sklep!' -> 'moj_sklep')"""
    name = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode('utf-8')
    name = name.lower()
    name = re.sub(r'[^a-z0-9]', '_', name)
    name = re.sub(r'_+', '_', name).strip('_')
    return name


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


# -----------------
# AUTH & REJESTRACJA
# -----------------

@app.route("/", methods=["GET", "POST"])
@app.route("/login", methods=["GET", "POST"])
def login():
    if "user_id" in session:
        return redirect(url_for("dashboard"))

    error = None
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        hashed = hash_password(password)

        try:
            conn = get_db()
            cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

            # FIX: pobieramy store_prefix wprost z kolumny store_prefix (nie slug)
            # COALESCE zabezpiecza na wypadek starych rekordów bez store_prefix
            cur.execute("""
                SELECT u.*, 
                       COALESCE(c.store_prefix, c.slug, 'default') AS store_prefix
                FROM users u
                LEFT JOIN clients c ON u.client_id = c.id
                WHERE u.username = %s AND u.password_hash = %s
            """, (username, hashed))

            user = cur.fetchone()
            cur.close()
            conn.close()

            if user:
                session["user_id"]      = user["id"]
                session["username"]     = user["username"]
                session["is_admin"]     = user.get("is_admin", False)
                session["store_prefix"] = user.get("store_prefix") or "default"
                return redirect(url_for("dashboard"))
            else:
                error = "Nieprawidłowy login lub hasło."
        except Exception as e:
            print(f"LOGIN ERROR: {e}")
            error = f"Błąd połączenia z bazą: {e}"

    return render_template("login.html", error=error)


@app.route("/register", methods=["GET", "POST"])
def register():
    if "user_id" in session:
        return redirect(url_for("dashboard"))

    error = None
    message = None

    if request.method == "POST":
        username   = request.form.get("username", "").strip()
        password   = request.form.get("password", "")
        store_name = request.form.get("store_name", "").strip()

        if not username or not password or not store_name:
            error = "Wypełnij wszystkie pola!"
        else:
            hashed = hash_password(password)
            slug   = generate_store_prefix(store_name)

            conn = None
            try:
                conn = psycopg2.connect(**DB_CONFIG)
                conn.autocommit = False
                cur = conn.cursor()

                # 1. Sprawdź czy user już istnieje
                cur.execute("SELECT id FROM users WHERE username = %s", (username,))
                if cur.fetchone():
                    error = "Użytkownik o takim loginie już istnieje!"
                else:
                    # 2. Sprawdź czy sklep już istnieje
                    cur.execute("SELECT id FROM clients WHERE slug = %s", (slug,))
                    if cur.fetchone():
                        error = "Sklep o takiej nazwie już istnieje!"
                    else:
                        # 3. Dodaj klienta
                        # FIX: dodajemy store_prefix (wymagane NOT NULL) = slug
                        # source_type jest NOT NULL w schemacie więc też podajemy
                        cur.execute("""
                            INSERT INTO clients (name, slug, store_prefix, source_type, field_mapping)
                            VALUES (%s, %s, %s, %s, %s)
                            RETURNING id
                        """, (store_name, slug, slug, 'url', '{}'))
                        client_id = cur.fetchone()[0]

                        # 4. Dodaj użytkownika
                        cur.execute("""
                            INSERT INTO users (username, password_hash, is_admin, client_id)
                            VALUES (%s, %s, %s, %s)
                        """, (username, hashed, False, client_id))

                        # 5. Utwórz tabelę produktów klienta
                        # FIX: pełna lista kolumn zgodna z pipeline (size, color, manufacturer)
                        table_products = f"{slug}_products"
                        cur.execute(f"""
                            CREATE TABLE IF NOT EXISTS {table_products} (
                                id               SERIAL PRIMARY KEY,
                                sku              TEXT NOT NULL,
                                name             TEXT,
                                size             VARCHAR(50),
                                color            VARCHAR(50),
                                manufacturer     VARCHAR(50),
                                price_normal     FLOAT,
                                price_special    FLOAT,
                                url              TEXT,
                                category         VARCHAR(100),
                                store            VARCHAR(50),
                                availability     VARCHAR(50),
                                image            TEXT,
                                description      TEXT,
                                date_of_download TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                UNIQUE (sku, store)
                            );
                        """)

                        # 6. Utwórz tabelę mappingów do konkurencji
                        mappings_table = f"{slug}_product_mappings"
                        cur.execute(f"""
                            CREATE TABLE IF NOT EXISTS {mappings_table} (
                                id               SERIAL PRIMARY KEY,
                                our_product_id   INTEGER REFERENCES {table_products}(id) ON DELETE CASCADE,
                                competitor_table TEXT NOT NULL,
                                competitor_id    INTEGER NOT NULL
                            );
                        """)

                        conn.commit()
                        message = f"Sklep '{store_name}' zarejestrowany! Możesz się teraz zalogować."

                cur.close()
            except Exception as e:
                if conn:
                    conn.rollback()
                print(f"REGISTER ERROR: {e}")
                error = f"Błąd bazy danych: {e}"
            finally:
                if conn:
                    conn.close()

    return render_template("register.html", error=error, message=message)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# -----------------
# FRONTEND PAGES
# -----------------

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


# ==========================================
# API — PRODUKTY, STATYSTYKI, PORÓWNANIA
# ==========================================

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

    if sort not in ALLOWED_SORTS: sort = "id"
    if order not in {"asc", "desc"}: order = "asc"

    where, params = [], []
    if category:     where.append("category = %s");     params.append(category)
    if store:        where.append("store = %s");        params.append(store)
    if availability: where.append("availability = %s"); params.append(availability)
    if manufacturer: where.append("manufacturer = %s"); params.append(manufacturer)
    if min_price:    where.append("price_normal >= %s"); params.append(float(min_price))
    if max_price:    where.append("price_normal <= %s"); params.append(float(max_price))
    if search:
        where.append("(name ILIKE %s OR sku ILIKE %s OR description ILIKE %s)")
        params += [f"%{search}%", f"%{search}%", f"%{search}%"]

    table_products = f"{session.get('store_prefix', 'default')}_products"
    sql = f"SELECT * FROM {table_products}"
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


@app.route("/api/products/<int:product_id>")
@login_required
def api_product_detail(product_id):
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        prefix          = session.get('store_prefix', 'default')
        table_products  = f"{prefix}_products"
        table_mappings  = f"{prefix}_product_mappings"
        competitor_table = f"{prefix}_competitors"
        COMPETITOR_TABLES = {competitor_table: "Rynek (Konkurencja)"}

        cur.execute(f"SELECT * FROM {table_products} WHERE id = %s", (product_id,))
        product = cur.fetchone()
        if not product:
            return jsonify({"ok": False, "error": "Produkt nie istnieje"}), 404
        product = dict(product)

        competitors = []
        for table, label in COMPETITOR_TABLES.items():
            cur.execute(f"""
                SELECT c.*,
                    '{label}' AS shop_label,
                    '{table}' AS shop_table,
                    COALESCE(p.price_special, p.price_normal) AS our_effective,
                    COALESCE(c.price_special, c.price_normal) AS comp_effective,
                    ROUND((COALESCE(c.price_special,c.price_normal)
                           - COALESCE(p.price_special,p.price_normal))::numeric, 2) AS diff_abs,
                    ROUND(((COALESCE(c.price_special,c.price_normal)
                            - COALESCE(p.price_special,p.price_normal))
                           / NULLIF(COALESCE(c.price_special,c.price_normal),0)*100)::numeric, 1) AS diff_pct
                FROM {table_mappings} m
                JOIN {table_products} p ON p.id = m.our_product_id
                JOIN {table}          c ON c.id = m.competitor_id
                WHERE m.our_product_id = %s
                  AND m.competitor_table = %s
            """, (product_id, table))
            competitors += [dict(r) for r in cur.fetchall()]

        cur.close(); conn.close()
        return jsonify({"ok": True, "product": product, "competitors": competitors})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/stats")
@login_required
def api_stats():
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        table_products = f"{session.get('store_prefix', 'default')}_products"

        cur.execute(f"""
            SELECT COUNT(*) AS total,
                   AVG(price_normal) AS avg_price_normal,
                   AVG(price_special) AS avg_price_special,
                   AVG(price_normal - COALESCE(price_special, price_normal)) AS avg_discount,
                   COUNT(DISTINCT category)     AS total_categories,
                   COUNT(DISTINCT store)        AS total_stores,
                   COUNT(DISTINCT manufacturer) AS total_manufacturers
            FROM {table_products}
        """)
        summary = dict(cur.fetchone())

        cur.execute(f"""
            SELECT category, COUNT(*) AS count,
                   AVG(price_normal) AS avg_price,
                   MIN(price_normal) AS min_price,
                   MAX(price_normal) AS max_price
            FROM {table_products}
            GROUP BY category ORDER BY count DESC
        """)
        by_category = [dict(r) for r in cur.fetchall()]

        cur.execute(f"""
            SELECT store, COUNT(*) AS count, AVG(price_normal) AS avg_price
            FROM {table_products} GROUP BY store ORDER BY count DESC
        """)
        by_store = [dict(r) for r in cur.fetchall()]

        cur.execute(f"""
            SELECT availability, COUNT(*) AS count
            FROM {table_products} GROUP BY availability ORDER BY count DESC
        """)
        by_availability = [dict(r) for r in cur.fetchall()]

        cur.execute(f"""
            SELECT manufacturer, COUNT(*) AS count, AVG(price_normal) AS avg_price
            FROM {table_products} GROUP BY manufacturer ORDER BY count DESC LIMIT 10
        """)
        by_manufacturer = [dict(r) for r in cur.fetchall()]

        cur.execute(f"""
            SELECT ROUND(((price_normal - COALESCE(price_special, price_normal))
                          / NULLIF(price_normal,0)*100)::numeric, 0) AS discount_pct,
                   COUNT(*) AS count
            FROM {table_products}
            WHERE price_special IS NOT NULL AND price_special < price_normal
            GROUP BY discount_pct ORDER BY discount_pct
        """)
        discount_dist = [dict(r) for r in cur.fetchall()]

        cur.close(); conn.close()
        return jsonify({
            "ok": True,
            "summary": summary,
            "by_category": by_category,
            "by_store": by_store,
            "by_availability": by_availability,
            "by_manufacturer": by_manufacturer,
            "discount_dist": discount_dist
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/categories")
@login_required
def api_categories():
    try:
        conn = get_db(); cur = conn.cursor()
        table_products = f"{session.get('store_prefix', 'default')}_products"
        cur.execute(f"SELECT DISTINCT category FROM {table_products} WHERE category IS NOT NULL ORDER BY category")
        cats = [r[0] for r in cur.fetchall()]
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": cats})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/stores")
@login_required
def api_stores():
    try:
        conn = get_db(); cur = conn.cursor()
        table_products = f"{session.get('store_prefix', 'default')}_products"
        cur.execute(f"SELECT DISTINCT store FROM {table_products} WHERE store IS NOT NULL ORDER BY store")
        data = [r[0] for r in cur.fetchall()]
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/manufacturers")
@login_required
def api_manufacturers():
    try:
        conn = get_db(); cur = conn.cursor()
        table_products = f"{session.get('store_prefix', 'default')}_products"
        cur.execute(f"SELECT DISTINCT manufacturer FROM {table_products} WHERE manufacturer IS NOT NULL ORDER BY manufacturer")
        data = [r[0] for r in cur.fetchall()]
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/comparison")
@login_required
def api_comparison():
    shop     = request.args.get("shop", "")
    category = request.args.get("category", "")
    diff     = request.args.get("diff", "")

    prefix = session.get('store_prefix', 'default')
    competitor_table  = f"{prefix}_competitors"
    COMPETITOR_TABLES = {competitor_table: "Rynek (Konkurencja)"}

    if shop and shop not in COMPETITOR_TABLES:
        return jsonify({"ok": False, "error": "Unknown shop"}), 400

    rows = []
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        table_products = f"{prefix}_products"
        table_mappings = f"{prefix}_product_mappings"

        for table, label in COMPETITOR_TABLES.items():
            if shop and table != shop:
                continue
            cat_filter = "AND p.category = %s" if category else ""
            params = [table]
            if category:
                params.append(category)
            cur.execute(f"""
                SELECT p.id AS our_id, p.sku, p.name AS our_name, p.category,
                       p.price_normal AS our_price_normal, p.price_special AS our_price_special,
                       p.availability AS our_availability,
                       c.id AS comp_id, c.name AS comp_name,
                       c.price_normal AS comp_price_normal, c.price_special AS comp_price_special,
                       c.availability AS comp_availability, c.url AS comp_url,
                       '{label}' AS shop_label, '{table}' AS shop_table,
                       COALESCE(p.price_special, p.price_normal) AS our_effective,
                       COALESCE(c.price_special, c.price_normal) AS comp_effective,
                       ROUND((COALESCE(c.price_special,c.price_normal)
                              - COALESCE(p.price_special,p.price_normal))::numeric, 2) AS diff_abs,
                       ROUND(((COALESCE(c.price_special,c.price_normal)
                               - COALESCE(p.price_special,p.price_normal))
                              / NULLIF(COALESCE(c.price_special,c.price_normal),0)*100)::numeric, 1) AS diff_pct
                FROM {table_mappings} m
                JOIN {table_products} p ON p.id = m.our_product_id
                JOIN {table}          c ON c.id = m.competitor_id
                WHERE m.competitor_table = %s {cat_filter}
                ORDER BY diff_abs DESC
            """, params)
            rows += [dict(r) for r in cur.fetchall()]
        cur.close(); conn.close()
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

    if diff == "cheaper":
        rows = [r for r in rows if r["diff_abs"] and float(r["diff_abs"]) > 0]
    elif diff == "expensive":
        rows = [r for r in rows if r["diff_abs"] and float(r["diff_abs"]) < 0]
    elif diff == "equal":
        rows = [r for r in rows if not r["diff_abs"] or float(r["diff_abs"]) == 0]

    return jsonify({"ok": True, "data": rows, "shops": COMPETITOR_TABLES})


@app.route("/api/report")
@login_required
def api_report():
    """
    Zwraca raport wygenerowany przez pipeline dla zalogowanego klienta.
    Tabela raportu to: {store_prefix}_report
    Widoczna TYLKO dla właściciela (izolacja przez store_prefix z sesji).
    """
    prefix     = session.get("store_prefix", "default")
    table_name = f"{prefix}_report"

    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Sprawdź czy tabela raportu już istnieje (pipeline mógł jeszcze nie skończyć)
        cur.execute("""
            SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = %s
            );
        """, (table_name,))
        table_exists = cur.fetchone()['exists']

        if not table_exists:
            cur.close(); conn.close()
            return jsonify({
                "ok": False,
                "error": "Raport jest w trakcie generowania lub jeszcze nie powstał. Wróć za chwilę."
            }), 404

        cur.execute(f"SELECT * FROM {table_name}")
        rows = cur.fetchall()
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": [dict(r) for r in rows]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/comparison/summary")
@login_required
def api_comparison_summary():
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        prefix           = session.get('store_prefix', 'default')
        table_products   = f"{prefix}_products"
        table_mappings   = f"{prefix}_product_mappings"
        competitor_table = f"{prefix}_competitors"
        COMPETITOR_TABLES = {competitor_table: "Rynek (Konkurencja)"}

        summary = []
        for table, label in COMPETITOR_TABLES.items():
            cur.execute(f"""
                SELECT '{label}' AS shop_label,
                       COUNT(*) AS total_mapped,
                       SUM(CASE WHEN COALESCE(c.price_special,c.price_normal) > COALESCE(p.price_special,p.price_normal) THEN 1 ELSE 0 END) AS we_cheaper,
                       SUM(CASE WHEN COALESCE(c.price_special,c.price_normal) < COALESCE(p.price_special,p.price_normal) THEN 1 ELSE 0 END) AS we_expensive,
                       SUM(CASE WHEN COALESCE(c.price_special,c.price_normal) = COALESCE(p.price_special,p.price_normal) THEN 1 ELSE 0 END) AS equal,
                       ROUND(AVG(COALESCE(c.price_special,c.price_normal)
                                 - COALESCE(p.price_special,p.price_normal))::numeric, 2) AS avg_diff_abs
                FROM {table_mappings} m
                JOIN {table_products} p ON p.id = m.our_product_id
                JOIN {table}          c ON c.id = m.competitor_id
                WHERE m.competitor_table = %s
            """, (table,))
            row = cur.fetchone()
            if row:
                row = dict(row)
                cur.execute(f"""
                    SELECT p.category, '{label}' AS shop_label, COUNT(*) AS count,
                           ROUND(AVG(COALESCE(c.price_special,c.price_normal)
                                     - COALESCE(p.price_special,p.price_normal))::numeric, 2) AS avg_diff
                    FROM {table_mappings} m
                    JOIN {table_products} p ON p.id = m.our_product_id
                    JOIN {table}          c ON c.id = m.competitor_id
                    WHERE m.competitor_table = %s
                    GROUP BY p.category ORDER BY avg_diff DESC
                """, (table,))
                row["by_category"] = [dict(r) for r in cur.fetchall()]
                summary.append(row)

        cur.close(); conn.close()
        return jsonify({"ok": True, "data": summary})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ==========================================
# ADMIN — UPLOAD I ZARZĄDZANIE PRODUKTAMI
# ==========================================

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
            vals.append(float(data[f]) if f in ("price_normal", "price_special") else data[f])
    if not cols:
        return jsonify({"ok": False, "error": "Brak danych"}), 400

    table_products = f"{session.get('store_prefix', 'default')}_products"
    sql = (f"INSERT INTO {table_products} ({', '.join(cols)}) "
           f"VALUES ({', '.join(['%s']*len(cols))}) RETURNING id")
    try:
        conn = get_db(); cur = conn.cursor()
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

    table_products = f"{session.get('store_prefix', 'default')}_products"
    try:
        conn = get_db(); cur = conn.cursor()
        cur.execute(f"UPDATE {table_products} SET {', '.join(fields)} WHERE id = %s", params)
        cur.close(); conn.close()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/admin/product/<int:product_id>", methods=["DELETE"])
@admin_required
def admin_delete_product(product_id):
    table_products = f"{session.get('store_prefix', 'default')}_products"
    try:
        conn = get_db(); cur = conn.cursor()
        cur.execute(f"DELETE FROM {table_products} WHERE id = %s", (product_id,))
        cur.close(); conn.close()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


def _coerce_row(raw: dict) -> dict:
    out = {}
    for f in PRODUCT_FIELDS:
        v = raw.get(f, "")
        if v in (None, ""):
            continue
        if f in ("price_normal", "price_special"):
            try:
                out[f] = float(str(v).replace(",", "."))
            except ValueError:
                pass
        else:
            out[f] = str(v).strip()
    return out


def _parse_csv(file_bytes: bytes) -> list[dict]:
    text   = file_bytes.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))
    return [_coerce_row(row) for row in reader]


def _parse_xml(file_bytes: bytes) -> list[dict]:
    root  = ET.fromstring(file_bytes)
    rows  = []
    items = root.findall("product") or list(root)
    for item in items:
        raw = {child.tag: child.text for child in item}
        raw.update(item.attrib)
        rows.append(_coerce_row(raw))
    return rows


@app.route("/api/admin/upload/preview", methods=["POST"])
@admin_required
def admin_upload_preview():
    if "file" not in request.files:
        return jsonify({"ok": False, "error": "Brak pliku"}), 400
    f    = request.files["file"]
    data = f.read()
    fname = f.filename.lower()
    try:
        if fname.endswith(".csv"):
            rows = _parse_csv(data)
        elif fname.endswith(".xml"):
            rows = _parse_xml(data)
        else:
            return jsonify({"ok": False, "error": "Obsługiwane formaty: .csv, .xml"}), 400
    except Exception as e:
        return jsonify({"ok": False, "error": f"Błąd parsowania: {e}"}), 400

    return jsonify({"ok": True, "rows": rows, "count": len(rows)})


@app.route("/api/admin/upload/confirm", methods=["POST"])
@admin_required
def admin_upload_confirm():
    payload = request.get_json()
    rows    = payload.get("rows", [])
    mode    = payload.get("mode", "insert")

    if not rows:
        return jsonify({"ok": False, "error": "Brak wierszy do wstawienia"}), 400

    inserted = updated = skipped = 0
    errors = []
    table_products = f"{session.get('store_prefix', 'default')}_products"

    try:
        conn = get_db()
        cur  = conn.cursor()

        for i, row in enumerate(rows):
            if not row: continue
            cols = list(row.keys())
            vals = list(row.values())
            if not cols: continue

            try:
                if mode == "upsert" and "sku" in row and row["sku"]:
                    set_clause = ", ".join(f"{c} = EXCLUDED.{c}" for c in cols if c != "sku")
                    sql = (
                        f"INSERT INTO {table_products} ({', '.join(cols)}) "
                        f"VALUES ({', '.join(['%s']*len(cols))}) "
                        f"ON CONFLICT (sku) DO UPDATE SET {set_clause} "
                        f"RETURNING (xmax = 0) AS inserted"
                    )
                    cur.execute(sql, vals)
                    was_inserted = cur.fetchone()[0]
                    if was_inserted: inserted += 1
                    else:            updated  += 1
                else:
                    sql = (
                        f"INSERT INTO {table_products} ({', '.join(cols)}) "
                        f"VALUES ({', '.join(['%s']*len(cols))}) "
                        f"ON CONFLICT DO NOTHING RETURNING id"
                    )
                    cur.execute(sql, vals)
                    if cur.fetchone(): inserted += 1
                    else:              skipped  += 1
            except Exception as e:
                errors.append({"row": i + 1, "error": str(e)})

        cur.close(); conn.close()
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

    return jsonify({
        "ok": True,
        "inserted": inserted,
        "updated": updated,
        "skipped": skipped,
        "errors": errors,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6767, debug=True)
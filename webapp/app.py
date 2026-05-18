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

#funkcje pomocnicze
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

#auth
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

#dashboard
@app.route("/dashboard")
@login_required
def dashboard():
    return render_template("dashboard.html",
                           username=session["username"],
                           is_admin=session.get("is_admin", False))

#api dane dla wykresow i tabelek
@app.route("/api/products")
@login_required
def api_products():
    category = request.args.get("category", "")
    sort = request.args.get("sort", "id")
    order = request.args.get("order", "asc")
    min_price = request.args.get("min_price", "")
    max_price = request.args.get("max_price", "")

    allowed_sorts = {"id", "name", "price", "category", "stock", "created_at"}
    allowed_orders = {"asc", "desc"}
    if sort  not in allowed_sorts: sort = "id"
    if order not in allowed_orders: order = "asc"

    where, params = [], []
    if category:
        where.append("category = %s"); params.append(category)
    if min_price:
        where.append("price >= %s"); params.append(float(min_price))
    if max_price:
        where.append("price <= %s"); params.append(float(max_price))

    sql = f"SELECT * FROM products"
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

        cur.execute("SELECT COUNT(*) AS total, AVG(price) AS avg_price, SUM(stock) AS total_stock FROM products")
        summary = dict(cur.fetchone())

        cur.execute("SELECT category, COUNT(*) AS count, AVG(price) AS avg_price, SUM(stock) AS total_stock FROM products GROUP BY category ORDER BY count DESC")
        by_category = [dict(r) for r in cur.fetchall()]

        cur.execute("SELECT DATE(created_at) AS day, COUNT(*) AS count FROM products GROUP BY day ORDER BY day DESC LIMIT 30")
        by_day = [dict(r) for r in cur.fetchall()]

        cur.close(); conn.close()
        return jsonify({"ok": True, "summary": summary, "by_category": by_category, "by_day": by_day})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/categories")
@login_required
def api_categories():
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute("SELECT DISTINCT category FROM products ORDER BY category")
        cats = [r[0] for r in cur.fetchall()]
        cur.close(); conn.close()
        return jsonify({"ok": True, "data": cats})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

#admin
@app.route("/admin")
@admin_required
def admin():
    return render_template("admin.html",
                           username=session["username"])

@app.route("/api/admin/product", methods=["POST"])
@admin_required
def admin_add_product():
    data = request.get_json()
    required = ["name", "category", "price", "stock"]
    if not all(k in data for k in required):
        return jsonify({"ok": False, "error": "Brakujące pola"}), 400
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute(
            "INSERT INTO products (name, category, price, stock) VALUES (%s,%s,%s,%s) RETURNING id",
            (data["name"], data["category"], float(data["price"]), int(data["stock"]))
        )
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
    for col in ["name", "category", "price", "stock"]:
        if col in data:
            fields.append(f"{col} = %s")
            params.append(float(data[col]) if col == "price" else
                          int(data[col])   if col == "stock" else data[col])
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

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6767, debug=True)

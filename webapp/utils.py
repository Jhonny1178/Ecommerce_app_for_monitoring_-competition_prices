# webapp/utils.py
import os
import psycopg2
from psycopg2 import sql
import psycopg2.extras
import hashlib
import re
import unicodedata
from functools import wraps
from flask import session, redirect, url_for, flash,request,jsonify,Blueprint

DB_CONFIG = {
    "host": os.environ.get("APP_DB_HOST", "ecommerce-db"),
    "port": int(os.environ.get("APP_DB_PORT", 5432)),
    "dbname": os.environ.get("APP_DB_NAME", "ecommerce_data"),
    "user": os.environ.get("APP_DB_USER", "postgres"),
    "password": os.environ.get("APP_DB_PASSWORD", "password"),
}

def get_db():
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    return conn
def get_db_transaction():
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = False
    return conn

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def generate_store_prefix(raw_name: str) -> str:
    value = unicodedata.normalize("NFKD", str(raw_name))
    value = value.encode("ascii", "ignore").decode("ascii")
    value = value.lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = value.strip("_")

    if not value:
        value = "client"

    if value[0].isdigit():
        value = f"client_{value}"

    return value[:50]

def generate_unique_store_prefix(conn, raw_name: str) -> str:
    base = generate_store_prefix(raw_name)

    with conn.cursor() as cur:
        candidate = base
        i = 1

        while True:
            cur.execute("""
                SELECT 1
                FROM clients
                WHERE slug = %s OR store_prefix = %s
                LIMIT 1
            """, (candidate, candidate))

            if cur.fetchone() is None:
                return candidate

            i += 1
            candidate = f"{base}_{i}"

def table_identifier(prefix: str, suffix: str):
    return sql.Identifier(f"{prefix}_{suffix}")


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            if request.path.startswith("/api/"):
                return jsonify({"ok": False, "error": "Unauthorized"}), 401
            return redirect(url_for("auth.login"))
        return f(*args, **kwargs)
    return decorated

def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            if request.path.startswith("/api/"):
                return jsonify({"ok": False, "error": "Unauthorized"}), 401
            return redirect(url_for("auth.login"))
        if not session.get("is_admin"):
            if request.path.startswith("/api/"):
                return jsonify({"ok": False, "error": "Forbidden"}), 403
            flash("Brak uprawnień administratora.", "error")
            return redirect(url_for("dashboard"))
        return f(*args, **kwargs)
    return decorated
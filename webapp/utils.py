# webapp/utils.py
import os
import psycopg2
import psycopg2.extras
import hashlib
import re
import unicodedata
from functools import wraps
from flask import session, redirect, url_for, flash

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

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def generate_store_prefix(name: str) -> str:
    name = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode('utf-8')
    name = name.lower()
    name = re.sub(r'[^a-z0-9]', '_', name)
    return re.sub(r'_+', '_', name).strip('_')

from flask import request, jsonify

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
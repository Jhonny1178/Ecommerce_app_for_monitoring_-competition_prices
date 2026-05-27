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
    "host": "localhost",
    "port":  5434,
    "dbname": os.environ.get("APP_DB_NAME", "ecommerce_data"),
    "user": os.environ.get("APP_DB_USER", "postgres"),
    "password": os.environ.get("APP_DB_PASSWORD", "***"),
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
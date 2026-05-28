from flask import Blueprint, render_template, request, redirect, url_for, session, jsonify
import psycopg2.extras
import requests
import json
from utils import get_db, hash_password

auth_bp = Blueprint('auth', __name__)


@auth_bp.route("/", methods=["GET", "POST"])
@auth_bp.route("/login", methods=["GET", "POST"])
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
                session["user_id"] = user["id"]
                session["username"] = user["username"]
                session["is_admin"] = user.get("is_admin", False)
                session["store_prefix"] = user.get("store_prefix") or "default"
                return redirect(url_for("dashboard"))
            else:
                error = "Nieprawidłowy login lub hasło."
        except Exception as e:
            error = f"Błąd połączenia z bazą: {e}"

    return render_template("login.html", error=error)


@auth_bp.route("/register", methods=["GET", "POST"])
def register():
    if "user_id" in session:
        return redirect(url_for("dashboard"))

    error = None
    message = None

    if request.method == "POST":
        company_name = request.form.get("company_name", "").strip()
        email = request.form.get("email", "").strip()

        # Zbieranie do 5 URLi z formularza (zakładamy, że frontend wyśle url_1, url_2...)
        competitor_urls = []
        for i in range(1, 6):
            url = request.form.get(f"url_{i}", "").strip()
            if url:
                competitor_urls.append(url)

        if not company_name or not email:
            error = "Wypełnij nazwę firmy i adres e-mail!"
        elif not competitor_urls:
            error = "Podaj przynajmniej jedną stronę konkurencji do weryfikacji!"
        else:
            try:
                conn = get_db()
                cur = conn.cursor()

                # 1. Zapisujemy wniosek do "poczekalni"
                urls_json = json.dumps(competitor_urls)
                cur.execute("""
                    INSERT INTO registration_requests (company_name, email, competitor_urls, status)
                    VALUES (%s, %s, %s::jsonb, 'pending')
                    RETURNING id
                """, (company_name, email, urls_json))

                request_id = cur.fetchone()[0]
                conn.commit()
                cur.close()
                conn.close()

                # 2. OPCJA B - Webhook wysyłający dane do generatora scraperów
                try:
                    payload = {
                        "request_id": request_id,
                        "company_name": company_name,
                        "urls": competitor_urls
                    }
                    requests.post("http://ai_generator:8080/api/check", json=payload, timeout=5)
                except requests.exceptions.RequestException as e:
                    print(f"Nie udało się połączyć z analizatorem (nie krytyczne): {e}")
                message = "Dziękujemy! Twój wniosek został przyjęty. Nasz system właśnie analizuje podane strony. Wyniki otrzymasz na podany adres e-mail."

            except psycopg2.errors.UniqueViolation:
                error = "Wniosek z tym adresem e-mail już istnieje w systemie."
            except Exception as e:
                print(f"REGISTER ERROR: {e}")
                error = "Wystąpił błąd podczas zapisywania wniosku."

    return render_template("register.html", error=error, message=message)


@auth_bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))

@auth_bp.route("/api/login", methods=["POST"])
def api_login():
    data = request.get_json() or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")
    hashed = hash_password(password)

    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("""
            SELECT u.*,
                COALESCE(c.store_prefix, c.slug, 'default') AS store_prefix
            FROM users u
            LEFT JOIN clients c ON u.client_id = c.id
            WHERE u.username = %s AND u.password_hash = %s
        """, (username, hashed))

        user = cur.fetchcone()
        cur.close()
        conn.close()
        if user:
            session["user_id"] = user["id"]
            session["username"] = user["username"]
            session["is_admin"] = user.get("is_admin", False)
            session["store_prefix"] = user.get("store_prefix") or "default"

            return jsonify({"ok": True, "message": "Zalogowano pomyślnie"})
        else:
            return jsonify({"ok": False, "error": "Nieprawidłowy login lub hasło."}), 401
    except Exception as e:
        return jsonify({"ok": False, "error": f"Błąd połączenia z bazą: {e}"}), 500
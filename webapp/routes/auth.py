from flask import Blueprint, request, session, jsonify
import psycopg2.extras
import requests
import json
from utils import get_db, hash_password, admin_required
import psycopg2
from psycopg2 import errors
import smtplib
from email.message import EmailMessage

auth_bp = Blueprint('auth', __name__)

def send_email(subject, body, to_email="ozminkowskimichal@gmail.com"):
    try:
        msg = EmailMessage()
        msg.set_content(body)
        msg["Subject"] = subject
        msg["From"] = "onboarding@test-r83ql3pdpkvgzw1j.mlsender.net"
        msg["To"] = to_email

        with smtplib.SMTP_SSL("smtp.resend.com", 465) as server:
            server.login("resend", "mlsn.93aa5bf5af520e3b79a55356534b1d71e837c28a10fd1aafa4c86626872461d6")
            server.send_message(msg)
    except Exception as e:
        print(f"Błąd wysyłania e-maila: {e}")





@auth_bp.route("/api/logout", methods=["POST"])
def api_logout():
    session.clear()
    return jsonify({"ok": True, "message": "Logged out successfully"})

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

        user = cur.fetchone()
        cur.close()
        conn.close()

        if user:
            session["user_id"] = user["id"]
            session["username"] = user["username"]
            session["is_admin"] = user.get("is_admin", False)
            session["status"] = user.get("status") or "active"
            session["store_prefix"] = user.get("store_prefix")
            return jsonify({
                "ok": True, 
                "message": "Zalogowano pomyślnie",
                "status": user.get("status"),
                "is_admin": user.get("is_admin", False)
            })
        else:
            return jsonify({"ok": False, "error": "Nieprawidłowy login lub hasło."}), 401
            
    except Exception as e:
        return jsonify({"ok": False, "error": f"Błąd połączenia z bazą: {e}"}), 500
    
@auth_bp.route("/api/register", methods=["POST"])
def api_register():
    data = request.get_json() or {}
    first_name = data.get("first_name", "").strip()
    last_name = data.get("last_name", "").strip()
    email = data.get("email", "").strip()
    password = data.get("password", "")
    company_domain = data.get("company_domain", "").strip()
    competitor_urls = data.get("urls", [])

    if not first_name or not last_name or not email or not password or not company_domain:
        return jsonify({"ok": False, "error": "Fill all required fields!"}), 400
    if not competitor_urls:
        return jsonify({"ok": False, "error": "Provide at least one competitor URL!"}), 400

    hashed = hash_password(password)

    try:
        conn = get_db()
        cur = conn.cursor()

        urls_json = json.dumps(competitor_urls)
        cur.execute("""
            INSERT INTO users (username, password_hash, first_name, last_name, company_domain, competitor_urls, status)
            VALUES (%s, %s, %s, %s, %s, %s::jsonb, 'pending_file')
            RETURNING id
        """, (email, hashed, first_name, last_name, company_domain, urls_json))
        
        user_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()

        return jsonify({"ok": True, "message": "Registration successful. Please login to continue."})

    except errors.UniqueViolation:
        return jsonify({"ok": False, "error": "User with this email already exists."}), 400
    except Exception as e:
        return jsonify({"ok": False, "error": f"Database error: {e}"}), 500
@auth_bp.route("/api/upload_onboarding_file", methods=["POST"])
def upload_onboarding_file():
    if "user_id" not in session:
        return jsonify({"ok": False, "error": "Not authenticated"}), 401
    
    if "file" not in request.files:
        return jsonify({"ok": False, "error": "No file uploaded"}), 400

    f = request.files["file"]
    
    try:
        conn = get_db()
        cur = conn.cursor()
        
        # Change status to pending_approval
        cur.execute("UPDATE users SET status = 'pending_approval' WHERE id = %s", (session['user_id'],))
        
        # Oczekujemy na zwrotke user_data aby utworzyc odpowiedni folder
        cur.execute("SELECT first_name, last_name, competitor_urls FROM users WHERE id = %s", (session['user_id'],))
        user_data = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        if user_data:
            import os
            nazwa_firmy = f"{user_data[0]} {user_data[1]}"
            bezpieczna_nazwa = "".join(c if c.isalnum() else "_" for c in nazwa_firmy).lower()
            
            # Pobranie docelowego folderu
            spiders_dir = os.environ.get("SPIDERS_DIR", "ecommerce_price_comparer/spiders")
            katalog_klienta = os.path.join(spiders_dir, bezpieczna_nazwa)
            os.makedirs(katalog_klienta, exist_ok=True)
            
            # Zapis do folderu z pająkami
            file_path = os.path.join(katalog_klienta, f.filename)
            f.save(file_path)

            if user_data[2]:
                try:
                    payload = {
                        "request_id": session['user_id'],
                        "company_name": f"{user_data[0]} {user_data[1]}",
                        "urls": user_data[2]
                    }
                    requests.post("http://ai_generator:8080/api/check", json=payload, timeout=5)
                except requests.exceptions.RequestException as e:
                    print(f"Błąd komunikacji z AI: {e}")

        session["status"] = "pending_approval"
        return jsonify({"ok": True, "message": "File uploaded successfully. Awaiting approval."})
    except Exception as e:
        return jsonify({"ok": False, "error": f"Database error: {e}"}), 500
@auth_bp.route("/api/send_message", methods=["POST"])
def api_send_message():
    data = request.get_json() or {}
    message = data.get("message", "").strip()
    
    if not message:
        return jsonify({"ok": False, "error": "Pusta wiadomość"}), 400

    username = session.get("username", "Nieznany")
    send_email(f"Nowa wiadomość od {username}", message)
    return jsonify({"ok": True, "message": "Wysłano"})

@auth_bp.route("/api/admin/pending_users", methods=["GET"])
def admin_pending_users():
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403
        
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT id, username, first_name, last_name, company_domain, competitor_urls, status FROM users WHERE status IN ('pending_approval', 'analyzing', 'completed')")
        users = cur.fetchall()
        cur.close()
        conn.close()
        return jsonify({"ok": True, "users": users})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/admin/user_logs/<int:user_id>", methods=["GET"])
def admin_user_logs(user_id):
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403
        
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT url, step, status, message, created_at FROM scraper_logs WHERE user_id = %s ORDER BY created_at ASC", (user_id,))
        logs = cur.fetchall()
        
        for log in logs:
            if log.get('created_at'):
                log['created_at'] = log['created_at'].isoformat()
        
        
        # Opcjonalnie dodatkowe dane usera
        cur.execute("SELECT first_name, last_name, company_domain, competitor_urls FROM users WHERE id = %s", (user_id,))
        user_info = cur.fetchone()
        
        cur.close()
        conn.close()
        return jsonify({"ok": True, "logs": logs, "user": user_info})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/admin/approve_user", methods=["POST"])
def admin_approve_user():
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403
        
    data = request.get_json() or {}
    user_id = data.get("user_id")
    
    if not user_id:
        return jsonify({"ok": False, "error": "Missing user_id"}), 400

    try:
        conn = get_db()
        cur = conn.cursor()
        
        # Zmieniamy status na awaiting_payment
        cur.execute("UPDATE users SET status = 'awaiting_payment' WHERE id = %s", (user_id,))
        
        conn.commit()
        
        cur.execute("SELECT username, first_name FROM users WHERE id = %s", (user_id,))
        user_row = cur.fetchone()
        
        cur.close()
        conn.close()
        
        if user_row:
            send_email(
                "Twój wniosek do e-ROCH został zatwierdzony!",
                f"Witaj {user_row[1]},\n\nTwój wniosek został zatwierdzony. Zaloguj się do panelu, aby wybrać pakiet i rozpocząć korzystanie ze scrapingu.",
                to_email=user_row[0]
            )
            
        return jsonify({"ok": True, "message": "User approved successfully."})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/admin/reject_user", methods=["POST"])
def admin_reject_user():
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403
        
    data = request.get_json() or {}
    user_id = data.get("user_id")
    reason = data.get("reason", "Brak powodu")
    
    if not user_id:
        return jsonify({"ok": False, "error": "Missing user_id"}), 400

    try:
        conn = get_db()
        cur = conn.cursor()
        
        cur.execute("UPDATE users SET status = 'rejected', rejection_reason = %s WHERE id = %s", (reason, user_id))
        
        conn.commit()

        cur.execute("SELECT username, first_name FROM users WHERE id = %s", (user_id,))
        user_row = cur.fetchone()

        cur.close()
        conn.close()
        
        if user_row:
            send_email(
                "Twój wniosek do e-ROCH został odrzucony",
                f"Witaj {user_row[1]},\n\nNiestety, Twój wniosek o założenie konta został odrzucony.\nPowód: {reason}",
                to_email=user_row[0]
            )
            
        return jsonify({"ok": True, "message": "User rejected."})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/subscription/buy", methods=["POST"])
def subscription_buy():
    if "user_id" not in session:
        return jsonify({"ok": False, "error": "Not authenticated"}), 401
        
    data = request.get_json() or {}
    package = data.get("package") # e.g. '500', '400', '300'
    
    try:
        conn = get_db()
        cur = conn.cursor()
        
        # Create client for this user if it doesn't exist
        cur.execute("SELECT username, company_domain, client_id FROM users WHERE id = %s", (session["user_id"],))
        user_row = cur.fetchone()
        
        client_id = user_row[2]
        if not client_id:
            domain = user_row[1] or f"client_{session['user_id']}"
            cur.execute("""
                INSERT INTO clients (name, slug, store_prefix, source_type) 
                VALUES (%s, %s, %s, 'local') RETURNING id
            """, (domain, domain, domain))
            client_id = cur.fetchone()[0]
            cur.execute("UPDATE users SET client_id = %s WHERE id = %s", (client_id, session["user_id"]))
            
        cur.execute("UPDATE users SET status = 'active' WHERE id = %s", (session['user_id'],))
        
        conn.commit()
        cur.close()
        conn.close()
        
        session["status"] = "active"
        return jsonify({"ok": True, "message": "Subscription activated successfully."})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/report_bug", methods=["POST"])
def api_report_bug():
    data = request.get_json() or {}
    message = data.get("message", "").strip()
    if not message:
        return jsonify({"ok": False, "error": "Brak treści"}), 400

    user_id = session.get("user_id")

    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO error_logs (user_id, category, message, error_type, is_reviewed)
            VALUES (%s, 'Klient', %s, 'Zgłoszony', FALSE)
        """, (user_id, message))
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    
@auth_bp.route("/api/admin/error_logs", methods=["GET"])
@admin_required
def get_error_logs():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)
    
    search = request.args.get('search', '').strip()
    category = request.args.get('category', '').strip()
    date_before = request.args.get('date_before', '').strip()
    date_after = request.args.get('date_after', '').strip()
    error_type = request.args.get('error_type', '').strip()
    is_reviewed = request.args.get('is_reviewed', '').strip()

    offset = (page - 1) * per_page
    
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        where_clauses = ["1=1"]
        params = []
        
        if search:
            where_clauses.append("error_code ILIKE %s")
            params.append(f"%{search}%")
        if category:
            where_clauses.append("category = %s")
            params.append(category)
        if error_type:
            where_clauses.append("error_type = %s")
            params.append(error_type)
        if is_reviewed in ['true', 'false']:
            where_clauses.append("is_reviewed = %s")
            params.append(is_reviewed == 'true')
        if date_after:
            where_clauses.append("created_at >= %s")
            params.append(date_after)
        if date_before:
            where_clauses.append("created_at <= %s")
            params.append(date_before + " 23:59:59")

        where_str = " AND ".join(where_clauses)
        
        cur.execute(f"SELECT COUNT(id) as total FROM error_logs WHERE {where_str}", params)
        total_items = cur.fetchone()['total']
        
        query = f"""
            SELECT id, category, error_code, error_type, is_reviewed, message,
                   TO_CHAR(created_at, 'DD.MM.YYYY') as created_at_str,
                   TO_CHAR(resolved_at, 'DD.MM.YYYY') as resolved_at_str
            FROM error_logs
            WHERE {where_str}
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """
        cur.execute(query, params + [per_page, offset])
        logs = cur.fetchall()
        cur.close()
        conn.close()
        
        import math
        return jsonify({
            "ok": True, 
            "data": logs,
            "pagination": {
                "total_items": total_items,
                "current_page": page,
                "per_page": per_page,
                "total_pages": math.ceil(total_items / per_page) if total_items > 0 else 1
            }
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/admin/error_logs/<int:log_id>/review", methods=["POST"])
@admin_required
def review_error_log(log_id):
    data = request.get_json() or {}
    is_reviewed = data.get("is_reviewed")
    resolved_at = data.get("resolved_at")
    
    try:
        conn = get_db()
        cur = conn.cursor()
        
        if resolved_at is not None:
            cur.execute("UPDATE error_logs SET resolved_at = %s WHERE id = %s", (resolved_at, log_id))
            
        if is_reviewed is not None:
            if is_reviewed:
                cur.execute("UPDATE error_logs SET is_reviewed = TRUE WHERE id = %s", (log_id,))
            else:
                cur.execute("UPDATE error_logs SET is_reviewed = FALSE, resolved_at = NULL WHERE id = %s", (log_id,))
                
        conn.commit()
        cur.close()
        conn.close()
        
        return jsonify({"ok": True, "message": "Status zaktualizowany"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    
@auth_bp.route("/api/admin/supported_stores", methods=["GET"])
@admin_required
def get_supported_stores():
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        cur.execute("""
            SELECT 
                id, 
                name AS store_name, 
                slug AS store_domain, 
                CASE WHEN is_active = TRUE THEN 'Aktywny' ELSE 'Wstrzymany' END AS status, 
                TO_CHAR(created_at, 'DD.MM.YYYY') AS added_date 
            FROM clients 
            ORDER BY name ASC
        """)
        stores = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({"ok": True, "data": stores})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
    
@auth_bp.route("/api/admin/registration_requests", methods=["GET"])
@admin_required
def get_registration_requests():
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        cur.execute("""
            SELECT id, 
                   first_name || ' ' || last_name AS company_name, 
                   username AS email, 
                   competitor_urls, 
                   status, 
                   '-' as requested_date 
            FROM users 
            WHERE status = 'pending_file'
            ORDER BY id DESC
        """)
        requests = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({"ok": True, "data": requests})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
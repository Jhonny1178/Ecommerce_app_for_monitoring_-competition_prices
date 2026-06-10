from flask import Blueprint, request, session, jsonify
import psycopg2.extras
import requests
import json
from utils import get_db, get_db_transaction, hash_password, admin_required
from services.provisioning import provision_client_from_request
import os
from werkzeug.utils import secure_filename
import psycopg2
from psycopg2 import errors
import smtplib
from email.message import EmailMessage
import traceback

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

    if not username or not password:
        return jsonify({"ok": False, "error": "Podaj login i hasło."}), 400

    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT
                u.id,
                u.username,
                u.password_hash,
                u.is_admin,
                u.client_id,
                u.status,
                c.slug AS client_slug,
                COALESCE(c.store_prefix, c.slug) AS store_prefix
            FROM users u
            LEFT JOIN clients c ON c.id = u.client_id
            WHERE u.username = %s
              AND u.password_hash = %s
        """, (username, hashed))

        user = cur.fetchone()
        cur.close()
        conn.close()

        if not user:
            return jsonify({"ok": False, "error": "Nieprawidłowy login lub hasło."}), 401

        session["user_id"] = user["id"]
        session["username"] = user["username"]
        session["is_admin"] = user.get("is_admin", False)
        session["status"] = user.get("status") or "pending_admin"
        session["client_id"] = user.get("client_id")
        session["client_slug"] = user.get("client_slug")
        session["store_prefix"] = user.get("store_prefix")

        return jsonify({
            "ok": True,
            "message": "Zalogowano pomyślnie",
            "status": user.get("status"),
            "is_admin": user.get("is_admin", False),
            "client_id": user.get("client_id"),
            "client_slug": user.get("client_slug"),
            "store_prefix": user.get("store_prefix")
        })

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

    requested_store_name = (
        data.get("store_name")
        or data.get("requested_store_name")
        or company_domain
    )

    if not first_name or not last_name or not email or not password or not company_domain:
        return jsonify({"ok": False, "error": "Fill all required fields!"}), 400

    if not competitor_urls:
        return jsonify({"ok": False, "error": "Provide at least one competitor URL!"}), 400

    hashed = hash_password(password)
    urls_json = json.dumps(competitor_urls)

    conn = get_db_transaction()

    try:
        cur = conn.cursor()

        cur.execute("""
            INSERT INTO users (
                username,
                password_hash,
                first_name,
                last_name,
                company_domain,
                competitor_urls,
                status
            )
            VALUES (%s, %s, %s, %s, %s, %s::jsonb, 'pending_admin')
            RETURNING id
        """, (
            email,
            hashed,
            first_name,
            last_name,
            company_domain,
            urls_json
        ))

        user_id = cur.fetchone()[0]

        cur.execute("""
            INSERT INTO onboarding_requests (
                user_id,
                requested_store_name,
                company_domain,
                competitor_urls,
                status
            )
            VALUES (%s, %s, %s, %s::jsonb, 'pending_admin')
        """, (
            user_id,
            requested_store_name,
            company_domain,
            urls_json
        ))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            "ok": True,
            "message": "Registration successful. Awaiting admin approval."
        })

    except errors.UniqueViolation:
        conn.rollback()
        conn.close()
        return jsonify({"ok": False, "error": "User with this email already exists."}), 400

    except Exception as e:
        conn.rollback()
        conn.close()
        return jsonify({"ok": False, "error": f"Database error: {e}"}), 500
@auth_bp.route("/api/upload_onboarding_file", methods=["POST"])
def upload_onboarding_file():
    if "user_id" not in session:
        return jsonify({"ok": False, "error": "Not authenticated"}), 401

    if "file" not in request.files:
        return jsonify({"ok": False, "error": "No file uploaded"}), 400

    uploaded_file = request.files["file"]

    if uploaded_file.filename == "":
        return jsonify({"ok": False, "error": "Empty filename"}), 400

    file_format = request.form.get("file_format", "").strip() or None
    field_mapping_raw = request.form.get("field_mapping", "{}")
    source_kind = request.form.get("source_kind", "file").strip()

    try:
        field_mapping = json.loads(field_mapping_raw)
    except json.JSONDecodeError:
        return jsonify({"ok": False, "error": "Invalid field_mapping JSON"}), 400

    filename = secure_filename(uploaded_file.filename)

    os.makedirs("/tmp/onboarding", exist_ok=True)
    file_path = f"/tmp/onboarding/user_{session['user_id']}_{filename}"
    uploaded_file.save(file_path)

    conn = get_db_transaction()

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT id
            FROM onboarding_requests
            WHERE user_id = %s
              AND status IN ('pending_admin', 'onboarding_required', 'onboarding_submitted')
            ORDER BY created_at DESC
            LIMIT 1
        """, (session["user_id"],))

        onboarding_request = cur.fetchone()

        if not onboarding_request:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({"ok": False, "error": "No onboarding request found"}), 404

        request_id = onboarding_request["id"]

        cur.execute("""
            INSERT INTO onboarding_sources (
                request_id,
                source_kind,
                source_path,
                source_url,
                file_format,
                original_name,
                mime_type
            )
            VALUES (%s, %s, %s, NULL, %s, %s, %s)
        """, (
            request_id,
            source_kind,
            file_path,
            file_format,
            uploaded_file.filename,
            uploaded_file.mimetype
        ))

        cur.execute("""
            UPDATE onboarding_requests
            SET source_type = %s,
                source_path = %s,
                file_format = %s,
                field_mapping = %s::jsonb,
                status = 'onboarding_submitted',
                updated_at = NOW()
            WHERE id = %s
        """, (
            source_kind,
            file_path,
            file_format,
            json.dumps(field_mapping),
            request_id
        ))

        cur.execute("""
            UPDATE users
            SET status = 'onboarding_submitted',
                updated_at = NOW()
            WHERE id = %s
        """, (session["user_id"],))

        conn.commit()
        cur.close()
        conn.close()

        session["status"] = "onboarding_submitted"

        return jsonify({
            "ok": True,
            "message": "File uploaded successfully. Awaiting admin approval.",
            "request_id": request_id,
            "source_path": file_path
        })

    except Exception as e:
        conn.rollback()
        conn.close()
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
@admin_required
def admin_pending_users():
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT
                u.id,
                u.username,
                u.first_name,
                u.last_name,
                u.status AS user_status,
                u.client_id,
                u.company_domain,
                u.competitor_urls,

                r.id AS request_id,
                r.requested_store_name,
                r.requested_store_slug,
                r.competitor_urls AS request_competitor_urls,
                r.status AS request_status,
                TO_CHAR(r.created_at, 'DD.MM.YYYY') AS requested_date
            FROM onboarding_requests r
            JOIN users u ON u.id = r.user_id
            WHERE r.status IN (
                'pending_admin',
                'onboarding_submitted',
                'scraper_review'
            )
            ORDER BY r.created_at DESC
        """)

        users = cur.fetchall()

        cur.close()
        conn.close()

        return jsonify({
            "ok": True,
            "users": users
        })

    except Exception as e:
        traceback.print_exc()
        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

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
@admin_required
def admin_approve_user():
    data = request.get_json() or {}

    request_id = data.get("request_id")
    user_id = data.get("user_id")

    conn = get_db_transaction()

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        if not request_id and user_id:
            cur.execute("""
                SELECT id
                FROM onboarding_requests
                WHERE user_id = %s
                  AND status = 'pending_admin'
                ORDER BY created_at DESC
                LIMIT 1
            """, (user_id,))

            row = cur.fetchone()

            if not row:
                conn.rollback()
                cur.close()
                conn.close()
                return jsonify({
                    "ok": False,
                    "error": "No pending onboarding request found for this user."
                }), 404

            request_id = row["id"]

        if not request_id:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({
                "ok": False,
                "error": "Missing request_id."
            }), 400

        cur.execute("""
            SELECT
                r.id,
                r.user_id,
                r.requested_store_name,
                r.requested_store_slug,
                r.competitor_urls,
                r.status,

                'pending'::TEXT AS source_type,
                NULL::TEXT AS source_path,
                NULL::TEXT AS source_url,
                NULL::TEXT AS file_format,
                '{}'::jsonb AS field_mapping
            FROM onboarding_requests r
            WHERE r.id = %s
              AND r.status = 'pending_admin'
            LIMIT 1
        """, (request_id,))

        onboarding_request = cur.fetchone()

        if not onboarding_request:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({
                "ok": False,
                "error": "Onboarding request not found or is not pending_admin."
            }), 404

        result = provision_client_from_request(
            conn=conn,
            user_id=onboarding_request["user_id"],
            request_id=onboarding_request["id"],
            store_name=onboarding_request["requested_store_name"],
            source_type=onboarding_request["source_type"],
            source_path=onboarding_request["source_path"],
            source_url=onboarding_request["source_url"],
            file_format=onboarding_request["file_format"],
            field_mapping=onboarding_request["field_mapping"] or {}
        )

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            "ok": True,
            "message": "User approved and client provisioned successfully.",
            "client_id": result.get("client_id"),
            "store_prefix": result.get("store_prefix"),
            "slug": result.get("slug")
        })


    except Exception as e:

        traceback.print_exc()

        conn.rollback()

        conn.close()

        return jsonify({

            "ok": False,

            "error": str(e)

        }), 500
@auth_bp.route("/api/admin/onboarding_requests/<int:request_id>/generate_scrapers", methods=["POST"])
def generate_scrapers_for_request(request_id):
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403

    conn = get_db_transaction()

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT
                r.id AS request_id,
                r.user_id,
                r.client_id,
                r.requested_store_slug,
                r.competitor_urls,
                r.status,
                c.slug AS client_slug,
                c.store_prefix
            FROM onboarding_requests r
            JOIN clients c ON c.id = r.client_id
            WHERE r.id = %s
            LIMIT 1
        """, (request_id,))

        onboarding_request = cur.fetchone()

        if not onboarding_request:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({"ok": False, "error": "Onboarding request not found or client not provisioned"}), 404

        if not onboarding_request["client_id"]:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({"ok": False, "error": "Client has not been provisioned yet"}), 400

        competitor_urls = onboarding_request.get("competitor_urls") or []

        payload = {
            "request_id": onboarding_request["request_id"],
            "user_id": onboarding_request["user_id"],
            "client_id": onboarding_request["client_id"],
            "store_slug": onboarding_request["store_prefix"] or onboarding_request["client_slug"],
            "urls": competitor_urls
        }

        try:
            response = requests.post(
                "http://ai_generator:8080/api/check",
                json=payload,
                timeout=10
            )
            response_ok = 200 <= response.status_code < 300

        except requests.exceptions.RequestException as e:
            cur.execute("""
                INSERT INTO scraper_logs (
                    user_id,
                    client_id,
                    request_id,
                    url,
                    step,
                    status,
                    message
                )
                VALUES (%s, %s, %s, NULL, 'ai_generator_request', 'failed', %s)
            """, (
                onboarding_request["user_id"],
                onboarding_request["client_id"],
                onboarding_request["request_id"],
                str(e)
            ))

            conn.commit()
            cur.close()
            conn.close()

            return jsonify({
                "ok": False,
                "error": f"AI generator request failed: {e}"
            }), 500

        if response_ok:
            cur.execute("""
                UPDATE onboarding_requests
                SET status = 'scraper_generating',
                    updated_at = NOW()
                WHERE id = %s
            """, (request_id,))

            cur.execute("""
                INSERT INTO scraper_logs (
                    user_id,
                    client_id,
                    request_id,
                    url,
                    step,
                    status,
                    message
                )
                VALUES (%s, %s, %s, NULL, 'ai_generator_request', 'started', %s)
            """, (
                onboarding_request["user_id"],
                onboarding_request["client_id"],
                onboarding_request["request_id"],
                "AI scraper generator started"
            ))

            conn.commit()
            cur.close()
            conn.close()

            return jsonify({
                "ok": True,
                "message": "AI scraper generation started",
                "payload": payload
            })

        cur.execute("""
            INSERT INTO scraper_logs (
                user_id,
                client_id,
                request_id,
                url,
                step,
                status,
                message
            )
            VALUES (%s, %s, %s, NULL, 'ai_generator_request', 'failed', %s)
        """, (
            onboarding_request["user_id"],
            onboarding_request["client_id"],
            onboarding_request["request_id"],
            f"AI generator returned status {response.status_code}: {response.text}"
        ))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            "ok": False,
            "error": f"AI generator returned status {response.status_code}",
            "details": response.text
        }), 500

    except Exception as e:
        conn.rollback()
        conn.close()
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/admin/scrapers/<int:scraper_id>/approve", methods=["POST"])
def approve_scraper(scraper_id):
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403

    conn = get_db_transaction()

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            UPDATE scraper_registry
            SET status = 'approved',
                approved_by = %s,
                approved_at = NOW()
            WHERE id = %s
            RETURNING client_id
        """, (
            session["user_id"],
            scraper_id
        ))

        row = cur.fetchone()

        if not row:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({"ok": False, "error": "Scraper not found"}), 404

        client_id = row["client_id"]

        cur.execute("""
            UPDATE clients c
            SET spiders_to_run = sub.spiders,
                updated_at = NOW()
            FROM (
                SELECT
                    client_id,
                    array_agg(spider_name ORDER BY spider_name) AS spiders
                FROM scraper_registry
                WHERE client_id = %s
                  AND status = 'approved'
                GROUP BY client_id
            ) sub
            WHERE c.id = sub.client_id
        """, (client_id,))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            "ok": True,
            "message": "Scraper approved and synchronized with clients.spiders_to_run"
        })

    except Exception as e:
        conn.rollback()
        conn.close()
        return jsonify({"ok": False, "error": str(e)}), 500
@auth_bp.route("/api/admin/scrapers", methods=["GET"])
def list_scrapers():
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403

    client_id = request.args.get("client_id", type=int)
    request_id = request.args.get("request_id", type=int)

    where_clauses = ["1=1"]
    params = []

    if client_id:
        where_clauses.append("sr.client_id = %s")
        params.append(client_id)

    if request_id:
        where_clauses.append("sr.request_id = %s")
        params.append(request_id)

    where_sql = " AND ".join(where_clauses)

    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute(f"""
            SELECT
                sr.id,
                sr.client_id,
                sr.request_id,
                c.name AS client_name,
                c.slug AS client_slug,
                sr.store_slug,
                sr.competitor_url,
                sr.competitor_name,
                sr.spider_name,
                sr.spider_module,
                sr.spider_path,
                sr.output_table,
                sr.status,
                sr.last_error,
                sr.generated_at,
                sr.approved_at
            FROM scraper_registry sr
            JOIN clients c ON c.id = sr.client_id
            WHERE {where_sql}
            ORDER BY sr.generated_at DESC
        """, params)

        scrapers = cur.fetchall()

        cur.close()
        conn.close()

        return jsonify({
            "ok": True,
            "data": scrapers
        })

    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
@auth_bp.route("/api/admin/reject_user", methods=["POST"])
def admin_reject_user():
    if not session.get("is_admin"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403

    data = request.get_json() or {}
    user_id = data.get("user_id")
    request_id = data.get("request_id")
    reason = data.get("reason", "Brak powodu")

    if not user_id and not request_id:
        return jsonify({"ok": False, "error": "Missing user_id or request_id"}), 400

    conn = get_db_transaction()

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        if request_id:
            cur.execute("""
                SELECT r.id, r.user_id, u.username, u.first_name
                FROM onboarding_requests r
                JOIN users u ON u.id = r.user_id
                WHERE r.id = %s
                LIMIT 1
            """, (request_id,))
        else:
            cur.execute("""
                SELECT r.id, r.user_id, u.username, u.first_name
                FROM onboarding_requests r
                JOIN users u ON u.id = r.user_id
                WHERE r.user_id = %s
                ORDER BY r.created_at DESC
                LIMIT 1
            """, (user_id,))

        onboarding_request = cur.fetchone()

        if not onboarding_request:
            conn.rollback()
            cur.close()
            conn.close()
            return jsonify({"ok": False, "error": "Onboarding request not found"}), 404

        cur.execute("""
            UPDATE onboarding_requests
            SET status = 'rejected',
                rejection_reason = %s,
                updated_at = NOW()
            WHERE id = %s
        """, (reason, onboarding_request["id"]))

        cur.execute("""
            UPDATE users
            SET status = 'rejected',
                rejection_reason = %s,
                updated_at = NOW()
            WHERE id = %s
        """, (reason, onboarding_request["user_id"]))

        conn.commit()

        user_email = onboarding_request["username"]
        user_first_name = onboarding_request["first_name"]

        cur.close()
        conn.close()

        if user_email:
            send_email(
                "Twój wniosek do e-ROCH został odrzucony",
                f"Witaj {user_first_name},\n\nNiestety, Twój wniosek o założenie konta został odrzucony.\nPowód: {reason}",
                to_email=user_email
            )

        return jsonify({"ok": True, "message": "User rejected."})

    except Exception as e:
        conn.rollback()
        conn.close()
        return jsonify({"ok": False, "error": str(e)}), 500

@auth_bp.route("/api/subscription/buy", methods=["POST"])
def subscription_buy():
    if "user_id" not in session:
        return jsonify({"ok": False, "error": "Not authenticated"}), 401

    data = request.get_json() or {}
    package = data.get("package")

    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT id, client_id, status
            FROM users
            WHERE id = %s
        """, (session["user_id"],))

        user = cur.fetchone()

        if not user:
            cur.close()
            conn.close()
            return jsonify({"ok": False, "error": "User not found"}), 404

        if not user["client_id"]:
            cur.close()
            conn.close()
            return jsonify({
                "ok": False,
                "error": "Client has not been provisioned yet. Wait for admin approval."
            }), 400

        cur.execute("""
            UPDATE users
            SET status = 'active',
                updated_at = NOW()
            WHERE id = %s
        """, (session["user_id"],))

        cur.execute("""
            UPDATE clients
            SET is_active = TRUE,
                updated_at = NOW()
            WHERE id = %s
        """, (user["client_id"],))

        conn.commit()
        cur.close()
        conn.close()

        session["status"] = "active"
        session["client_id"] = user["client_id"]

        return jsonify({
            "ok": True,
            "message": "Subscription activated successfully.",
            "package": package
        })

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
            SELECT
                r.id AS request_id,
                r.requested_store_name AS company_name,
                r.company_domain,
                r.competitor_urls,
                r.status,
                TO_CHAR(r.created_at, 'DD.MM.YYYY') AS requested_date,

                u.id AS user_id,
                u.username AS email,
                u.first_name,
                u.last_name,
                u.client_id
            FROM onboarding_requests r
            JOIN users u ON u.id = r.user_id
            ORDER BY r.created_at DESC
        """)

        requests_list = cur.fetchall()
        cur.close()
        conn.close()

        return jsonify({"ok": True, "data": requests_list})

    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
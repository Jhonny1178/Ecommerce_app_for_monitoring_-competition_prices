-- database/schema.sql

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1. Klienci aktywni w systemie
--    Ten rekord powstaje dopiero po akceptacji przez admina.
-- ============================================================

CREATE TABLE IF NOT EXISTS clients (
    id                      SERIAL PRIMARY KEY,

    name                    TEXT NOT NULL,
    slug                    TEXT UNIQUE NOT NULL,
    store_prefix            TEXT UNIQUE NOT NULL,

    is_active               BOOLEAN DEFAULT FALSE,
    created_at              TIMESTAMP DEFAULT NOW(),
    updated_at              TIMESTAMP DEFAULT NOW(),

    source_type             TEXT DEFAULT 'pending',
    source_path             TEXT,
    source_url              TEXT,
    file_format             TEXT,
    field_mapping           JSONB NOT NULL DEFAULT '{}'::jsonb,

    spiders_to_run          TEXT[] DEFAULT ARRAY[]::TEXT[],

    match_name_threshold    FLOAT DEFAULT 90.0,
    match_color_threshold   FLOAT DEFAULT 80.0,
    match_maker_threshold   FLOAT DEFAULT 80.0
);

-- ============================================================
-- 2. Użytkownicy systemu
--    users = konto i logowanie, nie pełne zgłoszenie biznesowe.
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
    id                  SERIAL PRIMARY KEY,

    username            TEXT UNIQUE NOT NULL,
    password_hash       TEXT NOT NULL,

    is_admin            BOOLEAN DEFAULT FALSE,
    client_id           INTEGER REFERENCES clients(id) ON DELETE SET NULL,

    status              TEXT DEFAULT 'pending_admin',

    first_name          TEXT,
    last_name           TEXT,
    email               TEXT,
    phone               TEXT,

    company_domain      TEXT,
    competitor_urls     JSONB DEFAULT '[]'::jsonb,

    rejection_reason    TEXT,

    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- 3. Zgłoszenia onboardingowe
--    To jest najważniejsza tabela przed utworzeniem klienta.
--    Admin powinien patrzeć głównie tutaj.
-- ============================================================

CREATE TABLE IF NOT EXISTS onboarding_requests (
    id                      SERIAL PRIMARY KEY,

    user_id                 INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id               INTEGER REFERENCES clients(id) ON DELETE SET NULL,

    requested_store_name    TEXT NOT NULL,
    requested_store_slug    TEXT,

    company_domain          TEXT,
    competitor_urls         JSONB DEFAULT '[]'::jsonb,

    status                  TEXT NOT NULL DEFAULT 'pending_admin',

    approved_by             INTEGER REFERENCES users(id) ON DELETE SET NULL,
    approved_at             TIMESTAMP,
    rejection_reason        TEXT,

    notes                   TEXT,

    created_at              TIMESTAMP DEFAULT NOW(),
    updated_at              TIMESTAMP DEFAULT NOW(),

    UNIQUE(user_id, requested_store_name)
);

-- ============================================================
-- 4. Źródła danych klienta
--    Plik CSV/XLSX albo link/API podany w formularzu onboardingu.
-- ============================================================

CREATE TABLE IF NOT EXISTS onboarding_sources (
    id              SERIAL PRIMARY KEY,

    request_id      INTEGER NOT NULL REFERENCES onboarding_requests(id) ON DELETE CASCADE,

    source_kind     TEXT NOT NULL,
    source_path     TEXT,
    source_url      TEXT,
    file_format     TEXT,

    original_name    TEXT,
    mime_type        TEXT,

    uploaded_at      TIMESTAMP DEFAULT NOW(),

    CHECK (source_kind IN ('file', 'url', 'api'))
);

-- ============================================================
-- 5. Mapowanie pól klienta do Twojego modelu danych
--    Np. klient ma kolumnę "CENA", a u Ciebie to "price_normal".
-- ============================================================

CREATE TABLE IF NOT EXISTS onboarding_field_mappings (
    id                  SERIAL PRIMARY KEY,

    request_id          INTEGER NOT NULL REFERENCES onboarding_requests(id) ON DELETE CASCADE,

    external_field      TEXT NOT NULL,
    internal_field      TEXT NOT NULL,

    is_required         BOOLEAN DEFAULT FALSE,
    sample_value        TEXT,

    created_at          TIMESTAMP DEFAULT NOW(),

    UNIQUE(request_id, external_field)
);

-- ============================================================
-- 6. Dodatkowe pola, które klient chce scrapować
--    Np. "materiał", "czas dostawy", "liczba opinii".
-- ============================================================

CREATE TABLE IF NOT EXISTS onboarding_scrape_fields (
    id                  SERIAL PRIMARY KEY,

    request_id          INTEGER NOT NULL REFERENCES onboarding_requests(id) ON DELETE CASCADE,

    field_name          TEXT NOT NULL,
    field_description   TEXT,
    is_required         BOOLEAN DEFAULT FALSE,

    created_at          TIMESTAMP DEFAULT NOW(),

    UNIQUE(request_id, field_name)
);

-- ============================================================
-- 7. Logi uruchomień całego pipeline dla klienta
--    Jeden rekord = jedno uruchomienie pipeline klienta.
-- ============================================================

CREATE TABLE IF NOT EXISTS pipeline_runs (
    id              SERIAL PRIMARY KEY,

    client_id       INTEGER REFERENCES clients(id) ON DELETE CASCADE,

    started_at      TIMESTAMP DEFAULT NOW(),
    finished_at     TIMESTAMP,

    status          TEXT DEFAULT 'running',
    error_msg       TEXT
);

-- ============================================================
-- 8. Logi pojedynczych tasków Airflow
--    Np. ingest, scraper_x, matching, report.
-- ============================================================

CREATE TABLE IF NOT EXISTS pipeline_task_runs (
    id                  SERIAL PRIMARY KEY,

    pipeline_run_id     INTEGER REFERENCES pipeline_runs(id) ON DELETE CASCADE,
    client_id           INTEGER REFERENCES clients(id) ON DELETE CASCADE,

    dag_id              TEXT,
    run_id              TEXT,
    task_id             TEXT NOT NULL,

    status              TEXT NOT NULL,

    started_at          TIMESTAMP,
    finished_at         TIMESTAMP,

    log_excerpt         TEXT,
    error_msg           TEXT,

    created_at          TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- 9. Rejestr scraperów
--    To łączy autonomiczny generator z Airflow.
--    Airflow powinien odpalać tylko scrapery ze statusem approved.
-- ============================================================

CREATE TABLE IF NOT EXISTS scraper_registry (
    id              SERIAL PRIMARY KEY,

    client_id       INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    request_id      INTEGER REFERENCES onboarding_requests(id) ON DELETE SET NULL,

    store_slug      TEXT NOT NULL,

    competitor_url  TEXT,
    competitor_name TEXT,

    spider_name     TEXT NOT NULL,
    spider_module   TEXT,
    spider_path     TEXT,

    output_table    TEXT NOT NULL,

    status          TEXT NOT NULL DEFAULT 'generated',

    last_error      TEXT,

    generated_at    TIMESTAMP DEFAULT NOW(),
    approved_by     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    approved_at     TIMESTAMP,

    UNIQUE(client_id, spider_name)
);

-- ============================================================
-- 10. Logi procesu generowania scraperów przez AI generator
--     Tu zapisujesz kroki: sitemap, sample HTML, selector generation itd.
-- ============================================================

CREATE TABLE IF NOT EXISTS scraper_logs (
    id              SERIAL PRIMARY KEY,

    user_id         INTEGER REFERENCES users(id) ON DELETE SET NULL,
    client_id       INTEGER REFERENCES clients(id) ON DELETE CASCADE,
    request_id      INTEGER REFERENCES onboarding_requests(id) ON DELETE CASCADE,
    scraper_id      INTEGER REFERENCES scraper_registry(id) ON DELETE SET NULL,

    url             TEXT,
    step            TEXT NOT NULL,
    status          TEXT NOT NULL,
    message         TEXT,

    created_at      TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- 11. Ogólne błędy aplikacji
--     Panel admina może pokazywać błędy aplikacji, scraperów i Airflow.
-- ============================================================

CREATE TABLE IF NOT EXISTS error_logs (
    id              SERIAL PRIMARY KEY,

    user_id         INTEGER REFERENCES users(id) ON DELETE SET NULL,
    client_id       INTEGER REFERENCES clients(id) ON DELETE CASCADE,

    category        VARCHAR(50) NOT NULL,
    error_code      VARCHAR(100),
    message         TEXT,
    error_type      VARCHAR(50) NOT NULL,

    is_reviewed     BOOLEAN DEFAULT FALSE,

    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at     TIMESTAMP
);

-- ============================================================
-- 12. Indeksy pomocnicze
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_users_client_id
ON users(client_id);

CREATE INDEX IF NOT EXISTS idx_users_status
ON users(status);

CREATE INDEX IF NOT EXISTS idx_onboarding_requests_user_id
ON onboarding_requests(user_id);

CREATE INDEX IF NOT EXISTS idx_onboarding_requests_client_id
ON onboarding_requests(client_id);

CREATE INDEX IF NOT EXISTS idx_onboarding_requests_status
ON onboarding_requests(status);

CREATE INDEX IF NOT EXISTS idx_onboarding_sources_request_id
ON onboarding_sources(request_id);

CREATE INDEX IF NOT EXISTS idx_onboarding_field_mappings_request_id
ON onboarding_field_mappings(request_id);

CREATE INDEX IF NOT EXISTS idx_onboarding_scrape_fields_request_id
ON onboarding_scrape_fields(request_id);

CREATE INDEX IF NOT EXISTS idx_pipeline_runs_client_id
ON pipeline_runs(client_id);

CREATE INDEX IF NOT EXISTS idx_pipeline_task_runs_client_id
ON pipeline_task_runs(client_id);

CREATE INDEX IF NOT EXISTS idx_pipeline_task_runs_pipeline_run_id
ON pipeline_task_runs(pipeline_run_id);

CREATE INDEX IF NOT EXISTS idx_scraper_registry_client_id
ON scraper_registry(client_id);

CREATE INDEX IF NOT EXISTS idx_scraper_registry_request_id
ON scraper_registry(request_id);

CREATE INDEX IF NOT EXISTS idx_scraper_registry_status
ON scraper_registry(status);

CREATE INDEX IF NOT EXISTS idx_scraper_logs_user_id
ON scraper_logs(user_id);

CREATE INDEX IF NOT EXISTS idx_scraper_logs_client_id
ON scraper_logs(client_id);

CREATE INDEX IF NOT EXISTS idx_scraper_logs_request_id
ON scraper_logs(request_id);

CREATE INDEX IF NOT EXISTS idx_error_logs_user_id
ON error_logs(user_id);

CREATE INDEX IF NOT EXISTS idx_error_logs_client_id
ON error_logs(client_id);

CREATE INDEX IF NOT EXISTS idx_error_logs_category
ON error_logs(category);

-- ============================================================
-- 13. Trigger aktualizujący updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_clients_updated_at ON clients;
CREATE TRIGGER trg_clients_updated_at
BEFORE UPDATE ON clients
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_onboarding_requests_updated_at ON onboarding_requests;
CREATE TRIGGER trg_onboarding_requests_updated_at
BEFORE UPDATE ON onboarding_requests
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- 14. DEV SEED
--     To jest tylko do lokalnego developmentu.
--     Produkcyjnie lepiej przenieść to do database/dev_seed.sql.
-- ============================================================

INSERT INTO users (
    username,
    password_hash,
    is_admin,
    client_id,
    status,
    first_name,
    last_name
)
VALUES (
    'admin',
    encode(digest('admin123', 'sha256'), 'hex'),
    TRUE,
    NULL,
    'active',
    'Admin',
    'System'
)
ON CONFLICT (username) DO NOTHING;

INSERT INTO clients (
    name,
    slug,
    store_prefix,
    is_active,
    source_type,
    source_path,
    source_url,
    file_format,
    field_mapping,
    spiders_to_run
)
VALUES (
    'Sklep Testowy',
    'sklep_testowy',
    'sklep_testowy',
    TRUE,
    'file',
    '/opt/airflow/dags/data/moje_produkty.csv',
    NULL,
    'csv',
    '{
        "SKU": "sku",
        "URL": "url",
        "CENA": "price_normal",
        "OPIS": "description",
        "KOLOR": "color",
        "MARKA": "manufacturer",
        "NAZWA": "name",
        "SKLEP": "store",
        "ROZMIAR": "size",
        "ZDJECIE": "image",
        "KATEGORIA": "category",
        "CENA_PROMO": "price_special",
        "DOSTEPNOSC": "availability",
        "DATA_POBRANIA": "date_of_download"
    }'::jsonb,
    ARRAY[]::TEXT[]
)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO users (
    username,
    password_hash,
    is_admin,
    client_id,
    status,
    first_name,
    last_name,
    company_domain,
    competitor_urls
)
VALUES (
    'klient1',
    encode(digest('klient123', 'sha256'), 'hex'),
    FALSE,
    (SELECT id FROM clients WHERE slug = 'sklep_testowy'),
    'active',
    'Klient',
    'Testowy',
    'sklep-testowy.pl',
    '["https://example-competitor.pl"]'::jsonb
)
ON CONFLICT (username) DO NOTHING;

INSERT INTO onboarding_requests (
    user_id,
    client_id,
    requested_store_name,
    requested_store_slug,
    company_domain,
    competitor_urls,
    source_type,
    source_path,
    file_format,
    field_mapping,
    status,
    approved_by,
    approved_at
)
VALUES (
    (SELECT id FROM users WHERE username = 'klient1'),
    (SELECT id FROM clients WHERE slug = 'sklep_testowy'),
    'Sklep Testowy',
    'sklep_testowy',
    'sklep-testowy.pl',
    '["https://example-competitor.pl"]'::jsonb,
    'file',
    '/opt/airflow/dags/data/moje_produkty.csv',
    'csv',
    '{
        "SKU": "sku",
        "URL": "url",
        "CENA": "price_normal",
        "OPIS": "description",
        "KOLOR": "color",
        "MARKA": "manufacturer",
        "NAZWA": "name",
        "SKLEP": "store",
        "ROZMIAR": "size",
        "ZDJECIE": "image",
        "KATEGORIA": "category",
        "CENA_PROMO": "price_special",
        "DOSTEPNOSC": "availability",
        "DATA_POBRANIA": "date_of_download"
    }'::jsonb,
    'approved',
    (SELECT id FROM users WHERE username = 'admin'),
    NOW()
)
ON CONFLICT (user_id, requested_store_name) DO NOTHING;

INSERT INTO onboarding_sources (
    request_id,
    source_kind,
    source_path,
    source_url,
    file_format,
    original_name,
    mime_type
)
VALUES (
    (
        SELECT id
        FROM onboarding_requests
        WHERE requested_store_slug = 'sklep_testowy'
        LIMIT 1
    ),
    'file',
    '/opt/airflow/dags/data/moje_produkty.csv',
    NULL,
    'csv',
    'moje_produkty.csv',
    'text/csv'
)
ON CONFLICT DO NOTHING;

INSERT INTO scraper_registry (
    client_id,
    request_id,
    store_slug,
    competitor_url,
    competitor_name,
    spider_name,
    spider_module,
    spider_path,
    output_table,
    status,
    approved_by,
    approved_at
)
VALUES (
    (SELECT id FROM clients WHERE slug = 'sklep_testowy'),
    (
        SELECT id
        FROM onboarding_requests
        WHERE requested_store_slug = 'sklep_testowy'
        LIMIT 1
    ),
    'sklep_testowy',
    'https://example-competitor.pl',
    'Example Competitor',
    'spider_dummy',
    'spiders.spider_dummy',
    'spiders/spider_dummy.py',
    'sklep_testowy_competitors',
    'approved',
    (SELECT id FROM users WHERE username = 'admin'),
    NOW()
)
ON CONFLICT (client_id, spider_name) DO NOTHING;

UPDATE clients c
SET spiders_to_run = sub.spiders
FROM (
    SELECT
        client_id,
        array_agg(spider_name ORDER BY spider_name) AS spiders
    FROM scraper_registry
    WHERE status = 'approved'
    GROUP BY client_id
) sub
WHERE c.id = sub.client_id;
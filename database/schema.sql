-- database/schema.sql

-- 1. Tabela klientów
CREATE TABLE IF NOT EXISTS clients (
    id                      SERIAL PRIMARY KEY,
    name                    TEXT NOT NULL,
    slug                    TEXT UNIQUE NOT NULL,
    store_prefix            TEXT UNIQUE NOT NULL,
    is_active               BOOLEAN DEFAULT TRUE,
    created_at              TIMESTAMP DEFAULT NOW(),

    source_type             TEXT NOT NULL,
    source_path             TEXT,
    file_format             TEXT,
    field_mapping           JSONB NOT NULL DEFAULT '{}',

    spiders_to_run          TEXT[] DEFAULT ARRAY['Calavado','jmbdesing','pod_pierzyna'],

    match_name_threshold    FLOAT DEFAULT 90.0,
    match_color_threshold   FLOAT DEFAULT 80.0,
    match_maker_threshold   FLOAT DEFAULT 80.0
);

CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    is_admin      BOOLEAN DEFAULT FALSE,
    client_id     INTEGER REFERENCES clients(id) ON DELETE SET NULL
);

-- 3. Logi uruchomień pipeline
CREATE TABLE IF NOT EXISTS pipeline_runs (
    id          SERIAL PRIMARY KEY,
    client_id   INTEGER REFERENCES clients(id) ON DELETE CASCADE,
    started_at  TIMESTAMP DEFAULT NOW(),
    finished_at TIMESTAMP,
    status      TEXT DEFAULT 'running',
    error_msg   TEXT
);

-- 4. Przykładowy superadmin (bez klienta)
INSERT INTO users (username, password_hash, is_admin, client_id)
VALUES (
    'admin',
    encode(sha256('admin123'::bytea), 'hex'),
    TRUE,
    NULL
)
ON CONFLICT (username) DO NOTHING;

-- 5. Przykładowy klient testowy
INSERT INTO clients (
    name, slug, store_prefix, is_active,
    source_type, source_path, file_format,
    field_mapping, spiders_to_run
) VALUES (
    'Sklep Testowy',
    'sklep_testowy',
    'sklep_testowy',
    TRUE,
    'url',
    'https://example.com/produkty.xlsx',
    'xlsx',
    '{
        "SKU":        "sku",
        "NAZWA":      "name",
        "ROZMIAR":    "size",
        "KOLOR":      "color",
        "MARKA":      "manufacturer",
        "CENA":       "price_normal",
        "CENA_PROMO": "price_special",
        "OPIS":       "description"
    }'::jsonb,
    ARRAY['Calavado', 'jmbdesing', 'pod_pierzyna']
)
ON CONFLICT (slug) DO NOTHING;

-- 6. Konto użytkownika dla klienta testowego
INSERT INTO users (username, password_hash, is_admin, client_id)
VALUES (
    'klient1',
    encode(sha256('klient123'::bytea), 'hex'),
    FALSE,
    (SELECT id FROM clients WHERE slug = 'sklep_testowy')
)
ON CONFLICT (username) DO NOTHING;
import os
import psycopg2
from urllib.parse import urlparse
from fastapi import FastAPI, BackgroundTasks
from pydantic import BaseModel
from typing import List
import uvicorn
from dotenv import load_dotenv, find_dotenv

load_dotenv(find_dotenv())

# --- Importy Twojego silnika AI ---
from core.sitemap_finder import find_sitemap
from core.sitemap_processor import get_product_links
from core.odchudzacz import build_llm_dataset, wybierz_pewne_probki
from core.prompt import generate_scraper_from_html
from core.spider_builder import wygeneruj_plik_spidera

app = FastAPI(title="Scraper Generator API")

# --- Konfiguracja bazy i ścieżek ---
DB_CONFIG = {
    "host": os.environ.get("APP_DB_HOST", "localhost"),
    "port": int(os.environ.get("APP_DB_PORT", 5434)),
    "dbname": os.environ.get("APP_DB_NAME", "ecommerce_data"),
    "user": os.environ.get("APP_DB_USER", "postgres"),
    "password": os.environ.get("APP_DB_PASSWORD", "postgres"),
}

# Definiujemy ścieżkę do projektu kolegi.
# Zmienna środowiskowa SPIDERS_DIR przyda się później w Dockerze.
SPIDERS_OUTPUT_DIR = os.environ.get("SPIDERS_DIR", "../ecommerce_price_comparer/spiders")


class GenerationRequest(BaseModel):
    request_id: int
    company_name: str  # NOWOŚĆ: Odbieramy nazwę firmy klienta
    urls: List[str]


def pobierz_nazwe_sklepu(url):
    domain = urlparse(url).netloc
    name = domain.replace('www.', '').split('.')[0]
    return name


def przygotuj_srodowisko_klienta(nazwa_firmy: str):
    """Tworzy bezpieczny folder dla klienta wewnątrz projektu Scrapy."""
    # Oczyszczamy nazwę firmy z dziwnych znaków i spacji, by była poprawną nazwą w Pythonie
    bezpieczna_nazwa = "".join(c if c.isalnum() else "_" for c in nazwa_firmy).lower()
    katalog_klienta = os.path.join(SPIDERS_OUTPUT_DIR, bezpieczna_nazwa)

    # 1. Tworzymy folder
    os.makedirs(katalog_klienta, exist_ok=True)

    # 2. Tworzymy plik __init__.py, bez którego Scrapy nie zauważy pająków!
    init_path = os.path.join(katalog_klienta, "__init__.py")
    if not os.path.exists(init_path):
        open(init_path, 'a').close()

    return katalog_klienta


def uruchom_autonomiczny_potok(url_sklepu, nazwa_firmy, docelowy_limit_scrapowania=None):
    nazwa_sklepu = pobierz_nazwe_sklepu(url_sklepu)
    print(f"\nURUCHAMIAM AI DLA SKLEPU: {nazwa_sklepu.upper()} (Klient: {nazwa_firmy})")

    # KROK 0-2: Sitemapy i linki
    znalezione_sitemapy = find_sitemap(url_sklepu)
    if not znalezione_sitemapy:
        print(f"[!] Błąd: Nie znaleziono sitemapy dla {url_sklepu}.")
        return False

    czyste_linki = get_product_links(znalezione_sitemapy)
    if not czyste_linki:
        print(f"[!] Błąd: Brak linków dla {url_sklepu}.")
        return False

    linki_do_pracy = list(czyste_linki)[:docelowy_limit_scrapowania] if docelowy_limit_scrapowania else list(
        czyste_linki)

    # Tymczasowe pliki robocze AI (mogą zostać w data_output)
    os.makedirs("data_output", exist_ok=True)
    probki_dla_llm = wybierz_pewne_probki(set(linki_do_pracy), ilosc=3)
    plik_datasetu = "data_output/dataset_dla_llm.txt"
    build_llm_dataset(probki_dla_llm)

    # Generowanie Mapy
    print("[AI] Generowanie mapy CSS...")
    generate_scraper_from_html(plik_datasetu, "data_output/selectors_map.json")

    # KROK 6: Zapis Spidera PROSTO DO FOLDERU KLIENTA
    katalog_klienta = przygotuj_srodowisko_klienta(nazwa_firmy)
    plik_spidera = os.path.join(katalog_klienta, f"{nazwa_sklepu}_spider.py")

    # Przekazujemy czyste_linki, aby Twój generator wpisał je jako string w pliku .py
    wygeneruj_plik_spidera("data_output/selectors_map.json", plik_spidera, nazwa_sklepu, linki=czyste_linki)
    print(f"-> Sukces! Pająk zapisany bezpośrednio na produkcję: {plik_spidera}")

    return True


def procesuj_wniosek_w_tle(request_id: int, company_name: str, urls: List[str]):
    print(f"\n[WORKER] Rozpoczynam wniosek #{request_id} dla firmy: {company_name}")
    conn = None

    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = True
        cur = conn.cursor()

        cur.execute("UPDATE registration_requests SET status = 'analyzing' WHERE id = %s", (request_id,))

        for url in urls:
            try:
                uruchom_autonomiczny_potok(url, company_name, docelowy_limit_scrapowania=10)
            except Exception as e:
                print(f"[!] Błąd krytyczny dla {url}: {e}")

        cur.execute("UPDATE registration_requests SET status = 'completed' WHERE id = %s", (request_id,))
        print(f"\n[WORKER] Koniec potoku. Pliki dla '{company_name}' dostarczone.")

    except Exception as e:
        print(f"\n[WORKER] Błąd bazy danych: {e}")
    finally:
        if conn:
            cur.close()
            conn.close()


@app.post("/api/check")
def trigger_generation(payload: GenerationRequest, background_tasks: BackgroundTasks):
    # Przekazujemy company_name do workera
    background_tasks.add_task(procesuj_wniosek_w_tle, payload.request_id, payload.company_name, payload.urls)

    return {
        "ok": True,
        "message": f"Wniosek #{payload.request_id} przyjęty. Proces AI wystartował w tle."
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
# Włączamy nasz walidator i formatnik
ITEM_PIPELINES = {
   'autonomiczny_scraper.pipelines.ValidationAndFormattingPipeline': 300,
}

# Ustawienia bezpieczeństwa
ROBOTSTXT_OBEY = False
DOWNLOAD_DELAY = 1.5 # Przerwa między requestami (zastępuje time.sleep())
CONCURRENT_REQUESTS = 4 # Ile jednoczesnych połączeń (Asynchroniczność!)

# Ukrywamy się jako zwykła przeglądarka
USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36'

# Konfiguracja eksportu do CSV (Zastępuje Pandas!)
FEEDS = {
    'data_output/produkty_baza.csv': {
        'format': 'csv',
        'encoding': 'utf-8-sig',
        'store_empty': False,
        'overwrite': True,
    },
}

# Żeby logi w konsoli były czytelniejsze
LOG_LEVEL = 'INFO'
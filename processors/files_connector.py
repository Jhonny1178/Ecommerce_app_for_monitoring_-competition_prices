import os
from dotenv import load_dotenv
import pandas as pd
from rapidfuzz import fuzz
from sqlalchemy import create_engine

load_dotenv()
db_password = os.getenv("DB_PASSWORD")


class MultiTenantReportGenerator:

    def __init__(self, config: dict):

        db_url = (
            f"postgresql://postgres:{db_password}@localhost:5432/ecommerce_data"
        )
        self.engine = create_engine(db_url)

        self.client_table = config.get("client_table")
        self.competitor_table = config.get("competitor_table")
        self.target_table_name = config.get("target_table")

        self.competitor_stores = config.get("competitor_stores", [])

    def generate_report(self, name_threshold, color_threshold, maker_threshold):
        print(
            f"\n[MATCHING] Rozpoczynam dopasowywanie produktów dla tabeli: {self.client_table}"
        )
        print(
            f"[MATCHING] Pobieranie danych z dedykowanej tabeli konkurencji: {self.competitor_table}"
        )

        # 1. Dynamiczne pobieranie danych klienta
        query_client = f"""
            SELECT sku, name, price_normal, url, manufacturer, size, color 
            FROM {self.client_table} 
            WHERE manufacturer IS NOT NULL 
              AND size IS NOT NULL;
        """
        client_df = pd.read_sql(query_client, self.engine)

        # 2. Dynamiczne pobieranie danych konkurencji z jej dedykowanej tabeli
        query_comp = f"""
            SELECT sku, name, store, price_normal, url, manufacturer, size, color 
            FROM {self.competitor_table} 
            WHERE manufacturer IS NOT NULL 
              AND size IS NOT NULL;
        """
        comp_df = pd.read_sql(query_comp, self.engine)

        print(f"[MATCHING] Liczba produktów klienta: {len(client_df)}")
        print(f"[MATCHING] Liczba produktów konkurencji: {len(comp_df)}")

        if client_df.empty or comp_df.empty:
            print(
                f"[MATCHING] Pomijam generowanie raportu - jedna z tabel jest pusta."
            )
            return None

        print("[MATCHING] Normalizacja danych do Smart Blockingu (ROZMIAR)...")
        for frame in [client_df, comp_df]:
            frame["block_size"] = (
                frame["size"].astype(str).str.lower().str.replace(" ", "")
            )

        matches_list = []

        print(
            f"[MATCHING] Szukanie dopasowań przy progach (Name: {name_threshold}%, Color: {color_threshold}%, Maker: {maker_threshold}%)..."
        )
        for idx, client_item in client_df.iterrows():

            base_record = {
                "client_sku": client_item["sku"],
                "client_name": client_item["name"],
                "client_price": client_item["price_normal"],
                "client_url": client_item["url"],
                "manufacturer": client_item["manufacturer"],
                "size": client_item["size"],
                "color": client_item["color"],
            }

            # Dynamiczne inicjalizowanie pustych kolumn dla sklepów konkurencji tego konkretnego klienta
            for comp_store in self.competitor_stores:
                base_record[f"{comp_store}_price"] = None
                base_record[f"{comp_store}_url"] = None
                base_record[f"{comp_store}_name"] = None

            candidates = comp_df[
                comp_df["block_size"] == client_item["block_size"]
            ]

            if not candidates.empty:
                for _, comp_item in candidates.iterrows():

                    name_score = fuzz.token_set_ratio(
                        str(client_item["name"]), str(comp_item["name"])
                    )
                    color_score = fuzz.token_set_ratio(
                        str(client_item["color"]), str(comp_item["color"])
                    )
                    maker_score = fuzz.token_set_ratio(
                        str(client_item["manufacturer"]),
                        str(comp_item["manufacturer"]),
                    )

                    if (
                        name_score >= name_threshold
                        and color_score >= color_threshold
                        and maker_score >= maker_threshold
                    ):
                        store = comp_item["store"]

                        if f"{store}_price" in base_record:
                            base_record[f"{store}_price"] = comp_item[
                                "price_normal"
                            ]
                            base_record[f"{store}_url"] = comp_item["url"]
                            base_record[f"{store}_name"] = comp_item["name"]

            matches_list.append(base_record)

        print("[MATCHING] Generowanie płaskiej tabeli wynikowej...")
        final_df = pd.DataFrame(matches_list)

        print(
            f"[MATCHING] Zapisywanie {len(final_df)} wierszy do tabeli analizy '{self.target_table_name}'..."
        )
        final_df.to_sql(
            self.target_table_name, self.engine, if_exists="replace", index=False
        )

        return final_df


# =====================================================================
# SYSTEM STEROWANIA: PĘTLA ORKIESTRATORA (Obsługa wielu klientów)
# =====================================================================
if __name__ == "__main__":

    # Wyobraź sobie, że tę listę konfiguracji pobierasz jednym zapytaniem SQL z tabeli metadanych rano
    harmonogram_poranny = [
        {
            "client_table": "sklep1",  # Tabela naszej pierwszej klientki
            "competitor_table": "sklep1_competitors",  # Dedykowana tabela z jej scraperów
            "target_table": "sklep1_report_analysis",  # Wynikowy raport dla niej
            "competitor_stores": ["podpierzyna", "calavado", "jmbdesing"],
        },
        {
            "client_table": "sklep2_meble",  # Inny klient (np. z branży meblarskiej)
            "competitor_table": "sklep2_meble_competitors",  # Tabela konkurencji dla mebli
            "target_table": "sklep2_meble_report_analysis",  # Wynikowy raport meblowy
            "competitor_stores": ["ikea", "brw", "agatameble"],
        },
    ]

    # Uruchomienie pętli dla wszystkich aktywnych klientów z bazy
    for klient_config in harmonogram_poranny:
        generator = MultiTenantReportGenerator(config=klient_config)
        result_df = generator.generate_report(
            name_threshold=90.0, color_threshold=80.0, maker_threshold=80.0
        )
        print("-" * 60)

    print("\n✅ Wszystkie dedykowane raporty zostały pomyślnie wygenerowane.")
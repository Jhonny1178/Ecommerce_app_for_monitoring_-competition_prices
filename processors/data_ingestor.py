import os
import requests
import xml.etree.ElementTree as ET
import psycopg2
import psycopg2.extras
import pandas as pd
from dotenv import load_dotenv
from datetime import datetime
from ecommerce_price_comparer.utilities.data_utility import DataCleaner
from ecommerce_price_comparer.items import ProductData
load_dotenv()
db_password = os.getenv("DB_PASSWORD")
client_to_db_map = {
    "id": "sku",
    "title": "name",
    "size": "size",
    "color": "color",
    "brand": "manufacturer",
    "price": "price_normal",
    "sale_price": "price_special",
    "product_type": "category",
    "description": "description",
    "availability": "availability",
    "image_link": "image",
    "link": "url"
}
class FastXmlIngestor:
    def __init__(self, table_name):
        self.table_name = table_name
        self.store_name = "lambfield"


        self.conn = psycopg2.connect(
            host='localhost',  # zmien na 'host.docker.internal' jeśli odpalasz w dockerze
            user='postgres',
            password=db_password,
            database="ecommerce_data",
        )
        self.cur = self.conn.cursor()
        self._create_table()

    def _create_table(self):
        query = f"""
            CREATE TABLE IF NOT EXISTS {self.table_name} (
            id SERIAL PRIMARY KEY,
            sku TEXT UNIQUE,
            name TEXT,
            size VARCHAR(20),
            color VARCHAR(30),
            manufacturer VARCHAR(50),
            category VARCHAR(50),
            price_normal FLOAT,
            price_special FLOAT,
            store VARCHAR(30),
            availability VARCHAR(50),
            date_of_download TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            url TEXT,
            image TEXT,
            description TEXT
            );
        """
        self.cur.execute(query)
        self.conn.commit()
        print(f"Baza danych gotowa. Tabela: {self.table_name}\n")

    def apply_data_cleaner(self, raw_item):
        to_lowercase_list = ['color', 'availability', 'manufacturer', 'name', 'size']
        to_normalize_prize = ['price_normal', 'price_special']

        clean_item = dict(raw_item)
        for category in clean_item.keys():
            if category != 'description':
                value = clean_item.get(category)
                if value is not None:
                    clean_item[category] = DataCleaner.to_strip(value)
        for category in to_lowercase_list:
            value = clean_item.get(category)
            if value is not None:
                clean_item[category] = DataCleaner.to_lowercase(value)
        for price in to_normalize_prize:
            value = clean_item.get(price)
            if value is not None:
                clean_item[price] = DataCleaner.clean_price(value)

        clean_item['availability'] = DataCleaner.standardize_availability_link(clean_item.get('availability'))
        clean_item['name'] = DataCleaner.standardize_name(clean_item.get('name'), clean_item.get('color'),
                                                          clean_item.get('size'), clean_item.get('manufacturer'))
        clean_item['size'] = DataCleaner.standardize_size(clean_item.get('size'))
        clean_item['color'] = DataCleaner.standardize_color(clean_item.get('color'))
        clean_item['sku'] = DataCleaner.sku_normalize(clean_item.get('name'), clean_item.get('color'),
                                                      clean_item.get('size'), clean_item.get('manufacturer'))
        clean_item['description'] = DataCleaner.clean_description(clean_item.get('description'))
        clean_item['category'] = DataCleaner.clean_category(clean_item.get('category'))
        clean_item['date_of_download'] = datetime.now().isoformat()

        return clean_item

    def process_and_load(self, url):
        print(f"Rozpoczynam strumieniowe pobieranie i ładowanie: {url}")

        headers = {'User-Agent': 'Mozilla/5.0'}
        response = requests.get(url, headers=headers, stream=True)
        response.raw.decode_content = True

        events = ET.iterparse(response.raw, events=("end",))
        batch = []
        total_processed = 0

        for event, elem in events:
            tag_name = elem.tag.split('}')[-1]

            if tag_name == "item":
                product_data = ProductData()
                product_data['store'] = self.store_name

                for internal_key in client_to_db_map.values():
                    if internal_key not in product_data:
                        product_data[internal_key] = None
                for child in elem:
                    child_tag = child.tag.split('}')[-1]
                    if child_tag in client_to_db_map:
                        internal_key = client_to_db_map[child_tag]

                        if internal_key == "category" and product_data.get("category") is not None:
                            continue

                        product_data[internal_key] = child.text

                cleaned_item = self.apply_data_cleaner(product_data)

                tuple_data = (
                    cleaned_item.get('sku'), cleaned_item.get('name'), cleaned_item.get('size'),
                    cleaned_item.get('color'), cleaned_item.get('manufacturer'), cleaned_item.get('category'),
                    cleaned_item.get('price_normal'), cleaned_item.get('price_special'), cleaned_item.get('store'),
                    cleaned_item.get('availability'), cleaned_item.get('date_of_download'), cleaned_item.get('url'),
                    cleaned_item.get('image'), cleaned_item.get('description')
                )

                if cleaned_item.get('sku'):
                    batch.append(tuple_data)
                    total_processed += 1

                elem.clear()

                if len(batch) >= 500:
                    self._save_batch(batch)
                    batch = []
                    print(f"-> Zapisano do bazy: {total_processed} produktów...")

        if batch:
            self._save_batch(batch)
            print(f"-> Zapisano do bazy: {total_processed} produktów...")

        print(
            f"\nWczytano łącznie {total_processed} wyczyszczonych produktów do tabeli {self.table_name}.")

    def _save_batch(self, batch_data):
        query = f"""
            INSERT INTO {self.table_name} (
                sku, name, size, color, manufacturer, category, 
                price_normal, price_special, store, availability, 
                date_of_download, url, image, description
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
            ON CONFLICT (sku) DO UPDATE SET
                price_normal = EXCLUDED.price_normal,
                price_special = EXCLUDED.price_special,
                availability = EXCLUDED.availability,
                date_of_download = EXCLUDED.date_of_download;
        """
        try:
            psycopg2.extras.execute_batch(self.cur, query, batch_data)
            self.conn.commit()
        except Exception as e:
            self.conn.rollback()
            print(f"Błąd zapisu paczki: {e}")

    def __del__(self):
        if hasattr(self, 'cur') and self.cur:
            self.cur.close()
        if hasattr(self, 'conn') and self.conn:
            self.conn.close()


if __name__ == '__main__':
    url_feed = "https://lambfield.com/data/export/feed10000_10e8959b59a79f3367f2f493.xml"

    ingestor = FastXmlIngestor(table_name='client_products')
    ingestor.process_and_load(url_feed)
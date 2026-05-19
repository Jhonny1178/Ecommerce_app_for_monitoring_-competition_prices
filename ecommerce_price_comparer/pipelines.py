from itemadapter import ItemAdapter
import psycopg2
import psycopg2.extras
import os
from dotenv import load_dotenv
from utilities.data_utility import DataCleaner
load_dotenv()
class EcommercePriceComparerPipeline:
    def __init__(self):
        self.to_lowercase_list = ['color','category','availability','manufacturer','name','size']
        self.to_normalize_prize =['price_normal','price_special']
    def process_item(self, item, spider):
        adapter = ItemAdapter(item)
        #striping all field besides description
        for category in adapter.field_names():
            if category != 'description':
                value = adapter.get(category)
                value = DataCleaner.to_strip(value,spider)
                adapter[category] = value
        for category in self.to_lowercase_list:
            value = adapter.get(category)
            value = DataCleaner.to_lowercase(value,spider)
            adapter[category] = value
        for price in self.to_normalize_prize:
            value = adapter.get(price)
            value = DataCleaner.clean_price(value)
            adapter[price] = value

        adapter['availability'] = DataCleaner.standardize_availability_link(adapter.get('availability'))
        adapter['name'] = DataCleaner.standardize_name(adapter.get('name'),adapter.get('color'),adapter.get('size'),adapter.get('manufacturer'))
        adapter['size'] = DataCleaner.standardize_size(adapter.get('size'))
        adapter['color'] = DataCleaner.standardize_color(adapter.get('color'))
        adapter['sku'] = DataCleaner.sku_normalize(adapter.get('name'),adapter.get('color'),adapter.get('size'),adapter.get('manufacturer'))
        adapter['description'] = DataCleaner.clean_description(adapter.get('description'))
        return item
class SaveToPostgresSQLPipeline:
    def __init__(self):
        self.conn = psycopg2.connect(
            host=os.getenv("DB_HOST"),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD"),
            database=os.getenv("DB_NAME"),
        )
        self.cur = self.conn.cursor()
        self.items_buffer = []
        self.batch_size = 100

    def open_spider(self, spider):
        self.table_name = getattr(spider, 'target_table', 'default_competitors')
        self.history_table_name = f"{self.table_name}_history"

        spider.logger.info(
            f"[PIPELINE] Uruchomiono zrzut do tabeli: {self.table_name} oraz historii: {self.history_table_name}")

        try:
            # Pakujemy tworzenie struktur w jeden try/except
            self.cur.execute(f"""
                CREATE TABLE IF NOT EXISTS {self.table_name} (
                    id SERIAL PRIMARY KEY,
                    sku TEXT UNIQUE,
                    name TEXT,
                    size VARCHAR(50),
                    color VARCHAR(50),
                    manufacturer VARCHAR(50),
                    category VARCHAR(100),
                    price_normal FLOAT,
                    price_special FLOAT,
                    store VARCHAR(50),
                    availability VARCHAR(50),
                    date_of_download TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    url TEXT,
                    image TEXT,
                    description TEXT
                );
            """)

            self.cur.execute(f"""
                CREATE TABLE IF NOT EXISTS {self.history_table_name} (
                    id SERIAL PRIMARY KEY,
                    sku TEXT,
                    store VARCHAR(50),
                    price_normal_old FLOAT,
                    price_normal_new FLOAT,
                    price_special_old FLOAT,
                    price_special_new FLOAT,
                    valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    valid_to TIMESTAMP,
                    is_current BOOLEAN DEFAULT TRUE
                );
            """)

            self.cur.execute("""
                CREATE OR REPLACE FUNCTION log_price_changes()
                RETURNS TRIGGER AS $$
                DECLARE
                    history_table TEXT := TG_ARGV[0];
                    query TEXT;
                BEGIN
                    IF (OLD.price_normal IS DISTINCT FROM NEW.price_normal) OR 
                       (OLD.price_special IS DISTINCT FROM NEW.price_special) THEN
                        query := format('UPDATE %I SET valid_to = CURRENT_TIMESTAMP, is_current = FALSE WHERE sku = $1 AND store = $2 AND is_current = TRUE', history_table);
                        EXECUTE query USING OLD.sku, OLD.store;
                        query := format('INSERT INTO %I (sku, store, price_normal_old, price_normal_new, price_special_old, price_special_new, valid_from, is_current) VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP, TRUE)', history_table);
                        EXECUTE query USING OLD.sku, OLD.store, OLD.price_normal, NEW.price_normal, OLD.price_special, NEW.price_special;
                    END IF;
                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql;
            """)

            self.cur.execute(f"DROP TRIGGER IF EXISTS trigger_price_history ON {self.table_name};")
            self.cur.execute(f"""
                CREATE TRIGGER trigger_price_history
                AFTER UPDATE ON {self.table_name}
                FOR EACH ROW
                EXECUTE FUNCTION log_price_changes('{self.history_table_name}');
            """)
            self.conn.commit()

        except psycopg2.errors.UniqueViolation:
            # Jeśli inny pająk właśnie założył tabelę mikrosekundę wcześniej, wycofujemy minitransakcję i lecimy dalej
            self.conn.rollback()
            spider.logger.info(f"[PIPELINE] Tabela {self.table_name} została już utworzona przez inny proces.")

    def process_item(self, item, spider):

        # Krotka musi idealnie pasować do kolejności kolumn w zapytaniu INSERT
        tuple_data = (
            item.get('sku'), item.get('name'), item.get('size'),
            item.get('color'), item.get('manufacturer'), item.get('category'),
            item.get('price_normal'), item.get('price_special'), item.get('store'),
            item.get('availability'), item.get('date_of_download'),
            item.get('url'), item.get('image'), item.get('description')
        )

        if item.get('sku'):
            self.items_buffer.append(tuple_data)

        # Gdy bufor ma >= 100 sztuk, ładujemy paczkę do bazy
        if len(self.items_buffer) >= self.batch_size:
            self._flush_buffer(spider)

        return item

    def _flush_buffer(self, spider):
        if not self.items_buffer:
            return

        # Używamy UPSERT: Wstawiamy nowy produkt LUB aktualizujemy jeśli SKU już istnieje.
        # Właśnie ta aktualizacja (UPDATE) uruchomi naszego Triggera historycznego!
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
            psycopg2.extras.execute_batch(self.cur, query, self.items_buffer)
            self.conn.commit()
            spider.logger.debug(f"[DATABASE] Wrzucono paczkę: {len(self.items_buffer)} produktów.")
        except Exception as e:
            self.conn.rollback()
            spider.logger.error(f"[DATABASE ERROR] Błąd zapisu paczki: {e}")
        finally:
            self.items_buffer.clear()

    def close_spider(self, spider):
        self._flush_buffer(spider)
        self.cur.close()
        self.conn.close()



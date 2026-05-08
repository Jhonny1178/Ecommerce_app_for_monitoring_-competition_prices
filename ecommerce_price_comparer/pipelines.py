from itemadapter import ItemAdapter
import psycopg2
import os
from dotenv import load_dotenv
from utilities.data_utility import DataCleaner
load_dotenv()
db_password = os.getenv("DB_PASSWORD")
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
            host='host.docker.internal',
            user='postgres',
            password=db_password,
            database="ecommerce_data",
        )
        self.cur = self.conn.cursor()
        self.cur.execute("""
            CREATE TABLE IF NOT EXISTS productsone (
            id SERIAL PRIMARY KEY,
            sku VARCHAR(100) UNIQUE,
            name TEXT,
            size VARCHAR(20),
            color VARCHAR(30),
            manufacturer VARCHAR(50),
            category VARCHAR(50),
            price_normal FLOAT,
            price_special FLOAT,
            store VARCHAR(30),
            availability VARCHAR(20),
            date_of_download TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            url TEXT,
            image TEXT,
            description TEXT
            );
        """
        )
        self.conn.commit()
        print("Table crated")

    def process_item(self, item, spider):
        try:
            self.cur.execute("""
            insert into productsone (
            sku,
            name,
            size,
            color,
            manufacturer,
            category,
            price_normal,
            price_special,
            store,
            availability,
            date_of_download,
            url,
            image,
            description
            ) values (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,%s
            )
            """, (
                item['sku'],
                item['name'],
                item['size'],
                item['color'],
                item['manufacturer'],
                item['category'],
                item['price_normal'],
                item['price_special'],
                item['store'],
                item['availability'],
                item['date_of_download'],
                item['url'],
                item['image'],
                item['description']
            ))
            self.conn.commit()
        except Exception as e:
            self.conn.rollback()
            spider.logger.error(f"Bład zapisu do bazy pod tytułem: {e}")
        return item
    def close_spider(self, spider):
        self.cur.close()
        self.conn.close()



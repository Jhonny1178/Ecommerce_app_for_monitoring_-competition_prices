# Define your item pipelines here
#
# Don't forget to add your pipeline to the ITEM_PIPELINES setting
# See: https://docs.scrapy.org/en/latest/topics/item-pipeline.html


# useful for handling different item types with a single interface
from itemadapter import ItemAdapter
import re
import psycopg2


class EcommercePriceComparerPipeline:
    def process_item(self, item, spider):
        adapter = ItemAdapter(item)
        field_names = adapter.field_names()
        # Striping
        for category in field_names:
            value = adapter.get(category)
            if value:
                if category != 'description':
                    value = adapter.get(category)
                    adapter[category] = value.strip()
            else:
                adapter[category] = None

        # loweracase
        to_lower = ['color','category','availability','manufacturer','name']
        for category in to_lower:
            value = adapter.get(category)
            if value:
                adapter[category] = value.lower()
            else:
                adapter[category] = None

        #price_format
        to_reg_price=['price_normal','price_special']
        for category in to_reg_price:
            price = adapter.get(category)
            if price:
                price = re.sub(r'[^0-9,]', '', price).replace(",", ".")
                adapter[category] = float(price)
            else:
                adapter[category] = None
        #availability
        to_shorten_avb = ['availability']
        for category in to_shorten_avb:
            value = adapter.get(category)
            if value:
                adapter[category] = value.replace("http://schema.org/", "")
            else:
                adapter[category] = None


        #name regulation
        to_reg_name = ['name']
        for category in to_reg_name:
            name = adapter.get(category)


            if name:
                if adapter['size'] and adapter['color']:
                    adapter[category] = name.replace(adapter['size'],"").replace(adapter['color'],"").strip()
                elif adapter['size']:
                    adapter[category] = name.replace(adapter['size'], "").strip()
                elif adapter['color']:
                    adapter[category] = name.replace(adapter['color'],"").strip()
                else:
                    adapter[category] = name.strip()
            else:
                adapter[category] = None


        # color
        color = ['color']
        junk_phrases = ['pościel utrzymana w', 'tonacji', 'tonacja', 'z pięknym subtelnym połyskiem', 'delikatna',
                        'pościel utrzymana jest w','naturalna']
        for category in color:
            value = adapter.get(category)
            if value:
                for phrase in junk_phrases:
                    value = value.replace(phrase, "")
                    value = value.strip()
                    adapter[category] = str(value.strip())
                if value[-2:]=="ej":
                    if value[-3]=="i":
                        value = value[0:len(value) - 2]
                        adapter[category] = value
                    else:
                        value = value[0:len(value)-2]+"y"
                        adapter[category] = value
                else:
                    if value[-1]=="a":
                        value = value[0:len(value) - 1] + "y"
                        adapter[category] = value
                adapter['sku'] = adapter['sku'] + "-" + adapter['color']
            else:
                adapter[category] = None




        return item
class SaveToPostgresSQLPipeline:
    def __init__(self):
        self.conn = psycopg2.connect(
            host="localhost",
            user='spiders_admin',
            password='PAssword!',
            database="ecommerce_data",
        )
        self.cur = self.conn.cursor()
        self.cur.execute("""
            CREATE TABLE IF NOT EXISTS Products (
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
    def process_item(self, item, spider):
        try:
            self.cur.execute("""
            insert into Products (
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


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
        to_lower = ['color','category','availability','manufacturer','name','size']
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
                price = re.sub(r'[^0-9,.]', '', price).replace(",", ".").replace(" ", "")
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

        #sku
        sku_is_none = ['sku']
        for category in sku_is_none:
            sku = adapter.get(category)
            if sku is None:
                if adapter['name'] and adapter['color'] and adapter['size']:
                    adapter['sku'] = adapter['name'] + "-" + adapter['color'] + "-" + adapter['size']
                elif adapter['name'] and adapter['color']:
                    adapter['sku'] = adapter['name'] + "-" + adapter['color']
                elif adapter['name'] and adapter['size']:
                    adapter['sku'] = adapter['name'] + "-" + adapter['size']
                elif adapter['color'] and adapter['size']:
                    adapter['sku'] = adapter['color'] + "-" + adapter['size']

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
        #size regulation
        to_reg_size = ['size']
        for size in to_reg_size:
            size = adapter.get(size)
            size = str(size).strip().lower()
            if '⌀' in size or 'śr.' in size:
                match = re.search(r'(\d+)', size)
                if match:
                    size = match.group(1)

            size_map = {
                'mała': 'S',
                'średnia': 'M',
                'duża': 'L',
                'pokrowiec tradycyjny': 'uniwersalny',

            }

            standardized = size_map.get(size.lower(), size)
            adapter['size'] = standardized




        # color
        color = ['color']
        junk_phrases = ['pościel utrzymana w', 'tonacji', 'tonacja', 'z pięknym subtelnym połyskiem', 'delikatna',
                        'pościel utrzymana jest w','naturalna', 'odcienie']
        color_map = {
            'niebieski': ['niebieski', 'turkus', 'turquesa', 'azul', 'denim', 'morski', 'blue', 'sky'],
            'szary': ['szary', 'szarości', 'antracyt', 'anthracit', 'silver', 'srebrny', 'grey', 'gray', 'plata',
                      'grafit','szarej'],
            'beżowy': ['beż', 'beżu', 'natural', 'crudo', 'piaskowy', 'sand', 'taupe', 'oat', 'linen', 'cream',
                       'kremowy','kremowej'],
            'biały': ['biały', 'bieli', 'white', 'blanco', 'ivory','białej'],
            'czarny': ['czarny', 'czerni', 'black', 'negro','czarnej'],
            'zielony': ['zielony', 'zieleni', 'green', 'verde', 'oliwka', 'olive', 'bottle','zielonej'],
            'żółty': ['żółty', 'żółtego', 'yellow', 'gold', 'oro', 'mostaza', 'ginkgo','żółtej'],
            'czerwony': ['czerwony', 'czerwieni', 'red', 'rojo', 'terracota','czerwonej'],
            'różowy': ['różowy', 'różu', 'rose', 'pink', 'nude', 'caldera','różowej'],
            'fioletowy': ['fiolet', 'fioletu', 'lila', 'lilac', 'violet', 'purple','fioletowej'],
            'brązowy': ['brąz', 'brązu', 'brown', 'marron', 'caffe', 'chocolate','brązowej'],
            'wielokolorowy': ['wielokolorowy', 'multicolor', 'mix','wielokolorowej'],
            'bordowy' : ['bordowa','bordowej']
        }
        for category in color:
            value = adapter.get(category)
            if value:
                for phrase in junk_phrases:
                    value = value.strip().lower()
                    value = value.replace(phrase, "")
                    value = value.strip()

                found_standard = None
                for standard, keywords in color_map.items():
                    if any(word in value for word in keywords):
                        found_standard = standard
                        break
                if found_standard:
                    adapter['color'] = found_standard
                else:
                    adapter['color'] = value

        return item
class SaveToPostgresSQLPipeline:
    def __init__(self):
        self.conn = psycopg2.connect(
            host='localhost',
            user='postgres',
            password='***',
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



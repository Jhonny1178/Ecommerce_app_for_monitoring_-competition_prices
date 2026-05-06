from itemadapter import ItemAdapter
import re
import psycopg2
from scrapy.utils import spider
import os
from dotenv import load_dotenv
load_dotenv()
db_password = os.getenv("DB_PASSWORD")
class DataCleaner:
    @staticmethod
    def to_lowercase(value, spider=None):
        if not value:
            return None
        try:
            return value.lower()
        except AttributeError:
            if spider:
                spider.logger.warning(f"Error with lowercasing: {value}")
            #mozna spróbować robic str(value).lower() ale narazie zostawie tak
            return value

    @staticmethod
    def to_strip(value,spider=None):
        if not value:
            return None
        try:
            return value.strip()
        except AttributeError:
            if spider:
                spider.logger.warning(f"Error with striping: {value}")
            return value
    @staticmethod
    def standardize_availability_link(link):
        if not link:
            return None
        return link.replace("http://schema.org/", "")
    @staticmethod
    def clean_price(price):
        if not price:
            return None
        price_str = str(price).strip()
        last_comma = price_str.rfind(',')
        last_dot = price_str.rfind('.')
        if last_comma > last_dot:
            price_str = price_str.replace('.', '').replace(',', '.')
        else:

            price_str = price_str.replace(',', '')

        price = re.sub(r'[^0-9.]', '', str(price_str))
        try:
            return float(price)
        except ValueError:
            return None
    @staticmethod
    def sku_normalize(name, color , size, manufacturer):
        parts_of_sku = [name, color , size, manufacturer]
        #moze dodać strip i lower ale raczej nie bo bedzie robione po nich

        validate_parts = [str("-".join(part.replace("-","").split())).strip() for part in parts_of_sku if part]
        sku = "-".join(validate_parts)
        if not sku:
            return None
        return sku
    @staticmethod
    def standardize_color(color, color_map , junk_phrases):
            if not color:
                return None
            for phrase in junk_phrases:
                color = color.replace(phrase, "")
                color = color.strip()
            for standard, keywords in color_map.items():
                if any(word in color for word in keywords):
                    return standard
            return color
    @staticmethod
    def standardize_name(name, color, size,manufacturer):
        if not name:
            return None
        to_clean_from_name = [size , color , manufacturer]
        for clean_part in to_clean_from_name:
            if clean_part:
                name = name.replace(str(clean_part), "")
        #unikamy podwojnych spacji przy usunieciach kilku
        return " ".join(name.split()).strip()
    @staticmethod
    def standardize_size(size, size_map):
        if not size:
            return None
        size_str = str(size).strip().lower()
        if '⌀' in size_str or 'śr.' in size_str:
            match = re.search(r'(\d+)', size_str)
            if match:
                return match.group(1)
        size_norm = re.sub(r'[^0-9x]', '', size_str)
        if 'x' in size_norm and any(char.isdigit() for char in size_norm):
            return size_norm
        return size_map.get(size_str, size_str)

    @staticmethod
    def clean_description(description):
        if not description:
            return None
        description = re.sub(r'\s+', ' ', description)
        return description.strip()

class EcommercePriceComparerPipeline:
    def __init__(self):
        self.junk_phrases = ['pościel utrzymana w', 'tonacji', 'tonacja', 'z pięknym subtelnym połyskiem', 'delikatna',
                        'pościel utrzymana jest w','naturalna', 'odcienie']
        self.color_map = {
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
        self.size_map = {
                'mała': 'S',
                'średnia': 'M',
                'duża': 'L',
                'pokrowiec tradycyjny': 'uniwersalny',

            }
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
        adapter['size'] = DataCleaner.standardize_size(adapter.get('size'),self.size_map)
        adapter['color'] = DataCleaner.standardize_color(adapter.get('color'),self.color_map,self.junk_phrases)
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



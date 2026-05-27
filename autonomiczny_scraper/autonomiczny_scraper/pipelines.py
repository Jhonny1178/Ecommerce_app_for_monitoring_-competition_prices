# Define your item pipelines here
#
# Don't forget to add your pipeline to the ITEM_PIPELINES setting
# See: https://docs.scrapy.org/en/latest/topics/item-pipeline.html


# useful for handling different item types with a single interface
from itemadapter import ItemAdapter


import json
from datetime import datetime
from scrapy.exceptions import DropItem
from core.validator import validate_and_clean_scraper_output

def get_spec(specs_dict, keywords):
    for k, v in specs_dict.items():
        if any(keyword.lower() in k.lower() for keyword in keywords):
            return v
    return None

class ValidationAndFormattingPipeline:
    def process_item(self, item, spider):
        # 1. Przekazujemy zescrapowane dane do TWOJEGO Pydantic (validator.py)
        is_valid, clean_data = validate_and_clean_scraper_output(dict(item))

        if not is_valid:
            # W Scrapy, jeśli dane są złe, rzucamy DropItem i Scrapy ich nie zapisze
            raise DropItem(f"Błąd walidacji: {clean_data}")

        # 2. TWOJA LOGIKA ODRZUCANIA ZBIORCZYCH (Grouped)
        sku_check = str(clean_data.get('sku') or '').lower()
        if 'grouped' in sku_check or 'parent' in sku_check:
            raise DropItem(f"Odrzucono stronę zbiorczą (SKU: '{sku_check}')")

        # 3. TWOJA LOGIKA WYCIĄGANIA KOLORÓW I WYMIARÓW Z CECH
        specs = clean_data.get('specs', {})
        rozmiar = get_spec(specs, ['wymiar', 'rozmiar', 'size']) or clean_data.get('size') or 'uniwersalny'
        kolor = get_spec(specs, ['kolor', 'barwa', 'color']) or clean_data.get('color')
        material = get_spec(specs, ['materiał', 'tkanina', 'skład']) or clean_data.get('material')

        wariant_info = item.get('_wariant_info', '')

        # 4. FINALNY SŁOWNIK (Taki sam jak u Ciebie w Pandas)
        final_row = {
            'url': item.get('url'),
            'nazwa': str(clean_data.get('product_name')) + wariant_info,
            'sku': clean_data.get('sku') or clean_data.get('product_id'),
            'marka': clean_data.get('brand'),
            'cena oryginalna': clean_data.get('old_price'),
            'cena na promocji': clean_data.get('special_price'),
            'kolor': kolor,
            'rozmiar': rozmiar,
            'materiał': material,
            'kategorie': json.dumps(clean_data.get('categories', []), ensure_ascii=False),
            'dostępność': clean_data.get('availability'),
            'zdjęcie': clean_data.get('image_url'),
            'pozostałe_cechy': json.dumps(specs, ensure_ascii=False),
            'data_pobrania': datetime.now().isoformat()
        }

        return final_row
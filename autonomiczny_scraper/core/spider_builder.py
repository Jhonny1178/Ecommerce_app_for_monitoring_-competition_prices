import json

def wygeneruj_plik_spidera(json_map_path="selectors_map.json", plik_wyjsciowy="autonomiczny_scraper/spiders/gotowy_scraper.py", nazwa_sklepu="sklep", linki=None):
    try:
        with open(json_map_path, "r", encoding="utf-8") as f:
            css_map = json.load(f)
    except FileNotFoundError:
        print(f"Błąd: Nie znaleziono pliku {json_map_path}")
        return

    formatted_map = "{\n"
    for k, v in css_map.items():
        val = f'"{v}"' if v is not None else 'None'
        formatted_map += f'        "{k}": {val},\n'
    formatted_map += "    }"

    linki_code = f"start_urls = {linki}" if linki else "start_urls = []"

    spider_code = f"""import scrapy
import re
import os
from datetime import datetime
from ecommerce_price_comparer.items import ProductData
from ecommerce_price_comparer.utilities.scraper_engine import extract_data_using_map

class GotowyScraperSpider(scrapy.Spider):
    name = "{nazwa_sklepu}_spider"

    # Mapa CSS wygenerowana przez Twoje AI
    css_map = {formatted_map}

    def start_requests(self):
        {linki_code}
        if start_urls:
            for url in start_urls:
                yield scrapy.Request(url=url.strip(), callback=self.parse)
        else:
            sciezka_do_linkow = getattr(self, 'links_file', '{nazwa_sklepu}_linki.txt')

            if os.path.exists(sciezka_do_linkow):
                with open(sciezka_do_linkow, 'r', encoding='utf-8') as f:
                    dla_kazdego_linku = f.read().splitlines()
                    for url in dla_kazdego_linku:
                        if url.strip():
                            yield scrapy.Request(url=url.strip(), callback=self.parse)
            else:
                self.logger.error(f"Brak pliku z linkami: {{sciezka_do_linkow}}")

    def parse(self, response):
        if response.status != 200:
            return

        raw_data_list = extract_data_using_map(response, self.css_map)

        if not raw_data_list:
            return

        for raw_data in raw_data_list:
            raw_data['url'] = response.url

            query_params = raw_data.get('_ajax_query_params')
            clean_url = raw_data.get('_clean_url')

            if query_params and clean_url:
                ajax_url = f"{{clean_url}}?ajax=1&action=refresh&{{query_params}}"
                raw_data['url'] = f"{{clean_url}}?{{query_params}}"

                yield scrapy.Request(
                    url=ajax_url,
                    callback=self.parse_ajax_price,
                    headers={{'X-Requested-With': 'XMLHttpRequest'}},
                    meta={{'raw_data': raw_data}}
                )
            else:
                yield self.build_product_data(raw_data)

    def parse_ajax_price(self, response):
        raw_data = response.meta['raw_data']
        try:
            price_html = response.json().get("product_prices", "")
            c_match = re.search(r'class="product-price--current"[\\s\\S]*?>[\\s\\n]*([\\d\\s\\xa0]+,[\\d]{{2}})', price_html)
            if c_match: 
                raw_data['special_price'] = c_match.group(1)
        except Exception:
            pass

        yield self.build_product_data(raw_data)

    def build_product_data(self, raw_data):
        # 1. TARCZA OCHRONNA: Odrzucamy strony zbiorcze (Parent/Grouped)
        sku = raw_data.get('sku') or raw_data.get('product_id')
        if sku and ('grouped' in str(sku).lower() or 'parent' in str(sku).lower()):
            self.logger.info(f"Odrzucono stronę zbiorczą (SKU: {{sku}})")
            return None 

        # 2. FUNKCJA POMOCNICZA: Szukanie w słowniku specyfikacji
        specs = raw_data.get('specifications', {{}})
        def get_spec(specs_dict, keywords):
            for k, v in specs_dict.items():
                if any(keyword.lower() in str(k).lower() for keyword in keywords):
                    return v
            return None

        # 3. WYCIĄGANIE Z CECH (Fallback)
        rozmiar = get_spec(specs, ['wymiar', 'rozmiar', 'size']) or raw_data.get('size')
        kolor = get_spec(specs, ['kolor', 'barwa', 'color']) or raw_data.get('color')

        # 4. BUDOWANIE OBIEKTU DLA KOLEGI
        item = ProductData()
        item['sku'] = sku
        item['name'] = raw_data.get('product_name')
        item['size'] = rozmiar
        item['color'] = kolor
        item['manufacturer'] = raw_data.get('brand')
        item['price_normal'] = raw_data.get('old_price')
        item['price_special'] = raw_data.get('special_price')

        kategorie = raw_data.get('categories')
        if isinstance(kategorie, list):
            item['category'] = " > ".join(kategorie)
        else:
            item['category'] = kategorie

        item['description'] = raw_data.get('description')
        item['store'] = self.name
        item['date_of_download'] = datetime.now().isoformat()
        item['availability'] = raw_data.get('availability')
        item['image'] = raw_data.get('image_url')
        item['url'] = raw_data.get('url')

        return item
"""

    with open(plik_wyjsciowy, "w", encoding="utf-8") as f:
        f.write(spider_code)
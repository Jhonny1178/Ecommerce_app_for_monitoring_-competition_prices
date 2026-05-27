import scrapy
import re
import json
from core.scraper_engine import extract_data_using_map



class AiProductSpider(scrapy.Spider):
    name = "ai_spider"

    def __init__(self, linki_do_pracy=None, *args, **kwargs):
        super(AiProductSpider, self).__init__(*args, **kwargs)
        self.start_urls = linki_do_pracy or []

        try:
            with open("data_output/selectors_map.json", "r", encoding="utf-8") as f:
                self.css_map = json.load(f)
        except FileNotFoundError:
            self.logger.error("Brak pliku selectors_map.json!")
            self.css_map = {}

    def parse(self, response):

        # UŻYWAMY TWOJEGO SILNIKA
        raw_data_list = extract_data_using_map(response, self.css_map)

        if not raw_data_list:
            self.logger.info(f"POMINIĘTO: {response.url}")
            return

        for index, raw_data in enumerate(raw_data_list):
            raw_data['url'] = response.url
            raw_data['_wariant_info'] = "" if len(raw_data_list) == 1 else f" (Wariant {index + 1})"

            # NOWA LOGIKA AJAX ZAAKCEPTOWANA ZE SCRAPER_ENGINE
            query_params = raw_data.get('_ajax_query_params')
            clean_url = raw_data.get('_clean_url')

            if query_params and clean_url:
                ajax_url = f"{clean_url}?ajax=1&action=refresh&{query_params}"

                # Aktualizujemy link końcowy w CSV, żeby prowadził prosto do wariantu
                raw_data['url'] = f"{clean_url}?{query_params}"

                yield scrapy.Request(
                    url=ajax_url,
                    callback=self.parse_ajax_price,
                    headers={'X-Requested-With': 'XMLHttpRequest'},
                    meta={'raw_data': raw_data}
                )
            else:
                # Jeśli nie ma wariantów, puszczamy normalnie
                yield raw_data

    def parse_ajax_price(self, response):
        raw_data = response.meta['raw_data']
        try:
            price_html = response.json().get("product_prices", "")
            c_match = re.search(r'class="product-price--current"[\s\S]*?>[\s\n]*([\d\s\xa0]+,[\d]{2})', price_html)
            if c_match:
                raw_data['special_price'] = c_match.group(1)
        except Exception:
            pass

        yield raw_data
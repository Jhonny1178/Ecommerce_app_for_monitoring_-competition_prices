import scrapy
import re
from core.scraper_engine import extract_data_using_map

class GotowyScraperSpider(scrapy.Spider):
    name = "gotowy_scraper"

    start_urls = ['https://podpierzyna.com/posciel-bawelniana-sarev-geos/', 'https://podpierzyna.com/pled-welniany-elvang-tartan-brown/', 'https://podpierzyna.com/podkladka-zakardowa-powlekana-na-stol-le-jacquard-francais-vent-douest-strawberry/', 'https://podpierzyna.com/pled-welniany-eskimo-apus-black/', 'https://podpierzyna.com/przescieradlo-jedwabne-seidenweber-portofino-elegance/', 'https://podpierzyna.com/taca-aquanova-moon-linen/', 'https://podpierzyna.com/przescieradlo-jersey-ze-sciagaczem-curt-bauer-uni-blei/', 'https://podpierzyna.com/poduszka-dekoracyjna-blumarine-blu-velvet-sky/', 'https://podpierzyna.com/serwetka-lniana-le-jacquard-francais-siena-taupe/', 'https://podpierzyna.com/recznik-do-sauny-graccioza-portobello-spa-wrap-storm/']

    # ==========================================
    # MIEJSCE NA POPRAWKI DLA CZŁOWIEKA:
    # ==========================================
    css_map = {
        "product_name": "h1.product_name__name",
        "product_id": "span.prod-id > span",
        "brand": "div.dictionary__param[data-producer='true'] a.dictionary__value_txt",
        "color": "div.dictionary__param[data-desc_value='true'] span.dictionary__value_txt",
        "old_price": None,
        "special_price": "strong.projector_prices__price > span[data-subscription-before]",
        "breadcrumbs_wrapper": None,
        "breadcrumb_item": None,
        "specifications_row": "div.dictionary__param",
        "spec_name": "span.dictionary__name_txt",
        "spec_value": "span.dictionary__value_txt",
        "variants_wrapper": "div.projector_details__versions",
        "variant_option": "option",
        "variant_price_attribute": None,
        "description": "section.longdescription",
    }

    def parse(self, response):
        if response.status != 200:
            self.logger.warning(f"Błąd pobierania: {response.url}")
            return

        raw_data_list = extract_data_using_map(response, self.css_map)

        if not raw_data_list:
            self.logger.info(f"Pominięto, brak danych: {response.url}")
            return

        for index, raw_data in enumerate(raw_data_list):
            raw_data['url'] = response.url
            raw_data['_wariant_info'] = "" if len(raw_data_list) == 1 else f" (Wariant {index + 1})"

            query_params = raw_data.get('_ajax_query_params')
            clean_url = raw_data.get('_clean_url')

            if query_params and clean_url:
                ajax_url = f"{clean_url}?ajax=1&action=refresh&{query_params}"
                raw_data['url'] = f"{clean_url}?{query_params}"

                yield scrapy.Request(
                    url=ajax_url,
                    callback=self.parse_ajax_price,
                    headers={'X-Requested-With': 'XMLHttpRequest'},
                    meta={'raw_data': raw_data}
                )
            else:
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

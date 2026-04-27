import scrapy
import json

from scrapy.utils.response import response_status_message

from ..items import ProductData
from datetime import datetime
import re
import itertools
class JmbdesingSpider(scrapy.Spider):
    name = "jmbdesing"
    allowed_domains = ["jmbdesign.com.pl"]
    start_urls = [
        "https://jmbdesign.com.pl/196-sypialnia",
        "https://jmbdesign.com.pl/51-akcesoria-do-lazienki",
        ]
    urls_for_later_use = [
        "https://jmbdesign.com.pl/196-sypialnia",
        "https://jmbdesign.com.pl/51-akcesoria-do-lazienki",
        "https://jmbdesign.com.pl/203-salon",
        "https://jmbdesign.com.pl/128-jadalnia",
        "https://podpierzyna.com/premium/"]
    custom_settings = {
        'FEEDS': {
            'products.json': {'format': 'json', 'overwrite': True},

        }
    }
    def parse(self, response):
        products_list = response.css('div.product-miniature__thumb a::attr(href)').getall()
        next_site = response.css('li.page-item a[rel="next"]::attr(href)').get()
        yield from response.follow_all(products_list, callback=self.prices)

        if next_site:
            yield response.follow(next_site, callback=self.parse)

    def prices(self, response):
        raw_json = response.css('script[type="application/ld+json"]::text').getall()
        final_json = None

        if raw_json:
            for small_json in raw_json:
                small_json = json.loads(small_json)
                if small_json['@type'] == "Product":
                    final_json = small_json


        color = response.css('b.apropo__features-product--label::text').get()

        name = response.css('h1::text').get()
        manufacturer = response.css('.product-manufacturer img::attr(alt)').get() or "JMB Design"

        product_id_match = re.search(r'id_product[":\s]+(\d+)', response.text)
        if not product_id_match:
            return

        description_raw = response.css('#description ::text').getall()

        description = " ".join(description_raw).strip()

        if not description:
            description = response.css('.product-description ::text').getall()
            description = " ".join(description).strip()
        clean_url = response.url.split('?')[0].split('#')[0]

        variant_groups = response.css('div.product-variants-item')
        all_dimensions_data = []

        for group in variant_groups:
            group_name = group.css('select::attr(name)').get()
            options = group.css('select option')

            current_group_list = []
            for opt in options:
                attr_id = opt.css('::attr(value)').get()
                attr_title = opt.css('::attr(title)').get() or opt.css('::text').get()
                if attr_id:
                    current_group_list.append({
                        'id': attr_id,
                        'name': attr_title.strip(),
                        'group': group_name
                    })

            if current_group_list:
                all_dimensions_data.append(current_group_list)

        if all_dimensions_data:
            for combination in itertools.product(*all_dimensions_data):
                full_size_label = " x ".join([c['name'] for c in combination])

                query_params = "&".join([f"{c['group']}={c['id']}" for c in combination])
                ajax_url = f"{clean_url}?ajax=1&action=refresh&{query_params}"

                yield scrapy.Request(
                    url=ajax_url,
                    callback=self.get_ajax_price,
                    headers={'X-Requested-With': 'XMLHttpRequest'},
                    meta={
                        'description': description,
                        'color': color,
                        'size': full_size_label,
                        'orig_url': clean_url,
                        'query_params': query_params,
                        'json' : final_json
                    }
                )

    def get_ajax_price(self, response):
        json_data = json.loads(response.text)
        final_json = response.meta.get('json')
        description = response.meta.get('description')

        price_html = json_data.get("product_prices", "")
        color = response.meta.get('color')
        if color is None:
            color = None
        current_match = re.search(r'class="product-price--current"[\s\S]*?>[\s\n]*([\d\s\xa0]+,[\d]{2})', price_html)
        regular_match = re.search(r'class="product-price--regular"[\s\S]*?>[\s\n]*([\d\s\xa0]+,[\d]{2})', price_html)
        if current_match:
            price_old = current_match.group(1)
        else:
            price_old = None
        if regular_match:
            price_special = regular_match.group(1)
        else:
            price_special = None

        if "name" in final_json:
            name = final_json["name"]
        else:
            name = None
        if "category" in final_json:
            category_raw = final_json["category"]
            match = re.search(r'[^>]+$', category_raw)
            if match:
                category = match.group(0)
            else:
                category = None

        else:
            category = None
        if "image" in final_json:
            image = final_json["image"]
        else:
            image = None
        if "brand" in final_json:
            if "name" in final_json:
                brand = final_json["brand"]["name"]
            else:
                brand = None
        else:
            brand = None
        if "offers" in final_json:
            if "availability" in final_json["offers"]:
                availability = final_json["offers"]["availability"]
            else:
                availability = None
            if "url" in final_json["offers"]:
                url = final_json["offers"]["url"]
            else:
                url = None
        else:
            url = None
            availability = None
        if "sku" in final_json:
            sku = final_json["sku"]
        else:
            sku = None


        product_data = ProductData()

        product_data['color'] = color
        product_data['size'] = response.meta['size']
        product_data['name'] = name
        product_data['description'] = description
        product_data['sku'] = sku
        product_data['price_normal'] = price_old
        product_data['price_special'] = price_special
        product_data['category'] = category
        product_data['manufacturer'] = brand
        product_data['url'] = f"{response.meta['orig_url']}?{response.meta['query_params']}"
        product_data['store'] = 'jmbdesing'
        product_data['date_of_download'] = datetime.now().isoformat()
        product_data['image'] = image
        product_data['availability'] = availability

        yield product_data


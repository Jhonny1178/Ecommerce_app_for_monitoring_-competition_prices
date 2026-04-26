import scrapy
import random
import json
import re
from datetime import datetime


from ..items import ProductData
class CalavadoSpider(scrapy.Spider):
    name = "Calavado"
    allowed_domains = ["calvado.com"]
    start_urls = [
        "https://www.calvado.com/sypialnia/posciel.html",
        "https://www.calvado.com/sypialnia.html",
        "https://www.calvado.com/lazienka.html",
        "https://www.calvado.com/kuchnia.html",
        "https://www.calvado.com/jadalnia.html",
        "https://www.calvado.com/salon-dekoracje.html",
        "https://www.calvado.com/ogrod-i-taras.html",
        "https://www.calvado.com/concept-design.html"


    ]
    custom_settings = {
        'FEEDS':{
            'products.json': {'format': 'json', 'overwrite' : True},

        }
    }
    def parse(self, response):
        all_products_links = response.css('li.item.last a.product-image.lasto::attr(href)')

        for link in all_products_links:
            yield response.follow(link,callback=self.parse)
        product_link = response.css('h2.product-name a::attr(href)')
        yield from response.follow_all(product_link, callback=self.parse_json)
        next_page = response.css('a.next::attr(href)').get()
        if next_page is not None:
            yield response.follow(next_page, callback=self.parse)
    def parse_json(self, response):
        table_json= response.css('#super-product-table tr')
        for row in table_json:
            product_json = response.css('script[type="application/ld+json"]::text').get()
            if product_json :
                product_json = json.loads(product_json)
                product_json = product_json[0]
            price_old = row.css('p.old-price span.price::text').get()
            if price_old is None:
                price_old = row.css('span.regular-price span.price::text').get()
            if row.css('td a::text').get():
                name = row.css('td a::text').get()
            else:
                name = None

            price_special = row.css('p.special-price span.price::text').get()

            size = re.search(r'\d+\s*x\s*\d+',name)
            if size:
                size = size.group(0)
            if product_json['offers']['availability']:
                availability = product_json['offers']['availability']
            else:
                availability = None
            if product_json['sku']:
                sku = product_json['sku'].replace('grouped',"").replace("-","").strip()
                sku = f"{sku}-{size}"
                sku = sku.replace(" ","-").strip()
            else:
                sku = None

            if 'description' in product_json:
                description = product_json['description']
            else:
                description = None
            if response.xpath('//text()[contains(., "Kolor")]/following::text()[1]').get():
                color = response.xpath('//text()[contains(., "Kolor")]/following::text()[1]').get()
            else:
                color = None

            if 'offers' in product_json:
                if 'category' in product_json['offers']:
                    category = product_json['offers']['category']
                else:
                    category = None
            else:
                category = None
            if 'manufacturer' in product_json:
                manufacturer = product_json['manufacturer']
            else:
                manufacturer = None
            if row.css('td a::attr(href)').get():
                url = row.css('td a::attr(href)').get()
            else:
                url = None
            if 'image' in product_json:
                image = product_json['image']
            else:
                image = None
            product_data = ProductData()
            product_data['color'] = color
            product_data['size'] = size
            product_data['name'] = name
            product_data['description'] = description
            product_data['sku'] = sku
            product_data['price_normal'] = price_old
            product_data['price_special'] = price_special
            product_data['category'] = category
            product_data['manufacturer'] = manufacturer
            product_data['url'] = url
            product_data['store']= 'calavado'
            product_data['date_of_download'] = datetime.now().isoformat()
            product_data['image'] = product_json['image']
            product_data['availability'] = availability

            yield product_data




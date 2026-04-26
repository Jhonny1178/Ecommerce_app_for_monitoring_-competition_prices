import scrapy
import re
import json
from ..items import ProductData
from datetime import datetime


class PodPierzynaSpider(scrapy.Spider):
    name = "pod_pierzyna"
    allowed_domains = ["podpierzyna.com"]
    start_urls = [
                    "https://podpierzyna.com/do-sypialni/",
                ]
    urls_for_later_use = [
                    "https://podpierzyna.com/do-sypialni/",
                    "https://podpierzyna.com/do-lazienki/",
                    "https://podpierzyna.com/do-domu/",
                    "https://podpierzyna.com/do-kuchni-jadalni/",
                    "https://podpierzyna.com/premium/"]
    custom_settings = {
        'FEEDS': {
            'products.jsonl': {'format': 'jsonlines', 'overwrite': True},
        }
    }

    def parse(self, response):
        category_links = response.css('div.core-navigation_items  a::attr(href)').getall()
        for link in category_links:
            yield response.follow(link, callback=self.get_product_links)

    def get_product_links(self, response):
        pattern = r'[^=]+$'
        page_links = response.css('section.search.products div.col-6 a.product__icon::attr(href)').getall()
        current_link = response.url
        match = re.search(pattern, current_link)
        if match:
            number = match.group(0)
            if not number.isdigit():
                number = None
        else:
            number = None
        if page_links:
            yield from response.follow_all(page_links, callback=self.get_data_from_links)
            if number:
                new_current_link = current_link.replace(str(number), str(int(number)+1))
                yield response.follow(new_current_link, callback=self.get_product_links)

            else:
                new_current_link = current_link + "?counter=1"
                yield response.follow(new_current_link, callback=self.get_product_links)
    def get_data_from_links(self, response):
        category = None
        final_json = None
        price_special = None
        price_old = None
        availability = None
        url = None
        raw_json = response.css('script[type="application/ld+json"]::text').getall()
        color = response.xpath('//text()[contains(., "Dominujący kolor")]/following::text()[1]').get()
        ajax_list = response.css('script.ajaxLoad::text').getall()
        for ajax_item in ajax_list:
            if "cena_raty" in ajax_item:
                match = re.search( r'\{(.*)\}', ajax_item, re.DOTALL)
                if match:
                    ajax = json.loads(match.group(0).replace("\'","\""))
                    sizes_and_info =  ajax["sizes"]
        if raw_json:
            final_json = raw_json
            for product in raw_json:
                product = json.loads(product)
                if product['@type'] == "Product":
                    final_json = product
                if product['@type'] == "BreadcrumbList":
                    json_temp = product["itemListElement"]

                    for dictionary in json_temp:
                        if dictionary["position"]==2:
                            category = dictionary["name"]
        for key, prices in sizes_and_info.items():
            size = prices['description']
            price_special = prices['price']['value']

            if 'normalprice' in prices['price']:
                price_old = prices['price']['normalprice']
            else:
                price_old = price_special
                price_special = None

            if 'code_extern' in prices:
                sku = prices['code_extern']
            else:
                sku = None
            if color:
                color = color
            else:
                color = None
            if size:
                size = size
            else:
                size = None
            if 'name' in final_json:
                name = final_json["name"]
            else:
                name = None
            if  'description' in final_json:
                description = final_json['description']
            else:
                description = None
            if 'brand' in final_json:
                if 'name' in final_json["brand"]:
                    brand = final_json["brand"]["name"]
                else:
                    brand = None
            else:
                brand = None

            if 'offers' in final_json:
                for offer in final_json["offers"]:
                    if offer['@type'] == "Offer":
                        if 'url' in offer:
                            url = offer['url']
                        else:
                            url = None
                        if 'availability' in offer:
                            availability = offer['availability']
                        else:
                            availability = None


            if 'image' in final_json:
                image = final_json["image"]
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
            product_data['manufacturer'] = brand
            product_data['url'] = url
            product_data['store'] = 'podpierzyna'
            product_data['date_of_download'] = datetime.now().isoformat()
            product_data['image'] = image
            product_data['availability'] = availability

            yield product_data



# Define here the models for your scraped items
#
# See documentation in:
# https://docs.scrapy.org/en/latest/topics/items.html

import scrapy

class EcommercePriceComparerItem(scrapy.Item):
    # define the fields for your item here like:
    # name = scrapy.Field()
    pass


class ProductData(scrapy.Item):
    sku = scrapy.Field()
    name = scrapy.Field()
    size = scrapy.Field()
    color = scrapy.Field()
    manufacturer = scrapy.Field()
    price_normal = scrapy.Field()
    price_special = scrapy.Field()
    category = scrapy.Field()
    description = scrapy.Field()
    store = scrapy.Field()
    date_of_download = scrapy.Field()
    availability = scrapy.Field()
    image = scrapy.Field()
    url = scrapy.Field()

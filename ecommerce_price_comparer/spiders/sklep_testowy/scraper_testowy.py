import scrapy
from datetime import datetime

class DummySpider(scrapy.Spider):
    name = "spider_dummy"

    # Ta funkcja zastąpi prawdziwe scrapowanie
    def start_requests(self):
        # Symulujemy znaleziony produkt konkurencji
        yield {
            "sku": "SKU-123",
            "name": "Biała koszula testowa",
            "price_normal": 99.99,
            "price_special": 90.99,
            "availability" : "instock",
            "size": "210x210",
            "color": "biały",
            "manufacturer": "joop",
            "category": "testowa",
            "url": "http://konkurencja.pl/produkt/1",
            "store": "sklep_konkurencji",
            "date_of_download": datetime.now()
        }
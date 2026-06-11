import scrapy
from datetime import datetime


class SpiderDummy(scrapy.Spider):
    name = "spider_dummy"

    def __init__(self, target_table=None, store_prefix=None, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.target_table = target_table
        self.store_prefix = store_prefix

    async def start(self):
        now = datetime.now().isoformat()

        products = [
            {
                "sku": "COMP-10001",
                "name": "Ręczniki Möve biały 30x50",
                "size": "30x50",
                "color": "biały",
                "manufacturer": "Möve",
                "category": "Ręczniki",
                "price_normal": 72.90,
                "price_special": None,
                "store": "spider_dummy",
                "availability": "dostępny",
                "date_of_download": now,
                "url": "https://dummy-competitor.test/products/comp-10001",
                "image": "",
                "description": "Testowy produkt konkurencji dopasowany do ręczników.",
            },
            {
                "sku": "COMP-10002",
                "name": "Koce i pledy Ulster Weavers szary 50x100",
                "size": "50x100",
                "color": "szary",
                "manufacturer": "Ulster Weavers",
                "category": "Koce i pledy",
                "price_normal": 239.99,
                "price_special": None,
                "store": "spider_dummy",
                "availability": "dostępny",
                "date_of_download": now,
                "url": "https://dummy-competitor.test/products/comp-10002",
                "image": "",
                "description": "Testowy produkt konkurencji dopasowany do koca.",
            },
            {
                "sku": "COMP-10003",
                "name": "Fartuchy kuchenne Eskimo Switzerland beżowy 70x140",
                "size": "70x140",
                "color": "beżowy",
                "manufacturer": "Eskimo Switzerland",
                "category": "Fartuchy kuchenne",
                "price_normal": 699.99,
                "price_special": None,
                "store": "spider_dummy",
                "availability": "dostępny",
                "date_of_download": now,
                "url": "https://dummy-competitor.test/products/comp-10003",
                "image": "",
                "description": "Testowy produkt konkurencji dopasowany do fartucha.",
            },
            {
                "sku": "COMP-10004",
                "name": "Pościel Lambfield Home granatowy uniw",
                "size": "uniw",
                "color": "granatowy",
                "manufacturer": "Lambfield Home",
                "category": "Pościel",
                "price_normal": 44.99,
                "price_special": 39.99,
                "store": "spider_dummy",
                "availability": "dostępny",
                "date_of_download": now,
                "url": "https://dummy-competitor.test/products/comp-10004",
                "image": "",
                "description": "Testowy produkt konkurencji dopasowany do pościeli.",
            },
        ]

        for product in products:
            yield product
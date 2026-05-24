import scrapy
from datetime import datetime

class DummySpider(scrapy.Spider):
    name = "spider_dummy"

    def start_requests(self):
        # 1. PRODUKTY DOCELOWE (Mają się zmatchować z CSV)
        matches = [
            # IDEALNE DOPASOWANIE (Dokładnie to samo co w CSV)
            {
                "sku": "COMP-100",
                "name": "Biała koszula męska",
                "size": "210x210",
                "color": "biały",
                "manufacturer": "joop",
                "price_normal": 189.99,
                "price_special": 139.99,
                "category": "Koszule",
                "description": "Koszula bawełniana konkurencji",
                "store": self.name,  # Używa nazwy "spider_dummy" - BARDZO WAŻNE!
                "date_of_download": datetime.now().isoformat(),
                "availability": "instock",
                "image": "http://img.comp.pl/1.jpg",
                "url": "http://konkurencja.pl/1"
            },
            # PODOBNE DOPASOWANIE (Zmieniona kolejność słów + dodatkowe słowo "klasyk")
            {
                "sku": "COMP-101",
                "name": "Spodnie jeansowe czarne klasyk",
                "size": "110x110",
                "color": "czarny",
                "manufacturer": "Levis",
                "price_normal": 279.00,
                "price_special": None,
                "category": "Spodnie",
                "description": "Czarne jeansy",
                "store": self.name,
                "date_of_download": datetime.now().isoformat(),
                "availability": "instock",
                "image": "http://img.comp.pl/2.jpg",
                "url": "http://konkurencja.pl/2"
            },
            # DOPASOWANIE ZE SPACJAMI W ROZMIARZE (Test dla Smart Blockingu)
            {
                "sku": "COMP-102",
                "name": "Zegarek srebrny klasyczny",
                "size": " 50 x 50 ",  # Celowe spacje!
                "color": "srebrny",
                "manufacturer": "Casio",
                "price_normal": 145.00,
                "price_special": 115.00,
                "category": "Zegarki",
                "description": "Zegarek na bransolecie srebrny",
                "store": self.name,
                "date_of_download": datetime.now().isoformat(),
                "availability": "instock",
                "image": "http://img.comp.pl/3.jpg",
                "url": "http://konkurencja.pl/3"
            }
        ]

        for m in matches:
            yield m

        # 2. SZUM (Produkty, które nie zmatchują się z niczym, żeby baza nie była pusta)
        for i in range(1, 6):
            yield {
                "sku": f"COMP-NOISE-{i}",
                "name": f"Losowy Produkt Konkurencji {i}",
                "size": f"{i}0x{i}0",
                "color": "zielony",
                "manufacturer": "Inna Marka",
                "price_normal": 50.0 + i,
                "price_special": None,
                "category": "Inne",
                "description": "Szum danych",
                "store": self.name,
                "date_of_download": datetime.now().isoformat(),
                "availability": "instock",
                "image": f"http://img.comp.pl/noise{i}.jpg",
                "url": f"http://konkurencja.pl/noise{i}"
            }
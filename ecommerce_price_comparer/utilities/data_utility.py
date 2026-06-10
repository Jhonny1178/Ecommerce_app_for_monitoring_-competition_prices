import re
junk_phrases = ['pościel utrzymana w', 'tonacji', 'tonacja', 'z pięknym subtelnym połyskiem', 'delikatna',
                        'pościel utrzymana jest w','naturalna', 'odcienie']
color_map = {
    'niebieski': ['niebieski', 'turkus', 'turquesa', 'azul', 'denim', 'morski', 'blue', 'sky'],
    'szary': ['szary', 'szarości', 'antracyt', 'anthracit', 'silver', 'srebrny', 'grey', 'gray', 'plata',
              'grafit','szarej'],
    'beżowy': ['beż', 'beżu', 'natural', 'crudo', 'piaskowy', 'sand', 'taupe', 'oat', 'linen', 'cream',
               'kremowy','kremowej'],
    'biały': ['biały', 'bieli', 'white', 'blanco', 'ivory','białej'],
    'czarny': ['czarny', 'czerni', 'black', 'negro','czarnej'],
    'zielony': ['zielony', 'zieleni', 'green', 'verde', 'oliwka', 'olive', 'bottle','zielonej'],
    'żółty': ['żółty', 'żółtego', 'yellow', 'gold', 'oro', 'mostaza', 'ginkgo','żółtej'],
    'czerwony': ['czerwony', 'czerwieni', 'red', 'rojo', 'terracota','czerwonej'],
    'różowy': ['różowy', 'różu', 'rose', 'pink', 'nude', 'caldera','różowej'],
    'fioletowy': ['fiolet', 'fioletu', 'lila', 'lilac', 'violet', 'purple','fioletowej'],
    'brązowy': ['brąz', 'brązu', 'brown', 'marron', 'caffe', 'chocolate','brązowej'],
    'wielokolorowy': ['wielokolorowy', 'multicolor', 'mix','wielokolorowej'],
    'bordowy' : ['bordowa','bordowej']
        }
size_map = {
    'mała': 'S',
    'średnia': 'M',
    'duża': 'L',
    'pokrowiec tradycyjny': 'uniwersalny',
    'one size' : 'uniwersalny',
}
class DataCleaner:
    @staticmethod
    def to_lowercase(value, spider=None):
        if not value:
            return None
        try:
            return value.lower()
        except AttributeError:
            if spider:
                spider.logger.warning(f"Error with lowercasing: {value}")
            #mozna spróbować robic str(value).lower() ale narazie zostawie tak
            return value

    @staticmethod
    def to_strip(value,spider=None):
        if not value:
            return None
        try:
            if isinstance(value, str):
                return value.strip()
            return value
        except AttributeError:
            if spider:
                spider.logger.warning(f"Error with striping: {value}")
            return value
    @staticmethod
    def standardize_availability_link(link):
        if not link:
            return None
        return link.replace("http://schema.org/", "")
    @staticmethod
    def clean_price(price):
        if not price:
            return None
        price_str = str(price).strip()
        last_comma = price_str.rfind(',')
        last_dot = price_str.rfind('.')
        if last_comma > last_dot:
            price_str = price_str.replace('.', '').replace(',', '.')
        else:

            price_str = price_str.replace(',', '')

        price = re.sub(r'[^0-9.]', '', str(price_str))
        try:
            return float(price)
        except ValueError:
            return None
    @staticmethod
    def sku_normalize(name, color , size, manufacturer):
        parts_of_sku = [name, color , size, manufacturer]
        #moze dodać strip i lower ale raczej nie bo bedzie robione po nich

        validate_parts = [str("-".join(part.replace("-","").split())).strip() for part in parts_of_sku if part]
        sku = "-".join(validate_parts)
        if not sku:
            return None
        return sku
    @staticmethod
    def standardize_color(color):
            if not color:
                return None
            for phrase in junk_phrases:
                color = color.replace(phrase, "")
                color = color.strip()
            for standard, keywords in color_map.items():
                if any(word in color for word in keywords):
                    return standard
            return color
    @staticmethod
    def standardize_name(name, color, size,manufacturer):
        if not name:
            return None
        to_clean_from_name = [size , color , manufacturer]
        for clean_part in to_clean_from_name:
            if clean_part:
                name = name.replace(str(clean_part), "")
        #unikamy podwojnych spacji przy usunieciach kilku
        return " ".join(name.split()).strip()
    @staticmethod
    def standardize_size(size):
        if not size:
            return None
        size_str = str(size).strip().lower()
        if '+' in size_str:
            size_str = size_str.split('+')[0].strip()
        if '⌀' in size_str or 'śr.' in size_str:
            match = re.search(r'(\d+)', size_str)
            if match:
                return match.group(1)
        size_norm = re.sub(r'[^0-9x]', '', size_str)
        if 'x' in size_norm and any(char.isdigit() for char in size_norm):
            return size_norm
        return size_map.get(size_str, size_str)

    @staticmethod
    def clean_description(description):
        if not description:
            return None
        description = re.sub(r'\s+', ' ', description)
        return description.strip()

    @staticmethod
    def clean_category(category_str):
        if not category_str:
            return None
        category_str = str(category_str).replace('&gt;', '>')
        parts = [part.strip() for part in category_str.split('>')]
        if len(parts) >= 2:
            return parts[1]
        elif len(parts) == 1:
            return parts[0]

        return None

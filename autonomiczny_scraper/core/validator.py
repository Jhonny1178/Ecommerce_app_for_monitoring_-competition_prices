import re
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, AliasChoices, field_validator, ValidationError

CATEGORY_BLACKLIST = [
    'regulamin', 'koszyk', 'konto', 'prywatności', 'cookie', 'rabat',
    'życzeń', 'polityce', 'dostawa', 'zwroty', 'pomoc', 'kontakt',
    'akceptuj', 'odrzuć', 'rodo'
]

SPECS_TRASH_PHRASES = ['oferta ma charakter', 'w zestawie', 'zobacz wszystkie']


class ProductDataContract(BaseModel):
    product_name: str = Field(validation_alias=AliasChoices('product_name', 'name', 'title'))
    product_id: Optional[str] = Field(default=None, validation_alias=AliasChoices('product_id', 'id', 'sku', 'index'))
    sku: Optional[str] = Field(default=None)
    brand: Optional[str] = Field(default=None,
                                 validation_alias=AliasChoices('brand', 'marka', 'manufacturer', 'producent'))
    old_price: Optional[float] = Field(default=None,
                                       validation_alias=AliasChoices('old_price', 'regular_price', 'base_price'))
    special_price: Optional[float] = Field(default=None,
                                           validation_alias=AliasChoices('special_price', 'price', 'promo_price'))
    categories: List[str] = Field(default=[], validation_alias=AliasChoices('categories', 'category', 'kategorie'))
    specs: Dict[str, str] = Field(default={},
                                  validation_alias=AliasChoices('specifications', 'specs', 'attributes', 'cechy'))
    availability: Optional[str] = Field(default=None,
                                        validation_alias=AliasChoices('availability', 'status', 'dostepnosc'))
    color: Optional[str] = Field(default=None)
    size: Optional[str] = Field(default=None)
    material: Optional[str] = Field(default=None)
    image_url: Optional[str] = Field(default=None, validation_alias=AliasChoices('image', 'image_url'))

    @field_validator('old_price', 'special_price', mode='before')
    @classmethod
    def clean_price(cls, value: Any) -> Optional[float]:
        if not value:
            return None
        if isinstance(value, str):
            val = value.replace(' ', '').replace('\xa0', '')
            clean_str = re.sub(r'[^\d,.]', '', val)

            if not clean_str:
                return None

            if '.' in clean_str and ',' in clean_str:
                clean_str = clean_str.replace('.', '').replace(',', '.')
            else:
                clean_str = clean_str.replace(',', '.')

            try:
                return float(clean_str)
            except ValueError:
                return None
        return value

    @field_validator('categories', mode='before')
    @classmethod
    def clean_categories(cls, value: Any) -> List[str]:
        if not isinstance(value, list):
            return []

        cleaned_list = []
        for cat in value:
            if not cat or not isinstance(cat, str):
                continue
            cat_clean = cat.strip()
            cat_lower = cat_clean.lower()

            if cat_clean and len(cat_clean) < 40:
                is_trash = False
                for bad_word in CATEGORY_BLACKLIST:
                    if re.search(fr'\b{bad_word}\b', cat_lower):
                        is_trash = True
                        break

                if cat_lower == 'google':
                    is_trash = True

                if not is_trash:
                    cleaned_list.append(cat_clean)

        return cleaned_list

    @field_validator('specs', mode='before')
    @classmethod
    def clean_specs(cls, value: Any) -> Dict[str, str]:
        if not isinstance(value, dict):
            return {}

        cleaned_specs = {}
        for k, v in value.items():
            k_clean = str(k).strip()
            v_clean = re.sub(r'\s+', ' ', str(v)).strip()

            v_clean = re.split(r'(?i)więcej', v_clean)[0].strip()

            if any(trash in v_clean.lower() for trash in SPECS_TRASH_PHRASES):
                continue

            if len(v_clean) < 150 and len(k_clean) < 50:
                cleaned_specs[k_clean] = v_clean

        return cleaned_specs


def validate_and_clean_scraper_output(raw_data: dict) -> tuple[bool, Any]:
    try:
        clean_data = ProductDataContract(**raw_data)
        return True, clean_data.model_dump()
    except ValidationError as e:
        return False, [f"{err['loc'][0]}: {err['msg']}" for err in e.errors()]
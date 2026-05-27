import copy
import re
import json
import itertools


def get_text(selector_obj, selector):
    if not selector:
        return None
    try:
        tag = selector_obj.css(selector)
        return tag.xpath('string(.)').get().strip() if tag else None
    except Exception:
        return None


def extract_after_keyword(text, keywords):
    for keyword in keywords:
        match = re.search(fr'\b{keyword}\b\s*[:\-]\s*([^.,\n\r<]+)', text, re.IGNORECASE)
        if match:
            val = match.group(1).strip()
            if val and len(val) < 40 and not val.lower().startswith('zobacz'):
                return val
    return None


def extract_data_using_map(response, css_map):
    css_map = {k: (v if v != "null" else None) for k, v in css_map.items()}
    is_product_page = False
    ld_data = {}
    categories = []

    og_type = response.css('meta[property="og:type"]::attr(content)').get()
    if og_type in ['product', 'product.item']:
        is_product_page = True

    for script_string in response.css('script[type="application/ld+json"]::text').getall():
        if script_string:
            try:
                data = json.loads(script_string, strict=False)
                if isinstance(data, dict): data = [data]

                for item in data:
                    if item.get('@type') in ['Product', 'ProductGroup']:
                        is_product_page = True
                        ld_data['product_name'] = item.get('name')
                        ld_data['description'] = item.get('description')
                        ld_data['sku'] = item.get('sku')

                        b = item.get('brand')
                        if isinstance(b, dict):
                            ld_data['brand'] = b.get('name')
                        elif isinstance(b, str):
                            ld_data['brand'] = b

                        img = item.get('image')
                        if isinstance(img, list) and img:
                            ld_data['image_url'] = img[0]
                        elif isinstance(img, str):
                            ld_data['image_url'] = img

                        offers = item.get('offers', {})
                        if isinstance(offers, list) and offers: offers = offers[0]
                        if isinstance(offers, dict):
                            ld_data['special_price'] = offers.get('price')
                            availability = offers.get('availability', '')
                            ld_data['availability'] = availability.split('/')[-1] if availability else None

                    if item.get('@type') == 'BreadcrumbList':
                        elements = sorted(item.get('itemListElement', []), key=lambda x: int(x.get('position', 0)))
                        for el in elements:
                            name = el.get('name') or el.get('item', {}).get('name')
                            if name: categories.append(name.strip())
            except Exception:
                pass

    if not is_product_page:
        test_name_selector = css_map.get('product_name')
        if test_name_selector and response.css(test_name_selector):
            is_product_page = True

    if not is_product_page:
        return []

    ld_data['categories'] = categories if categories else None

    product_name = ld_data.get('product_name') or get_text(response, css_map.get('product_name'))
    product_id = get_text(response, css_map.get('product_id')) or ld_data.get('sku')

    if not product_id and response.url:
        url_sku_match = re.search(r'-([a-zA-Z0-9]+)\.html$', response.url)
        if url_sku_match:
            product_id = url_sku_match.group(1).upper()

    brand = ld_data.get('brand') or get_text(response, css_map.get('brand'))
    old_price = get_text(response, css_map.get('old_price'))
    special_price = ld_data.get('special_price') or get_text(response, css_map.get('special_price'))
    description = ld_data.get('description') or get_text(response, css_map.get('description'))

    if not ld_data.get('categories'):
        cat_wrapper_sel = css_map.get('breadcrumbs_wrapper')
        cat_item_sel = css_map.get('breadcrumb_item')
        if cat_wrapper_sel and cat_item_sel:
            try:
                wrapper = response.css(cat_wrapper_sel)
                if wrapper: categories = [item.xpath('string(.)').get().strip() for item in wrapper.css(cat_item_sel) if
                                          item.xpath('string(.)').get().strip()]
            except:
                pass

    specifications = {}
    spec_row_sel = css_map.get('specifications_row')
    spec_name_sel = css_map.get('spec_name')
    spec_val_sel = css_map.get('spec_value')
    if spec_row_sel and spec_name_sel and spec_val_sel:
        try:
            for row in response.css(spec_row_sel):
                k_tag = row.css(spec_name_sel)
                v_tag = row.css(spec_val_sel)
                if k_tag and v_tag:
                    k_text = k_tag.xpath('string(.)').get().strip()
                    v_text = v_tag.xpath('string(.)').get().strip()
                    if k_text: specifications[k_text] = v_text
        except Exception:
            pass

    full_text = " ".join(response.css('body ::text').getall())
    desc_text = str(description) if description else full_text

    heuristic_color = extract_after_keyword(desc_text, ["Kolor", "Barwa", "Odcień"]) or get_text(response,
                                                                                                 css_map.get('color'))
    heuristic_material = extract_after_keyword(desc_text, ["Materiał", "Skład", "Tkanina", "Wypełnienie"])
    heuristic_size = None

    size_match = re.search(r'\b\d{2,3}\s*[xX*]\s*\d{2,3}(?:\s*[xX*]\s*\d{2,3})?\b', str(product_name) + " " + desc_text)
    if size_match:
        heuristic_size = size_match.group(0).lower().replace(" ", "")

    # =========================================================
    # TWOJA LOGIKA: Kombinatoryka wariantów (itertools.product)
    # Zamiast czytać listę w dół, budujemy grupy!
    # =========================================================
    variants = []

    # Wyciągamy bazowy URL bez parametrów na potrzeby AJAX-a
    clean_url = response.url.split('?')[0].split('#')[0]

    var_wrap_sel = css_map.get('variants_wrapper')

    all_dimensions_data = []

    # Jeśli AI podało jakiś wrapper wariantów, szukamy w nim selektów.
    # Jeśli nie, próbujemy domyślnie namierzyć tagi 'select' na stronie.
    select_blocks = response.css(f'{var_wrap_sel} select') if var_wrap_sel else response.css('select')

    if select_blocks:
        for select_tag in select_blocks:
            group_name = select_tag.attrib.get('name')
            if not group_name:
                continue

            options = select_tag.css('option')
            current_group_list = []

            for opt in options:
                attr_id = opt.attrib.get('value')
                # Zabezpieczenie przed pustymi opcjami (np. "Wybierz rozmiar")
                if not attr_id or attr_id.strip() == "":
                    continue

                attr_title = opt.attrib.get('title') or opt.xpath('string(.)').get().strip()

                current_group_list.append({
                    'id': attr_id,
                    'name': attr_title,
                    'group': group_name
                })

            if current_group_list:
                all_dimensions_data.append(current_group_list)

    # =========================================================
    # ŁĄCZENIE KOMBINACJI
    # =========================================================
    if all_dimensions_data:
        # Tworzy każdy możliwy zestaw, np. (Kolor Czerwony, Rozmiar M)
        for combination in itertools.product(*all_dimensions_data):
            # Łączymy nazwy dla Pipeline'u, np. "Czerwony x M"
            full_size_label = " x ".join([c['name'] for c in combination])

            # Budujemy pełnego stringa pod AJAX, np. "group[1]=12&group[2]=24"
            query_params = "&".join([f"{c['group']}={c['id']}" for c in combination])

            variant_specs = copy.deepcopy(specifications)
            variant_specs['Wariant'] = full_size_label

            variants.append({
                'product_name': product_name,
                'product_id': product_id,
                'sku': ld_data.get('sku'),
                'brand': brand,
                'old_price': old_price,
                'special_price': special_price,
                'categories': categories,
                'specifications': variant_specs,
                'availability': ld_data.get('availability'),
                'description': description,
                'color': heuristic_color,
                'size': full_size_label,
                'material': heuristic_material,
                'image_url': ld_data.get('image_url'),

                '_ajax_query_params': query_params,
                '_clean_url': clean_url
            })

    if not variants:
        variants.append({
            'product_name': product_name, 'product_id': product_id, 'sku': ld_data.get('sku'),
            'brand': brand, 'old_price': old_price, 'special_price': special_price,
            'categories': categories, 'specifications': specifications,
            'availability': ld_data.get('availability'), 'description': description,
            'color': heuristic_color, 'size': heuristic_size, 'material': heuristic_material,
            'image_url': ld_data.get('image_url')
        })

    return variants
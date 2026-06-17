import 'package:flutter/material.dart';
import 'dart:convert';
import 'product_details_screen.dart';
import 'package:tonten/core/api/api_client.dart';

class ProductsListScreen extends StatefulWidget {
  final bool matchedOnly;

  const ProductsListScreen({super.key, required this.matchedOnly});

  @override
  State<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends State<ProductsListScreen> {
  List<dynamic> _products = [];
  bool _isLoading = true;
  int _currentPage = 1;
  int _totalPages = 1;

  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  List<String> _availableCategories = [];
  String? _selectedCategory;
  int? _minMatches;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchProducts();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await ApiClient.get(Uri.parse('/api/categories'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && mounted) {
          setState(() {
            _availableCategories = List<String>.from(data['data'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint("Błąd pobierania kategorii: $e");
    }
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);

    try {
      final encodedSearch = Uri.encodeQueryComponent(_searchQuery);
      String urlStr = "/api/products?page=$_currentPage&per_page=20&matched_only=${widget.matchedOnly}&search=$encodedSearch";

      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        urlStr += "&category=${Uri.encodeQueryComponent(_selectedCategory!)}";
      }
      if (_minMatches != null) {
        urlStr += "&min_matches=$_minMatches";
      }

      final response = await ApiClient.get(Uri.parse(urlStr), headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && mounted) {
          setState(() {
            _products = data['data'] ?? [];
            _totalPages = data['pagination']?['total_pages'] ?? 1;
          });
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Błąd pobierania produktów: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearch() {
    setState(() {
      _searchQuery = _searchController.text.trim();
      _currentPage = 1;
    });
    _fetchProducts();
  }

  num? _toNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. WYSZUKIWARKA
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Szukaj produktu (nazwa lub SKU)...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _onSearch(),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _onSearch,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Szukaj", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 2. NOWOCZESNE FILTRY W JEDNYM RZĘDZIE
        Row(
          children: [
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _selectedCategory,
                    icon: const Icon(Icons.filter_list, size: 20),
                    hint: const Text('Kategoria: Wszystkie'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Kategoria: Wszystkie')),
                      ..._availableCategories.map(
                        (cat) => DropdownMenuItem(value: cat, child: Text(cat, overflow: TextOverflow.ellipsis)),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedCategory = val;
                        _currentPage = 1;
                      });
                      _fetchProducts();
                    },
                  ),
                ),
              ),
            ),
            
            // Elegancki "Segmented Control" dla dopasowań
            if (widget.matchedOnly) ...[
              const SizedBox(width: 24),
              Expanded(
                flex: 1,
                child: _buildSegmentedMatchesControl(colorScheme),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),

        // 3. PŁASKA LISTA WYNIKÓW (Zamiast kafelków)
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? const Center(child: Text("Brak produktów spełniających kryteria."))
                  : ListView.separated(
                      itemCount: _products.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.3)),
                      itemBuilder: (context, index) {
                        return _buildFlatProductRow(_products[index], colorScheme);
                      },
                    ),
        ),

        // 4. PAGINACJA
        if (!_isLoading && _totalPages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _fetchProducts(); } : null,
                ),
                Text('Strona $_currentPage z $_totalPages', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < _totalPages ? () { setState(() => _currentPage++); _fetchProducts(); } : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Czysty, applowy przełącznik dopasowań
  Widget _buildSegmentedMatchesControl(ColorScheme colorScheme) {
    final options = [
      {'val': null, 'label': 'Wszystkie'},
      {'val': 1, 'label': '1+'},
      {'val': 2, 'label': '2+'},
      {'val': 3, 'label': '3+'},
      {'val': 5, 'label': '5+'},
    ];

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final val = opt['val'] as int?;
          final label = opt['label'] as String;
          final isSelected = _minMatches == val;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _minMatches = val;
                  _currentPage = 1;
                });
                _fetchProducts();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Płaski, lekki wiersz produktu zamiast ciężkiej "Karty"
  Widget _buildFlatProductRow(dynamic product, ColorScheme colorScheme) {
    final String name = product['name']?.toString() ?? 'Brak nazwy';
    final String sku = product['sku']?.toString() ?? 'N/A';
    final num? price = _toNum(
      product['display_price'] ??
          product['price'] ??
          product['price_special'] ??
          product['price_normal'],
    );
    final String imageUrl = product['image']?.toString() ?? '';
    final int competitorsCount = int.tryParse('${product['competitors_count'] ?? 0}') ?? 0;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ProductDetailsScreen(productId: product['id'])),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: imageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, size: 24),
                      ),
                    )
                  : const Icon(Icons.inventory, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text("SKU: $sku", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price != null ? "${price.toStringAsFixed(2)} zł" : "-",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colorScheme.primary),
                ),
                if (competitorsCount > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.compare_arrows, size: 14, color: colorScheme.secondary),
                      const SizedBox(width: 4),
                      Text(
                        '$competitorsCount dopasowań',
                        style: TextStyle(color: colorScheme.secondary, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(width: 16),
            Icon(Icons.chevron_right, color: colorScheme.outlineVariant, size: 20),
          ],
        ),
      ),
    );
  }
}
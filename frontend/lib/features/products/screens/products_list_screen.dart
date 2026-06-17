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

  String? _selectedCategory;
  String? _selectedBrand;
  String? _selectedStore;
  int? _minMatches;
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  List<String> _availableCategories = [];
  List<String> _availableBrands = [];
  List<String> _availableStores = [];
  int _maxStoresScraped = 5;

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _fetchFiltersData();
    _fetchProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabController = DefaultTabController.maybeOf(context);
    if (_tabController != tabController) {
      _tabController?.removeListener(_onTabChanged);
      _tabController = tabController;
      _tabController?.addListener(_onTabChanged);
    }
  }

  void _onTabChanged() {
    if (_tabController != null && !_tabController!.indexIsChanging) {
      _fetchProducts();
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _fetchFiltersData() async {
    try {
      final response = await ApiClient.get(Uri.parse('/api/filters'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && mounted) {
          setState(() {
            _availableCategories = List<String>.from(data['categories'] ?? []);
            _availableBrands = List<String>.from(data['brands'] ?? []);
            _availableStores = List<String>.from(data['stores'] ?? []);
            _maxStoresScraped = data['max_stores'] ?? 5;
          });
        }
      }
    } catch (e) {
      debugPrint("Błąd pobierania filtrów: $e");
    }
  }

  Future<void> _fetchProducts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final encodedSearch = Uri.encodeQueryComponent(_searchQuery);
      String urlStr = "/api/products?page=$_currentPage&per_page=20&matched_only=${widget.matchedOnly}&search=$encodedSearch";

      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        urlStr += "&category=${Uri.encodeQueryComponent(_selectedCategory!)}";
      }
      if (_selectedBrand != null && _selectedBrand!.isNotEmpty) {
        urlStr += "&brand=${Uri.encodeQueryComponent(_selectedBrand!)}";
      }
      if (_selectedStore != null && _selectedStore!.isNotEmpty) {
        urlStr += "&store=${Uri.encodeQueryComponent(_selectedStore!)}";
      }
      if (_minMatches != null) {
        urlStr += "&min_matches=$_minMatches";
      }
      if (_minPriceController.text.isNotEmpty) {
        urlStr += "&price_min=${_minPriceController.text}";
      }
      if (_maxPriceController.text.isNotEmpty) {
        urlStr += "&price_max=${_maxPriceController.text}";
      }

      final response = await ApiClient.get(Uri.parse(urlStr), headers: {'Accept': 'application/json'});

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          setState(() {
            _products = data['data'] ?? [];
            _totalPages = data['pagination']?['total_pages'] ?? 1;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Błąd pobierania: ${data['error'] ?? 'Nieznany'}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Błąd pobierania produktów: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearch() {
    setState(() => _currentPage = 1);
    _fetchProducts();
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedBrand = null;
      _selectedStore = null;
      _minMatches = null;
      _minPriceController.clear();
      _maxPriceController.clear();
      _searchController.clear();
      _searchQuery = "";
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Wpisz nazwę produktu lub SKU...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onSubmitted: (val) {
                  _searchQuery = val;
                  _onSearch();
                },
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () {
                _searchQuery = _searchController.text;
                _onSearch();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.search, size: 18),
              label: const Text("Szukaj", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildDropdown('Marka', _selectedBrand, _availableBrands, (val) {
              setState(() { _selectedBrand = val; _currentPage = 1; });
              _fetchProducts();
            }, colorScheme),

            _buildDropdown('Kategoria', _selectedCategory, _availableCategories, (val) {
              setState(() { _selectedCategory = val; _currentPage = 1; });
              _fetchProducts();
            }, colorScheme),

            _buildDropdown('Sklep konkurencji', _selectedStore, _availableStores, (val) {
              setState(() { _selectedStore = val; _currentPage = 1; });
              _fetchProducts();
            }, colorScheme),

            if (widget.matchedOnly)
              _buildMatchesDropdown(colorScheme),

            _buildPriceRange(colorScheme),

            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear, size: 16),
              label: const Text("Wyczyść", style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 24),

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

  Widget _buildDropdown(String label, String? currentValue, List<String> options, Function(String?) onChanged, ColorScheme colorScheme) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: currentValue,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          hint: Text(label, style: const TextStyle(fontSize: 13)),
          items: [
            DropdownMenuItem(value: null, child: Text('$label: Wszystkie', style: const TextStyle(fontSize: 13))),
            ...options.map((e) => DropdownMenuItem(value: e, child: Text('$label: $e', style: const TextStyle(fontSize: 13)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildMatchesDropdown(ColorScheme colorScheme) {
    List<int> dynamicMatches = List.generate(_maxStoresScraped, (index) => index + 1);

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _minMatches,
          icon: const Icon(Icons.filter_alt_outlined, size: 18),
          hint: const Text('Dopasowania: Wszystkie', style: TextStyle(fontSize: 13)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Dopasowania: Wszystkie', style: TextStyle(fontSize: 13))),
            ...dynamicMatches.map((e) => DropdownMenuItem(
                  value: e,
                  child: Text('$e+ dopasowań ze sklepów', style: const TextStyle(fontSize: 13)),
                )),
          ],
          onChanged: (val) {
            setState(() { _minMatches = val; _currentPage = 1; });
            _fetchProducts();
          },
        ),
      ),
    );
  }

  Widget _buildPriceRange(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 80,
          height: 38,
          child: TextField(
            controller: _minPriceController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cena od',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) { setState(() => _currentPage = 1); _fetchProducts(); },
          ),
        ),
        const SizedBox(width: 8),
        const Text("-", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          height: 38,
          child: TextField(
            controller: _maxPriceController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cena do',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) { setState(() => _currentPage = 1); _fetchProducts(); },
          ),
        ),
      ],
    );
  }

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
        ).then((_) {
          _fetchProducts();
        });
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
                  Text("SKU: $sku | Kat: ${product['category'] ?? '-'} | Marka: ${product['manufacturer'] ?? '-'}", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
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
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

class ProductDetailsScreen extends StatefulWidget {
  final int productId;

  const ProductDetailsScreen({super.key, required this.productId});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _product;
  List<dynamic> _competitors = [];
  
  bool _isRecommending = false;
  double? _recommendedPrice;
  String? _recommendationReason;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final url = Uri.parse("/api/products/${widget.productId}");
      final response = await http.get(url, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          setState(() {
            _product = data['data'];
            _competitors = data['competitors'] ?? [];
          });
        }
      }
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Błąd pobierania detali: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getRecommendation() async {
    setState(() => _isRecommending = true);
    try {
      final url = Uri.parse("/api/products/${widget.productId}/recommend");
      final response = await http.post(url, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          setState(() {
            _recommendedPrice = data['recommendation'];
            _recommendationReason = data['reason'];
          });
        }
      }
    } catch (e) {
      debugPrint("Błąd AI: $e");
    } finally {
      setState(() => _isRecommending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text("Szczegóły Produktu", style: GoogleFonts.overpass()),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _product == null
              ? const Center(child: Text("Nie znaleziono produktu."))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProductHeader(colorScheme),
                      const SizedBox(height: 32),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildCompetitorsSection(colorScheme),
                          ),
                          const SizedBox(width: 32),
                          Expanded(
                            flex: 1,
                            child: _buildRecommendationSection(colorScheme),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProductHeader(ColorScheme colorScheme) {
    final String name = _product?['name'] ?? 'Brak nazwy';
    final String sku = _product?['sku'] ?? 'N/A';
    final String category = _product?['category'] ?? 'Brak kategorii';
    final double? priceNormal = _product?['price_normal'];
    final double? priceSpecial = _product?['price_special'];
    final String imageUrl = _product?['image'] ?? '';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, size: 50),
                    ),
                  )
                : const Icon(Icons.inventory, size: 50),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: GoogleFonts.overpass(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text("SKU: $sku", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (priceNormal != null && priceSpecial != null)
                Text(
                  "${priceNormal.toStringAsFixed(2)} zł",
                  style: TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 18,
                  ),
                ),
              Text(
                "${(priceSpecial ?? priceNormal ?? 0).toStringAsFixed(2)} zł",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 36,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompetitorsSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Ceny u konkurencji",
          style: GoogleFonts.overpass(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _competitors.isEmpty
            ? Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text("Brak danych o konkurencji (aktualnie wyświetlamy test_competitors jako główne produkty)"),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _competitors.length,
                itemBuilder: (context, index) {
                  final comp = _competitors[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(comp['comp_name'] ?? 'Nieznany konkurent'),
                      subtitle: Text("Sklep: ${comp['shop_label']}"),
                      trailing: Text(
                        "${comp['comp_price_special'] ?? comp['comp_price_normal'] ?? 0} zł",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }

  Widget _buildRecommendationSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Text(
                "Inteligentna wycena",
                style: GoogleFonts.overpass(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_recommendedPrice != null) ...[
            Text(
              "Sugerowana cena:",
              style: TextStyle(color: colorScheme.onSecondaryContainer.withOpacity(0.8)),
            ),
            const SizedBox(height: 8),
            Text(
              "${_recommendedPrice!.toStringAsFixed(2)} zł",
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _recommendationReason ?? "",
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            Text(
              "Nasz model AI może wyliczyć optymalną cenę dla tego produktu, analizując rynek.",
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSecondaryContainer.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 24),
          ],
          ElevatedButton(
            onPressed: _isRecommending ? null : _getRecommendation,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.onSecondaryContainer,
              foregroundColor: colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isRecommending
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: colorScheme.secondaryContainer,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    "Generuj rekomendację",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}

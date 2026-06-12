import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tonten/core/api/api_client.dart';

class ProductDetailsScreen extends StatefulWidget {
  final int productId;

  const ProductDetailsScreen({
    super.key,
    required this.productId,
  });

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

  String _subscriptionPlan = 'Podstawowy';

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final meResponse = await ApiClient.get(Uri.parse('/api/me'));
      if (meResponse.statusCode == 200) {
        final meData = jsonDecode(meResponse.body);
        if (meData['ok'] == true && meData['user'] != null) {
          _subscriptionPlan = meData['user']['subscription_plan'] ?? 'Podstawowy';
        }
      }

      final url = Uri.parse("/api/products/${widget.productId}");

      final response = await ApiClient.get(
        url,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['ok'] == true) {
          if (mounted) {
            setState(() {
              _product = data['data'];
              _competitors = data['competitors'] ?? [];
            });
          }
        } else {
          debugPrint("API error: ${data['error']}");
        }
      } else {
        debugPrint("HTTP error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Błąd pobierania detali: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _getRecommendation() async {
    if (mounted) {
      setState(() => _isRecommending = true);
    }

    try {
      final url = Uri.parse("/api/products/${widget.productId}/recommend");

      final response = await ApiClient.post(
        url,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['ok'] == true) {
          final rawRecommendation = data['recommendation'];

          if (mounted) {
            setState(() {
              _recommendedPrice = rawRecommendation is num
                  ? rawRecommendation.toDouble()
                  : double.tryParse(rawRecommendation?.toString() ?? '');

              _recommendationReason = data['reason']?.toString();
            });
          }
        }
      } else {
        debugPrint("HTTP recommendation error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Błąd AI: $e");
    } finally {
      if (mounted) {
        setState(() => _isRecommending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          "Szczegóły Produktu",
          style: GoogleFonts.overpass(),
        ),
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
    final String name = _product?['name']?.toString() ?? 'Brak nazwy';
    final String sku = _product?['sku']?.toString() ?? 'N/A';
    final String category = _product?['category']?.toString() ?? 'Brak kategorii';

    final num? priceNormal = _toNum(_product?['price_normal']);
    final num? priceSpecial = _toNum(_product?['price_special']);

    final String imageUrl = _product?['image']?.toString() ?? '';

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
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.image_not_supported, size: 50),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: GoogleFonts.overpass(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "SKU: $sku",
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
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
        style: GoogleFonts.overpass(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 16),
      _competitors.isEmpty
          ? Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text("Brak danych o konkurencji."),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _competitors.length,
              itemBuilder: (context, index) {
                final comp = _competitors[index];

                final String compName =
                    comp['comp_name']?.toString() ??
                    comp['name']?.toString() ??
                    'Nieznany produkt';

                final String shopName =
                    comp['shop_label']?.toString() ??
                    comp['store']?.toString() ??
                    'Nieznany sklep';

                final num? price = _toNum(
                  comp['comp_price_special'] ??
                      comp['comp_price_normal'] ??
                      comp['price_special'] ??
                      comp['price_normal'],
                );

                final String url = comp['url']?.toString() ?? '';
                final String imageUrl = comp['image']?.toString() ?? '';

                final num? priceDifference = _toNum(
                  comp['price_difference'],
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: imageUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.image_not_supported),
                                  ),
                                )
                              : const Icon(Icons.image_not_supported),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                compName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Sklep: $shopName",
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                              if (url.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (priceDifference != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  priceDifference == 0
                                      ? "Cena taka sama"
                                      : priceDifference > 0
                                          ? "Konkurencja drożej o ${priceDifference.toStringAsFixed(2)} zł"
                                          : "Konkurencja taniej o ${priceDifference.abs().toStringAsFixed(2)} zł",
                                  style: TextStyle(
                                    color: priceDifference > 0
                                        ? Colors.green
                                        : priceDifference < 0
                                            ? colorScheme.error
                                            : colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          price != null
                              ? "${price.toStringAsFixed(2)} zł"
                              : "Brak ceny",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    ],
  );
}

  Widget _buildRecommendationSection(ColorScheme colorScheme) {
    final hasPremium = _subscriptionPlan == 'Premium';

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
              Icon(
                Icons.auto_awesome,
                color: colorScheme.onSecondaryContainer,
              ),
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
          if (!hasPremium) ...[
            Icon(Icons.lock, size: 48, color: colorScheme.onSecondaryContainer.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              "Funkcja dostępna w pakiecie Premium.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Nasz model AI wyliczy dla Ciebie optymalną cenę. Zmień pakiet, aby odblokować.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSecondaryContainer.withOpacity(0.7),
              ),
            ),
          ] else ...[
            if (_recommendedPrice != null) ...[
              Text(
                "Sugerowana cena:",
                style: TextStyle(
                  color: colorScheme.onSecondaryContainer.withOpacity(0.8),
                ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  num? _toNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }
}
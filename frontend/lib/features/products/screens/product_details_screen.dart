import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tonten/core/api/api_client.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _launchCompetitorUrl(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie można otworzyć tego linku'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _fetchDetails() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final meResponse = await ApiClient.get(Uri.parse('/api/me'));
      if (meResponse.statusCode == 200) {
        final meData = jsonDecode(meResponse.body);
        if (meData['ok'] == true && meData['user'] != null) {
          _subscriptionPlan = meData['user']['subscription_plan'] ?? 'Podstawowy';
        }
      }

      final url = Uri.parse("/api/products/${widget.productId}");
      final response = await ApiClient.get(url, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && mounted) {
          setState(() {
            _product = data['data'];
            _competitors = data['competitors'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint("Błąd pobierania detali: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---- NAPRAWIONA FUNKCJA Z OBSŁUGĄ BŁĘDÓW ----
  Future<void> _getRecommendation() async {
    if (mounted) setState(() => _isRecommending = true);
    try {
      final url = Uri.parse("/api/products/${widget.productId}/recommend");
      final response = await ApiClient.post(url, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && mounted) {
          final rawRecommendation = data['recommendation'];
          setState(() {
            _recommendedPrice = rawRecommendation is num
                ? rawRecommendation.toDouble()
                : double.tryParse(rawRecommendation?.toString() ?? '');
            _recommendationReason = data['reason']?.toString();
          });
        } else if (mounted) {
          // Jeśli Python zwróci błąd, wyświetlimy go na czerwonym pasku!
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Błąd AI: ${data['error'] ?? 'Nieznany błąd'}'), backgroundColor: Colors.red),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd serwera (HTTP ${response.statusCode})'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint("Błąd AI: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd połączenia: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecommending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMatches = _competitors.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text("Szczegóły produktu", style: GoogleFonts.overpass(fontWeight: FontWeight.w600)),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _product == null
              ? const Center(child: Text("Nie znaleziono produktu."))
              : Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProductHeader(colorScheme),
                      const SizedBox(height: 24),
                      
                      if (hasMatches) ...[
                        DefaultTabController(
                          length: 2,
                          child: Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5))),
                                  ),
                                  child: TabBar(
                                    labelColor: colorScheme.primary,
                                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                                    indicatorColor: colorScheme.primary,
                                    indicatorWeight: 3,
                                    tabs: const [
                                      Tab(text: "Porównanie cen"),
                                      Tab(text: "Specyfikacja"),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      SingleChildScrollView(
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(flex: 2, child: _buildCompetitorsSection(colorScheme)),
                                            const SizedBox(width: 32),
                                            Expanded(flex: 1, child: _buildRecommendationSection(colorScheme)),
                                          ],
                                        ),
                                      ),
                                      SingleChildScrollView(
                                        child: _buildSpecificationTab(colorScheme),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        // Wyświetlamy panel AI obok specyfikacji nawet dla produktów bez konkurencji
                        Expanded(
                          child: SingleChildScrollView(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: _buildSpecificationTab(colorScheme)),
                                const SizedBox(width: 32),
                                Expanded(flex: 1, child: _buildRecommendationSection(colorScheme)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildProductHeader(ColorScheme colorScheme) {
    final String name = _product?['name']?.toString() ?? 'Brak nazwy';
    final String sku = _product?['sku']?.toString() ?? 'N/A';
    final num? priceNormal = _toNum(_product?['price_normal']);
    final num? priceSpecial = _toNum(_product?['price_special']);
    
    final String imageUrl = _product?['image']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 120,
            height: 120,
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
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, size: 40),
                    ),
                  )
                : const Icon(Icons.inventory, size: 40),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.overpass(fontSize: 28, fontWeight: FontWeight.bold)),
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
                    fontSize: 16,
                  ),
                ),
              Text(
                "${(priceSpecial ?? priceNormal ?? 0).toStringAsFixed(2)} zł",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 32, color: colorScheme.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecificationTab(ColorScheme colorScheme) {
    final String category = _product?['category']?.toString() ?? '-';
    final String manufacturer = _product?['manufacturer']?.toString() ?? '-';
    final String color = _product?['color']?.toString() ?? '-';
    final String size = _product?['size']?.toString() ?? '-';
    final String availability = _product?['availability']?.toString() ?? '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Specyfikacja techniczna", style: GoogleFonts.overpass(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                _buildSimpleSpecRow("Kategoria", category, true, colorScheme),
                _buildSimpleSpecRow("Producent", manufacturer, false, colorScheme),
                _buildSimpleSpecRow("Kolor", color, true, colorScheme),
                _buildSimpleSpecRow("Rozmiar", size, false, colorScheme),
                _buildSimpleSpecRow("Dostępność", availability, true, colorScheme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleSpecRow(String label, String value, bool isEven, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: isEven ? colorScheme.surfaceContainerHighest.withOpacity(0.3) : colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          ),
          Expanded(
            flex: 3,
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompetitorsSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Zarejestrowane oferty rynku", style: GoogleFonts.overpass(fontSize: 20, fontWeight: FontWeight.bold)),
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
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _competitors.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.3)),
                itemBuilder: (context, index) {
                  final comp = _competitors[index];
                  final String compName = comp['comp_name']?.toString() ?? comp['name']?.toString() ?? 'Nieznany produkt';
                  final String shopName = comp['shop_label']?.toString() ?? comp['store']?.toString() ?? 'Nieznany sklep';
                  final num? price = _toNum(comp['comp_price_special'] ?? comp['comp_price_normal'] ?? comp['price_special'] ?? comp['price_normal']);
                  final String url = comp['url']?.toString() ?? '';
                  
                  final String imageUrl = comp['image']?.toString() ?? '';
                  
                  final num? priceDifference = _toNum(comp['price_difference']);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: imageUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, size: 24),
                                  ),
                                )
                              : const Icon(Icons.image_not_supported, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(compName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text("Sklep: $shopName", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                              if (url.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () => _launchCompetitorUrl(url),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.open_in_new, size: 12, color: colorScheme.primary),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          "Otwórz ofertę",
                                          style: TextStyle(color: colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(price != null ? "${price.toStringAsFixed(2)} zł" : "Brak ceny", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.primary)),
                            if (priceDifference != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: priceDifference == 0 ? colorScheme.surfaceContainerHighest : priceDifference > 0 ? Colors.green.withOpacity(0.15) : colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  priceDifference == 0
                                      ? "Cena równa"
                                      : priceDifference > 0
                                          ? "+ ${priceDifference.toStringAsFixed(2)} zł drożej"
                                          : "- ${priceDifference.abs().toStringAsFixed(2)} zł taniej",
                                  style: TextStyle(
                                    color: priceDifference == 0 ? colorScheme.onSurface : priceDifference > 0 ? Colors.green[800] : colorScheme.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }

  Widget _buildRecommendationSection(ColorScheme colorScheme) {
    final hasPremium = _subscriptionPlan == 'Premium';
    
    final hasMatches = _competitors.isNotEmpty; 

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.secondary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.secondary),
              const SizedBox(width: 10),
              Text("Inteligentna wycena", style: GoogleFonts.overpass(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer)),
            ],
          ),
          const SizedBox(height: 24),
          if (!hasPremium) ...[
            Icon(Icons.lock_outline, size: 48, color: colorScheme.secondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text("Wymagany pakiet Premium", textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer)),
            const SizedBox(height: 8),
            Text("Model AI przeanalizuje rynek i wskaże idealną cenę.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: colorScheme.onSecondaryContainer.withOpacity(0.8))),
          ] else ...[
            if (_recommendedPrice != null) ...[
              Text("Sugerowana cena:", style: TextStyle(color: colorScheme.onSecondaryContainer.withOpacity(0.8), fontSize: 13)),
              const SizedBox(height: 4),
              Text("${_recommendedPrice!.toStringAsFixed(2)} zł", style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: colorScheme.secondary)),
              const SizedBox(height: 16),
              Text(_recommendationReason ?? "", style: TextStyle(fontSize: 13, height: 1.5, color: colorScheme.onSecondaryContainer)),
              const SizedBox(height: 24),
            ] else ...[
              Text(
                hasMatches 
                  ? "Model AI jest gotowy do analizy tego produktu." 
                  : "Model AI nie ma danych rynkowych dla tego produktu.", 
                style: TextStyle(fontSize: 13, height: 1.5, color: colorScheme.onSecondaryContainer.withOpacity(0.8))
              ),
              const SizedBox(height: 24),
            ],
            FilledButton.icon(
              onPressed: _isRecommending || !hasMatches ? null : _getRecommendation,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.secondary,
                foregroundColor: colorScheme.onSecondary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _isRecommending 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : (hasMatches ? const Icon(Icons.psychology) : const Icon(Icons.block)),
              label: Text(
                _isRecommending 
                    ? "Analizowanie..." 
                    : (hasMatches ? "Generuj cenę" : "Brak ofert z rynku"), 
                style: const TextStyle(fontWeight: FontWeight.bold)
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
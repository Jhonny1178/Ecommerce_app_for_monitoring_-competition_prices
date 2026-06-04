import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tonten/core/api/api_client.dart';
import 'dart:convert';
import '../../products/screens/products_list_screen.dart';
import '../../../core/utils/dialog_utils.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isFabExpanded = false;
  int _selectedTabIndex = 0;
  bool _isLoadingStats = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final url = Uri.parse("/api/stats");
      final response = await ApiClient.get(url, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          setState(() {
            _stats = data['summary'] ?? {};
          });
        }
      }
      setState(() => _isLoadingStats = false);
    } catch (e) {
      debugPrint("Błąd pobierania statystyk: $e");
      setState(() => _isLoadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _buildAppBar(colorScheme),
      floatingActionButton: _buildExpandableFab(colorScheme),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCustomTabBar(colorScheme),
            const SizedBox(height: 32),
            if (_selectedTabIndex == 0) ...[
              _isLoadingStats
                ? const Center(child: CircularProgressIndicator())
                : _buildKpiSection(colorScheme),
            ] else if (_selectedTabIndex == 1) ...[
              const SizedBox(
                height: 800,
                child: ProductsListScreen(),
              ),
            ]
          ],
        ),
      ),
    );
  }
  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 80,
      title: Text(
        'e-ROCH',
        style: GoogleFonts.overpass(fontSize: 64),
      ),
      actions: [

        IconButton(
          icon: const Icon(Icons.account_circle_outlined, size: 28),
          onPressed: () {},
        ),
        const SizedBox(width: 16),
      ],
    );
  }
  Widget _buildCustomTabBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTabButton('Dashboard', 0, colorScheme),
          _buildTabButton('Produkty', 1, colorScheme),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index, ColorScheme colorScheme) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiSection(ColorScheme colorScheme) {
    final totalProducts = _stats['total']?.toString() ?? '0';
    final avgPrice = _stats['avg_price_normal'] != null
      ? '${_stats['avg_price_normal']} zł'
      : 'Brak danych';

    final totalStores = _stats['total_stores']?.toString() ?? '0';
    return Row(
      children: [
        Expanded(child: _buildKpiCard('Produkty w bazie', totalProducts, '', colorScheme)),
        const SizedBox(width: 16),
        Expanded(child: _buildKpiCard('Średnia cena', avgPrice, '', colorScheme)),
        const SizedBox(width: 16),
        Expanded(child: _buildKpiCard('Monitorowane sklepy', totalStores, '', colorScheme)),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, String hint, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 16),
          Center(child: Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold))),
          const SizedBox(height: 16),
          Center(
            child: Text(hint, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
          ),
        ],
      ),
    );
  }
  Widget _buildExpandableFab(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _isFabExpanded
            ? Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    heroTag: 'reportErrorFab',
                    onPressed: () => DialogUtils.showReportBugDialog(context),
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    elevation: 1,
                    icon: const Icon(Icons.error_outline),
                    label: const Text('Zgłoś błąd'),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    heroTag: 'settingsFab',
                    onPressed: () {},
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    elevation: 1,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Ustawienia'),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
        ),
        FloatingActionButton(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          heroTag: 'menuToggleFab',
          onPressed: () {
            setState(() {
              _isFabExpanded = !_isFabExpanded;
            });
          },
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 2,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            ),
            child: Icon(
              _isFabExpanded ? Icons.close : Icons.menu,
              key: ValueKey<bool>(_isFabExpanded),
            ),                             
          ),
        ),
      ],
    );
  }
}

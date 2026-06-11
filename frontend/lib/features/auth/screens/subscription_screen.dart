import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';
import 'dart:convert';
import 'auth_router.dart';
import 'login_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = false;

  Future<void> _buyPackage(String package) async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse("/api/subscription/buy");
      final response = await ApiClient.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'package': package}));
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AuthRouter(status: 'pending_admin', isAdmin: false)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'] ?? 'Błąd'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd połączenia: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _logout() async {
    await ApiClient.post(Uri.parse("/api/logout"));
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Wybierz Pakiet'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _logout)],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Text('Konto wstępnie skonfigurowane!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Wybierz plan, aby rozpocząć korzystanie z e-ROCH. Pierwszy miesiąc jest darmowy.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPackageCard('Podstawowy', '300 zł/m-c', ['Codzienna aktualizacja cen konkurencji'], 'Podstawowy', colorScheme),
                  const SizedBox(width: 24),
                  _buildPackageCard('Pro', '400 zł/m-c', ['Codzienna aktualizacja cen konkurencji', 'Historia cen konkurencji'], 'Pro', colorScheme, featured: true),
                  const SizedBox(width: 24),
                  _buildPackageCard('Premium', '500 zł/m-c', ['Codzienna aktualizacja cen konkurencji', 'Historia cen konkurencji', 'Inteligentna rekomendacja cen'], 'Premium', colorScheme),
                ],
              ),
              const SizedBox(height: 48),
              const Text(
                'Twój wniosek po wyborze pakietu trafi do weryfikacji przez administratora.\nW przyszłości będziesz mógł zmienić pakiet lub z niego zrezygnować.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackageCard(String title, String price, List<String> features, String packageId, ColorScheme colorScheme, {bool featured = false}) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: featured ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: featured ? Border.all(color: colorScheme.primary, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: featured ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text(price, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: featured ? colorScheme.onPrimaryContainer : colorScheme.onSurface)),
          const SizedBox(height: 24),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [const Icon(Icons.check, size: 16), const SizedBox(width: 8), Expanded(child: Text(f))]),
          )),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isLoading ? null : () => _buyPackage(packageId),
            style: FilledButton.styleFrom(
              backgroundColor: featured ? colorScheme.primary : colorScheme.secondary,
              foregroundColor: featured ? colorScheme.onPrimary : colorScheme.onSecondary,
            ),
            child: const Text('Wybierz i aktywuj'),
          ),
        ],
      ),
    );
  }
}

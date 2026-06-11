import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';
import 'dart:convert';
import 'auth_router.dart';
import 'login_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  final bool isChangingPlan;
  final String? currentPlan;

  const SubscriptionScreen({
    super.key,
    this.isChangingPlan = false,
    this.currentPlan,
  });

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = false;

  Future<void> _buyPackage(String package) async {
    setState(() => _isLoading = true);
    try {
      final endpoint = widget.isChangingPlan ? "/api/subscription/change" : "/api/subscription/buy";
      final url = Uri.parse(endpoint);
      final response = await ApiClient.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'package': package}));
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          if (widget.isChangingPlan) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pakiet został zmieniony.'), backgroundColor: Colors.green));
            Navigator.of(context).pop(true); // Wracamy do dashboardu, informując o zmianie
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AuthRouter(status: 'pending_admin', isAdmin: false)),
            );
          }
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
        title: Text(widget.isChangingPlan ? 'Zmiana Pakietu' : 'Wybierz Pakiet'),
        actions: [
          if (!widget.isChangingPlan)
            IconButton(icon: const Icon(Icons.logout), onPressed: _logout)
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Text(
                widget.isChangingPlan ? 'Wybierz nowy pakiet' : 'Konto wstępnie skonfigurowane!',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isChangingPlan 
                    ? 'Wybierz nowy plan. Zmiana zostanie zastosowana natychmiastowo.'
                    : 'Wybierz plan, aby rozpocząć korzystanie z e-ROCH. Pierwszy miesiąc jest darmowy.',
                style: const TextStyle(fontSize: 16),
              ),
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
              if (!widget.isChangingPlan)
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
          ElevatedButton(
            onPressed: _isLoading || (widget.currentPlan == packageId) ? null : () => _buyPackage(packageId),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              _isLoading 
                  ? 'Przetwarzanie...' 
                  : (widget.currentPlan == packageId ? 'Aktualny plan' : 'Wybierz'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

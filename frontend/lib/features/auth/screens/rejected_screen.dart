import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';
import 'login_screen.dart';

class RejectedScreen extends StatelessWidget {
  const RejectedScreen({super.key});

  void _logout(BuildContext context) async {
    await ApiClient.post(Uri.parse("/api/logout"));
    if (context.mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Odrzucono'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => _logout(context))
        ],
      ),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel, size: 64, color: colorScheme.error),
              const SizedBox(height: 24),
              const Text(
                'Twój wniosek został odrzucony',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Niestety, po analizie Twojego pliku oraz stron konkurencji, nie jesteśmy w stanie podjąć współpracy. Zostałeś powiadomiony mailowo o szczegółach.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

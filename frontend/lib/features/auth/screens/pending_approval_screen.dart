import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';
import 'login_screen.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

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
        title: const Text('Oczekiwanie na weryfikację'),
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
              Icon(Icons.hourglass_empty, size: 64, color: colorScheme.primary),
              const SizedBox(height: 24),
              const Text(
                'Twój wniosek jest analizowany',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'System weryfikuje podane dane oraz przesłany plik z produktami. Otrzymasz od nas informację mailową z ostateczną decyzją w przeciągu 5 dni roboczych.',
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

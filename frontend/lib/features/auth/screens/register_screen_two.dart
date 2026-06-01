import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RegisterScreenTwo extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onSuccess;
  final String name;
  final String surname;
  final String email;

  const RegisterScreenTwo({
    super.key, 
    required this.onBack,
    required this.onSuccess,
    required this.name,
    required this.surname,
    required this.email,
    });

  @override
  State<RegisterScreenTwo> createState() => _RegisterScreenTwoState();
}

class _RegisterScreenTwoState extends State<RegisterScreenTwo> {
  final _mainDomainController = TextEditingController();

  final List<TextEditingController> _competitors = [TextEditingController()];

  bool _isLoading = false;

  Future<void> _submitRegistration() async {
    setState(() => _isLoading = true);

    try {
      final url = Uri.parse("/api/register");
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'company_name': _mainDomainController.text, 
          'email': widget.email,
          'urls': _competitors.map((c) => c.text).where((text) => text.isNotEmpty).toList(),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Sukces!'), backgroundColor: Colors.green),
        );
        widget.onSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? 'Błąd rejestracji'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd połączenia: $e'), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _mainDomainController.dispose();
    for (var controller in _competitors) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addCompetitor() {
    if (_competitors.length < 5) {
      setState(() {
        _competitors.add(TextEditingController());
      });
    }
  }

  void _removeCompetitor(int index) {
    setState(() {
      _competitors[index].dispose();
      _competitors.removeAt(index);
    });
  }

  bool get _isValid {
    if (_mainDomainController.text.isEmpty) return false;
    for (var controller in _competitors) {
      if (controller.text.isEmpty) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _mainDomainController,
            onChanged: (val) => setState(() {}),
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surfaceContainerHigh,
              labelText: 'Domena Twojego sklepu',
              hintText: 'Wpisz domenę swojego sklepu...',
              border: const UnderlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          
          if (_competitors.length < 5)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                children: [
                  InkWell(
                    onTap: _addCompetitor,
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      backgroundColor: colorScheme.primary,
                      radius: 16,
                      child: Icon(Icons.add, color: colorScheme.onPrimary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Text(
                        'Dodaj 1-5 domen sklepów konkurencji',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ...List.generate(_competitors.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _removeCompetitor(index),
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      backgroundColor: colorScheme.primary,
                      radius: 16,
                      child: Icon(Icons.remove, color: colorScheme.onPrimary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: TextField(
                      controller: _competitors[index],
                      onChanged: (val) => setState(() {}),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHigh,
                        labelText: 'Domena sklepu konkurencji nr ${index + 1}',
                        hintText: 'Wpisz domenę sklepu konkurencji...',
                        border: const UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.undo),
                label: const Text('Wróć'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  side: BorderSide(color: colorScheme.outline),
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: FilledButton(
                  onPressed: _isValid && !_isLoading ? _submitRegistration : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  ),
                  child: const Text(
                    'Wyślij wniosek o zarejestrowanie sklepu',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ],
      )
    );
  }
}
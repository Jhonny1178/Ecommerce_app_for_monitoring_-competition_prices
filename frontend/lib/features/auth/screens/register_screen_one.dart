import 'package:flutter/material.dart';

class RegisterScreenOne extends StatefulWidget {
  final Function(String name, String surname, String email, String password) onNext;

  const RegisterScreenOne({super.key, required this.onNext});

  @override
  State<RegisterScreenOne> createState() => _RegisterScreenOneState();
}

class _RegisterScreenOneState extends State<RegisterScreenOne> {
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isValid {
    return _nameController.text.isNotEmpty &&
          _surnameController.text.isNotEmpty &&
          _emailController.text.isNotEmpty &&
          _passwordController.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildField(context, 'Imię', 'Wpisz swoje imię...', _nameController),
          const SizedBox(height: 20),
          _buildField(context, 'Nazwisko', 'Wpisz swoje nazwisko...', _surnameController),
          const SizedBox(height: 20),
          _buildField(context, 'E-mail', 'Wpisz swój e-mail...', _emailController),
          const SizedBox(height: 20),
          _buildField(context, 'Hasło', 'Wpisz swoje hasło...', _passwordController, obscureText: true),
          const SizedBox(height: 32),
          Center(
            child: FilledButton(
              onPressed: _isValid ? () {
                widget.onNext(
                  _nameController.text,
                  _surnameController.text,
                  _emailController.text,
                  _passwordController.text
                );
              } : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
              child: const Text('Przejdź do drugiego etapu rejestracji'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(BuildContext context, String label, String hint, TextEditingController controller, {bool obscureText = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: (val) => setState(() {}),
      decoration: InputDecoration(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        labelText: label,
        hintText: hint,
        border: const UnderlineInputBorder(),
      ),
    );
  }
}
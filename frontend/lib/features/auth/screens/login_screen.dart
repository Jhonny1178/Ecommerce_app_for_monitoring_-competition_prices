import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_router.dart';
import 'register_screen_one.dart';
import 'register_screen_two.dart';
import '../../../core/utils/dialog_utils.dart';

class LoginScreen extends StatefulWidget {
  final int initialTabIndex;
  const LoginScreen({super.key, this.initialTabIndex = 0});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isPasswordObscured = true;
  bool _isFabExpanded = false;

  String _regName = '';
  String _regSurname = '';
  String _regEmail = '';
  String _regPassword = '';

  int _registerStep = 1;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse("/api/login");
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username':_emailController.text,
          'password': _passwordController.text,
        }),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['ok'] == true) {
        final status = responseData['status'] ?? 'active';
        final isAdmin = responseData['is_admin'] == true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AuthRouter(status: status, isAdmin: isAdmin)),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zalogowano pomyślnie!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(responseData['error'] ?? 'Nieznany błąd logowania'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Błąd komunikacji z serwerem: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _nextStep(String name, String surname, String email, String password) {
     setState(() {
      _regName = name;
      _regSurname = surname;
      _regEmail = email;
      _regPassword = password;
      _registerStep = 2;
    });
  }
  void _prevStep() => setState(() => _registerStep = 1);

  bool get _isLoginValid {
    return _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _isFabExpanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FloatingActionButton.extended(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        heroTag: 'reportErrorFab',
                        onPressed: () =>
                            DialogUtils.showReportBugDialog(context),
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                        elevation: 1,
                        icon: const Icon(Icons.error_outline),
                        label: const Text('Zgłoś błąd'),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton.extended(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        heroTag: 'settingsFabGlobal',
                        onPressed: () => DialogUtils.showSettingsDialog(context),
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
      ),

      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant, 
                    width: 1),
                ),
              ),
              child: Center(
                child: Text(
                  'e-ROCH',
                  style: GoogleFonts.overpass(
                    fontSize: 64,
                  ),
                ),
              ),
            ),

            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 500,
                    margin: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer, 
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                            border: Border(
                              top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
                              left: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
                              right: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
                            ),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.label,
                            labelColor: colorScheme.primary,
                            unselectedLabelColor: colorScheme.onSurfaceVariant,
                            indicatorColor: colorScheme.primary,
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(text: 'Login'),
                              Tab(text: 'Rejestracja'),
                            ],
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _tabController,
                          builder:(context, child) {
                            if (_tabController.index == 0) {
                              return _buildLoginForm(colorScheme);
                            }
                            else {
                              return _registerStep == 1
                                ? RegisterScreenOne(onNext: _nextStep)
                                : RegisterScreenTwo(
                                  onBack: _prevStep,
                                  email: _regEmail,
                                  name: _regName,
                                  surname: _regSurname,
                                  password: _regPassword,
                                  onSuccess: () {
                                    _tabController.animateTo(0);
                                    _prevStep();
                                  }
                                );
                            }
                          },
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailController,
            onChanged: (val) => setState(() {}),
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surfaceContainerHigh,
              labelText: 'E-mail',
              hintText: 'Wpisz swój e-mail...',
              border: const UnderlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          
          TextField(
            controller: _passwordController,
            onChanged: (val) => setState(() {}),
            onSubmitted: (_) => _login(),
            obscureText: _isPasswordObscured,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surfaceContainerHigh,
              labelText: 'Hasło',
              hintText: 'Wpisz swoje hasło...',
              border: const UnderlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordObscured = !_isPasswordObscured;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 32),

          Center(
            child: FilledButton(
              onPressed: (_isLoginValid && !_isLoading) ?  _login : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40, vertical: 20
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _isLoading
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                )
                : const Text(
                  'Zaloguj się',
                  style: TextStyle(fontSize: 16),
                ),
            ),
          ),
        ],
      ),
    );
  }
}
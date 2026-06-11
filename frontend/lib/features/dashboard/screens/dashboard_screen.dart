import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tonten/core/api/api_client.dart';

import '../../products/screens/products_list_screen.dart';
import '../../../core/utils/dialog_utils.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/screens/file_upload_screen.dart';
import '../../auth/screens/subscription_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isFabExpanded = false;
  int _selectedTabIndex = 0;
  bool _isLoadingStats = true;
  bool _isCheckingUserStatus = true;
  final TextEditingController _newPasswordController = TextEditingController();
  bool _isChangingPassword = false;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
    _fetchStats();
  }

  Future<void> _checkUserStatus() async {
    try {
      final response = await ApiClient.get(
        Uri.parse('/api/me'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        if (mounted) {
          setState(() => _isCheckingUserStatus = false);
        }
        return;
      }

      final data = jsonDecode(response.body);

      if (data['ok'] != true) {
        if (mounted) {
          setState(() => _isCheckingUserStatus = false);
        }
        return;
      }

      final user = data['user'] ?? {};
      final status = user['status']?.toString();

      if (!mounted) return;

      if (status == 'onboarding_required') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FileUploadScreen()),
        );
        return;
      }

      setState(() => _isCheckingUserStatus = false);
    } catch (e) {
      debugPrint('Błąd sprawdzania statusu użytkownika: $e');

      if (mounted) {
        setState(() => _isCheckingUserStatus = false);
      }
    }
  }

  Future<void> _fetchStats() async {
    try {
      final response = await ApiClient.get(
        Uri.parse('/api/stats'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['ok'] == true) {
          if (mounted) {
            setState(() {
              _stats = data['summary'] ?? {};
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Błąd pobierania statystyk: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  Future<void> _openProfileOrOnboarding() async {
  try {
    final response = await ApiClient.get(Uri.parse('/api/me'), headers: {'Accept': 'application/json'});
    if (!mounted) return;
    
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Błąd profilu'), backgroundColor: Colors.red));
      return;
    }
    
    final data = jsonDecode(response.body);
    final user = data['user'] ?? {};
    final status = user['status']?.toString();
    
    if (status == 'onboarding_required') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FileUploadScreen()));
      return;
    }
    
    final onboardingRequest = data['onboarding_request'] ?? {};
    final onboardingSource = data['onboarding_source'] ?? {};
    final mappings = data['field_mappings'] as List? ?? [];
    final competitors = onboardingRequest['competitor_urls'] as List? ?? user['competitor_urls'] as List? ?? [];

    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          backgroundColor: colorScheme.surface,
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 800,
            height: 600,
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Profil i Ustawienia', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        IconButton(icon: Icon(Icons.close, color: colorScheme.onSurface), onPressed: () => Navigator.pop(dialogContext)),
                      ],
                    ),
                  ),
                  TabBar(
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    indicatorColor: colorScheme.primary,
                    tabs: const [
                      Tab(text: 'Dane konta i sklepu', icon: Icon(Icons.person)),
                      Tab(text: 'Subskrypcja', icon: Icon(Icons.payment)),
                      Tab(text: 'Bezpieczeństwo', icon: Icon(Icons.security)),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Zakładka 1: Dane
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _dialogSectionTitle('Dane użytkownika', colorScheme),
                              _infoLine('Imię i nazwisko', '${user['first_name'] ?? '-'} ${user['last_name'] ?? ''}'),
                              _infoLine('Email', '${user['email'] ?? user['username'] ?? '-'}'),
                              const Divider(),
                              _dialogSectionTitle('Dane sklepu', colorScheme),
                              _infoLine('Nazwa sklepu', '${onboardingRequest['requested_store_name'] ?? user['client_name'] ?? '-'}'),
                              _infoLine('Domena', '${onboardingRequest['company_domain'] ?? user['company_domain'] ?? '-'}'),
                              const Divider(),
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FileUploadScreen()));
                                },
                                icon: const Icon(Icons.edit),
                                label: const Text('Edytuj konfigurację techniczną'),
                              ),
                            ],
                          ),
                        ),
                        // Zakładka 2: Płatności
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.stars, size: 64, color: Colors.amber),
                              const SizedBox(height: 16),
                              Text('Twój aktualny plan:', style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant)),
                              Text('${user['subscription_plan'] ?? 'Brak'}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                              const SizedBox(height: 24),
                              Text('Zarządzanie płatnościami pozwala na zmianę lub anulowanie subskrypcji systemu e-ROCH.', style: TextStyle(color: colorScheme.onSurface)),
                              const SizedBox(height: 32),
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                                },
                                icon: const Icon(Icons.payment),
                                label: const Text('Zmień plan / Zarządzaj płatnościami'),
                              ),
                            ],
                          ),
                        ),
                        // Zakładka 3: Bezpieczeństwo
                        StatefulBuilder(
                          builder: (context, setTabState) {
                            return Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Zmiana hasła', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _newPasswordController,
                                    obscureText: true,
                                    decoration: InputDecoration(
                                      labelText: 'Nowe hasło',
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                    onPressed: _isChangingPassword ? null : () async {
                                      if (_newPasswordController.text.length < 6) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hasło musi mieć min. 6 znaków'), backgroundColor: Colors.red));
                                        return;
                                      }
                                      setTabState(() => _isChangingPassword = true);
                                      try {
                                        final res = await ApiClient.post(
                                          Uri.parse('/api/change_password'),
                                          headers: {'Content-Type': 'application/json'},
                                          body: jsonEncode({'new_password': _newPasswordController.text}),
                                        );
                                        if (res.statusCode == 200) {
                                          _newPasswordController.clear();
                                          if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hasło zmienione pomyślnie'), backgroundColor: Colors.green));
                                        }
                                      } finally {
                                        setTabState(() => _isChangingPassword = false);
                                      }
                                    },
                                    child: _isChangingPassword ? const CircularProgressIndicator(color: Colors.white) : const Text('Zapisz nowe hasło'),
                                  )
                                ],
                              ),
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd profilu: $e'), backgroundColor: Colors.red));
  }
}

  void _logout() async {
    await ApiClient.post(Uri.parse('/api/logout'));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isCheckingUserStatus) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: _buildExpandableFab(colorScheme),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(colorScheme),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
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
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'e-ROCH',
            style: GoogleFonts.overpass(
              fontSize: 64,
            ),
          ),
          Positioned(
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none, size: 28),
                  onPressed: () {},
                ),
                PopupMenuButton<String>(
                  offset: const Offset(0, 50),
                  icon: const Icon(Icons.account_circle_outlined, size: 28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    if (value == 'profile') _openProfileOrOnboarding();
                    if (value == 'logout') _logout();
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'profile',
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Profil / konfiguracja',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout,
                            color: colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Wyloguj się',
                            style: TextStyle(
                              color: colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
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
        Expanded(
          child: _buildKpiCard(
            'Produkty w bazie',
            totalProducts,
            '',
            colorScheme,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKpiCard(
            'Średnia cena',
            avgPrice,
            '',
            colorScheme,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKpiCard(
            'Monitorowane sklepy',
            totalStores,
            '',
            colorScheme,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(
    String title,
    String value,
    String hint,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              hint,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
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
    );
  }

  Widget _dialogSectionTitle(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    final normalizedValue = value.trim().isEmpty ? '-' : value;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              normalizedValue,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
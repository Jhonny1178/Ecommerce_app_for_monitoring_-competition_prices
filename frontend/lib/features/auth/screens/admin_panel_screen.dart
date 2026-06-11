import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tonten/core/api/api_client.dart';
import 'dart:convert';
import 'login_screen.dart';
import 'admin_user_details_screen.dart';
import '../../../../main.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _selectedTabIndex = 0;

  bool _isLoadingUsers = true;
  List<dynamic> _users = [];

  bool _isLoadingLogs = true;
  List<dynamic> _logs = [];
  int _currentLogPage = 1;
  int _totalLogPages = 1;

  String _searchQuery = "";
  String? _filterCategory;
  String? _filterErrorType;
  bool? _filterIsReviewed;
  DateTime? _filterDateBefore;
  DateTime? _filterDateAfter;
  final TextEditingController _searchController = TextEditingController();

  bool _isFabExpanded = false;

  bool _isLoadingStores = true;
  List<dynamic> _stores = [];

  bool _isLoadingRegRequests = true;
  List<dynamic> _regRequests = [];

  @override
  void initState() {
    super.initState();
    _fetchPendingUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPendingUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final response = await ApiClient.get(Uri.parse("/api/admin/pending_users"));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() => _users = data['users'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching users: $e");
    } finally {
      setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _fetchErrorLogs() async {
    setState(() => _isLoadingLogs = true);
    try {
      String urlStr = "/api/admin/error_logs?page=$_currentLogPage&per_page=10";
      if (_searchQuery.isNotEmpty) urlStr += "&search=$_searchQuery";
      if (_filterCategory != null && _filterCategory!.isNotEmpty) urlStr += "&category=$_filterCategory";
      if (_filterErrorType != null && _filterErrorType!.isNotEmpty) urlStr += "&error_type=$_filterErrorType";
      if (_filterIsReviewed != null) urlStr += "&is_reviewed=$_filterIsReviewed";
      if (_filterDateBefore != null) urlStr += "&date_before=${_filterDateBefore!.toIso8601String().substring(0, 10)}";
      if (_filterDateAfter != null) urlStr += "&date_after=${_filterDateAfter!.toIso8601String().substring(0, 10)}";

      final response = await ApiClient.get(Uri.parse(urlStr));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() {
          _logs = data['data'] ?? [];
          _totalLogPages = data['pagination']['total_pages'] ?? 1;
        });
      }
    } catch (e) {
      debugPrint("Error fetching logs: $e");
    } finally {
      setState(() => _isLoadingLogs = false);
    }
  }

  Future<void> _fetchStores() async {
    setState(() => _isLoadingStores = true);
    try {
      final response = await ApiClient.get(Uri.parse("/api/admin/supported_stores"));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() => _stores = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching stores: $e");
    } finally {
      setState(() => _isLoadingStores = false);
    }
  }

  Future<void> _fetchRegRequests() async {
    setState(() => _isLoadingRegRequests = true);
    try {
      final response = await ApiClient.get(Uri.parse("/api/admin/registration_requests"));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() => _regRequests = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching reg requests: $e");
    } finally {
      setState(() => _isLoadingRegRequests = false);
    }
  }

  Future<void> _approveRegistrationRequest(
    Map<String, dynamic> req, {
    bool closeDialog = false,
  }) async {
    try {
      final requestId = req['request_id'];
      final userId = req['user_id'] ?? req['id'];

      final response = await ApiClient.post(
        Uri.parse("/api/admin/approve_user"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "request_id": requestId,
          "user_id": userId,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          if (closeDialog) {
            Navigator.pop(context);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wniosek został zatwierdzony. Klient i tabele zostały utworzone.'),
              backgroundColor: Colors.green,
            ),
          );
        }

        await _fetchPendingUsers();
        await _fetchStores();
        await _fetchRegRequests();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error']?.toString() ?? 'Nie udało się zatwierdzić wniosku.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error approving registration request: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Błąd zatwierdzania wniosku: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectRegistrationRequest(
    Map<String, dynamic> req, {
    bool closeDialog = false,
  }) async {
    try {
      final requestId = req['request_id'];
      final userId = req['user_id'] ?? req['id'];

      final response = await ApiClient.post(
        Uri.parse("/api/admin/reject_user"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "request_id": requestId,
          "user_id": userId,
          "reason": "Odrzucono przez administratora",
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          if (closeDialog) {
            Navigator.pop(context);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wniosek został odrzucony.'),
              backgroundColor: Colors.orange,
            ),
          );
        }

        await _fetchPendingUsers();
        await _fetchStores();
        await _fetchRegRequests();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error']?.toString() ?? 'Nie udało się odrzucić wniosku.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error rejecting registration request: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Błąd odrzucania wniosku: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _updateReviewStatus(int logId, {bool? isReviewed, String? resolvedAtDateStr}) async {
    try {
      Map<String, dynamic> bodyData = {};
      if (isReviewed != null) bodyData['is_reviewed'] = isReviewed;
      if (resolvedAtDateStr != null) bodyData['resolved_at'] = resolvedAtDateStr;

      final response = await ApiClient.post(
        Uri.parse("/api/admin/error_logs/$logId/review"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyData),
      );
      if (response.statusCode == 200) {
        _fetchErrorLogs();
      }
    } catch (e) {
      debugPrint("Error updating review status: $e");
    }
  }

  void _logout() async {
    await ApiClient.post(Uri.parse("/api/logout"));
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = "";
      _filterCategory = null;
      _filterErrorType = null;
      _filterIsReviewed = null;
      _filterDateBefore = null;
      _filterDateAfter = null;
      _currentLogPage = 1;
    });
    _fetchErrorLogs();
  }

  void _showErrorModal(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final colorScheme = Theme.of(context).colorScheme;
            final bool isReviewed = log['is_reviewed'] == true;

            return Dialog(
              backgroundColor: colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 900,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text('Kategoria', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant))),
                          Expanded(flex: 3, child: Text('Kod błędu', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant))),
                          Expanded(flex: 2, child: Text('Data błędu', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant))),
                          Expanded(flex: 3, child: Text('Data naprawienia', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant))),
                          Expanded(flex: 2, child: Text('Typ błędu', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant))),
                          Expanded(flex: 2, child: Text('Czy przejrzany?', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        border: Border.all(color: colorScheme.surfaceContainerHighest),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 2, child: Text(log['category'] ?? '-')),
                          Expanded(flex: 3, child: Text(log['error_code'] ?? 'null')),
                          Expanded(flex: 2, child: Text(log['created_at_str'] ?? '-')),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Text(log['resolved_at_str'] ?? 'null'),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2030),
                                    );
                                    if (picked != null) {
                                      final dateStr = picked.toIso8601String().substring(0, 10);
                                      await _updateReviewStatus(log['id'], resolvedAtDateStr: dateStr);
                                      setStateDialog(() => log['resolved_at_str'] = dateStr);
                                    }
                                  },
                                  child: Icon(Icons.calendar_today, size: 18, color: colorScheme.primary),
                                )
                              ],
                            ),
                          ),
                          Expanded(flex: 2, child: Text(log['error_type'] ?? '-')),
                          Expanded(
                            flex: 2,
                            child: Checkbox(
                              value: isReviewed,
                              activeColor: colorScheme.primary,
                              onChanged: (val) async {
                                final newVal = val ?? false;
                                await _updateReviewStatus(log['id'], isReviewed: newVal);
                                setStateDialog(() => log['is_reviewed'] = newVal);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text('Treść błędu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                        color: colorScheme.surfaceContainerLowest,
                      ),
                      child: Text(log['message'] ?? 'Brak treści'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: _buildExpandableFab(colorScheme),
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
                        IconButton(icon: const Icon(Icons.notifications_none, size: 28), onPressed: () {}),
                        PopupMenuButton<String>(
                          offset: const Offset(0, 50),
                          icon: const Icon(Icons.account_circle_outlined, size: 28),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (value) {
                            if (value == 'logout') _logout();
                          },
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'logout',
                              child: Row(
                                children: [
                                  Icon(Icons.logout, color: colorScheme.error, size: 20),
                                  const SizedBox(width: 12),
                                  Text('Wyloguj się', style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
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
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCustomTabBar(colorScheme),
                    const SizedBox(height: 32),

                    if (_selectedTabIndex == 0) ...[
                      _buildDashboardTab(),
                    ] else if (_selectedTabIndex == 1) ...[
                      _buildErrorLogsTab(colorScheme),
                    ] else if (_selectedTabIndex == 2) ...[
                      const Center(child: Text('Moduł Scraperów (W budowie)')),
                    ] else if (_selectedTabIndex == 3) ...[
                      _buildSupportedStoresTab(colorScheme),
                    ]
                  ],
                ),
              ),
            ),
          ],
        ),
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
          _buildTabButton('Logi błędów', 1, colorScheme),
          _buildTabButton('Scrapery', 2, colorScheme),
          _buildTabButton('Obsługiwane sklepy', 3, colorScheme),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index, ColorScheme colorScheme) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () {
        setState(() => _selectedTabIndex = index);

        if (index == 0) _fetchPendingUsers();
        if (index == 1 && _logs.isEmpty) _fetchErrorLogs();

        if (index == 3) {
          _fetchStores();
          _fetchRegRequests();
        }
      },
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

  Widget _buildDashboardTab() {
    if (_isLoadingUsers) return const Center(child: CircularProgressIndicator());
    if (_users.isEmpty) return const Center(child: Text('Brak wniosków oczekujących na zatwierdzenie'));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final u = _users[index];
        Color statusColor = Colors.grey;
        String statusText = (u['request_status'] ?? u['status'] ?? u['user_status'] ?? '-').toString();

        if (statusText == 'pending_admin') {
          statusColor = Colors.orange;
          statusText = 'Oczekuje na zatwierdzenie';
        } else if (statusText == 'onboarding_submitted') {
          statusColor = Colors.blue;
          statusText = 'Dane onboardingowe przesłane';
        } else if (statusText == 'scraper_review') {
          statusColor = Colors.purple;
          statusText = 'Scrapery do weryfikacji';
        } else if (statusText == 'approved') {
          statusColor = Colors.green;
          statusText = 'Zatwierdzony';
        } else if (statusText == 'rejected') {
          statusColor = Colors.red;
          statusText = 'Odrzucony';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AdminUserDetailsScreen(userId: u['id']),
              )).then((_) => _fetchPendingUsers());
            },
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${u['first_name'] ?? ''} ${u['last_name'] ?? ''} (${u['username'] ?? '-'})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Firma: ${u['requested_store_name'] ?? u['company_domain'] ?? '-'}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorLogsTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 250,
              height: 40,
              child: TextField(
                controller: _searchController,
                onSubmitted: (val) {
                  setState(() { _searchQuery = val; _currentLogPage = 1; });
                  _fetchErrorLogs();
                },
                decoration: InputDecoration(
                  hintText: 'Wyszukaj błąd po kodzie...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
              ),
            ),

            _buildDropdownFilter(
              label: 'Kategoria',
              currentValue: _filterCategory,
              options: ['Klient', 'Scrapery', 'System'],
              onChanged: (val) { setState(() { _filterCategory = val; _currentLogPage = 1; }); _fetchErrorLogs(); },
              colorScheme: colorScheme,
            ),

            _buildDateFilter(
              label: 'Data: przed',
              currentDate: _filterDateBefore,
              isBefore: true,
              colorScheme: colorScheme,
            ),

            _buildDateFilter(
              label: 'Data: po',
              currentDate: _filterDateAfter,
              isBefore: false,
              colorScheme: colorScheme,
            ),

            _buildDropdownFilter(
              label: 'Typ błędu',
              currentValue: _filterErrorType,
              options: ['Zgłoszony', 'Auto'],
              onChanged: (val) { setState(() { _filterErrorType = val; _currentLogPage = 1; }); _fetchErrorLogs(); },
              colorScheme: colorScheme,
            ),

            _buildDropdownFilter(
              label: 'Czy przejrzany?',
              currentValue: _filterIsReviewed == null ? null : (_filterIsReviewed! ? 'Tak' : 'Nie'),
              options: ['Tak', 'Nie'],
              onChanged: (val) {
                setState(() {
                  if (val == null) _filterIsReviewed = null;
                  else _filterIsReviewed = val == 'Tak';
                  _currentLogPage = 1;
                });
                _fetchErrorLogs();
              },
              colorScheme: colorScheme,
            ),

            TextButton.icon(
              onPressed: _clearFilters,
              style: TextButton.styleFrom(foregroundColor: colorScheme.onSurfaceVariant),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Wyczyść filtry'),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _isLoadingLogs
                ? const Padding(padding: EdgeInsets.all(48.0), child: Center(child: CircularProgressIndicator()))
                : _logs.isEmpty
                    ? const Padding(padding: EdgeInsets.all(48.0), child: Center(child: Text("Brak zgłoszonych błędów pasujących do kryteriów.")))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                showCheckboxColumn: false,
                                headingRowColor: MaterialStateProperty.resolveWith((states) => colorScheme.primaryContainer.withOpacity(0.3)),
                                dataRowMaxHeight: 65,
                                columns: const [
                                  DataColumn(label: Expanded(child: Text('Kategoria', style: TextStyle(fontWeight: FontWeight.bold)))),
                                  DataColumn(label: Expanded(child: Text('Kod błędu', style: TextStyle(fontWeight: FontWeight.bold)))),
                                  DataColumn(label: Expanded(child: Text('Data błędu', style: TextStyle(fontWeight: FontWeight.bold)))),
                                  DataColumn(label: Expanded(child: Text('Data naprawienia', style: TextStyle(fontWeight: FontWeight.bold)))),
                                  DataColumn(label: Expanded(child: Text('Typ', style: TextStyle(fontWeight: FontWeight.bold)))),
                                  DataColumn(label: Expanded(child: Text('Czy przejrzany?', style: TextStyle(fontWeight: FontWeight.bold)))),
                                ],
                                rows: _logs.map((log) {
                                  final bool isReviewed = log['is_reviewed'] == true;
                                  return DataRow(
                                    onSelectChanged: (_) => _showErrorModal(log),
                                    cells: [
                                      DataCell(Text(log['category'] ?? '-')),
                                      DataCell(Text(log['error_code'] ?? 'null')),
                                      DataCell(Text(log['created_at_str'] ?? '-')),
                                      DataCell(Text(log['resolved_at_str'] ?? 'Brak')),
                                      DataCell(Text(log['error_type'] ?? '-')),
                                      DataCell(Text(isReviewed ? 'Tak' : 'Nie', style: TextStyle(color: isReviewed ? colorScheme.primary : colorScheme.error, fontWeight: FontWeight.bold))),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          if (_totalLogPages > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)))),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: _currentLogPage > 1 ? () { setState(() => _currentLogPage--); _fetchErrorLogs(); } : null,
                                  ),
                                  Text('Strona $_currentLogPage z $_totalLogPages', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: _currentLogPage < _totalLogPages ? () { setState(() => _currentLogPage++); _fetchErrorLogs(); } : null,
                                  ),
                                ],
                              ),
                            )
                        ],
                      );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildSupportedStoresTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Aktualnie obsługiwane sklepy', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
        const SizedBox(height: 16),
        _buildStoresTable(colorScheme),

        const SizedBox(height: 48),

        Text('Wnioski o rejestrację', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
        const SizedBox(height: 16),
        _buildRegRequestsTable(colorScheme),
      ],
    );
  }

  Widget _buildStoresTable(ColorScheme colorScheme) {
    if (_isLoadingStores) return const Padding(padding: EdgeInsets.all(24.0), child: Center(child: CircularProgressIndicator()));
    if (_stores.isEmpty) return const Padding(padding: EdgeInsets.all(24.0), child: Center(child: Text('Brak obsługiwanych sklepów w bazie.')));

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: MaterialStateProperty.resolveWith((states) => colorScheme.primaryContainer.withOpacity(0.3)),
                dataRowMaxHeight: 65,
                columns: const [
                  DataColumn(label: Expanded(child: Text('Nazwa sklepu', style: TextStyle(fontWeight: FontWeight.bold)))),
                  DataColumn(label: Expanded(child: Text('Domena', style: TextStyle(fontWeight: FontWeight.bold)))),
                  DataColumn(label: Expanded(child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold)))),
                  DataColumn(label: Expanded(child: Text('Data dodania', style: TextStyle(fontWeight: FontWeight.bold)))),
                ],
                rows: _stores.map((store) {
                  final bool isActive = store['status'] == 'Aktywny';
                  return DataRow(
                    cells: [
                      DataCell(Text(store['store_name'] ?? '-')),
                      DataCell(Text(store['store_domain'] ?? '-')),
                      DataCell(Text(store['status'] ?? 'Nieznany', style: TextStyle(color: isActive ? colorScheme.primary : colorScheme.error, fontWeight: FontWeight.bold))),
                      DataCell(Text(store['added_date'] ?? '-')),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildRegRequestsTable(ColorScheme colorScheme) {
    if (_isLoadingRegRequests) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_regRequests.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(child: Text('Brak wniosków o rejestrację.')),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                showCheckboxColumn: false,
                headingRowColor: MaterialStateProperty.resolveWith(
                  (states) => colorScheme.primaryContainer.withOpacity(0.3),
                ),
                dataRowMaxHeight: 65,
                columns: const [
                  DataColumn(
                    label: Expanded(
                      child: Text('Firma', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  DataColumn(
                    label: Expanded(
                      child: Text('E-mail', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  DataColumn(
                    label: Expanded(
                      child: Text('Konkurencja', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  DataColumn(
                    label: Expanded(
                      child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  DataColumn(
                    label: Expanded(
                      child: Text('Data wniosku', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  DataColumn(
                    label: Expanded(
                      child: Text('Akcje', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
                rows: _regRequests.map((req) {
                  String compText = 'Brak';

                  if (req['competitor_urls'] != null && req['competitor_urls'] is List) {
                    compText = '${(req['competitor_urls'] as List).length} adresy';
                  }

                  final status = req['status']?.toString() ?? '-';
                  final canModerate = status == 'pending_admin';

                  return DataRow(
                    onSelectChanged: (_) => _showRegRequestModal(req),
                    cells: [
                      DataCell(Text(req['company_name'] ?? '-')),
                      DataCell(Text(req['email'] ?? '-')),
                      DataCell(Text(compText)),
                      DataCell(
                        Text(
                          status,
                          style: TextStyle(
                            color: status == 'pending_admin'
                                ? Colors.orange
                                : status == 'approved'
                                    ? Colors.green
                                    : status == 'rejected'
                                        ? Colors.red
                                        : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(Text(req['requested_date'] ?? '-')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Zatwierdź',
                              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                              onPressed: canModerate
                                  ? () => _approveRegistrationRequest(req)
                                  : null,
                            ),
                            IconButton(
                              tooltip: 'Odrzuć',
                              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                              onPressed: canModerate
                                  ? () => _rejectRegistrationRequest(req)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String? currentValue,
    required List<String> options,
    required Function(String?) onChanged,
    required ColorScheme colorScheme,
  }) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == "") onChanged(null);
        else onChanged(val);
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem<String>(value: "", child: Text('Wszystkie')),
        ...options.map((option) => PopupMenuItem<String>(value: option, child: Text(option))),
      ],
      child: Container(
        height: 35,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: currentValue != null ? colorScheme.primaryContainer : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentValue ?? label, style: TextStyle(fontSize: 13, fontWeight: currentValue != null ? FontWeight.bold : FontWeight.normal)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilter({
    required String label,
    required DateTime? currentDate,
    required bool isBefore,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: currentDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          setState(() {
            if (isBefore) _filterDateBefore = picked;
            else _filterDateAfter = picked;
            _currentLogPage = 1;
          });
          _fetchErrorLogs();
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 35,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: currentDate != null ? colorScheme.primaryContainer : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentDate != null ? currentDate.toIso8601String().substring(0, 10) : label,
              style: TextStyle(fontSize: 13, fontWeight: currentDate != null ? FontWeight.bold : FontWeight.normal),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  void _showRegRequestModal(Map<String, dynamic> req) {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        List<dynamic> urls = [];
        if (req['competitor_urls'] != null && req['competitor_urls'] is List) {
          urls = req['competitor_urls'] as List;
        }

        final status = req['status']?.toString() ?? '-';
        final canModerate = status == 'pending_admin';

        return Dialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 600,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Szczegóły wniosku',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Text(
                  'Firma: ${req['company_name'] ?? '-'}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),

                Text(
                  'E-mail: ${req['email'] ?? '-'}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),

                Text(
                  'Status: $status',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),

                Text(
                  'Data: ${req['requested_date'] ?? '-'}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Wskazana konkurencja:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (urls.isEmpty)
                  Text(
                    'Klient nie wskazał żadnej konkurencji.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                else
                  Container(
                    height: urls.length > 3 ? 200 : urls.length * 60.0,
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                      color: colorScheme.surfaceContainerLowest,
                    ),
                    child: ListView.separated(
                      itemCount: urls.length,
                      separatorBuilder: (context, index) => Divider(
                        color: colorScheme.outlineVariant,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: Icon(Icons.link, color: colorScheme.primary),
                          title: Text(
                            urls[index].toString(),
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 24),

                if (canModerate)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _rejectRegistrationRequest(
                          req,
                          closeDialog: true,
                        ),
                        icon: const Icon(Icons.close),
                        label: const Text('Odrzuć'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _approveRegistrationRequest(
                          req,
                          closeDialog: true,
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Zatwierdź'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
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
              child: FloatingActionButton.extended(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                heroTag: 'settingsFabAdmin',
                onPressed: () {
                  setState(() => _isFabExpanded = false);
                  _showSettingsModal();
                },
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                elevation: 1,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Ustawienia'),
              ),
            )
          : const SizedBox.shrink(),
        ),
        FloatingActionButton(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          heroTag: 'menuToggleFabAdmin',
          onPressed: () => setState(() => _isFabExpanded = !_isFabExpanded),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 2,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
            child: Icon(_isFabExpanded ? Icons.close : Icons.menu, key: ValueKey<bool>(_isFabExpanded)),
          ),
        ),
      ],
    );
  }

  void _showSettingsModal() {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return Dialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ustawienia systemu', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 24),

                ValueListenableBuilder<ThemeMode>(
                  valueListenable: globalThemeNotifier,
                  builder: (context, currentMode, child) {
                    bool isDark = currentMode == ThemeMode.dark ||
                                 (currentMode == ThemeMode.system && Theme.of(context).brightness == Brightness.dark);

                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tryb ciemny (Dark Mode)', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Zmienia schemat kolorów aplikacji'),
                      value: isDark,
                      activeColor: colorScheme.primary,
                      onChanged: (bool value) {
                        globalThemeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}
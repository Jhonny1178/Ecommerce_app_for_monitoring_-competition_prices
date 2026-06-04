import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tonten/core/api/api_client.dart';
import 'dart:convert';
import 'login_screen.dart';
import 'admin_user_details_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchPendingUsers();
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
      final response = await ApiClient.get(Uri.parse("/api/admin/error_logs?page=$_currentLogPage&per_page=10"));
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

  Future<void> _toggleReviewStatus(int logId, bool currentStatus) async {
    try {
      final response = await ApiClient.post(
        Uri.parse("/api/admin/error_logs/$logId/review"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'is_reviewed': !currentStatus}),
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

  void _showErrorDetails(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Szczegóły błędu'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Zamknij')
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
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
            icon: const Icon(Icons.notifications_none, size: 28),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, size: 28),
            onPressed: _logout,
            tooltip: 'Wyloguj się',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
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
              const Center(child: Text('Obsługiwane Sklepy (W budowie)')),
            ]
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
        if (index == 0 && _users.isEmpty) _fetchPendingUsers();
        if (index == 1 && _logs.isEmpty) _fetchErrorLogs();
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
        String statusText = u['status'];
        if (u['status'] == 'pending_approval') {
          statusColor = Colors.orange;
          statusText = 'Oczekuje na wdrożenie';
        } else if (u['status'] == 'analyzing') {
          statusColor = Colors.blue;
          statusText = 'Tworzenie Scraperów';
        } else if (u['status'] == 'completed') {
          statusColor = Colors.green;
          statusText = 'Gotowy do weryfikacji';
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
                        Text('${u['first_name']} ${u['last_name']} (${u['username']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text('Firma: ${u['company_domain']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            _buildFilterChip('Kategoria', colorScheme),
            _buildFilterChip('Data: przed', colorScheme),
            _buildFilterChip('Data: po', colorScheme),
            _buildFilterChip('Typ błędu', colorScheme),
            _buildFilterChip('Czy przejrzany?', colorScheme),
          ],
        ),
        const SizedBox(height: 24),
        
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _isLoadingLogs
              ? const Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _logs.isEmpty 
                  ? const Padding(
                      padding: EdgeInsets.all(48.0),
                      child: Center(child: Text("Brak zgłoszonych błędów.")),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: MaterialStateProperty.resolveWith(
                                (states) => colorScheme.primaryContainer.withOpacity(0.3)),
                            dataRowMaxHeight: 65,
                            columns: const [
                              DataColumn(label: Text('Kategoria', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Kod błędu', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Data błędu', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Data naprawienia', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Typ', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Czy przejrzany?', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Treść', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _logs.map((log) {
                              final bool isReviewed = log['is_reviewed'] == true;
                              return DataRow(
                                color: MaterialStateProperty.resolveWith(
                                  (states) => isReviewed ? Colors.transparent : colorScheme.errorContainer.withOpacity(0.2)
                                ),
                                cells: [
                                  DataCell(Text(log['category'] ?? '-')),
                                  DataCell(Text(log['error_code'] ?? 'null')),
                                  DataCell(Text(log['created_at_str'] ?? '-')),
                                  DataCell(Text(log['resolved_at_str'] ?? 'Brak')),
                                  DataCell(Text(log['error_type'] ?? '-')),
                                  DataCell(
                                    Row(
                                      children: [
                                        Switch(
                                          value: isReviewed,
                                          onChanged: (val) => _toggleReviewStatus(log['id'], isReviewed),
                                          activeColor: Colors.green,
                                        ),
                                        Text(isReviewed ? 'Tak' : 'Nie', style: TextStyle(color: isReviewed ? Colors.green : Colors.red, fontWeight: FontWeight.bold))
                                      ],
                                    )
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.remove_red_eye, size: 20),
                                      tooltip: 'Pokaż treść',
                                      onPressed: () => _showErrorDetails(log['message'] ?? 'Brak treści'),
                                    )
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                        if (_totalLogPages > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5))),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: _currentLogPage > 1
                                      ? () {
                                          setState(() => _currentLogPage--);
                                          _fetchErrorLogs();
                                        }
                                      : null,
                                ),
                                Text('Strona $_currentLogPage z $_totalLogPages', style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: _currentLogPage < _totalLogPages
                                      ? () {
                                          setState(() => _currentLogPage++);
                                          _fetchErrorLogs();
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          )
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, ColorScheme colorScheme) {
    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}
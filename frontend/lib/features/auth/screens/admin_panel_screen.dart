import 'package:flutter/material.dart';
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
  bool _isLoading = true;
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchPendingUsers();
  }

  Future<void> _fetchPendingUsers() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.get(Uri.parse("/api/admin/pending_users"));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() => _users = data['users'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching users: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }



  void _logout() async {
    await ApiClient.post(Uri.parse("/api/logout"));
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Administratora'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchPendingUsers), IconButton(icon: const Icon(Icons.logout), onPressed: _logout)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('Brak wniosków oczekujących na zatwierdzenie'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
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
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AdminUserDetailsScreen(userId: u['id']),
                          )).then((_) => _fetchPendingUsers());
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
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
                ),
    );
  }
}

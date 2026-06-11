import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:tonten/core/api/api_client.dart';

class AdminScraperLogsScreen extends StatefulWidget {
  final int scraperId;
  final String spiderName;

  const AdminScraperLogsScreen({
    super.key,
    required this.scraperId,
    required this.spiderName,
  });

  @override
  State<AdminScraperLogsScreen> createState() => _AdminScraperLogsScreenState();
}

class _AdminScraperLogsScreenState extends State<AdminScraperLogsScreen> {
  bool _isLoading = true;
  List<dynamic> _runs = [];

  @override
  void initState() {
    super.initState();
    _fetchRuns();
  }

  Future<void> _fetchRuns() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.get(
        Uri.parse("/api/admin/scrapers/${widget.scraperId}/runs"),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() => _runs = data['runs'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching scraper runs: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showLogDialog(Map<String, dynamic> run) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Logi uruchomienia z ${DateTime.parse(run['started_at']).toLocal().toString().substring(0, 16)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (run['error_msg'] != null && run['error_msg'].toString().isNotEmpty) ...[
                    const Text('Błąd:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    Text(run['error_msg'], style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                  ],
                  const Text('Zrzut konsoli:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      run['log_excerpt'] ?? 'Brak logów',
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        color: Colors.greenAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zamknij'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Historia: ${widget.spiderName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRuns,
            tooltip: 'Odśwież',
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _runs.isEmpty
              ? const Center(child: Text('Brak historii uruchomień dla tego scrapera.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _runs.length,
                  itemBuilder: (context, index) {
                    final run = _runs[index];
                    final status = run['status'] ?? 'unknown';
                    Color statusColor = Colors.grey;
                    if (status == 'success') statusColor = Colors.green;
                    else if (status == 'failed') statusColor = Colors.red;
                    else if (status == 'running') statusColor = Colors.blue;

                    final startedAt = run['started_at'] != null 
                        ? DateTime.parse(run['started_at']).toLocal().toString().substring(0, 16)
                        : '-';
                        
                    final finishedAt = run['finished_at'] != null 
                        ? DateTime.parse(run['finished_at']).toLocal().toString().substring(11, 16)
                        : '...';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      elevation: 0,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.2),
                          child: Icon(
                            status == 'success' ? Icons.check : (status == 'failed' ? Icons.error : Icons.autorenew),
                            color: statusColor,
                          ),
                        ),
                        title: Text('Start: $startedAt'),
                        subtitle: Text('Zakończenie: $finishedAt'),
                        trailing: ElevatedButton(
                          onPressed: () => _showLogDialog(run),
                          child: const Text('Pokaż logi'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

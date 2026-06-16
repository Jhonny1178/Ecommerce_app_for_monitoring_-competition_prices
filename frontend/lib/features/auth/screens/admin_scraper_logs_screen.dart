import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:tonten/core/api/api_client.dart';
import '../widgets/pipeline_graph_widget.dart';

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

  List<Widget> _buildParsedLogs(String logsText) {
    if (logsText.isEmpty) return [const Text('Brak logów')];
    
    final lines = logsText.split('\n');
    final List<Widget> widgets = [];
    
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      Color textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87;
      IconData icon = Icons.info_outline;
      Color iconColor = Colors.grey;

      final lowerLine = line.toLowerCase();
      bool isImportant = false;

      if (lowerLine.contains('error') || lowerLine.contains('exception') || lowerLine.contains('traceback') || lowerLine.contains('fail')) {
        textColor = Colors.red;
        icon = Icons.error;
        iconColor = Colors.red;
        isImportant = true;
      } else if (lowerLine.contains('warning')) {
        textColor = Colors.orange;
        icon = Icons.warning;
        iconColor = Colors.orange;
        isImportant = true;
      } else if (lowerLine.contains('success') || lowerLine.contains('finished') || lowerLine.contains('done') || lowerLine.contains('info: closing spider') || lowerLine.contains('spider opened')) {
        textColor = Colors.green;
        icon = Icons.check_circle;
        iconColor = Colors.green;
        isImportant = true;
      } else if (lowerLine.contains('[scraper]') || lowerLine.contains('[ingest]') || lowerLine.contains('[matching]') || lowerLine.contains('statscollector') || lowerLine.contains('item_scraped_count')) {
        textColor = Colors.blue;
        icon = Icons.info_outline;
        iconColor = Colors.blue;
        isImportant = true;
      }

      if (!isImportant && !lowerLine.contains('critical')) {
        continue; // Pomijamy wszystkie inne logi (szczególnie DEBUG i INFO ze Scrapy)
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.trim(),
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: textColor),
                ),
              ),
            ],
          ),
        )
      );
    }
    
    return widgets;
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
                        ? DateTime.parse(run['started_at']).toLocal()
                        : null;
                        
                    final finishedAt = run['finished_at'] != null 
                        ? DateTime.parse(run['finished_at']).toLocal()
                        : null;

                    String durationStr = 'Trwa...';
                    if (startedAt != null && finishedAt != null) {
                      final diff = finishedAt.difference(startedAt);
                      durationStr = '${diff.inMinutes}m ${diff.inSeconds % 60}s';
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      elevation: 0,
                      child: ExpansionTile(
                        initiallyExpanded: index == 0,
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.2),
                          child: Icon(
                            status == 'success' ? Icons.check : (status == 'failed' ? Icons.error : Icons.autorenew),
                            color: statusColor,
                          ),
                        ),
                        title: Text('Data: ${startedAt?.toString().substring(0, 10) ?? '-'}'),
                        subtitle: Text('Start: ${startedAt?.toString().substring(11, 19) ?? '-'} | Koniec: ${finishedAt?.toString().substring(11, 19) ?? '-'} | Czas: $durationStr'),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (run['error_msg'] != null && run['error_msg'].toString().isNotEmpty) ...[
                                  const Text('Błąd:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                  Text(run['error_msg'], style: const TextStyle(color: Colors.red)),
                                  const SizedBox(height: 16),
                                ],
                                const Text('Przebieg zadań Airflow:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 8),
                                PipelineGraphWidget(pipelineRunId: run['pipeline_run_id'], spiderName: widget.spiderName),
                                const SizedBox(height: 24),
                                const Text('Zdarzenia / Logi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: _buildParsedLogs(run['log_excerpt'] ?? ''),
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

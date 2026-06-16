import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';
import 'dart:convert';

class PipelineGraphWidget extends StatefulWidget {
  final int? pipelineRunId;
  final String? spiderName;

  const PipelineGraphWidget({super.key, required this.pipelineRunId, this.spiderName});

  @override
  State<PipelineGraphWidget> createState() => _PipelineGraphWidgetState();
}

class _PipelineGraphWidgetState extends State<PipelineGraphWidget> {
  bool _isLoading = true;
  List<dynamic> _tasks = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.pipelineRunId != null) {
      _fetchTasks();
    } else {
      _isLoading = false;
      _error = "Brak ID pipeline'u dla tego uruchomienia";
    }
  }

  Future<void> _fetchTasks() async {
    try {
      final response = await ApiClient.get(
        Uri.parse("/api/admin/pipeline_runs/${widget.pipelineRunId}/tasks"),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          setState(() {
            final allTasks = data['tasks'] as List<dynamic>? ?? [];
            _tasks = allTasks.where((task) {
              final taskId = task['task_id'] as String? ?? '';
              if (widget.spiderName != null && (taskId.startsWith('scrape_') || taskId.startsWith('scraper_'))) {
                // If it's a scraper task, only keep it if it's the one we are currently viewing
                // For "nasz_klient", the ingest task is named "nasz_klient" which doesn't start with scrape_, so it's kept.
                // But if the spider name is Calavado, it keeps scrape_calavado and hides others.
                return taskId.toLowerCase().contains(widget.spiderName!.toLowerCase());
              }
              return true;
            }).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = data['error'] ?? 'Błąd pobierania zadań';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Błąd połączenia: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Brak zarejestrowanych zadań dla tego uruchomienia.'),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_tasks.length * 2 - 1, (index) {
            if (index % 2 == 1) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(Icons.arrow_forward, color: colorScheme.onSurfaceVariant),
              );
            }
            final taskIndex = index ~/ 2;
            final task = _tasks[taskIndex];
            final status = task['status'] ?? 'unknown';
            final taskId = task['task_id'] ?? 'unknown';
            
            Color statusColor = colorScheme.onSurfaceVariant;
            IconData statusIcon = Icons.help_outline;
            if (status == 'success') {
              statusColor = Colors.green;
              statusIcon = Icons.check_circle;
            } else if (status == 'failed') {
              statusColor = Colors.red;
              statusIcon = Icons.error;
            } else if (status == 'running') {
              statusColor = Colors.blue;
              statusIcon = Icons.autorenew;
            } else if (status == 'skipped') {
              statusColor = Colors.orange;
              statusIcon = Icons.skip_next;
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.05),
                border: Border.all(color: statusColor.withOpacity(0.5), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(statusIcon, color: statusColor, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    taskId,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  )
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

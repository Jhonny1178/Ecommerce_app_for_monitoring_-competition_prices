import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';

class PipelineGraphWidget extends StatefulWidget {
  final int? pipelineRunId;

  const PipelineGraphWidget({
    super.key,
    required this.pipelineRunId,
  });

  @override
  State<PipelineGraphWidget> createState() =>
      _PipelineGraphWidgetState();
}

class _PipelineGraphWidgetState
    extends State<PipelineGraphWidget> {
  bool _isLoading = true;
  List<dynamic> _tasks = [];
  String? _error;

  @override
  void initState() {
    super.initState();

    if (widget.pipelineRunId == null) {
      _isLoading = false;
      _error = 'Brak ID pipeline’u.';
    } else {
      _fetchTasks();
    }
  }

  Future<void> _fetchTasks() async {
    try {
      final response = await ApiClient.get(
        Uri.parse(
          "/api/admin/pipeline_runs/"
          "${widget.pipelineRunId}/tasks",
        ),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data['ok'] == true) {
        final tasks = List<dynamic>.from(
          data['tasks'] ?? [],
        );

        tasks.removeWhere((task) {
          final taskId =
              task['task_id']?.toString() ?? '';

          final status =
              task['status']?.toString() ?? '';

          return taskId.startsWith(
                    'finish_pipeline_',
                  ) &&
              status == 'skipped';
        });

        tasks.sort((first, second) {
          final firstId =
              first['task_id']?.toString() ?? '';

          final secondId =
              second['task_id']?.toString() ?? '';

          final orderResult =
              _taskOrder(firstId).compareTo(
            _taskOrder(secondId),
          );

          if (orderResult != 0) {
            return orderResult;
          }

          return firstId.compareTo(secondId);
        });

        if (mounted) {
          setState(() {
            _tasks = tasks;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = data['error']?.toString() ??
                'Błąd pobierania zadań.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  int _taskOrder(String taskId) {
    final value = taskId.toLowerCase();

    if (value.contains('reset_competitors')) {
      return 20;
    }

    if (value.contains('calavado')) {
      return 30;
    }

    if (value.contains('jmbdesing')) {
      return 31;
    }

    if (value.contains('pod_pierzyna')) {
      return 32;
    }

    if (value.startsWith('scrape_') ||
        value.startsWith('scraper_')) {
      return 35;
    }

    if (value.contains('matching')) {
      return 40;
    }

    if (value.contains('finish')) {
      return 50;
    }

    return 10;
  }

  String _displayTaskName(String taskId) {
    final value = taskId.toLowerCase();

    if (value.contains('reset_competitors')) {
      return 'Przygotowanie danych konkurencji';
    }

    if (value.contains('calavado')) {
      return 'Scraper: Calavado';
    }

    if (value.contains('jmbdesing')) {
      return 'Scraper: jmbdesing';
    }

    if (value.contains('pod_pierzyna')) {
      return 'Scraper: pod_pierzyna';
    }

    if (value.contains('matching')) {
      return 'Matching produktów';
    }

    if (value.contains('finish')) {
      return 'Zakończenie pipeline’u';
    }

    return 'Aktualizacja danych klienta';
  }

  Color _statusColor(
    dynamic value,
    ColorScheme colorScheme,
  ) {
    switch (value?.toString().toLowerCase()) {
      case 'success':
        return Colors.green;
      case 'failed':
        return colorScheme.error;
      case 'running':
        return Colors.blue;
      case 'skipped':
        return Colors.orange;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  String _statusLabel(dynamic value) {
    switch (value?.toString().toLowerCase()) {
      case 'success':
        return 'Sukces';
      case 'failed':
        return 'Błąd';
      case 'running':
        return 'W trakcie';
      case 'skipped':
        return 'Pominięto';
      default:
        return 'Nieznany';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Text(
        _error!,
        style: TextStyle(
          color: colorScheme.error,
        ),
      );
    }

    if (_tasks.isEmpty) {
      return const Text(
        'Brak zarejestrowanych zadań.',
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'Przebieg procesu',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            _tasks.length,
            (index) {
              final task = _tasks[index];

              final taskId =
                  task['task_id']?.toString() ??
                      '-';

              final status =
                  task['status'];

              final statusColor =
                  _statusColor(
                status,
                colorScheme,
              );

              return Container(
                width: 220,
                padding:
                    const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor
                      .withOpacity(0.06),
                  borderRadius:
                      BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor
                        .withOpacity(0.45),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          statusColor
                              .withOpacity(0.15),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            _displayTaskName(
                              taskId,
                            ),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          Text(
                            _statusLabel(status),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Logi etapów',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        ..._tasks.map((task) {
          final taskId =
              task['task_id']?.toString() ?? '-';

          final status =
              task['status'];

          final statusColor =
              _statusColor(
            status,
            colorScheme,
          );

          final logs =
              task['log_excerpt']?.toString() ??
                  '';

          final error =
              task['error_msg']?.toString() ??
                  '';

          return Card(
            elevation: 0,
            margin:
                const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              initiallyExpanded:
                  status == 'failed',
              leading: Icon(
                status == 'success'
                    ? Icons.check_circle
                    : status == 'failed'
                        ? Icons.error
                        : Icons.info_outline,
                color: statusColor,
              ),
              title: Text(
                _displayTaskName(taskId),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _statusLabel(status),
              ),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      if (error.isNotEmpty) ...[
                        Text(
                          error,
                          style: TextStyle(
                            color:
                                colorScheme.error,
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                      ],
                      Container(
                        width: double.infinity,
                        constraints:
                            const BoxConstraints(
                          maxHeight: 280,
                        ),
                        padding:
                            const EdgeInsets.all(
                          12,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.4),
                          borderRadius:
                              BorderRadius.circular(
                            8,
                          ),
                        ),
                        child:
                            SingleChildScrollView(
                          child: SelectableText(
                            logs.isEmpty
                                ? 'Brak zapisanych logów '
                                    'dla tego etapu.'
                                : logs,
                            style:
                                const TextStyle(
                              fontFamily:
                                  'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
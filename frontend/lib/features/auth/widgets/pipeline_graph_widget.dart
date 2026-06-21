import 'dart:async';
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

class _PipelineGraphWidgetState extends State<PipelineGraphWidget> {
  bool _isLoading = true;
  bool _isFetching = false;

  List<Map<String, dynamic>> _tasks = [];
  String? _error;

  Timer? _refreshTimer;

  final Set<String> _expandedTaskIds = <String>{};
  final Map<String, String> _previousStatuses = <String, String>{};

  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();

    if (widget.pipelineRunId == null) {
      _isLoading = false;
      _error = 'Brak ID pipeline’u.';
      return;
    }

    _fetchTasks(showLoader: true);
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(
    covariant PipelineGraphWidget oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pipelineRunId == widget.pipelineRunId) {
      return;
    }

    _requestGeneration++;
    _refreshTimer?.cancel();

    _isFetching = false;
    _tasks = [];
    _error = null;

    _expandedTaskIds.clear();
    _previousStatuses.clear();

    if (widget.pipelineRunId == null) {
      setState(() {
        _isLoading = false;
        _error = 'Brak ID pipeline’u.';
      });

      return;
    }

    _fetchTasks(showLoader: true);
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        _fetchTasks();
      },
    );
  }

  Future<void> _fetchTasks({
    bool showLoader = false,
  }) async {
    if (_isFetching || widget.pipelineRunId == null) {
      return;
    }

    final int currentGeneration = _requestGeneration;

    _isFetching = true;

    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await ApiClient.get(
        Uri.parse(
          '/api/admin/pipeline_runs/'
          '${widget.pipelineRunId}/tasks',
        ),
      );

      if (!mounted || currentGeneration != _requestGeneration) {
        return;
      }

      final String contentType =
          response.headers['content-type'] ?? '';

      if (!contentType.contains('application/json')) {
        final String preview = response.body.length > 300
            ? response.body.substring(0, 300)
            : response.body;

        throw Exception(
          'Backend zwrócił kod ${response.statusCode} '
          'zamiast JSON.\n$preview',
        );
      }

      final dynamic decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception(
          'Backend zwrócił nieprawidłowy format danych.',
        );
      }

      if (response.statusCode != 200 || decoded['ok'] != true) {
        throw Exception(
          decoded['error']?.toString() ??
              'Nie udało się pobrać zadań pipeline’u.',
        );
      }

      final List<Map<String, dynamic>> incomingTasks = [];

      final dynamic rawTasks = decoded['tasks'];

      if (rawTasks is List) {
        for (final dynamic rawTask in rawTasks) {
          if (rawTask is Map) {
            incomingTasks.add(
              Map<String, dynamic>.from(rawTask),
            );
          }
        }
      }

      incomingTasks.removeWhere((task) {
        final String taskId =
            task['task_id']?.toString() ?? '';

        final String status =
            task['status']?.toString().toLowerCase() ?? '';

        return taskId.startsWith('finish_pipeline_') &&
            status == 'skipped';
      });

      incomingTasks.sort((first, second) {
        final String firstId =
            first['task_id']?.toString() ?? '';

        final String secondId =
            second['task_id']?.toString() ?? '';

        final int orderResult =
            _taskOrder(firstId).compareTo(
          _taskOrder(secondId),
        );

        if (orderResult != 0) {
          return orderResult;
        }

        return firstId.compareTo(secondId);
      });

      final Map<String, Map<String, dynamic>> oldTasks = {
        for (final task in _tasks)
          task['task_id']?.toString() ?? '': task,
      };

      final List<Map<String, dynamic>> mergedTasks =
          incomingTasks.map((task) {
        final String taskId =
            task['task_id']?.toString() ?? '';

        final Map<String, dynamic>? oldTask = oldTasks[taskId];

        if (oldTask != null) {
          final String incomingLogs = _cleanLogText(
            task['log_excerpt'] ?? task['logs'],
          );

          final String oldLogs = _cleanLogText(
            oldTask['log_excerpt'] ?? oldTask['logs'],
          );

          if (incomingLogs.isEmpty && oldLogs.isNotEmpty) {
            task['log_excerpt'] = oldLogs;
          } else if (incomingLogs.length < oldLogs.length) {
            task['log_excerpt'] = oldLogs;
          }
        }

        return task;
      }).toList();

      for (final Map<String, dynamic> task in mergedTasks) {
        final String taskId =
            task['task_id']?.toString() ?? '';

        if (taskId.isEmpty) {
          continue;
        }

        final String currentStatus =
            task['status']?.toString().toLowerCase() ?? '';

        final String? previousStatus =
            _previousStatuses[taskId];

        if (currentStatus == 'running' &&
            previousStatus != 'running') {
          _expandedTaskIds.add(taskId);
        }

        if (currentStatus == 'failed') {
          _expandedTaskIds.add(taskId);
        }

        _previousStatuses[taskId] = currentStatus;
      }

      if (!mounted || currentGeneration != _requestGeneration) {
        return;
      }

      setState(() {
        _tasks = mergedTasks;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || currentGeneration != _requestGeneration) {
        return;
      }

      if (_tasks.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      } else {
        debugPrint(
          'Błąd odświeżania pipeline’u: $e',
        );
      }
    } finally {
      if (currentGeneration == _requestGeneration) {
        _isFetching = false;
      }

      if (mounted &&
          currentGeneration == _requestGeneration &&
          _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int _taskOrder(String taskId) {
    final String value = taskId.toLowerCase();

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
    final String value = taskId.toLowerCase();

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

    if (value.startsWith('scrape_') ||
        value.startsWith('scraper_')) {
      final String cleanedName = taskId
          .replaceFirst('scrape_', '')
          .replaceFirst('scraper_', '');

      return 'Scraper: $cleanedName';
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

  IconData _statusIcon(dynamic value) {
    switch (value?.toString().toLowerCase()) {
      case 'success':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'running':
        return Icons.autorenew;
      case 'skipped':
        return Icons.skip_next;
      default:
        return Icons.info_outline;
    }
  }

  String _cleanLogText(dynamic value) {
    final String text = value?.toString() ?? '';

    return text
        .replaceAll(
          RegExp(r'\x1B\[[0-9;]*[A-Za-z]'),
          '',
        )
        .replaceAll('\r', '')
        .trim();
  }

  String _getTaskLogs(Map<String, dynamic> task) {
    final String excerpt =
        _cleanLogText(task['log_excerpt']);

    if (excerpt.isNotEmpty) {
      return excerpt;
    }

    return _cleanLogText(task['logs']);
  }

  String _getTaskError(Map<String, dynamic> task) {
    final String errorMessage =
        _cleanLogText(task['error_msg']);

    if (errorMessage.isNotEmpty) {
      return errorMessage;
    }

    return _cleanLogText(task['error']);
  }

  String _limitLogLines(String logs) {
    const int maxLines = 120;

    final List<String> lines = logs.split('\n');

    if (lines.length <= maxLines) {
      return logs;
    }

    final List<String> visibleLines =
        lines.sublist(lines.length - maxLines);

    return [
      '--- pokazano ostatnie $maxLines z ${lines.length} linii ---',
      '',
      ...visibleLines,
    ].join('\n');
  }

  Widget _buildLogContent({
    required String logs,
  }) {
    final ColorScheme colorScheme =
        Theme.of(context).colorScheme;

    if (logs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Brak szczegółowych logów dla tego etapu.',
              ),
            ),
          ],
        ),
      );
    }

    final String visibleLogs = _limitLogLines(logs);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF3A3A3A),
        ),
      ),
      child: Text(
        visibleLogs,
        softWrap: true,
        style: const TextStyle(
          color: Color(0xFFE6EDF3),
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildTaskSection(
    Map<String, dynamic> task,
    ColorScheme colorScheme,
  ) {
    final String taskId =
        task['task_id']?.toString() ?? '-';

    final dynamic status = task['status'];

    final String normalizedStatus =
        status?.toString().toLowerCase() ?? '';

    final Color statusColor =
        _statusColor(status, colorScheme);

    final String logs = _getTaskLogs(task);
    final String error = _getTaskError(task);

    final bool isExpanded =
        _expandedTaskIds.contains(taskId);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedTaskIds.remove(taskId);
                  } else {
                    _expandedTaskIds.add(taskId);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusIcon(status),
                      color: statusColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayTaskName(taskId),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
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
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildLogContent(
                    logs: logs,
                  ),
                  if (normalizedStatus == 'running') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Log jest odświeżany automatycznie co 3 sekundy.',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme =
        Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Spróbuj ponownie',
              onPressed: () {
                _fetchTasks(showLoader: true);
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Brak zarejestrowanych zadań.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Przebieg procesu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Odśwież zadania i logi',
              onPressed: _isFetching
                  ? null
                  : () {
                      _fetchTasks();
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            _tasks.length,
            (index) {
              final Map<String, dynamic> task =
                  _tasks[index];

              final String taskId =
                  task['task_id']?.toString() ?? '-';

              final dynamic status = task['status'];

              final Color statusColor =
                  _statusColor(status, colorScheme);

              return Container(
                width: 220,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor.withOpacity(0.45),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          statusColor.withOpacity(0.15),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayTaskName(taskId),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
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
        ..._tasks.map(
          (task) => _buildTaskSection(
            task,
            colorScheme,
          ),
        ),
      ],
    );
  }
}


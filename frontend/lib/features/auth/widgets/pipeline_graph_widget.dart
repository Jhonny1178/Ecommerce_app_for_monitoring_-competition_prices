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

  List<dynamic> _tasks = [];
  String? _error;

  Timer? _refreshTimer;

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

    if (oldWidget.pipelineRunId != widget.pipelineRunId) {
      _refreshTimer?.cancel();

      _tasks = [];
      _error = null;

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

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTasks({
    bool showLoader = false,
  }) async {
    if (_isFetching || widget.pipelineRunId == null) {
      return;
    }

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

      final contentType =
          response.headers['content-type'] ?? '';

      if (!contentType.contains('application/json')) {
        final preview = response.body.length > 300
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

      if (response.statusCode == 200 &&
          decoded['ok'] == true) {
        final tasks = List<dynamic>.from(
          decoded['tasks'] ?? [],
        );

        tasks.removeWhere((task) {
          final taskId =
              task['task_id']?.toString() ?? '';

          final status = task['status']
                  ?.toString()
                  .toLowerCase() ??
              '';

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

          final orderResult = _taskOrder(
            firstId,
          ).compareTo(
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
            _error = null;
            _isLoading = false;
          });
        }
      } else {
        final message =
            decoded['error']?.toString() ??
                'Błąd pobierania zadań.';

        if (mounted && _tasks.isEmpty) {
          setState(() {
            _error = message;
            _isLoading = false;
          });
        } else {
          debugPrint(
            'Błąd odświeżania pipeline’u: $message',
          );
        }
      }
    } catch (e) {
      if (mounted && _tasks.isEmpty) {
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
      _isFetching = false;

      if (mounted && _isLoading) {
        setState(() {
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

    if (value.startsWith('scrape_') ||
        value.startsWith('scraper_')) {
      final cleanedName = taskId
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
    final text = value?.toString() ?? '';

    return text
        .replaceAll(
          RegExp(r'\x1B\[[0-9;]*[A-Za-z]'),
          '',
        )
        .replaceAll('\r', '')
        .trim();
  }

  Widget _buildLogContainer({
    required String taskId,
    required String logs,
  }) {
    if (logs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.35),
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

    return RepaintBoundary(
      key: ValueKey<String>(
        'pipeline-log-'
        '${widget.pipelineRunId}-'
        '$taskId-'
        '${logs.hashCode}',
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(
          minHeight: 80,
          maxHeight: 320,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF3A3A3A),
          ),
        ),
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Text(
              logs,
              style: const TextStyle(
                color: Color(0xFFE6EDF3),
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
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
          color: colorScheme
              .surfaceContainerHighest
              .withOpacity(0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Brak zarejestrowanych zadań.',
        ),
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
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
              final task = _tasks[index];

              final taskId =
                  task['task_id']?.toString() ??
                      '-';

              final status = task['status'];

              final statusColor =
                  _statusColor(
                status,
                colorScheme,
              );

              return Container(
                width: 220,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(
                    0.06,
                  ),
                  borderRadius:
                      BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor.withOpacity(
                      0.45,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          statusColor.withOpacity(
                        0.15,
                      ),
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
                            CrossAxisAlignment.start,
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
        ..._tasks.map((task) {
          final taskId =
              task['task_id']?.toString() ?? '-';

          final status = task['status'];

          final normalizedStatus =
              status?.toString().toLowerCase() ??
                  '';

          final statusColor =
              _statusColor(
            status,
            colorScheme,
          );

          final logs = _cleanLogText(
            task['log_excerpt'] ??
                task['logs'],
          );

          final error = _cleanLogText(
            task['error_msg'] ??
                task['error'],
          );

          final shouldExpand =
              normalizedStatus == 'failed' ||
                  normalizedStatus == 'running';

          return Card(
            elevation: 0,
            margin:
                const EdgeInsets.only(bottom: 8),
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(12),
              side: BorderSide(
                color: colorScheme.outlineVariant,
              ),
            ),
            child: ExpansionTile(
              key: PageStorageKey<String>(
                'pipeline-task-'
                '${widget.pipelineRunId}-'
                '$taskId',
              ),
              maintainState: true,
              initiallyExpanded: shouldExpand,
              leading: Icon(
                _statusIcon(status),
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
                style: TextStyle(
                  color: statusColor,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    14,
                    0,
                    14,
                    14,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      if (error.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.all(
                            12,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme
                                .errorContainer,
                            borderRadius:
                                BorderRadius.circular(
                              8,
                            ),
                          ),
                          child: SelectionArea(
                            child: Text(
                              error,
                              style: TextStyle(
                                color: colorScheme
                                    .onErrorContainer,
                                fontFamily:
                                    'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _buildLogContainer(
                        taskId: taskId,
                        logs: logs,
                      ),
                      if (normalizedStatus ==
                          'running') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Log jest odświeżany '
                                'automatycznie co 3 sekundy.',
                                style: TextStyle(
                                  color: colorScheme
                                      .onSurfaceVariant,
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
            ),
          );
        }),
      ],
    );
  }
}


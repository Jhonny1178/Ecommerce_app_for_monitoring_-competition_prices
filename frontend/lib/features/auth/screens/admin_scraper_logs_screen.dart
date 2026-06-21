import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';

import '../widgets/pipeline_graph_widget.dart';

class AdminScraperLogsScreen extends StatefulWidget {
  final int clientId;
  final String clientName;
  final String scheduleLabel;

  const AdminScraperLogsScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.scheduleLabel,
  });

  @override
  State<AdminScraperLogsScreen> createState() =>
      _AdminScraperLogsScreenState();
}

class _AdminScraperLogsScreenState
    extends State<AdminScraperLogsScreen> {
  bool _isLoading = true;
  List<dynamic> _runs = [];
  String? _error;

  Timer? _runsRefreshTimer;
  bool _isFetchingRuns = false;

  @override
  void initState() {
    super.initState();

    _fetchRuns(showLoader: true);

    _runsRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        _fetchRuns();
      },
    );
  }

  @override
  void dispose() {
    _runsRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRuns({
    bool showLoader = false,
  }) async {
    if (_isFetchingRuns) {
      return;
    }

    _isFetchingRuns = true;

    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await ApiClient.get(
        Uri.parse(
          "/api/admin/clients/"
          "${widget.clientId}/pipeline-runs",
        ),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data['ok'] == true) {
        if (mounted) {
          setState(() {
            _runs = data['runs'] ?? [];
            _error = null;
          });
        }
      } else {
        final message = data['error']?.toString() ??
            'Nie udało się pobrać historii.';

        if (mounted && _runs.isEmpty) {
          setState(() {
            _error = message;
          });
        } else {
          debugPrint(
            'Background pipeline refresh error: $message',
          );
        }
      }
    } catch (e) {
      if (mounted && _runs.isEmpty) {
        setState(() {
          _error = e.toString();
        });
      } else {
        debugPrint(
          'Background pipeline refresh exception: $e',
        );
      }
    } finally {
      _isFetchingRuns = false;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteRun(
    int pipelineRunId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme =
            Theme.of(context).colorScheme;

        return AlertDialog(
          title: const Text(
            'Usunąć przebieg?',
          ),
          content: const Text(
            'Usunięte zostanie tylko to jedno '
            'uruchomienie oraz logi jego etapów. '
            'Pozostałe uruchomienia pozostaną bez zmian.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Anuluj'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor:
                    colorScheme.onError,
              ),
              icon: const Icon(
                Icons.delete_outline,
              ),
              label: const Text('Usuń'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final response = await ApiClient.post(
        Uri.parse(
          "/api/admin/pipeline-runs/"
          "$pipelineRunId/delete",
        ),
      );

      final data = jsonDecode(response.body);

      if (!mounted) {
        return;
      }

      if (response.statusCode == 200 &&
          data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Wybrane uruchomienie zostało usunięte.',
            ),
          ),
        );

        await _fetchRuns();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error']?.toString() ??
                  'Nie udało się usunąć uruchomienia.',
            ),
            backgroundColor:
                Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Błąd usuwania uruchomienia: $e',
          ),
          backgroundColor:
              Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '-';
    }

    String twoDigits(int number) =>
        number.toString().padLeft(2, '0');

    return '${twoDigits(date.day)}.'
        '${twoDigits(date.month)}.'
        '${date.year}';
  }

  String _formatTime(DateTime? date) {
    if (date == null) {
      return '-';
    }

    String twoDigits(int number) =>
        number.toString().padLeft(2, '0');

    return '${twoDigits(date.hour)}:'
        '${twoDigits(date.minute)}:'
        '${twoDigits(date.second)}';
  }

  String _formatDuration(dynamic value) {
    final seconds = int.tryParse(
      value?.toString() ?? '',
    );

    if (seconds == null) {
      return 'Trwa...';
    }

    final duration = Duration(
      seconds: seconds,
    );

    if (duration.inHours > 0) {
      return '${duration.inHours}h '
          '${duration.inMinutes.remainder(60)}m';
    }

    return '${duration.inMinutes}m '
        '${duration.inSeconds.remainder(60)}s';
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
      default:
        return 'Nieznany';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pipeline: ${widget.clientName}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Odśwież',
            onPressed: () {
              _fetchRuns(showLoader: true);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: colorScheme.error,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorScheme
                            .primaryContainer
                            .withOpacity(0.35),
                        borderRadius:
                            BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_tree_outlined,
                            size: 42,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.clientName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.scheduleLabel,
                                  style: TextStyle(
                                    color: colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Historia uruchomień',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_runs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'Brak historii pipeline’u.',
                          ),
                        ),
                      )
                    else
                      ...List.generate(
                        _runs.length,
                        (index) {
                          final run = _runs[index];

                          final startedAt =
                              _parseDate(
                            run['started_at'],
                          );

                          final finishedAt =
                              _parseDate(
                            run['finished_at'],
                          );

                          final status =
                              run['status'];

                          final statusText =
                              status
                                  ?.toString()
                                  .toLowerCase() ??
                              '';

                          final statusColor =
                              _statusColor(
                            status,
                            colorScheme,
                          );

                          final pipelineRunId =
                              int.tryParse(
                            run['pipeline_run_id']
                                    ?.toString() ??
                                '',
                          );

                          return Card(
                            key: PageStorageKey<String>(
                              'pipeline-run-'
                              '${pipelineRunId ?? index}',
                            ),
                            margin:
                                const EdgeInsets.only(
                              bottom: 14,
                            ),
                            elevation: 0,
                            child: ExpansionTile(
                              initiallyExpanded:
                                  index == 0,
                              leading: CircleAvatar(
                                backgroundColor:
                                    statusColor
                                        .withOpacity(0.15),
                                child: Icon(
                                  statusText == 'success'
                                      ? Icons.check
                                      : statusText ==
                                              'failed'
                                          ? Icons.error
                                          : Icons.autorenew,
                                  color: statusColor,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    _formatDate(
                                      startedAt,
                                    ),
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(
                                    width: 10,
                                  ),
                                  Text(
                                    _statusLabel(
                                      status,
                                    ),
                                    style: TextStyle(
                                      color:
                                          statusColor,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Start: '
                                '${_formatTime(startedAt)}'
                                '  •  Koniec: '
                                '${_formatTime(finishedAt)}'
                                '  •  Czas: '
                                '${_formatDuration(run['duration_seconds'])}',
                              ),
                              children: [
                                Align(
                                  alignment:
                                      Alignment.centerRight,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.only(
                                      right: 18,
                                      top: 8,
                                    ),
                                    child: TextButton.icon(
                                      onPressed:
                                          statusText ==
                                                      'running' ||
                                                  pipelineRunId ==
                                                      null
                                              ? null
                                              : () {
                                                  _deleteRun(
                                                    pipelineRunId,
                                                  );
                                                },
                                      icon: const Icon(
                                        Icons.delete_outline,
                                      ),
                                      label: const Text(
                                        'Usuń ten przebieg',
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.all(
                                    18,
                                  ),
                                  child:
                                      PipelineGraphWidget(
                                    pipelineRunId:
                                        pipelineRunId,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
    );
  }
}

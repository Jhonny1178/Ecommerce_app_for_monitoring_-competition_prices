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

  @override
  void initState() {
    super.initState();
    _fetchRuns();
  }

  Future<void> _fetchRuns() async {
    if (mounted) {
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
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = data['error']?.toString() ??
                'Nie udało się pobrać historii.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';

    String twoDigits(int number) =>
        number.toString().padLeft(2, '0');

    return '${twoDigits(date.day)}.'
        '${twoDigits(date.month)}.'
        '${date.year}';
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '-';

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

    if (seconds == null) return 'Trwa...';

    final duration = Duration(seconds: seconds);

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
            onPressed: _fetchRuns,
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

                          final statusColor =
                              _statusColor(
                            status,
                            colorScheme,
                          );

                          return Card(
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
                                  status == 'success'
                                      ? Icons.check
                                      : status == 'failed'
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
                                Padding(
                                  padding:
                                      const EdgeInsets
                                          .all(18),
                                  child:
                                      PipelineGraphWidget(
                                    pipelineRunId:
                                        run[
                                            'pipeline_run_id'],
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
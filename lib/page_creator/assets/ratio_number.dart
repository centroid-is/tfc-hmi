import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';
import '../../providers/database.dart';
import '../../widgets/graph.dart';
import 'package:tfc/converter/color_converter.dart';
import 'package:tfc_dart/converter/duration_converter.dart';
import 'package:tfc_dart/core/database.dart';

part 'ratio_number.g.dart';

@JsonSerializable()
class RatioNumberConfig extends BaseAsset {
  String key1;
  String key2;
  @JsonKey(name: 'key1_label')
  String key1Label;
  @JsonKey(name: 'key2_label')
  String key2Label;
  @ColorConverter()
  @JsonKey(name: 'text_color')
  Color textColor;
  @DurationMinutesConverter()
  @JsonKey(name: 'since_minutes')
  Duration sinceMinutes;
  @JsonKey(name: 'how_many')
  int howMany;
  @JsonKey(name: 'poll_interval')
  Duration pollInterval;
  @JsonKey(name: 'graph_header')
  String? graphHeader;

  RatioNumberConfig({
    required this.key1,
    required this.key2,
    this.key1Label = '',
    this.key2Label = '',
    this.textColor = Colors.black,
    this.sinceMinutes = const Duration(minutes: 10),
    this.howMany = 10,
    this.pollInterval = const Duration(seconds: 1),
    this.graphHeader,
  });

  RatioNumberConfig.preview()
      : key1 = "key1",
        key2 = "key2",
        key1Label = "Key 1",
        key2Label = "Key 2",
        textColor = Colors.black,
        sinceMinutes = const Duration(minutes: 10),
        howMany = 10,
        pollInterval = const Duration(seconds: 1);

  factory RatioNumberConfig.fromJson(Map<String, dynamic> json) =>
      _$RatioNumberConfigFromJson(json);
  Map<String, dynamic> toJson() => _$RatioNumberConfigToJson(this);

  // Helper method to get display label for a key
  String getDisplayLabel(String key) {
    if (key == key1) {
      return key1Label.isNotEmpty ? key1Label : key1;
    } else if (key == key2) {
      return key2Label.isNotEmpty ? key2Label : key2;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) => RatioNumberWidget(config: this);

  @override
  Widget configure(BuildContext context) =>
      _RatioNumberConfigEditor(config: this);
}

class _RatioNumberConfigEditor extends ConsumerStatefulWidget {
  final RatioNumberConfig config;
  const _RatioNumberConfigEditor({required this.config});

  @override
  ConsumerState<_RatioNumberConfigEditor> createState() =>
      _RatioNumberConfigEditorState();
}

class _RatioNumberConfigEditorState
    extends ConsumerState<_RatioNumberConfigEditor> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyField(
            initialValue: widget.config.key1,
            onChanged: (value) => setState(() => widget.config.key1 = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.key1Label,
            decoration: const InputDecoration(
              labelText: 'Key 1 Label',
              helperText: 'Custom label for Key 1 in legend (optional)',
            ),
            onChanged: (value) =>
                setState(() => widget.config.key1Label = value),
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.key2,
            onChanged: (value) => setState(() => widget.config.key2 = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.key2Label,
            decoration: const InputDecoration(
              labelText: 'Key 2 Label',
              helperText: 'Custom label for Key 2 in legend (optional)',
            ),
            onChanged: (value) =>
                setState(() => widget.config.key2Label = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.text,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (value) => setState(() => widget.config.text = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.graphHeader,
            decoration: const InputDecoration(
              labelText: 'Graph Header',
              helperText: 'Custom header for the graph dialog (optional)',
            ),
            onChanged: (value) =>
                setState(() => widget.config.graphHeader = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.sinceMinutes.inMinutes.toString(),
            decoration: const InputDecoration(
              labelText: 'Since (minutes)',
              helperText: 'Time window for counting data points',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final minutes = int.tryParse(value);
              if (minutes != null && minutes > 0) {
                setState(() =>
                    widget.config.sinceMinutes = Duration(minutes: minutes));
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButton<TextPos>(
            value: widget.config.textPos ?? TextPos.right,
            isExpanded: true,
            onChanged: (value) =>
                setState(() => widget.config.textPos = value!),
            items: TextPos.values
                .map((e) =>
                    DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
                .toList(),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            initialValue: widget.config.coordinates,
            onChanged: (c) => setState(() => widget.config.coordinates = c),
            enableAngle: true,
          ),
          const SizedBox(height: 16),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (size) => setState(() => widget.config.size = size),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.howMany.toString(),
            decoration: const InputDecoration(
              labelText: 'How Many Buckets',
              helperText: 'Number of time buckets for historical data',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final howMany = int.tryParse(value);
              if (howMany != null && howMany > 0) {
                setState(() => widget.config.howMany = howMany);
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.pollInterval.inSeconds.toString(),
            decoration: const InputDecoration(
              labelText: 'Poll Interval (seconds)',
              helperText: 'How often to refresh the ratio',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final seconds = int.tryParse(value);
              if (seconds != null && seconds > 0) {
                setState(() =>
                    widget.config.pollInterval = Duration(seconds: seconds));
              }
            },
          ),
        ],
      ),
    );
  }
}

class RatioNumberWidget extends ConsumerStatefulWidget {
  final RatioNumberConfig config;
  const RatioNumberWidget({super.key, required this.config});

  @override
  ConsumerState<RatioNumberWidget> createState() => _RatioNumberWidgetState();
}

class _RatioNumberWidgetState extends ConsumerState<RatioNumberWidget> {
  @override
  Widget build(BuildContext context) {
    if (widget.config.key1 == "key1" && widget.config.key2 == "key2") {
      return _buildDisplay(context, "75.0%");
    }

    return StreamBuilder<Map<String, int>>(
      stream: _getCountsStream(ref),
      builder: (context, snapshot) {
        String displayValue = "---";

        if (snapshot.hasData) {
          final counts = snapshot.data!;
          final count1 = counts[widget.config.key1] ?? 0;
          final count2 = counts[widget.config.key2] ?? 0;
          final total = count1 + count2;

          if (total > 0) {
            final ratio = count1 / total;
            final percentage = ratio * 100;
            displayValue = "${percentage.toStringAsFixed(1)}%";
          } else {
            displayValue = "0.0%";
          }
        }

        return _buildDisplay(context, displayValue);
      },
    );
  }

  Stream<Map<String, int>> _getCountsStream(WidgetRef ref) {
    final databaseAsync = ref.watch(databaseProvider);

    return databaseAsync.when(
      data: (database) {
        if (database == null) {
          return Stream.value({});
        }

        return Stream.periodic(
          widget.config.pollInterval,
          (_) async {
            final count1 = await database.countTimeseriesDataMultiple(
                widget.config.key1, widget.config.sinceMinutes, 1);
            final count2 = await database.countTimeseriesDataMultiple(
                widget.config.key2, widget.config.sinceMinutes, 1);
            return {
              widget.config.key1: count1.values.first,
              widget.config.key2: count2.values.first,
            };
          },
        ).asyncMap((future) => future);
      },
      loading: () => Stream.value({}),
      error: (e, st) => Stream.value({}),
    );
  }

  Widget _buildDisplay(BuildContext context, String value) {
    Widget displayWidget = FittedBox(
      fit: BoxFit.contain,
      child: Transform.rotate(
        angle: (widget.config.coordinates.angle ?? 0) * math.pi / 180,
        child: Text(
          value,
          style: TextStyle(
            color: widget.config.textColor,
          ),
        ),
      ),
    );

    // Make clickable to show bar chart
    displayWidget = GestureDetector(
      onTap: () => _showBarChartDialog(context),
      child: displayWidget,
    );

    return displayWidget;
  }

  Future<List<TimeseriesData<dynamic>>> _getQueue(
      Database db, String key) async {
    return await db.queryTimeseriesData(
        key,
        DateTime.now()
            .subtract(widget.config.sinceMinutes * widget.config.howMany),
        orderBy: 'time DESC');
  }

  void _showBarChartDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Database?>(
        future: ref.read(databaseProvider.future),
        builder: (context, snapshot) {
          final size = MediaQuery.of(context).size;

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Dialog(
              child: Container(
                width: size.width * 0.8,
                height: size.height * 0.8,
                padding: const EdgeInsets.all(16),
                child: const Center(child: CircularProgressIndicator()),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return Dialog(
              child: Container(
                width: size.width * 0.8,
                height: size.height * 0.8,
                padding: const EdgeInsets.all(16),
                child:
                    Text('Database not found: ${snapshot.error ?? "No data"}'),
              ),
            );
          }

          final database = snapshot.data!;
          return FutureBuilder<List<List<TimeseriesData<dynamic>>>>(
            future: Future.wait([
              _getQueue(database, widget.config.key1),
              _getQueue(database, widget.config.key2),
            ]),
            builder: (context, queueSnapshot) {
              if (queueSnapshot.connectionState == ConnectionState.waiting) {
                return Dialog(
                  child: Container(
                    width: size.width * 0.8,
                    height: size.height * 0.8,
                    padding: const EdgeInsets.all(16),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              if (queueSnapshot.hasError) {
                return Dialog(
                  child: Container(
                    width: size.width * 0.8,
                    height: size.height * 0.8,
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading data: ${queueSnapshot.error}'),
                  ),
                );
              }

              final queues = queueSnapshot.data!;
              final key1Queue = queues[0];
              final key2Queue = queues[1];

              return Dialog(
                child: Container(
                  width: size.width * 0.8,
                  height: size.height * 0.8,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.config.graphHeader ??
                                widget.config.text ??
                                'Ratio Analysis',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: RatioAnalysisView(
                          config: widget.config,
                          key1Queue: key1Queue,
                          key2Queue: key2Queue,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class RatioAnalysisView extends StatefulWidget {
  final RatioNumberConfig config;
  final List<TimeseriesData<dynamic>> key1Queue;
  final List<TimeseriesData<dynamic>> key2Queue;

  const RatioAnalysisView({
    super.key,
    required this.config,
    required this.key1Queue,
    required this.key2Queue,
  });

  @override
  State<RatioAnalysisView> createState() => _RatioAnalysisViewState();
}

class _RatioAnalysisViewState extends State<RatioAnalysisView> {
  bool _showChart = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toggle button row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ToggleButtons(
              isSelected: [_showChart, !_showChart],
              onPressed: (index) {
                setState(() {
                  _showChart = index == 0;
                });
              },
              borderRadius: BorderRadius.circular(8),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart),
                      SizedBox(width: 8),
                      Text('Chart'),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.table_chart),
                      SizedBox(width: 8),
                      Text('Table'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Content area
        Expanded(
          child: _showChart
              ? RatioBarChart(
                  config: widget.config,
                  key1Queue: widget.key1Queue,
                  key2Queue: widget.key2Queue,
                )
              : RatioTableView(
                  config: widget.config,
                  key1Queue: widget.key1Queue,
                  key2Queue: widget.key2Queue,
                ),
        ),
      ],
    );
  }
}

class RatioTableView extends StatefulWidget {
  final RatioNumberConfig config;
  final List<TimeseriesData<dynamic>> key1Queue;
  final List<TimeseriesData<dynamic>> key2Queue;

  const RatioTableView({
    super.key,
    required this.config,
    required this.key1Queue,
    required this.key2Queue,
  });

  @override
  State<RatioTableView> createState() => _RatioTableViewState();
}

class _RatioTableViewState extends State<RatioTableView> {
  String?
      _activeFilter; // null = no filter, 'key1' = filter by key1, 'key2' = filter by key2

  @override
  Widget build(BuildContext context) {
    // Combine and sort all data points by time
    final allData = <_TableRow>[];

    for (final dataPoint in widget.key1Queue) {
      allData.add(_TableRow(
        time: dataPoint.time,
        key: widget.config.getDisplayLabel(widget.config.key1),
        value: dataPoint.value.toString(),
        color: Colors.blue,
        keyType: 'key1',
      ));
    }

    for (final dataPoint in widget.key2Queue) {
      allData.add(_TableRow(
        time: dataPoint.time,
        key: widget.config.getDisplayLabel(widget.config.key2),
        value: dataPoint.value.toString(),
        color: Colors.red,
        keyType: 'key2',
      ));
    }

    // Sort by time (newest first)
    allData.sort((a, b) => b.time.compareTo(a.time));

    // Apply filter if active
    final filteredData = _activeFilter == null
        ? allData
        : allData.where((row) => row.keyType == _activeFilter).toList();

    return SingleChildScrollView(
      child: Column(
        children: [
          // Summary row
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem(
                    context,
                    widget.config.getDisplayLabel(widget.config.key1),
                    widget.key1Queue.length,
                    Colors.blue,
                    'key1',
                  ),
                  _buildSummaryItem(
                    context,
                    widget.config.getDisplayLabel(widget.config.key2),
                    widget.key2Queue.length,
                    Colors.red,
                    'key2',
                  ),
                  _buildSummaryItem(
                    context,
                    'Total',
                    widget.key1Queue.length + widget.key2Queue.length,
                    Colors.grey,
                    null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Data table - now spans full width
          Card(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('Key')),
                  DataColumn(label: Text('Value')),
                ],
                rows: filteredData.map((row) {
                  return DataRow(
                    cells: [
                      DataCell(Text(_formatDateTime(row.time))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: row.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: row.color),
                          ),
                          child: Text(
                            row.key,
                            style: TextStyle(
                              color: row.color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(row.value)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(BuildContext context, String label, int count,
      Color color, String? filterKey) {
    final isActive = _activeFilter == filterKey;

    return GestureDetector(
      onTap: () {
        setState(() {
          _activeFilter = isActive ? null : filterKey;
        });
      },
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? color : color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: isActive ? Colors.white : color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}

// Helper class for table rows
class _TableRow {
  final DateTime time;
  final String key;
  final String value;
  final Color color;
  final String keyType; // 'key1' or 'key2' for filtering

  _TableRow({
    required this.time,
    required this.key,
    required this.value,
    required this.color,
    required this.keyType,
  });
}

class RatioBarChart extends ConsumerWidget {
  final RatioNumberConfig config;
  final List<TimeseriesData<dynamic>> key1Queue;
  final List<TimeseriesData<dynamic>> key2Queue;

  const RatioBarChart({
    super.key,
    required this.config,
    required this.key1Queue,
    required this.key2Queue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Create time buckets for the historical data
    final buckets = _createTimeBuckets();
    final key1Data = _aggregateDataByBucket(key1Queue, buckets);
    final key2Data = _aggregateDataByBucket(key2Queue, buckets);

    final data = <Map<String, dynamic>>[];
    for (final entry in key1Data.entries) {
      data.add({
        'x': entry.key.millisecondsSinceEpoch.toDouble(),
        'y': entry.value.toDouble(),
        's': config.getDisplayLabel(config.key1),
      });
    }
    for (final entry in key2Data.entries) {
      data.add({
        'x': entry.key.millisecondsSinceEpoch.toDouble(),
        'y': entry.value.toDouble(),
        's': config.getDisplayLabel(config.key2),
      });
    }

    return Graph(
      config: GraphConfig(
        type: GraphType.barTimeseries,
        xAxis: GraphAxisConfig(unit: ''),
        yAxis: GraphAxisConfig(unit: 'Count'),
        pan: false,
        width: 0.5,
      ),
      data: data,
      showButtons: false,
      chartTheme: ref.watch(chartThemeNotifierProvider),
      redraw: () {},
    ).build(context);
  }

  List<DateTime> _createTimeBuckets() {
    final buckets = <DateTime>[];
    final bucketDuration = config.sinceMinutes;
    final endTime = DateTime.now();

    for (int i = config.howMany - 1; i >= 0; i--) {
      final bucketStart = endTime.subtract(bucketDuration * (i + 1));
      buckets.add(bucketStart);
    }

    return buckets;
  }

  Map<DateTime, int> _aggregateDataByBucket(
      List<TimeseriesData<dynamic>> dataPoints, List<DateTime> buckets) {
    final result = <DateTime, int>{};

    for (final bucket in buckets) {
      final bucketEnd = bucket.add(config.sinceMinutes);
      final count = dataPoints
          .where((point) =>
              point.time.isAfter(bucket) && point.time.isBefore(bucketEnd))
          .length;
      result[bucket] = count;
    }

    return result;
  }
}

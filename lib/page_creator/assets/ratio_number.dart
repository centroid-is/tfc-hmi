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
  @override
  String get displayName => 'Ratio Number';
  @override
  String get category => 'Text & Numbers';

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
  @JsonKey(name: 'bars_clock_aligned', defaultValue: false)
  bool barsClockAligned;
  @JsonKey(name: 'integers_only', defaultValue: false)
  bool integersOnly;
  @JsonKey(name: 'bars_interactive', defaultValue: false)
  bool barsInteractive;
  @JsonKey(name: 'interval_presets', defaultValue: [1, 5, 10, 60, 240])
  List<int> intervalPresets;

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
    this.barsClockAligned = false,
    this.integersOnly = false,
    this.barsInteractive = false,
    this.intervalPresets = const [1, 5, 10, 60, 240],
  });

  RatioNumberConfig.preview()
      : key1 = "key1",
        key2 = "key2",
        key1Label = "Key 1",
        key2Label = "Key 2",
        textColor = Colors.black,
        sinceMinutes = const Duration(minutes: 10),
        howMany = 10,
        pollInterval = const Duration(seconds: 1),
        barsClockAligned = false,
        integersOnly = false,
        barsInteractive = false,
        intervalPresets = const [1, 5, 10, 60, 240];

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
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Clock-Aligned Bars'),
            subtitle: const Text(
                'Align bar chart buckets to clock boundaries (e.g. on the hour)'),
            value: widget.config.barsClockAligned,
            onChanged: (value) =>
                setState(() => widget.config.barsClockAligned = value),
          ),
          SwitchListTile(
            title: const Text('Integer Ticks'),
            subtitle:
                const Text('Only show whole numbers on the bar chart Y-axis'),
            value: widget.config.integersOnly,
            onChanged: (value) =>
                setState(() => widget.config.integersOnly = value),
          ),
          SwitchListTile(
            title: const Text('Interactive Bars'),
            subtitle:
                const Text('Show tooltip on hover/tap in bar chart'),
            value: widget.config.barsInteractive,
            onChanged: (value) =>
                setState(() => widget.config.barsInteractive = value),
          ),
          const SizedBox(height: 16),
          const Text('Available Intervals',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [1, 5, 10, 30, 60, 240, 720, 1440].map((minutes) {
              final selected =
                  widget.config.intervalPresets.contains(minutes);
              return FilterChip(
                label: Text(_formatIntervalMinutes(minutes)),
                selected: selected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      widget.config.intervalPresets.add(minutes);
                      widget.config.intervalPresets.sort();
                    } else {
                      widget.config.intervalPresets.remove(minutes);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

String _formatIntervalMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  if (minutes < 1440) return '${minutes ~/ 60}h';
  return '${minutes ~/ 1440}d';
}

String _formatInterval(Duration d) => _formatIntervalMinutes(d.inMinutes);

/// Returns the end of the current clock-aligned bucket.
/// E.g., with a 1-hour interval at 10:35, returns 11:00.
DateTime _clockAlignedEnd(DateTime time, Duration interval) {
  final ms = interval.inMilliseconds;
  final startOfDay = DateTime(time.year, time.month, time.day);
  final msSinceStartOfDay = time.difference(startOfDay).inMilliseconds;
  final bucketStart = (msSinceStartOfDay ~/ ms) * ms;
  return startOfDay.add(Duration(milliseconds: bucketStart + ms));
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
    final endTime = widget.config.barsClockAligned
        ? _clockAlignedEnd(DateTime.now(), widget.config.sinceMinutes)
        : DateTime.now();
    return await db.queryTimeseriesData(
        key,
        endTime.subtract(widget.config.sinceMinutes * widget.config.howMany),
        orderBy: 'time DESC');
  }

  void _showBarChartDialog(BuildContext context) async {
    final navigator = Navigator.of(context);
    final db = await ref.read(databaseProvider.future);
    if (db == null || !mounted) return;
    final results = await Future.wait([
      _getQueue(db, widget.config.key1),
      _getQueue(db, widget.config.key2),
    ]);
    if (!mounted) return;
    final key1Queue = results[0];
    final key2Queue = results[1];

    showDialog(
      context: navigator.context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
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
  }
}

class RatioAnalysisView extends ConsumerStatefulWidget {
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
  ConsumerState<RatioAnalysisView> createState() => _RatioAnalysisViewState();
}

class _RatioAnalysisViewState extends ConsumerState<RatioAnalysisView> {
  bool _showChart = true;
  late Duration _selectedInterval;
  late List<TimeseriesData<dynamic>> _key1Queue;
  late List<TimeseriesData<dynamic>> _key2Queue;
  bool _isLoading = false;

  // Cache: interval → (key1Data, key2Data)
  final Map<Duration, (List<TimeseriesData<dynamic>>, List<TimeseriesData<dynamic>>)> _cache = {};

  @override
  void initState() {
    super.initState();
    _selectedInterval = widget.config.sinceMinutes;
    _key1Queue = widget.key1Queue;
    _key2Queue = widget.key2Queue;
    // Seed cache with initial data
    _cache[_selectedInterval] = (_key1Queue, _key2Queue);
    // Prefetch other intervals after first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchAll());
  }

  Future<void> _prefetchAll() async {
    final db = await ref.read(databaseProvider.future);
    if (db == null || !mounted) return;
    final presets = widget.config.intervalPresets
        .map((m) => Duration(minutes: m))
        .toList();
    for (final interval in presets) {
      if (_cache.containsKey(interval)) continue;
      final data = await _fetchForInterval(db, interval);
      if (!mounted) return;
      _cache[interval] = data;
    }
  }

  Future<(List<TimeseriesData<dynamic>>, List<TimeseriesData<dynamic>>)>
      _fetchForInterval(Database db, Duration interval) async {
    final endTime = widget.config.barsClockAligned
        ? _clockAlignedEnd(DateTime.now(), interval)
        : DateTime.now();
    final since = interval * widget.config.howMany;
    final results = await Future.wait([
      db.queryTimeseriesData(
          widget.config.key1, endTime.subtract(since),
          orderBy: 'time DESC'),
      db.queryTimeseriesData(
          widget.config.key2, endTime.subtract(since),
          orderBy: 'time DESC'),
    ]);
    return (results[0], results[1]);
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final db = await ref.read(databaseProvider.future);
      if (db == null) return;
      // Fetch current view first
      final data = await _fetchForInterval(db, _selectedInterval);
      if (!mounted) return;
      _cache[_selectedInterval] = data;
      setState(() {
        _key1Queue = data.$1;
        _key2Queue = data.$2;
        _isLoading = false;
      });
      // Then refresh all other cached intervals in background
      final presets = widget.config.intervalPresets
          .map((m) => Duration(minutes: m))
          .toList();
      for (final interval in presets) {
        if (interval == _selectedInterval) continue;
        final other = await _fetchForInterval(db, interval);
        if (!mounted) return;
        _cache[interval] = other;
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeInterval(Duration interval) {
    _selectedInterval = interval;
    final cached = _cache[interval];
    if (cached != null) {
      setState(() {
        _key1Queue = cached.$1;
        _key2Queue = cached.$2;
      });
    } else {
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = widget.config.intervalPresets
        .map((m) => Duration(minutes: m))
        .toList();

    return Column(
      children: [
        // Control bar: interval toggles | chart/table toggle (centered) | refresh
        Stack(
          alignment: Alignment.center,
          children: [
            // Chart/Table toggle (true center)
            ToggleButtons(
              isSelected: [_showChart, !_showChart],
              onPressed: (index) {
                setState(() => _showChart = index == 0);
              },
              borderRadius: BorderRadius.circular(8),
              constraints:
                  const BoxConstraints(minHeight: 36, minWidth: 48),
              children: const [
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart, size: 18),
                      SizedBox(width: 4),
                      Text('Chart'),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.table_chart, size: 18),
                      SizedBox(width: 4),
                      Text('Table'),
                    ],
                  ),
                ),
              ],
            ),
            // Interval toggles (left) + refresh (right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (presets.length > 1)
                  ToggleButtons(
                    isSelected:
                        presets.map((p) => p == _selectedInterval).toList(),
                    onPressed: (i) => _changeInterval(presets[i]),
                    borderRadius: BorderRadius.circular(8),
                    constraints:
                        const BoxConstraints(minHeight: 36, minWidth: 48),
                    children: presets
                        .map((d) => Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Text(_formatInterval(d)),
                            ))
                        .toList(),
                  )
                else
                  const SizedBox.shrink(),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _fetchData,
                  tooltip: 'Refresh',
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
                  key1Queue: _key1Queue,
                  key2Queue: _key2Queue,
                  intervalOverride: _selectedInterval,
                )
              : RatioTableView(
                  config: widget.config,
                  key1Queue: _key1Queue,
                  key2Queue: _key2Queue,
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
  final Duration? intervalOverride;

  const RatioBarChart({
    super.key,
    required this.config,
    required this.key1Queue,
    required this.key2Queue,
    this.intervalOverride,
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

    final key1Label = config.getDisplayLabel(config.key1);
    final key2Label = config.getDisplayLabel(config.key2);

    return Graph(
      config: GraphConfig(
        type: GraphType.barTimeseries,
        xAxis: GraphAxisConfig(unit: ''),
        yAxis: GraphAxisConfig(unit: 'Count', integersOnly: config.integersOnly),
        pan: false,
        tooltip: config.barsInteractive,
        width: 0.5,
      ),
      data: data,
      showButtons: false,
      chartTheme: ref.watch(chartThemeNotifierProvider),
      redraw: () {},
      tooltipBuilder: (point) {
        final x = point.xValue as double;
        // Find both series for this time bucket
        final match1 = data.where((d) => d['x'] == x && d['s'] == key1Label);
        final match2 = data.where((d) => d['x'] == x && d['s'] == key2Label);
        final v1 = match1.isNotEmpty ? (match1.first['y'] as double).round() : 0;
        final v2 = match2.isNotEmpty ? (match2.first['y'] as double).round() : 0;
        final total = v1 + v2;
        final pct = total > 0 ? (v1 / total * 100).toStringAsFixed(1) : '0.0';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$key1Label: $v1', style: const TextStyle(color: Colors.white, fontSize: 12)),
            Text('$key2Label: $v2', style: const TextStyle(color: Colors.white, fontSize: 12)),
            const Divider(height: 8, color: Colors.white54),
            Text('Ratio: $pct%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        );
      },
    ).build(context);
  }

  List<DateTime> _createTimeBuckets() {
    final buckets = <DateTime>[];
    final bucketDuration = intervalOverride ?? config.sinceMinutes;
    final endTime = config.barsClockAligned
        ? _clockAlignedEnd(DateTime.now(), bucketDuration)
        : DateTime.now();

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
      final bucketEnd = bucket.add(intervalOverride ?? config.sinceMinutes);
      final count = dataPoints
          .where((point) =>
              point.time.isAfter(bucket) && point.time.isBefore(bucketEnd))
          .length;
      result[bucket] = count;
    }

    return result;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/converter/duration_converter.dart';

import 'common.dart';
import '../../widgets/graph.dart';
import '../../providers/database.dart';
import '../../core/database.dart';
import '../../core/database_drift.dart' as drift_db;

part 'graph.g.dart';

@JsonSerializable(explicitToJson: true)
class GraphSeriesConfig {
  String key;
  String label;

  GraphSeriesConfig({
    required this.key,
    required this.label,
  });

  factory GraphSeriesConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphSeriesConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphSeriesConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class GraphAssetConfig extends BaseAsset {
  @JsonKey(name: 'graph_type')
  GraphType graphType;
  @JsonKey(name: 'primary_series')
  List<GraphSeriesConfig> primarySeries;
  @JsonKey(name: 'secondary_series')
  List<GraphSeriesConfig> secondarySeries;
  @JsonKey(name: 'x_axis')
  GraphAxisConfig xAxis;
  @JsonKey(name: 'y_axis')
  GraphAxisConfig yAxis;
  @JsonKey(name: 'y_axis2')
  GraphAxisConfig? yAxis2;
  @DurationMinutesConverter()
  @JsonKey(name: 'time_window_min')
  Duration timeWindowMinutes;
  @JsonKey(name: 'header_text')
  String? headerText;

  GraphAssetConfig({
    this.graphType = GraphType.line,
    List<GraphSeriesConfig>? primarySeries,
    List<GraphSeriesConfig>? secondarySeries,
    GraphAxisConfig? xAxis,
    GraphAxisConfig? yAxis,
    this.yAxis2,
    this.timeWindowMinutes = const Duration(minutes: 10),
    this.headerText,
  })  : primarySeries = primarySeries ?? [],
        secondarySeries = secondarySeries ?? [],
        xAxis = xAxis ?? GraphAxisConfig(unit: 's'),
        yAxis = yAxis ?? GraphAxisConfig(unit: '');

  factory GraphAssetConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphAssetConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$GraphAssetConfigToJson(this);

  GraphAssetConfig.preview()
      : graphType = GraphType.line,
        primarySeries = [],
        secondarySeries = [],
        xAxis = GraphAxisConfig(unit: 's'),
        yAxis = GraphAxisConfig(unit: ''),
        timeWindowMinutes = const Duration(minutes: 10);

  @override
  Widget build(BuildContext context) => GraphAsset(this);

  @override
  Widget configure(BuildContext context) => GraphContentConfig(config: this);

  GraphConfig toGraphConfig() => GraphConfig(
        type: graphType,
        xAxis: xAxis,
        yAxis: yAxis,
        yAxis2: yAxis2,
        xSpan: timeWindowMinutes,
      );
}

class GraphContentConfig extends StatefulWidget {
  final GraphAssetConfig config;
  const GraphContentConfig({required this.config});

  @override
  State<GraphContentConfig> createState() => GraphContentConfigState();
}

class GraphContentConfigState extends State<GraphContentConfig> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          MediaQuery.of(context).size.height * 0.8, // Use 80% of screen height
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<GraphType>(
                value: widget.config.graphType,
                onChanged: (value) {
                  setState(() {
                    widget.config.graphType = value!;
                  });
                },
                items: GraphType.values
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                              e.name[0].toUpperCase() + e.name.substring(1)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              _buildSeriesSection(
                'Primary Y Series',
                widget.config.primarySeries,
                (updated) =>
                    setState(() => widget.config.primarySeries = updated),
              ),
              const SizedBox(height: 16),
              _buildSeriesSection(
                'Secondary Y Series',
                widget.config.secondarySeries,
                (updated) =>
                    setState(() => widget.config.secondarySeries = updated),
              ),
              const SizedBox(height: 16),
              _buildAxisConfig(
                'X Axis',
                widget.config.xAxis,
                (updated) => setState(() => widget.config.xAxis = updated!),
                showBoolean: false,
              ),
              const SizedBox(height: 16),
              _buildAxisConfig(
                'Y Axis',
                widget.config.yAxis,
                (updated) => setState(() => widget.config.yAxis = updated!),
              ),
              const SizedBox(height: 16),
              _buildAxisConfig(
                'Y Axis 2 (optional)',
                widget.config.yAxis2,
                (updated) => setState(() => widget.config.yAxis2 = updated),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue:
                    widget.config.timeWindowMinutes.inMinutes.toString(),
                decoration:
                    const InputDecoration(labelText: 'Time Window (minutes)'),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    widget.config.timeWindowMinutes =
                        Duration(minutes: int.tryParse(value) ?? 10);
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: widget.config.headerText,
                decoration: const InputDecoration(labelText: 'Header Text'),
                onChanged: (value) {
                  setState(() => widget.config.headerText = value);
                },
              ),
              const SizedBox(height: 16),
              SizeField(
                initialValue: widget.config.size,
                onChanged: (value) =>
                    setState(() => widget.config.size = value),
              ),
              const SizedBox(height: 16),
              CoordinatesField(
                initialValue: widget.config.coordinates,
                onChanged: (c) => setState(() => widget.config.coordinates = c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesSection(
    String title,
    List<GraphSeriesConfig> series,
    ValueChanged<List<GraphSeriesConfig>> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ...series.asMap().entries.map((entry) {
          final idx = entry.key;
          final config = entry.value;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              title: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextFormField(
                  initialValue: config.label,
                  decoration: const InputDecoration(labelText: 'Label'),
                  onChanged: (value) {
                    final updated = List<GraphSeriesConfig>.from(series);
                    updated[idx] = GraphSeriesConfig(
                      key: config.key,
                      label: value,
                    );
                    onChanged(updated);
                  },
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.all(8.0),
                child: KeyField(
                  initialValue: config.key,
                  onChanged: (value) {
                    final updated = List<GraphSeriesConfig>.from(series);
                    updated[idx] = GraphSeriesConfig(
                      key: value,
                      label: config.label,
                    );
                    onChanged(updated);
                  },
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  final updated = List<GraphSeriesConfig>.from(series)
                    ..removeAt(idx);
                  onChanged(updated);
                },
              ),
            ),
          );
        }),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Series'),
          onPressed: () {
            final updated = List<GraphSeriesConfig>.from(series)
              ..add(GraphSeriesConfig(
                key: '',
                label: '',
              ));
            onChanged(updated);
          },
        ),
      ],
    );
  }

  Widget _buildAxisConfig(String label, GraphAxisConfig? axis,
      ValueChanged<GraphAxisConfig?> onChanged,
      {bool showBoolean = true}) {
    axis ??= GraphAxisConfig(unit: '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // Use Wrap for better responsive behavior
        Row(
          spacing: 8,
          children: [
            SizedBox(
              width: 120,
              child: TextFormField(
                initialValue: axis.unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                onChanged: (value) {
                  onChanged(GraphAxisConfig(
                    unit: value,
                    min: axis!.min,
                    max: axis.max,
                    boolean: axis.boolean,
                  ));
                },
              ),
            ),
            SizedBox(
              width: 120,
              child: TextFormField(
                initialValue: axis.min?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Min'),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  onChanged(GraphAxisConfig(
                    unit: axis!.unit,
                    min: double.tryParse(value),
                    max: axis.max,
                    boolean: axis.boolean,
                  ));
                },
              ),
            ),
            SizedBox(
              width: 120,
              child: TextFormField(
                initialValue: axis.max?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Max'),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  onChanged(GraphAxisConfig(
                    unit: axis!.unit,
                    min: axis.min,
                    max: double.tryParse(value),
                    boolean: axis.boolean,
                  ));
                },
              ),
            ),
          ],
        ),
        if (showBoolean) const SizedBox(height: 8),
        if (showBoolean)
          Row(
            children: [
              const Text('Boolean'),
              const SizedBox(width: 16),
              Switch(
                value: axis.boolean,
                onChanged: (value) {
                  onChanged(GraphAxisConfig(
                      unit: axis!.unit,
                      min: axis.min,
                      max: axis.max,
                      boolean: value));
                },
              ),
            ],
          ),
      ],
    );
  }
}

// The actual widget that displays the graph using the configuration
class GraphAsset extends ConsumerStatefulWidget {
  final GraphAssetConfig config;
  const GraphAsset(this.config, {super.key});

  @override
  ConsumerState<GraphAsset> createState() => _GraphAssetState();
}

class _GraphAssetState extends ConsumerState<GraphAsset> {
  late Graph _graph;
  int _dataMinX;
  Database? _db;
  final List<StreamSubscription<String>> _realtimeSubscriptions = [];

  _GraphAssetState() : _dataMinX = 0;

  @override
  void initState() {
    super.initState();
    _graph = Graph(
        config: widget.config.toGraphConfig(),
        data: [],
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanUpdate,
        redraw: () {
          if (mounted) {
            setState(() {});
          }
        });

    ref.read(databaseProvider.future).then((db) async {
      if (!mounted) return;
      _db = db;
      final start =
          DateTime.now().subtract(widget.config.timeWindowMinutes * 2);
      _dataMinX = start.millisecondsSinceEpoch.toInt();
      _addData(
          await _queryData(DateTimeRange(start: start, end: DateTime.now())));
      _initRealtimeUpdates();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _graph.theme(ref.watch(chartThemeNotifierProvider));
  }

  void _initRealtimeUpdates() async {
    if (_db == null) return; // this should never happen
    final db = _db!;

    Future<StreamSubscription<String>> initSeries(
        GraphSeriesConfig series, bool isPrimary) async {
      final tableName = series.key;
      final channelName = await db.db.enableNotificationChannel(tableName);
      final subscription = db.db.listenToChannel(channelName).listen((payload) {
        drift_db.NotificationData notification =
            drift_db.NotificationData.fromJson(payload);
        if (notification.action == drift_db.NotificationAction.insert) {
          if (notification.data.containsKey('time') &&
              notification.data.containsKey('value')) {
            final time = DateTime.parse(notification.data['time']);
            final value = notification.data['value'];
            _addData([
              {
                'x': time.millisecondsSinceEpoch.toDouble(),
                isPrimary ? 'y' : 'y2': value,
                's': series.key
              }
            ]);
          }
          // todo non time value case
        }
      });
      return subscription;
    }

    for (final series in widget.config.primarySeries) {
      _realtimeSubscriptions.add(await initSeries(series, true));
    }
    for (final series in widget.config.secondarySeries) {
      _realtimeSubscriptions.add(await initSeries(series, false));
    }
  }

  Future<List<Map<String, dynamic>>> _queryData(DateTimeRange range) async {
    if (_db == null) return [];
    final db = _db!;
    final primarySeries =
        widget.config.primarySeries.map((e) => e.key).toList();
    final secondarySeries =
        widget.config.secondarySeries.map((e) => e.key).toList();
    final keys = {'y': primarySeries, 'y2': secondarySeries};
    //final allKeys = [...primarySeries, ...secondarySeries];

    //final watch = Stopwatch()..start();

    // final res = await db.queryTimeseriesDataMultiple(allKeys, range.end,
    //     from: range.start);

    //print('queryTimeseriesDataMultiple took ${watch.elapsed}');

    // print('first result: ${res.entries.first.value.first.time}');
    // print('last result: ${res.entries.first.value.last.time}');

    final result = <Map<String, dynamic>>[];

    // for (final foo in res.entries) {
    //   for (final value in foo.value) {
    //     result.add({
    //       'x': value.time.millisecondsSinceEpoch.toDouble(),
    //       'y': value.value, // todo
    //       's': foo.key
    //     });
    //   }
    // }

    for (final entry in keys.entries) {
      for (final key in entry.value) {
        final data =
            await db.queryTimeseriesData(key, range.end, from: range.start);
        result.addAll(data.map((e) {
          dynamic value = e.value;
          if (value is bool) {
            value = e.value ? 1.0 : 0.0;
          }
          return {
            'x': e.time.millisecondsSinceEpoch.toDouble(),
            entry.key: value,
            's': key
          };
        }).toList());
      }
    }
    return result;
  }

  void _addData(List<Map<String, dynamic>> data) {
    _graph.addAll(data);
  }

  static double? _numFrom(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
    return null;
  }

  Future<void> _onPanUpdate(GraphPanEvent event) async {
    if (event.visibleMinX == null || event.visibleMaxX == null) return;

    // X axis
    // | buffer1 |      window     | buffer2 |
    // |   50%   |     100%        |   50%   |

    final xWindowSize = event.visibleMaxX! - event.visibleMinX!;

    // if _dataMinX is not within buffer1, we need to add to the data

    final buffer1Min = event.visibleMinX! - xWindowSize * 0.5;
    // ignore: unused_local_variable
    final buffer1Max = event.visibleMinX!;

    if (_dataMinX > buffer1Max) {
      // fetch one time window of data
      final start = DateTime.fromMillisecondsSinceEpoch(_dataMinX.toInt())
          .subtract(widget.config.timeWindowMinutes);
      //print(
      //    "fetching data from $start to ${DateTime.fromMillisecondsSinceEpoch(_dataMinX.toInt())}");
      final data = await _queryData(DateTimeRange(
        start: start,
        end: DateTime.fromMillisecondsSinceEpoch(_dataMinX.toInt()),
      ));
      _dataMinX = start.millisecondsSinceEpoch.toInt();

      _addData(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _graph.build();
  }

  @override
  void dispose() {
    super.dispose();
    for (final subscription in _realtimeSubscriptions) {
      subscription.cancel();
    }
    _realtimeSubscriptions.clear();
  }
}

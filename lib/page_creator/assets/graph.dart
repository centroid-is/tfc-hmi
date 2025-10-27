import 'dart:async';
import 'dart:math' as math;

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

  String get legend => label.isNotEmpty ? label : key;

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
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: TextFormField(
                initialValue: axis.title,
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (value) {
                  onChanged(GraphAxisConfig(
                    title: value,
                    unit: axis!.unit,
                    min: axis.min,
                    max: axis.max,
                    boolean: axis.boolean,
                  ));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
  int _dataMaxX;
  Database? _db;
  bool _realTimeActive = true;
  final List<StreamSubscription<String>> _realtimeSubscriptions = [];

  _GraphAssetState()
      : _dataMinX = 0,
        _dataMaxX = 0;

  @override
  void initState() {
    super.initState();
    _graph = Graph(
        config: widget.config.toGraphConfig(),
        data: [],
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanUpdate,
        onNowPressed: _onNowPressed,
        onSetDatePressed: _disableRealtimeUpdates,
        redraw: () {
          if (mounted) {
            setState(() {});
          }
        });

    ref.read(databaseProvider.future).then((db) async {
      if (!mounted) return;
      _db = db;
      final start =
          // 300% of the time window, refer to panUpdate method for more details
          DateTime.now().subtract(widget.config.timeWindowMinutes * 3);
      final end = DateTime.now();
      _dataMinX = start.millisecondsSinceEpoch.toInt();
      _dataMaxX = end.millisecondsSinceEpoch.toInt();
      _addData(await _queryData(DateTimeRange(start: start, end: end)));
      _initRealtimeUpdates();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _graph.theme(ref.watch(chartThemeNotifierProvider));
  }

  void _initRealtimeUpdates() async {
    _graph.setNowButtonDisabled(_realTimeActive);
    if (!_realTimeActive) return;
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
            _dataMaxX = time.millisecondsSinceEpoch.toInt();
            _addData([
              {
                'x': time.millisecondsSinceEpoch.toDouble(),
                isPrimary ? 'y' : 'y2': value,
                's': series.legend
              }
            ]);
            _graph.panForward(time.millisecondsSinceEpoch.toDouble());
          }
          // todo non time value case
        }
      });
      return subscription;
    }

    // if we are already subscribing to realtime updates, don't do it again
    if (_realtimeSubscriptions.isNotEmpty) {
      return;
    }

    for (final series in widget.config.primarySeries) {
      _realtimeSubscriptions.add(await initSeries(series, true));
    }
    for (final series in widget.config.secondarySeries) {
      _realtimeSubscriptions.add(await initSeries(series, false));
    }
    if (!_realTimeActive) {
      _disableRealtimeUpdates();
    }
  }

  void _disableRealtimeUpdates() {
    _realTimeActive = false;
    _graph.setNowButtonDisabled(_realTimeActive);
    for (final subscription in _realtimeSubscriptions) {
      subscription.cancel();
    }
    _realtimeSubscriptions.clear();
  }

  void _onNowPressed() {
    _realTimeActive = true;
    _initRealtimeUpdates();
  }

  Future<List<Map<String, dynamic>>> _queryData(DateTimeRange range) async {
    if (_db == null) return [];
    final db = _db!;
    final keys = {
      'y': widget.config.primarySeries,
      'y2': widget.config.secondarySeries
    };
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
      final axisKey = entry.key;
      for (final series in entry.value) {
        final data = await db.queryTimeseriesData(series.key, range.end,
            from: range.start);
        result.addAll(data.map((e) {
          dynamic value = e.value;
          if (value is bool) {
            value = e.value ? 1.0 : 0.0;
          }
          return {
            'x': e.time.millisecondsSinceEpoch.toDouble(),
            axisKey: value,
            's': series.legend
          };
        }).toList());
      }
    }
    return result;
  }

  void _addData(List<Map<String, dynamic>> data) {
    _graph.addAll(data);
  }

  Future<void> _onPanUpdate(GraphPanEvent event) async {
    if (event.visibleMinX == null || event.visibleMaxX == null) return;

    // if we are panning to the left, we disable realtime updates
    // apperantly +dx is to the left and -dx is to the right
    if (event.delta != null && event.delta!.dx > 0) {
      _disableRealtimeUpdates();
    }

    // When panning, the data size size will differ
    // To begin with it is 300% and the window shows the real time data

    // Initial data size is 300%
    // X axis
    //
    // | buffer1 | buffer2 |      window     |
    // |   100%  |   100%  |     100%        |
    // Now if we pan into buffer2, it becomes the case below rigth

    // Min data size is 300%
    // X axis
    // | buffer1 |      window     | buffer2 |
    // |   100%  |     100%        |   100%  |
    // Now if we pan into buffer2 we fetch 100% data for that direction, see below

    // Data size is 400%
    // X axis
    // | buffer1 |      window     | buffer2 | buffer3 |
    // |   100%  |     100%        |   100%  |   100%  |

    // Max data size is 500%
    // X axis
    // | buffer1 |      window     | buffer2 |
    // |   200%  |     100%        |   200%  |

    final xWindowSize = event.visibleMaxX! - event.visibleMinX!;

    final double mustMin = event.visibleMinX! - xWindowSize * 0.5;
    final double mustMax = math.min(event.visibleMaxX! + xWindowSize * 0.5,
        DateTime.now().millisecondsSinceEpoch.toDouble());
    final double capMin = event.visibleMinX! - xWindowSize * 2.0;
    final double capMax = math.min(event.visibleMaxX! + xWindowSize * 2.0,
        DateTime.now().millisecondsSinceEpoch.toDouble());

    if (_dataMinX > mustMin) {
      // fetch one time window of data
      final end = DateTime.fromMillisecondsSinceEpoch(_dataMinX.toInt());
      final start = end.subtract(widget.config.timeWindowMinutes);
      _dataMinX = start.millisecondsSinceEpoch
          .toInt(); // we only want to query the data once, so if we get subsequent onpanupdate we don't query the same data again
      final data = await _queryData(DateTimeRange(start: start, end: end));
      _addData(data);
    }

    if (_dataMaxX < mustMax) {
      // fetch one time window of data
      final start = DateTime.fromMillisecondsSinceEpoch(_dataMaxX.toInt());
      final end = start.add(widget.config.timeWindowMinutes);
      _dataMaxX = end.millisecondsSinceEpoch.toInt();
      final data = await _queryData(DateTimeRange(start: start, end: end));
      _addData(data);
    }

    // if we are not yet within the must range, we might have jumped back in time or forward in time
    if (_dataMinX > mustMin || _dataMaxX < mustMax) {
      final start = DateTime.fromMillisecondsSinceEpoch(capMin.toInt());
      final end = DateTime.fromMillisecondsSinceEpoch(capMax.toInt());
      _dataMinX = start.millisecondsSinceEpoch.toInt();
      _dataMaxX = end.millisecondsSinceEpoch.toInt();
      final data = await _queryData(DateTimeRange(start: start, end: end));
      _addData(data);
    }

    // --- Prune to stay within the 500% cap ---
    bool removed = false;
    _graph.removeWhere((row) {
      final x = row['x'];
      final out = (x < capMin) || (x > capMax);
      if (out) removed = true;
      return out;
    });

    // Keep trackers consistent with pruning
    if (removed) {
      if (_dataMinX < capMin) _dataMinX = capMin.toInt();
      if (_dataMaxX > capMax) _dataMaxX = capMax.toInt();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _graph.build(context);
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

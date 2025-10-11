// graph.dart (Graph Asset with 200% window + DB backfill on pan)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tfc/converter/duration_converter.dart';

import 'common.dart';
import '../../providers/collector.dart';
import '../../widgets/graph.dart';

// NEW: DB access for backfill
import '../../providers/database.dart';
import '../../core/database.dart';

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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 900),
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

  Widget _buildAxisConfig(
    String label,
    GraphAxisConfig? axis,
    ValueChanged<GraphAxisConfig?> onChanged,
  ) {
    axis ??= GraphAxisConfig(unit: '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // Use Wrap for better responsive behavior
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
                    step: axis.step,
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
                    step: axis.step,
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
                    step: axis.step,
                  ));
                },
              ),
            ),
            SizedBox(
              width: 120,
              child: TextFormField(
                initialValue: axis.step?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Step'),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  onChanged(GraphAxisConfig(
                    unit: axis!.unit,
                    min: axis.min,
                    max: double.tryParse(value),
                    step: double.tryParse(value),
                  ));
                },
              ),
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
  // --- NEW: local buffers & simple update stream ---
  final Map<String, List<List<double>>> _buffers =
      {}; // key -> [[t,y],...], t ms
  final Map<String, StreamSubscription> _subs = {};
  final _invalidate$ = PublishSubject<void>();
  Stream<List<List<List<double>>>>? _combined$;

  // Keep order stable
  List<String> _seriesKeys = [];
  List<GraphSeriesConfig> _allSeries = [];

  // Active viewport (absolute). If null, defaults to [now-window, now]
  DateTimeRange? _viewportAbs;

  @override
  void initState() {
    super.initState();
    _combined$ = _invalidate$
        .sampleTime(const Duration(milliseconds: 200)) // ~5 fps
        .map((_) => _buildWindowData())
        .shareReplay(maxSize: 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureStreams();
  }

  @override
  void didUpdateWidget(covariant GraphAsset oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureStreams();
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    _invalidate$.close();
    super.dispose();
  }

  void _ensureStreams() {
    final collector = ref.read(collectorProvider).value;
    if (collector == null) return;

    _allSeries = [
      ...widget.config.primarySeries,
      ...widget.config.secondarySeries
    ];
    final keys = _allSeries.map((s) => s.key).toList();

    if (!_listEquals(keys, _seriesKeys)) {
      // reset
      for (final s in _subs.values) {
        s.cancel();
      }
      _subs.clear();
      _buffers.clear();
      _seriesKeys = keys;

      // initialize viewport
      final now = DateTime.now();
      _viewportAbs = DateTimeRange(
        start: now.subtract(widget.config.timeWindowMinutes),
        end: now,
      );

      // Subscribe each series; keep a local buffer.
      // We fetch a bit more past data at start to avoid immediate DB backfills.
      final initialSince = widget.config.timeWindowMinutes * 2.0;
      for (final s in _allSeries) {
        _buffers[s.key] = <List<double>>[];
        _subs[s.key] = collector
            .collectStream(s.key, since: initialSince)
            .listen((seriesData) => _mergeChunk(s.key, seriesData));
      }
      _invalidate$.add(null); // reslice to 200%
    }
  }

  void _mergeChunk(String key, List<TimeseriesData<dynamic>> chunk) {
    if (chunk.isEmpty) return;
    final buf = _buffers[key]!;

    // Compute chunk min/max (ms) once
    double cMin = double.infinity, cMax = double.negativeInfinity;
    for (final s in chunk) {
      final t = s.time.millisecondsSinceEpoch.toDouble();
      if (t < cMin) cMin = t;
      if (t > cMax) cMax = t;
    }

    // If the buffer is empty, take everything
    if (buf.isEmpty) {
      buf.addAll(_convertSlice(chunk, 0, chunk.length));
      _invalidateIfIntersects(cMin, cMax);
      return;
    }

    final bufMin = buf.first[0];
    final bufMax = buf.last[0];

    // Quick exits: whole chunk is left or right
    if (cMax < bufMin) {
      // All older → prepend
      _buffers[key] = [..._convertSlice(chunk, 0, chunk.length), ...buf];
      _invalidateIfIntersects(cMin, cMax);
      return;
    }
    if (cMin > bufMax) {
      // All newer → append
      buf.addAll(_convertSlice(chunk, 0, chunk.length));
      _invalidateIfIntersects(cMin, cMax);
      return;
    }

    // Partial overlap: take only true edges (t < bufMin) and (t > bufMax)
    int lastOlder = -1; // last index with t < bufMin
    int firstNewer = chunk.length; // first index with t > bufMax

    for (int i = 0; i < chunk.length; i++) {
      final t = chunk[i].time.millisecondsSinceEpoch.toDouble();
      if (t < bufMin) lastOlder = i;
      if (firstNewer == chunk.length && t > bufMax) firstNewer = i;
    }

    bool touched = false;

    if (lastOlder >= 0) {
      final older = _convertSlice(chunk, 0, lastOlder + 1);
      _buffers[key] = [...older, ...buf];
      touched = true;
    }
    if (firstNewer < chunk.length) {
      final newer = _convertSlice(chunk, firstNewer, chunk.length);
      buf.addAll(newer);
      touched = true;
    }

    if (touched) {
      final sMin = lastOlder >= 0 ? cMin : double.infinity;
      final sMax = firstNewer < chunk.length ? cMax : double.negativeInfinity;
      // intersect against requested 200% window
      _invalidateIfIntersects(
        sMin.isFinite ? sMin : bufMin,
        sMax.isFinite ? sMax : bufMax,
      );
    }
  }

  List<List<double>> _convertSlice(
      List<TimeseriesData<dynamic>> src, int from, int to) {
    // [from, to)  — assumes src is chronological ASC (your DB query is ASC; RT ticks append)
    final out = <List<double>>[];
    for (int i = from; i < to; i++) {
      final v = _numFrom(src[i].value);
      if (v == null) continue;
      out.add([src[i].time.millisecondsSinceEpoch.toDouble(), v]);
    }
    return out;
  }

  void _invalidateIfIntersects(double sliceMin, double sliceMax) {
    final req = _requestedRange();
    final rMin = req.start.millisecondsSinceEpoch.toDouble();
    final rMax = req.end.millisecondsSinceEpoch.toDouble();
    if (sliceMax >= rMin && sliceMin <= rMax) {
      _invalidate$.add(null);
    }
  }

  double? _numFrom(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
    return null;
  }

  DateTimeRange _requestedRange() {
    final span = _viewportAbs?.duration ?? widget.config.timeWindowMinutes;
    final margin = span * 0.5;
    final start = (_viewportAbs?.start ??
            DateTime.now().subtract(widget.config.timeWindowMinutes))
        .subtract(margin)
        .toUtc();
    final end = (_viewportAbs?.end ?? DateTime.now()).add(margin).toUtc();
    return DateTimeRange(start: start, end: end);
  }

  // Slice current viewport ±50% (no copies of points; sublist keeps refs)
  List<List<List<double>>> _buildWindowData() {
    final List<List<List<double>>> out = [];
    if (_viewportAbs == null) {
      return List.generate(_allSeries.length, (_) => []);
    }

    final span = _viewportAbs!.duration;
    final margin = span * 0.5;
    final reqStart = (_viewportAbs!.start.subtract(margin)).toUtc();
    final reqEnd = (_viewportAbs!.end.add(margin)).toUtc();
    final minMs = reqStart.millisecondsSinceEpoch.toDouble();
    final maxMs = reqEnd.millisecondsSinceEpoch.toDouble();

    for (final s in _allSeries) {
      final buf = _buffers[s.key]!;
      if (buf.isEmpty) {
        out.add([]);
        continue;
      }
      final lo = _lowerBound(buf, minMs);
      final hi = _upperBound(buf, maxMs);
      final window = (lo < hi) ? buf.sublist(lo, hi) : const <List<double>>[];
      out.add(window);
    }
    return out;
  }

  int _lowerBound(List<List<double>> a, double t) {
    int l = 0, r = a.length;
    while (l < r) {
      final m = (l + r) >> 1;
      if (a[m][0] < t) {
        l = m + 1;
      } else {
        r = m;
      }
    }
    return l;
  }

  int _upperBound(List<List<double>> a, double t) {
    int l = 0, r = a.length;
    while (l < r) {
      final m = (l + r) >> 1;
      if (a[m][0] <= t) {
        l = m + 1;
      } else {
        r = m;
      }
    }
    return l;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // --- DB backfill when pan reveals gaps outside current buffer ---
  Future<void> _backfillIfMissing(DateTimeRange visible) async {
    final dbAsync = ref.read(databaseProvider);
    final db = dbAsync.value;
    if (db == null) return;

    final span = visible.duration;
    final margin = span * 0.5;
    final reqStart = visible.start.subtract(margin).toUtc();
    final reqEnd = visible.end.add(margin).toUtc();

    for (final s in _allSeries) {
      final buf = _buffers[s.key]!;
      if (buf.isEmpty) {
        // Fetch full required window
        final fetched = await db.queryTimeseriesData(
          s.key,
          reqEnd,
          from: reqStart,
        );
        if (fetched.isNotEmpty) {
          for (final row in fetched) {
            final y = _numFrom(row.value);
            if (y == null) continue;
            buf.add([row.time.millisecondsSinceEpoch.toDouble(), y]);
          }
          buf.sort((a, b) => a[0].compareTo(b[0]));
        }
        continue;
      }

      final bufStart = DateTime.fromMillisecondsSinceEpoch(buf.first[0].toInt(),
          isUtc: true);
      final bufEnd =
          DateTime.fromMillisecondsSinceEpoch(buf.last[0].toInt(), isUtc: true);

      // Missing on the left?
      if (reqStart.isBefore(bufStart)) {
        final fetched = await db.queryTimeseriesData(
          s.key,
          bufStart, // to
          from: reqStart,
        );
        if (fetched.isNotEmpty) {
          final prepend = <List<double>>[];
          for (final row in fetched) {
            final y = _numFrom(row.value);
            if (y == null) continue;
            final t = row.time.millisecondsSinceEpoch.toDouble();
            if (t < buf.first[0]) prepend.add([t, y]);
          }
          if (prepend.isNotEmpty) {
            // Insert at front (keep sorted)
            _buffers[s.key] = [...prepend, ...buf];
          }
        }
      }

      // Missing on the right?
      if (reqEnd.isAfter(bufEnd)) {
        final fetched = await db.queryTimeseriesData(
          s.key,
          reqEnd, // to
          from: bufEnd,
        );
        if (fetched.isNotEmpty) {
          for (final row in fetched) {
            final y = _numFrom(row.value);
            if (y == null) continue;
            final t = row.time.millisecondsSinceEpoch.toDouble();
            if (t > buf.last[0]) buf.add([t, y]);
          }
        }
      }
    }

    _invalidate$.add(null);
  }

  @override
  Widget build(BuildContext context) {
    final collectorAsync = ref.watch(collectorProvider);

    return collectorAsync.when(
      data: (collector) {
        if (collector == null) {
          return const Center(child: Text('No collector available'));
        }

        return StreamBuilder<List<List<List<double>>>>(
          stream: _combined$,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              // Kick an initial emission once we have subscriptions
              _invalidate$.add(null);
              return const Center(child: CircularProgressIndicator());
            }

            final sliced = snapshot.data!;
            // Convert to the format expected by the Graph widget
            final graphData = <Map<GraphDataConfig, List<List<double>>>>[];

            int i = 0;
            for (var series in _allSeries) {
              final points =
                  (i < sliced.length) ? sliced[i] : const <List<double>>[];
              graphData.add({
                GraphDataConfig(
                  label: series.label,
                  mainAxis: widget.config.primarySeries.contains(series),
                  color: GraphConfig.colors[i % GraphConfig.colors.length],
                ): points,
              });
              i++;
            }

            return Stack(children: [
              RepaintBoundary(
                // ⬅ isolate chart+legend painting
                key: ValueKey('chart:${_seriesKeys.join("|")}'),
                child: Graph(
                  config: GraphConfig(
                    type: widget.config.graphType,
                    xAxis: widget.config.xAxis,
                    yAxis: widget.config.yAxis,
                    yAxis2: widget.config.yAxis2,
                    xSpan: widget.config.timeWindowMinutes,
                  ),
                  data: graphData,
                  showDate: false,
                  onPanUpdate: (ev) {
                    if (ev.minTime != null && ev.maxTime != null) {
                      _viewportAbs = DateTimeRange(
                        start: ev.minTime!.toUtc(),
                        end: ev.maxTime!.toUtc(),
                      );
                      _invalidate$.add(null); // reslice to 200%
                    }
                  },
                  onPanEnd: (ev) async {
                    if (ev.minTime != null && ev.maxTime != null) {
                      _viewportAbs = DateTimeRange(
                        start: ev.minTime!.toUtc(),
                        end: ev.maxTime!.toUtc(),
                      );
                      await _backfillIfMissing(_viewportAbs!);
                    }
                  },
                ),
              ),
            ]);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }
}

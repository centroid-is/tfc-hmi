import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tfc/converter/duration_converter.dart';

import 'common.dart';
import '../../providers/collector.dart';
import '../../widgets/graph.dart';

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
                    max: axis.max,
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
  Stream<List<List<List<double>>>>? _combined$;
  List<String> _seriesKeys = [];
  List<GraphSeriesConfig> _allSeries = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureCombinedStream();
  }

  @override
  void didUpdateWidget(covariant GraphAsset oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureCombinedStream();
  }

  void _ensureCombinedStream() {
    final collector = ref.read(collectorProvider).value;
    if (collector == null) return;

    _allSeries = [
      ...widget.config.primarySeries,
      ...widget.config.secondarySeries
    ];
    final keys = _allSeries.map((s) => s.key).toList();

    if (!_listEquals(keys, _seriesKeys)) {
      _seriesKeys = keys;
      // TODO: make this as time window, when panning is implemented better

      Iterable<Stream<List<List<double>>>> streams = _allSeries.map((s) =>
          collector
              .collectStream(s.key,
                  since: widget.config.timeWindowMinutes * 1.5)
              .map((seriesData) => seriesData
                  .map((sample) {
                    final value = sample.value;
                    final time = sample.time.millisecondsSinceEpoch.toDouble();
                    double? y;
                    if (value is num) {
                      y = value.toDouble();
                    } else if (value is Map && value['value'] is num) {
                      y = (value['value'] as num).toDouble();
                    }
                    return y != null ? [time, y] : null;
                  })
                  .whereType<List<double>>()
                  .toList()));
      // cap UI update rate (e.g., 10–20 fps)
      _combined$ = Rx.combineLatestList(streams)
          .sampleTime(const Duration(milliseconds: 200)); // ~5 fps
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b) ||
        a.length == b.length &&
            a.asMap().entries.every((e) => e.value == b[e.key])) {
      return true;
    }
    return false;
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
            List<List<List<double>>> data;
            if (snapshot.hasData) {
              data = snapshot.data!;
            } else {
              return const Center(child: CircularProgressIndicator());
            }

            // Convert to the format expected by the Graph widget
            final graphData = <Map<GraphDataConfig, List<List<double>>>>[];

            int i = 0;
            for (var series in _allSeries) {
              graphData.add({
                GraphDataConfig(
                  label: series.label,
                  mainAxis: widget.config.primarySeries.contains(series),
                  color: GraphConfig.colors[i],
                ): data[i++],
              });
            }

            return Stack(
              children: [
                // Wrap the graph in a GestureDetector for interaction detection
                GestureDetector(
                  onTapDown: (_) => {},
                  onPanStart: (_) => {},
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
                  ),
                ),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }
}

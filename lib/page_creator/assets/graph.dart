import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tfc/core/duration_converter.dart';

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

  GraphAssetConfig({
    this.graphType = GraphType.line,
    List<GraphSeriesConfig>? primarySeries,
    List<GraphSeriesConfig>? secondarySeries,
    GraphAxisConfig? xAxis,
    GraphAxisConfig? yAxis,
    this.yAxis2,
    this.timeWindowMinutes = const Duration(minutes: 10),
  })  : primarySeries = primarySeries ?? [],
        secondarySeries = secondarySeries ?? [],
        xAxis = xAxis ?? GraphAxisConfig(unit: 's'),
        yAxis = yAxis ?? GraphAxisConfig(unit: '');

  factory GraphAssetConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphAssetConfigFromJson(json);
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
  Widget configure(BuildContext context) => _ConfigContent(config: this);
}

class _ConfigContent extends StatefulWidget {
  final GraphAssetConfig config;
  const _ConfigContent({required this.config});

  @override
  State<_ConfigContent> createState() => _ConfigContentState();
}

class _ConfigContentState extends State<_ConfigContent> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
                        child:
                            Text(e.name[0].toUpperCase() + e.name.substring(1)),
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
            SizeField(
              initialValue: widget.config.size,
              onChanged: (value) => setState(() => widget.config.size = value),
            ),
            const SizedBox(height: 16),
            CoordinatesField(
              initialValue: widget.config.coordinates,
              onChanged: (c) => setState(() => widget.config.coordinates = c),
            ),
          ],
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
        Row(
          children: [
            Expanded(
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
            const SizedBox(width: 8),
            Expanded(
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
            const SizedBox(width: 8),
            Expanded(
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
            const SizedBox(width: 8),
            Expanded(
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
class GraphAsset extends ConsumerWidget {
  final GraphAssetConfig config;
  const GraphAsset(this.config, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectorAsync = ref.watch(collectorProvider);

    return collectorAsync.when(
      data: (collector) {
        if (collector == null) {
          return const Center(child: Text('No collector available'));
        }

        // Gather all keys from both series lists
        final allSeries = [
          ...config.primarySeries,
          ...config.secondarySeries,
        ];

        // For each key, get a stream of timeseries data
        final streams = allSeries.map((series) {
          return collector.collectStream(
            series.key,
            // TODO: make this as time window, when panning is implemented better
            since: const Duration(days: 365),
          );
        }).toList();

        return StreamBuilder<List<List<dynamic>>>(
          stream: Rx.combineLatestList(streams),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            // Each entry in data is a list of TimeseriesData for a series
            // Convert to the format expected by the Graph widget
            final graphData = <Map<GraphDataConfig, List<List<double>>>>[];

            for (int i = 0; i < allSeries.length; i++) {
              final series = allSeries[i];
              final seriesData = data[i];
              final points = <List<double>>[];

              for (final sample in seriesData) {
                // Expecting TimeseriesData<dynamic> with .value and .time
                final value = sample.value;
                final time = sample.time.millisecondsSinceEpoch.toDouble();
                double? y;
                if (value is num) {
                  y = value.toDouble();
                } else if (value is Map && value['value'] is num) {
                  y = (value['value'] as num).toDouble();
                }
                if (y != null) {
                  points.add([time, y]);
                }
              }

              graphData.add({
                GraphDataConfig(
                  label: series.label,
                  mainAxis: i == 0,
                ): points,
              });
            }

            return Graph(
              config: GraphConfig(
                type: config.graphType,
                xAxis: config.xAxis,
                yAxis: config.yAxis,
                yAxis2: config.yAxis2,
                xSpan: config.timeWindowMinutes,
              ),
              data: graphData,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';
import '../../providers/database.dart';
import '../../widgets/graph.dart';
import '../../converter/color_converter.dart';
import '../../converter/duration_converter.dart';
import '../../core/database.dart';

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

class _RatioNumberConfigEditor extends StatefulWidget {
  final RatioNumberConfig config;
  const _RatioNumberConfigEditor({required this.config});

  @override
  State<_RatioNumberConfigEditor> createState() =>
      _RatioNumberConfigEditorState();
}

class _RatioNumberConfigEditorState extends State<_RatioNumberConfigEditor> {
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

class RatioNumberWidget extends ConsumerWidget {
  final RatioNumberConfig config;
  const RatioNumberWidget({super.key, required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (config.key1 == "key1" && config.key2 == "key2") {
      return _buildDisplay(context, "75.0%");
    }

    return StreamBuilder<Map<String, int>>(
      stream: _getCountsStream(ref),
      builder: (context, snapshot) {
        String displayValue = "---";

        if (snapshot.hasData) {
          final counts = snapshot.data!;
          final count1 = counts[config.key1] ?? 0;
          final count2 = counts[config.key2] ?? 0;
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
          config.pollInterval,
          (_) async {
            final count1 = await database.countTimeseriesDataMultiple(
                config.key1, config.sinceMinutes, 1);
            final count2 = await database.countTimeseriesDataMultiple(
                config.key2, config.sinceMinutes, 1);
            return {
              config.key1: count1.values.first,
              config.key2: count2.values.first,
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
        angle: (config.coordinates.angle ?? 0) * math.pi / 180,
        child: Text(
          value,
          style: TextStyle(
            color: config.textColor,
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

  void _showBarChartDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 800,
          height: 600,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    config.graphHeader ?? config.text ?? 'Ratio Analysis',
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
                child: RatioBarChart(config: config),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RatioBarChart extends ConsumerWidget {
  final RatioNumberConfig config;

  const RatioBarChart({super.key, required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final databaseAsync = ref.watch(databaseProvider);

    return databaseAsync.when(
      data: (database) {
        if (database == null) {
          return const Center(child: Text('No database available'));
        }

        return FutureBuilder<Map<String, Map<DateTime, int>>>(
          future: _getHistoricalCounts(database),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final historicalData = snapshot.data!;
            final graphData = <Map<GraphDataConfig, List<List<double>>>>[];

            // Create data for key1 using actual DateTime values
            final key1Data = <List<double>>[];
            final key1SortedKeys = historicalData[config.key1]!.keys.toList()
              ..sort();
            for (final bucketStart in key1SortedKeys) {
              key1Data.add([
                bucketStart.millisecondsSinceEpoch.toDouble(),
                historicalData[config.key1]![bucketStart]?.toDouble() ?? 0.0
              ]);
            }
            graphData.add({
              GraphDataConfig(
                label: config.getDisplayLabel(config.key1),
                color: Colors.blue,
              ): key1Data,
            });

            // Create data for key2 using actual DateTime values
            final key2Data = <List<double>>[];
            final key2SortedKeys = historicalData[config.key2]!.keys.toList()
              ..sort();
            for (final bucketStart in key2SortedKeys) {
              key2Data.add([
                bucketStart.millisecondsSinceEpoch.toDouble(),
                historicalData[config.key2]![bucketStart]?.toDouble() ?? 0.0
              ]);
            }
            graphData.add({
              GraphDataConfig(
                label: config.getDisplayLabel(config.key2),
                color: Colors.red,
              ): key2Data,
            });

            return Graph(
              config: GraphConfig(
                type: GraphType.barTimeseries,
                xAxis: GraphAxisConfig(unit: ''),
                yAxis: GraphAxisConfig(unit: 'Count'),
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

  Future<Map<String, Map<DateTime, int>>> _getHistoricalCounts(
      Database database) async {
    final key1Counts = await database.countTimeseriesDataMultiple(
        config.key1, config.sinceMinutes, config.howMany);
    final key2Counts = await database.countTimeseriesDataMultiple(
        config.key2, config.sinceMinutes, config.howMany);

    return {
      config.key1: key1Counts,
      config.key2: key2Counts,
    };
  }
}

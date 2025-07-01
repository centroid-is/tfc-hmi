import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cristalyse/cristalyse.dart';

import '../converter/color_converter.dart';

part 'graph.g.dart';

@JsonSerializable(explicitToJson: true)
class GraphDataConfig {
  final String label;
  final bool mainAxis; // Whether this is the main axis or a secondary axis
  @OptionalColorConverter()
  final Color? color;

  GraphDataConfig({
    required this.label,
    this.mainAxis = true,
    this.color,
  });

  factory GraphDataConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphDataConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphDataConfigToJson(this);
}

@JsonEnum()
enum GraphType {
  line,
  bar,
  scatter,
  timeseries,
}

@JsonSerializable(explicitToJson: true)
class GraphAxisConfig {
  final String unit;
  final double? min;
  final double? max;
  final double? step;

  GraphAxisConfig({
    required this.unit,
    this.min,
    this.max,
    this.step,
  });

  factory GraphAxisConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphAxisConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphAxisConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class GraphConfig {
  final GraphType type;
  final GraphAxisConfig xAxis;
  final GraphAxisConfig yAxis;
  final GraphAxisConfig? yAxis2;
  final Duration? xSpan; // New field for timeseries span

  static const List<Color> colors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.brown,
    Colors.grey,
    Colors.teal,
    Colors.lime,
    Colors.indigo,
    Colors.cyan,
    Colors.amber,
    Colors.deepPurple,
    Colors.deepOrange,
    Colors.deepOrange,
    Colors.deepOrange,
  ];

  GraphConfig({
    required this.type,
    required this.xAxis,
    required this.yAxis,
    this.yAxis2,
    this.xSpan,
  });

  factory GraphConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphConfigToJson(this);
}

class Graph extends StatefulWidget {
  final GraphConfig config;
  final List<Map<GraphDataConfig, List<List<double>>>> data;
  final Function()? onPanCompleted;

  const Graph({
    super.key,
    required this.config,
    required this.data,
    this.onPanCompleted,
  });

  @override
  State<Graph> createState() => _GraphState();
}

class _GraphState extends State<Graph> {
  final Set<String> _hiddenSeries = {};
  Offset _legendOffset = const Offset(16, 16); // left, top

  @override
  Widget build(BuildContext context) {
    // Filter out hidden series
    final filteredData = widget.data.map((seriesMap) {
      return Map.fromEntries(
        seriesMap.entries.where((e) => !_hiddenSeries.contains(e.key.label)),
      );
    }).toList();

    Widget chart = _buildChart(filteredData);

    return Stack(
      children: [
        chart,
        Positioned(
          left: _legendOffset.dx,
          top: _legendOffset.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _legendOffset += details.delta;
                if (_legendOffset.dx < 0) {
                  _legendOffset = Offset(0, _legendOffset.dy);
                }
                if (_legendOffset.dy < 0) {
                  _legendOffset = Offset(_legendOffset.dx, 0);
                }
              });
            },
            child: _buildLegend(context),
          ),
        ),
      ],
    );
  }

  Widget _buildChart(
      List<Map<GraphDataConfig, List<List<double>>>> filteredData) {
    // If no data is provided, show an empty container
    if (filteredData.isEmpty || filteredData.every((m) => m.isEmpty)) {
      return const SizedBox.shrink();
    }

    // Convert data to cristalyse format
    final cristalyseData = _convertToCristalyseData(filteredData);
    if (cristalyseData.isEmpty) {
      return const SizedBox.shrink();
    }

    // Build chart based on type
    switch (widget.config.type) {
      case GraphType.line:
        return _buildLineChart(cristalyseData);
      case GraphType.bar:
        return _buildBarChart(cristalyseData);
      case GraphType.scatter:
        return _buildScatterChart(cristalyseData);
      case GraphType.timeseries:
        return _buildTimeSeriesChart(cristalyseData);
    }
  }

  Widget _buildLineChart(List<Map<String, dynamic>> data) {
    var chart = CristalyseChart()
        .data(data)
        .mapping(x: 'x', y: 'y', color: 'series')
        .geomLine(strokeWidth: 2.0, alpha: 0.8)
        .geomPoint(size: 4.0, alpha: 0.7)
        .scaleXContinuous()
        .scaleYContinuous();

    // Add secondary Y-axis if configured
    if (widget.config.yAxis2 != null) {
      chart = chart.mappingY2('y2');
    }

    // Add pan interaction if callback is provided
    if (widget.onPanCompleted != null) {
      chart = chart.interaction(
        pan: PanConfig(
          enabled: true,
          onPanEnd: (info) => widget.onPanCompleted!(),
          updateXDomain: true,
          updateYDomain: false,
        ),
      );
    }

    return chart.theme(ChartTheme.defaultTheme()).build();
  }

  Widget _buildBarChart(List<Map<String, dynamic>> data) {
    var chart = CristalyseChart()
        .data(data)
        .mapping(x: 'x', y: 'y', color: 'series')
        .geomBar(width: 0.8, alpha: 0.8)
        .scaleXOrdinal()
        .scaleYContinuous();

    // Add secondary Y-axis if configured
    if (widget.config.yAxis2 != null) {
      chart = chart.mappingY2('y2');
    }

    // Add pan interaction if callback is provided
    if (widget.onPanCompleted != null) {
      chart = chart.interaction(
        pan: PanConfig(
          enabled: true,
          onPanEnd: (info) => widget.onPanCompleted!(),
        ),
      );
    }

    return chart.theme(ChartTheme.defaultTheme()).build();
  }

  Widget _buildScatterChart(List<Map<String, dynamic>> data) {
    var chart = CristalyseChart()
        .data(data)
        .mapping(x: 'x', y: 'y', color: 'series')
        .geomPoint(size: 6.0, alpha: 0.7)
        .scaleXContinuous()
        .scaleYContinuous();

    // Add secondary Y-axis if configured
    if (widget.config.yAxis2 != null) {
      chart = chart.mappingY2('y2');
    }

    // Add pan interaction if callback is provided
    if (widget.onPanCompleted != null) {
      chart = chart.interaction(
        pan: PanConfig(
          enabled: true,
          onPanEnd: (info) => widget.onPanCompleted!(),
        ),
      );
    }

    return chart.theme(ChartTheme.defaultTheme()).build();
  }

  Widget _buildTimeSeriesChart(List<Map<String, dynamic>> data) {
    var chart = CristalyseChart()
        .data(data)
        .mapping(x: 'x', y: 'y', color: 'series')
        .geomLine(strokeWidth: 2.0, alpha: 0.8)
        .geomPoint(size: 4.0, alpha: 0.7)
        .scaleXContinuous()
        .scaleYContinuous();

    // Add secondary Y-axis if configured
    if (widget.config.yAxis2 != null) {
      chart = chart.mappingY2('y2');
    }

    // Add pan interaction if callback is provided
    if (widget.onPanCompleted != null) {
      chart = chart.interaction(
        pan: PanConfig(
          enabled: true,
          onPanEnd: (info) => widget.onPanCompleted!(),
        ),
      );
    }

    return chart.theme(ChartTheme.defaultTheme()).build();
  }

  Widget _buildLegend(BuildContext context) {
    // Collect all series configs
    final configs = <GraphDataConfig>{};
    for (final map in widget.data) {
      configs.addAll(map.keys);
    }
    if (configs.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).colorScheme.surfaceBright.withAlpha(200),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: configs.toList().asMap().entries.map((entry) {
            final i = entry.key;
            final config = entry.value;
            final isHidden = _hiddenSeries.contains(config.label);
            final color = config.color ??
                GraphConfig.colors[i % GraphConfig.colors.length];

            return InkWell(
              onTap: () {
                setState(() {
                  if (isHidden) {
                    _hiddenSeries.remove(config.label);
                  } else {
                    _hiddenSeries.add(config.label);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Color dot
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isHidden ? color.withAlpha(128) : color,
                        border: Border.all(
                          color: color,
                          width: 2,
                        ),
                      ),
                    ),
                    Text(
                      config.label,
                      style: TextStyle(
                        decoration:
                            isHidden ? TextDecoration.lineThrough : null,
                        color: isHidden ? Colors.grey : color,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Convert the complex data structure to cristalyse format
  List<Map<String, dynamic>> _convertToCristalyseData(
      List<Map<GraphDataConfig, List<List<double>>>> filteredData) {
    final result = <Map<String, dynamic>>[];
    final usedLabels = <String>{};

    for (var seriesMap in filteredData) {
      seriesMap.forEach((config, points) {
        // Validate label uniqueness
        if (usedLabels.contains(config.label)) {
          throw ArgumentError('Duplicate series label: ${config.label}');
        }
        usedLabels.add(config.label);

        // Filter out invalid points
        final validPoints = points.where(_isValidDataPoint).toList();
        if (validPoints.isEmpty) return;

        // Convert points to cristalyse format
        for (final point in validPoints) {
          final dataPoint = <String, dynamic>{
            'series': config.label,
            'x': point[0],
            'y': point[1],
          };

          // Add secondary Y-axis data if this series uses it
          if (!config.mainAxis && widget.config.yAxis2 != null) {
            dataPoint['y2'] = point[1];
          }

          // Handle timeseries data
          if (widget.config.type == GraphType.timeseries) {
            dataPoint['x'] =
                DateTime.fromMillisecondsSinceEpoch(point[0].toInt());
          }

          result.add(dataPoint);
        }
      });
    }

    return result;
  }

  // Validation methods
  bool _isValidNumber(double value) {
    return !value.isNaN && !value.isInfinite;
  }

  bool _isValidDataPoint(List<double> point) {
    return point.length == 2 &&
        _isValidNumber(point[0]) &&
        _isValidNumber(point[1]);
  }
}

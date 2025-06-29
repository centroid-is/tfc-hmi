import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;

part 'graph.g.dart';

@JsonSerializable(explicitToJson: true)
class GraphDataConfig {
  final String label;
  final bool mainAxis; // Whether this is the main axis or a secondary axis

  GraphDataConfig({
    required this.label,
    this.mainAxis = true,
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

  GraphConfig({
    required this.type,
    required this.xAxis,
    required this.yAxis,
    this.yAxis2,
  });

  factory GraphConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphConfigToJson(this);
}

class Graph extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // If no data is provided, show an empty container with the same dimensions
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    // Configure behaviors
    switch (config.type) {
      case GraphType.line:
        final behaviors = [
          charts.PanAndZoomBehavior<num>(
            panningCompletedCallback: () {
              if (onPanCompleted != null) {
                onPanCompleted!();
              }
            },
          ),
        ];
        final series = _convertDataToNumericSeries();
        // Return empty container if no valid series data
        if (series.isEmpty) {
          return const SizedBox.shrink();
        }
        return charts.LineChart(
          series,
          animate: false,
          domainAxis: _buildAxisSpec(config.xAxis, 15),
          primaryMeasureAxis: _buildAxisSpec(config.yAxis),
          secondaryMeasureAxis:
              config.yAxis2 != null ? _buildAxisSpec(config.yAxis2!) : null,
          behaviors: behaviors,
        );

      case GraphType.bar:
        final behaviors = [
          charts.PanAndZoomBehavior<String>(
            panningCompletedCallback: () {
              if (onPanCompleted != null) {
                onPanCompleted!();
              }
            },
          ),
        ];
        final series = _convertDataToBarSeries();
        // Return empty container if no valid series data
        if (series.isEmpty) {
          return const SizedBox.shrink();
        }
        return charts.BarChart(
          series,
          animate: false,
          domainAxis: _buildStringAxisSpec(config.xAxis),
          primaryMeasureAxis: _buildAxisSpec(config.yAxis),
          secondaryMeasureAxis:
              config.yAxis2 != null ? _buildAxisSpec(config.yAxis2!) : null,
          behaviors: behaviors,
        );

      case GraphType.scatter:
        final behaviors = [
          charts.PanAndZoomBehavior<num>(
            panningCompletedCallback: () {
              if (onPanCompleted != null) {
                onPanCompleted!();
              }
            },
          ),
        ];
        final series = _convertDataToNumericSeries();
        // Return empty container if no valid series data
        if (series.isEmpty) {
          return const SizedBox.shrink();
        }
        return charts.ScatterPlotChart(
          series,
          animate: false,
          domainAxis: _buildAxisSpec(config.xAxis),
          primaryMeasureAxis: _buildAxisSpec(config.yAxis),
          secondaryMeasureAxis:
              config.yAxis2 != null ? _buildAxisSpec(config.yAxis2!) : null,
          behaviors: behaviors,
        );

      case GraphType.timeseries:
        return const SizedBox.shrink(); //todo
    }
  }

  // Helper to calculate delta between viewports
  double _calculateDelta(
    charts.NumericExtents previous,
    charts.NumericExtents current,
  ) {
    final previousCenter = (previous.min! + previous.max!) / 2;
    final currentCenter = (current.min! + current.max!) / 2;
    return previousCenter - currentCenter;
  }

  // Add these validation methods

  bool _isValidNumber(double value) {
    return !value.isNaN && !value.isInfinite;
  }

  bool _isValidDataPoint(List<double> point) {
    return point.length == 2 &&
        _isValidNumber(point[0]) &&
        _isValidNumber(point[1]);
  }

  // Convert input data to numeric series (for line and scatter charts)
  List<charts.Series<_Point, num>> _convertDataToNumericSeries() {
    final seriesList = <charts.Series<_Point, num>>[];
    final usedLabels = <String>{};

    for (var seriesMap in data) {
      seriesMap.forEach((config, points) {
        // Validate label uniqueness
        if (usedLabels.contains(config.label)) {
          throw ArgumentError('Duplicate series label: ${config.label}');
        }
        usedLabels.add(config.label);

        // Filter out invalid points
        final validPoints = points.where(_isValidDataPoint).toList();
        if (validPoints.isEmpty) return;

        final data = validPoints.map((p) => _Point(p[0], p[1])).toList();
        seriesList.add(
          charts.Series<_Point, num>(
            id: config.label,
            data: data,
            domainFn: (_Point point, _) => point.x,
            measureFn: (_Point point, _) => point.y,
          ),
        );
        if (!config.mainAxis) {
          seriesList.last.setAttribute(
              charts.measureAxisIdKey, charts.Axis.secondaryMeasureAxisId);
        }
      });
    }
    return seriesList;
  }

  // Convert input data to bar series (for bar charts)
  List<charts.Series<_BarPoint, String>> _convertDataToBarSeries() {
    final seriesList = <charts.Series<_BarPoint, String>>[];
    for (var seriesMap in data) {
      seriesMap.forEach((config, points) {
        final data =
            points.map((p) => _BarPoint(p[0].toString(), p[1])).toList();
        seriesList.add(
          charts.Series<_BarPoint, String>(
            id: config.label,
            data: data,
            domainFn: (_BarPoint point, _) => point.x,
            measureFn: (_BarPoint point, _) => point.y,
          ),
        );
      });
    }
    return seriesList;
  }

  // Build axis specification from configuration
  charts.NumericAxisSpec _buildAxisSpec(GraphAxisConfig axisConfig,
      [int? offset]) {
    // Validate axis configuration
    if (axisConfig.min != null && axisConfig.max != null) {
      if (axisConfig.min! >= axisConfig.max!) {
        throw ArgumentError('Axis min must be less than max');
      }
    }
    if (axisConfig.step != null && axisConfig.step! <= 0) {
      throw ArgumentError('Axis step must be positive');
    }

    return charts.NumericAxisSpec(
      viewport: axisConfig.min != null && axisConfig.max != null
          ? charts.NumericExtents(axisConfig.min!, axisConfig.max!)
          : null,
      tickProviderSpec: axisConfig.step != null
          ? charts.StaticNumericTickProviderSpec(
              _generateTicks(axisConfig.min, axisConfig.max, axisConfig.step!),
            )
          : null,
      renderSpec: charts.GridlineRendererSpec(
        labelStyle: charts.TextStyleSpec(fontSize: 12),
        lineStyle: charts.LineStyleSpec(
          thickness: 1,
          color: charts.MaterialPalette.gray.shade300,
        ),
        labelOffsetFromAxisPx: offset,
      ),
      showAxisLine: true,
      tickFormatterSpec: charts.BasicNumericTickFormatterSpec(
        (num? value) => value != null
            ? '${value.toStringAsFixed(1)} ${axisConfig.unit}'
            : '',
      ),
    );
  }

  // Build string axis specification for bar charts
  charts.AxisSpec<String> _buildStringAxisSpec(GraphAxisConfig axisConfig) {
    return charts.AxisSpec<String>(
      renderSpec: charts.GridlineRendererSpec(
        labelStyle: charts.TextStyleSpec(fontSize: 12),
        lineStyle: charts.LineStyleSpec(
          thickness: 1,
          color: charts.MaterialPalette.gray.shade300,
        ),
      ),
      showAxisLine: true,
    );
  }

  // Generate ticks for static axis configuration
  List<charts.TickSpec<num>> _generateTicks(
      double? min, double? max, double step) {
    if (min == null || max == null) return [];
    final ticks = <charts.TickSpec<num>>[];
    double current = min;
    while (current <= max) {
      ticks.add(charts.TickSpec(current));
      current += step;
    }
    return ticks;
  }
}

// Internal class to represent a data point
class _Point {
  final double x;
  final double y;

  _Point(this.x, this.y);
}

// Internal class to represent a bar point
class _BarPoint {
  final String x;
  final double y;

  _BarPoint(this.x, this.y);
}

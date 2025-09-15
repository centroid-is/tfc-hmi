import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;

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
  barTimeseries,
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
  @JsonKey(includeFromJson: false, includeToJson: false)
  final DateTimeRange? xRange; // New field for timeseries range

  static const List<Color> colors = [
    Colors.blue,
    Colors.red,
    Colors.green,
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
    Colors.yellow,
  ];

  GraphConfig({
    required this.type,
    required this.xAxis,
    required this.yAxis,
    this.yAxis2,
    this.xSpan,
    this.xRange,
  });

  factory GraphConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphConfigToJson(this);
}

class Graph extends StatefulWidget {
  final GraphConfig config;
  final List<Map<GraphDataConfig, List<List<double>>>> data;
  final Function()? onPanCompleted;
  final bool showDate; // Simple boolean flag

  const Graph({
    super.key,
    required this.config,
    required this.data,
    this.onPanCompleted,
    this.showDate = false,
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
    // If no data is provided, show an empty container with the same dimensions
    if (filteredData.isEmpty || filteredData.every((m) => m.isEmpty)) {
      return const SizedBox.shrink();
    }

    // Configure behaviors
    switch (widget.config.type) {
      case GraphType.timeseries:
        // Use DateTime as x-axis
        final series = _convertDataToTimeSeries(filteredData);
        return charts.TimeSeriesChart(
          series,
          animate: false,
          defaultRenderer: charts.LineRendererConfig<DateTime>(),
          domainAxis: _buildDateTimeAxisSpec(
              widget.config.xAxis, widget.config.xSpan, widget.config.xRange),
          primaryMeasureAxis: _buildAxisSpec(widget.config.yAxis),
          secondaryMeasureAxis: widget.config.yAxis2 != null
              ? _buildAxisSpec(widget.config.yAxis2!)
              : null,
          behaviors: [
            charts.PanAndZoomBehavior<DateTime>(
              panningCompletedCallback: () {
                if (widget.onPanCompleted != null) {
                  widget.onPanCompleted!();
                }
              },
            ),
          ],
        );
      case GraphType.line:
        // Use numeric x-axis
        final series = _convertDataToNumericSeries(filteredData);
        return charts.LineChart(
          series,
          animate: false,
          domainAxis: _buildAxisSpec(widget.config.xAxis, 15),
          primaryMeasureAxis: _buildAxisSpec(widget.config.yAxis),
          secondaryMeasureAxis: widget.config.yAxis2 != null
              ? _buildAxisSpec(widget.config.yAxis2!)
              : null,
          behaviors: [
            charts.PanAndZoomBehavior<num>(
              panningCompletedCallback: () {
                if (widget.onPanCompleted != null) {
                  widget.onPanCompleted!();
                }
              },
            ),
          ],
        );
      case GraphType.barTimeseries:
        // Use DateTime as x-axis for bar chart
        final series = _convertDataToTimeBarSeries(filteredData);
        return charts.TimeSeriesChart(
          series,
          defaultRenderer: charts.BarRendererConfig<DateTime>(),
          animate: false,
          domainAxis: _buildDateTimeAxisSpec(
              widget.config.xAxis, widget.config.xSpan, widget.config.xRange),
          primaryMeasureAxis: _buildAxisSpec(widget.config.yAxis),
          secondaryMeasureAxis: widget.config.yAxis2 != null
              ? _buildAxisSpec(widget.config.yAxis2!)
              : null,
          behaviors: [
            charts.PanAndZoomBehavior<DateTime>(
              panningCompletedCallback: () {
                if (widget.onPanCompleted != null) {
                  widget.onPanCompleted!();
                }
              },
            ),
          ],
        );
      case GraphType.bar:
        // Use string x-axis
        final series = _convertDataToBarSeries(filteredData);
        return charts.BarChart(
          series,
          animate: false,
          domainAxis: _buildAxisSpec(widget.config.xAxis),
          primaryMeasureAxis: _buildAxisSpec(widget.config.yAxis),
          secondaryMeasureAxis: widget.config.yAxis2 != null
              ? _buildAxisSpec(widget.config.yAxis2!)
              : null,
          behaviors: [
            charts.PanAndZoomBehavior<String>(
              panningCompletedCallback: () {
                if (widget.onPanCompleted != null) {
                  widget.onPanCompleted!();
                }
              },
            ),
          ],
        );
      case GraphType.scatter:
        final behaviors = [
          charts.PanAndZoomBehavior<num>(
            panningCompletedCallback: () {
              if (widget.onPanCompleted != null) {
                widget.onPanCompleted!();
              }
            },
          ),
        ];
        final series = _convertDataToNumericSeries(filteredData);
        // Return empty container if no valid series data
        if (series.isEmpty) {
          return const SizedBox.shrink();
        }
        return charts.ScatterPlotChart(
          series,
          animate: false,
          domainAxis: _buildAxisSpec(widget.config.xAxis),
          primaryMeasureAxis: _buildAxisSpec(widget.config.yAxis),
          secondaryMeasureAxis: widget.config.yAxis2 != null
              ? _buildAxisSpec(widget.config.yAxis2!)
              : null,
          behaviors: behaviors,
        );
    }
  }

  Widget _buildLegend(BuildContext context) {
    // Collect all series configs
    final configs = <GraphDataConfig>{};
    for (final map in widget.data) {
      configs.addAll(map.keys);
    }
    if (configs.isEmpty) return const SizedBox.shrink();

    // Use the same color palette as charts
    final palette = charts.MaterialPalette.getOrderedPalettes(configs.length);

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
            final chartColor = palette[i].shadeDefault.darker;
            final color = config.color ??
                Color.fromARGB(
                    chartColor.a, chartColor.r, chartColor.g, chartColor.b);

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

  static int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  // Convert input data to numeric series (for line and scatter charts)
  List<charts.Series<_Point, num>> _convertDataToNumericSeries(
      List<Map<GraphDataConfig, List<List<double>>>> data) {
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

        final series = charts.Series<_Point, num>(
          id: config.label,
          data: data,
          domainFn: (_Point point, _) => point.x,
          measureFn: (_Point point, _) => point.y,
          seriesColor: config.color != null
              ? charts.Color(
                  a: _floatToInt8(config.color!.a),
                  r: _floatToInt8(config.color!.r),
                  g: _floatToInt8(config.color!.g),
                  b: _floatToInt8(config.color!.b),
                )
              : null,
        );
        if (!config.mainAxis) {
          series.setAttribute(
              charts.measureAxisIdKey, charts.Axis.secondaryMeasureAxisId);
        }
        seriesList.add(series);
      });
    }
    return seriesList;
  }

  List<charts.Series<_TimePoint, DateTime>> _convertDataToTimeBarSeries(
      List<Map<GraphDataConfig, List<List<double>>>> data) {
    final seriesList = <charts.Series<_TimePoint, DateTime>>[];
    for (var seriesMap in data) {
      seriesMap.forEach((config, points) {
        final data = points
            .where((p) => p.length == 2)
            .map((p) => _TimePoint(
                DateTime.fromMillisecondsSinceEpoch(p[0].toInt()), p[1]))
            .toList();
        if (data.isNotEmpty) {
          final series = charts.Series<_TimePoint, DateTime>(
            id: config.label,
            data: data,
            domainFn: (_TimePoint point, _) => point.time,
            measureFn: (_TimePoint point, _) => point.value,
            seriesColor: config.color != null
                ? charts.Color(
                    a: _floatToInt8(config.color!.a),
                    r: _floatToInt8(config.color!.r),
                    g: _floatToInt8(config.color!.g),
                    b: _floatToInt8(config.color!.b),
                  )
                : null,
          );
          if (!config.mainAxis) {
            series.setAttribute(
                charts.measureAxisIdKey, charts.Axis.secondaryMeasureAxisId);
          }
          seriesList.add(series);
        }
      });
    }
    return seriesList;
  }

  // Convert input data to bar series (for bar charts)
  List<charts.Series<_BarPoint, String>> _convertDataToBarSeries(
      List<Map<GraphDataConfig, List<List<double>>>> data) {
    final seriesList = <charts.Series<_BarPoint, String>>[];
    for (var seriesMap in data) {
      seriesMap.forEach((config, points) {
        final data =
            points.map((p) => _BarPoint(p[0].toString(), p[1])).toList();
        final series = charts.Series<_BarPoint, String>(
          id: config.label,
          data: data,
          domainFn: (_BarPoint point, _) => point.x,
          measureFn: (_BarPoint point, _) => point.y,
          seriesColor: config.color != null
              ? charts.Color(
                  a: _floatToInt8(config.color!.a),
                  r: _floatToInt8(config.color!.r),
                  g: _floatToInt8(config.color!.g),
                  b: _floatToInt8(config.color!.b),
                )
              : null,
        );
        if (!config.mainAxis) {
          series.setAttribute(
              charts.measureAxisIdKey, charts.Axis.secondaryMeasureAxisId);
        }
        seriesList.add(series);
      });
    }
    return seriesList;
  }

  // Convert input data to time series (for timeseries charts)
  List<charts.Series<_TimePoint, DateTime>> _convertDataToTimeSeries(
      List<Map<GraphDataConfig, List<List<double>>>> data) {
    final seriesList = <charts.Series<_TimePoint, DateTime>>[];
    for (var seriesMap in data) {
      seriesMap.forEach((config, points) {
        final data = points
            .where((p) => p.length == 2)
            .map((p) => _TimePoint(
                DateTime.fromMillisecondsSinceEpoch(p[0].toInt()), p[1]))
            .toList();
        if (data.isNotEmpty) {
          final series = charts.Series<_TimePoint, DateTime>(
            id: config.label,
            data: data,
            domainFn: (_TimePoint point, _) => point.time,
            measureFn: (_TimePoint point, _) => point.value,
            seriesColor: config.color != null
                ? charts.Color(
                    a: _floatToInt8(config.color!.a),
                    r: _floatToInt8(config.color!.r),
                    g: _floatToInt8(config.color!.g),
                    b: _floatToInt8(config.color!.b),
                  )
                : null,
          );
          if (!config.mainAxis) {
            series.setAttribute(
                charts.measureAxisIdKey, charts.Axis.secondaryMeasureAxisId);
          }
          seriesList.add(series);
        }
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

  charts.DateTimeAxisSpec _buildDateTimeAxisSpec(GraphAxisConfig axisConfig,
      [Duration? xSpan, DateTimeRange? xRange]) {
    // If you gave min/max in ms since epoch, you can use them to zoom the viewport:
    charts.DateTimeExtents? extents;

    if (xRange != null) {
      // Use xRange to set the viewport
      extents = charts.DateTimeExtents(
        start: xRange.start,
        end: xRange.end,
      );
    } else if (axisConfig.min != null && axisConfig.max != null) {
      // Use explicit min/max from axis config
      extents = charts.DateTimeExtents(
        start: DateTime.fromMillisecondsSinceEpoch(axisConfig.min!.toInt()),
        end: DateTime.fromMillisecondsSinceEpoch(axisConfig.max!.toInt()),
      );
    } else if (xSpan != null) {
      // Use xSpan to calculate viewport from the latest data point
      final allTimePoints = <DateTime>[];
      for (var seriesMap in widget.data) {
        seriesMap.forEach((config, points) {
          for (var point in points) {
            if (point.length == 2) {
              allTimePoints
                  .add(DateTime.fromMillisecondsSinceEpoch(point[0].toInt()));
            }
          }
        });
      }

      if (allTimePoints.isNotEmpty) {
        final latestTime = allTimePoints.reduce((a, b) => a.isAfter(b) ? a : b);
        final startTime = latestTime.subtract(xSpan);
        extents = charts.DateTimeExtents(
          start: startTime,
          end: latestTime,
        );
      }
    }

    // Determine appropriate tick provider based on time span
    charts.DateTimeTickProviderSpec tickProviderSpec;
    charts.DateTimeTickFormatterSpec tickFormatterSpec;

    if (extents != null) {
      final duration = extents.end.difference(extents.start);

      // Use AutoDateTimeTickProviderSpec for dynamic tick generation when panning
      // This allows ticks to be generated for the current viewport as you pan
      tickProviderSpec = const charts.AutoDateTimeTickProviderSpec();

      // Set appropriate formatter based on duration
      if (duration.inMinutes <= 1) {
        // For very short spans (≤1 minute), use 10-second intervals
        tickProviderSpec = charts.StaticDateTimeTickProviderSpec(
          _generateTimeTicks(
              extents.start, extents.end, const Duration(seconds: 10)),
        );
        tickFormatterSpec = const charts.AutoDateTimeTickFormatterSpec(
          minute: charts.TimeFormatterSpec(
            format: 'HH:mm:ss',
            transitionFormat: 'HH:mm:ss',
          ),
        );
      } else if (duration.inMinutes <= 5) {
        tickFormatterSpec = const charts.AutoDateTimeTickFormatterSpec(
          minute: charts.TimeFormatterSpec(
            format: 'HH:mm:ss',
            transitionFormat: 'HH:mm:ss',
          ),
        );
      } else if (duration.inMinutes <= 30) {
        tickFormatterSpec = charts.AutoDateTimeTickFormatterSpec(
          minute: charts.TimeFormatterSpec(
            format: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
            transitionFormat: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
          ),
        );
      } else if (duration.inHours <= 2) {
        tickFormatterSpec = charts.AutoDateTimeTickFormatterSpec(
          minute: charts.TimeFormatterSpec(
            format: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
            transitionFormat: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
          ),
        );
      } else {
        tickFormatterSpec = charts.AutoDateTimeTickFormatterSpec(
          minute: charts.TimeFormatterSpec(
            format: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
            transitionFormat: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
          ),
          hour: charts.TimeFormatterSpec(
            format: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
            transitionFormat: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
          ),
          day: charts.TimeFormatterSpec(
            format: 'MM/dd',
            transitionFormat: 'yyyy-MM-dd',
          ),
        );
      }
    } else {
      // Fallback to auto tick provider
      tickProviderSpec = const charts.AutoDateTimeTickProviderSpec();
      tickFormatterSpec = charts.AutoDateTimeTickFormatterSpec(
        minute: charts.TimeFormatterSpec(
          format: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
          transitionFormat: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
        ),
        hour: charts.TimeFormatterSpec(
          format: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
          transitionFormat: widget.showDate ? 'MM/dd HH:mm' : 'HH:mm',
        ),
        day: charts.TimeFormatterSpec(
          format: 'MM/dd',
          transitionFormat: 'yyyy-MM-dd',
        ),
      );
    }

    return charts.DateTimeAxisSpec(
      viewport: extents,
      tickProviderSpec: tickProviderSpec,
      tickFormatterSpec: tickFormatterSpec,
      showAxisLine: true,
    );
  }

  // Helper method to generate time ticks
  List<charts.TickSpec<DateTime>> _generateTimeTicks(
      DateTime start, DateTime end, Duration interval) {
    final ticks = <charts.TickSpec<DateTime>>[];

    // Round start time down to the nearest interval
    DateTime current = _roundDownToInterval(start, interval);

    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      ticks.add(charts.TickSpec(current));
      current = current.add(interval);
    }

    return ticks;
  }

  // Helper method to round down to the nearest interval
  DateTime _roundDownToInterval(DateTime dateTime, Duration interval) {
    if (interval.inSeconds >= 60) {
      // For minute intervals and above
      final minutes =
          (dateTime.minute ~/ (interval.inMinutes)) * interval.inMinutes;
      return DateTime(dateTime.year, dateTime.month, dateTime.day,
          dateTime.hour, minutes, 0, 0);
    } else {
      // For second intervals
      final seconds =
          (dateTime.second ~/ interval.inSeconds) * interval.inSeconds;
      return DateTime(dateTime.year, dateTime.month, dateTime.day,
          dateTime.hour, dateTime.minute, seconds, 0);
    }
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

// Internal class to represent a time series data point
class _TimePoint {
  final DateTime time;
  final double value;

  _TimePoint(this.time, this.value);

  @override
  String toString() {
    return 'TimePoint(time: $time, value: $value)';
  }
}

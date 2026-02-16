import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cristalyse/cristalyse.dart' as cs;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../theme.dart';
import '../providers/theme.dart';
import 'button_graph.dart';

part 'graph.g.dart';

/// -------------------- Data models --------------------

@JsonEnum()
enum GraphType {
  line,
  bar,
  scatter,
  pie,
  // real-time / time on X
  timeseries,
  barTimeseries,
}

@JsonSerializable(explicitToJson: true)
class GraphAxisConfig {
  final String? title;
  final String unit;
  final double? min;
  final double? max;
  final bool boolean;
  @JsonKey(defaultValue: false)
  final bool integersOnly;

  const GraphAxisConfig({
    this.title,
    required this.unit,
    this.min,
    this.max,
    this.boolean = false,
    this.integersOnly = false,
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

  /// For timeseries: window width to show (e.g. last 10s/5m/1h)
  final Duration? xSpan;

  /// For timeseries: explicit viewport
  @JsonKey(includeFromJson: false, includeToJson: false)
  final DateTimeRange? xRange;

  @JsonKey(defaultValue: true)
  final bool pan;
  @JsonKey(defaultValue: true)
  final bool zoom;

  // Stroke or bar width or point size
  @JsonKey(defaultValue: 2)
  final double width;

  /// Fallback palette for series without explicit color
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
    Colors.yellow,
  ];

  const GraphConfig({
    required this.type,
    required this.xAxis,
    required this.yAxis,
    this.yAxis2,
    this.xSpan,
    this.xRange,
    this.pan = true,
    this.width = 2,
    this.zoom = true,
  });

  factory GraphConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphConfigToJson(this);
}

/// -------------------- Pan event surface --------------------

class GraphPanEvent {
  /// Current visible X range (data coordinates)
  final double? visibleMinX;
  final double? visibleMaxX;

  /// Current visible Y range (data coordinates)
  final double? visibleMinY;
  final double? visibleMaxY;

  /// Pan delta from last position (screen coordinates)
  final Offset? delta;

  /// Total pan distance from start (screen coordinates)
  final Offset? totalDelta;

  GraphPanEvent(cs.PanInfo info)
      : visibleMinX = info.visibleMinX,
        visibleMaxX = info.visibleMaxX,
        visibleMinY = info.visibleMinY,
        visibleMaxY = info.visibleMaxY,
        delta = info.delta,
        totalDelta = info.totalDelta;
}

/// -------------------- Graph  --------------------

class Graph {
  final GraphConfig config;

  /// CristalyseChart().data([
  ///   {'x': 1, 'y': 2, 'y2': 85, 'category': 'A'},
  ///   {'x': 2, 'y': 3, 'y2': 92, 'category': 'B'},
  /// ])
  final List<Map<String, dynamic>> data;
  final bool showButtons;
  final Map<String, Color> categoryColors;

  /// Panning callbacks
  final void Function(GraphPanEvent event)? onPanStart;
  final void Function(GraphPanEvent event)? onPanUpdate;
  final void Function(GraphPanEvent event)? onPanEnd;
  final void Function()? onNowPressed; // When the user clicks the now button
  final void Function()? onSetDatePressed;
  final void Function() redraw;

  Graph(
      {required this.config,
      required this.data,
      this.onPanStart,
      this.onPanUpdate,
      this.onPanEnd,
      this.onNowPressed,
      this.onSetDatePressed,
      this.showButtons = true,
      required this.redraw,
      cs.ChartTheme? chartTheme,
      this.categoryColors = const {}})
      : _data = data,
        _chartWidget = Center(child: const CircularProgressIndicator()) {
    _chart = _createChart();
    if (chartTheme != null) {
      _chart.theme(chartTheme);
    }
    if ((config.type == GraphType.timeseries ||
            config.type == GraphType.barTimeseries) &&
        config.xSpan != null) {
      _lastPanInfo = cs.PanInfo(
          visibleMinX: DateTime.now()
              .subtract(config.xSpan!)
              .millisecondsSinceEpoch
              .toDouble(),
          visibleMaxX: DateTime.now().millisecondsSinceEpoch.toDouble(),
          state: cs.PanState.start);
    } else if (config.xAxis.min != null && config.xAxis.max != null) {
      _lastPanInfo = cs.PanInfo(
          visibleMinX: config.xAxis.min!,
          visibleMaxX: config.xAxis.max!,
          state: cs.PanState.start);
    } else {
      _lastPanInfo =
          cs.PanInfo(visibleMinX: 0, visibleMaxX: 0, state: cs.PanState.start);
    }
    if (_data.isNotEmpty) {
      _chart.data(_data);
      if (categoryColors.isNotEmpty) {
        _chart.customPalette(categoryColors: categoryColors);
      }
      _chartWidget = _chart.build();
      _isLoading = false;
    }
  }

  late final List<Map<String, dynamic>> _data;
  late cs.CristalyseChart _chart;
  Widget _chartWidget;
  bool _showDate = false; // if viewport is not today, show date
  late cs.PanInfo _lastPanInfo;
  bool _isLoading = true;
  final cs.PanController _panController = cs.PanController();
  bool _nowDisabled = false;

  void theme(cs.ChartTheme theme) {
    _chart.theme(theme);
  }

  void panForward(double maxX) {
    if (_lastPanInfo.visibleMaxX == null || _lastPanInfo.visibleMinX == null) {
      return;
    }
    final currentWindowSize =
        _lastPanInfo.visibleMaxX! - _lastPanInfo.visibleMinX!;
    // check if visibleMaxX is already bigger than maxX
    if (_lastPanInfo.visibleMaxX! > maxX) {
      return;
    }
    // Check if we are half a percent from the new maxX if we are, we really dont need to pan
    if ((maxX - _lastPanInfo.visibleMaxX!) / currentWindowSize <= 0.005) {
      return;
    }
    final newMinX = maxX - currentWindowSize;
    _panController.panTo(cs.PanInfo(
      visibleMinX: newMinX,
      visibleMaxX: maxX,
      state: cs.PanState
          .start, // start is the most innocent state, we dont want this to cause any heavy actions
    ));
  }

  void setNowButtonDisabled(bool disabled) {
    _nowDisabled = disabled;
    redraw();
  }

  void _setXAxis(cs.CristalyseChart chart) {
    cs.LabelCallback? xLabels;
    if (config.type == GraphType.timeseries ||
        config.type == GraphType.barTimeseries) {
      xLabels = (v) {
        final date = DateTime.fromMillisecondsSinceEpoch(v.toInt());
        return _formatTime(date, showDate: _showDate);
      };
    }
    if (config.type == GraphType.timeseries) {
      if (config.xRange != null) {
        chart.scaleXContinuous(
            min: config.xRange?.start.millisecondsSinceEpoch.toDouble(),
            max: config.xRange?.end.millisecondsSinceEpoch.toDouble(),
            labels: xLabels,
            tickConfig: cs.TickConfig(simpleLinear: true),
            title: config.xAxis.title);
      } else if (config.xSpan != null) {
        chart.scaleXContinuous(
            min: DateTime.now()
                .subtract(config.xSpan!)
                .millisecondsSinceEpoch
                .toDouble(),
            max: DateTime.now().millisecondsSinceEpoch.toDouble(),
            labels: xLabels,
            tickConfig: cs.TickConfig(simpleLinear: true),
            title: config.xAxis.title);
      } else {
        chart.scaleXContinuous(
            min: config.xAxis.min,
            max: config.xAxis.max,
            labels: xLabels,
            tickConfig: cs.TickConfig(simpleLinear: true),
            title: config.xAxis.title);
      }
    } else if (config.type == GraphType.barTimeseries) {
      chart.scaleXOrdinal(labels: xLabels, title: config.xAxis.title);
    }
  }

  cs.CristalyseChart _createChart() {
    cs.PanConfig? panConfig;
    if (config.pan) {
      panConfig = cs.PanConfig(
          enabled: true,
          updateXDomain: true,
          updateYDomain: false,
          throttle: const Duration(milliseconds: 1000),
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanStart: _onPanStart,
          controller: _panController,
          // It is hard to detect if there is gap in data, so if we got data from 14:00 - 15:00 and nothing betwen 15:00 and 17:00 and then real time after that, lets just keep this off
          boundaryClampingX: false);
    }

    final chart = cs.CristalyseChart()
        .mapping(x: 'x', y: 'y', color: 's')
        .scaleYContinuous(
          min: config.yAxis.min,
          max: config.yAxis.max,
          labels: (v) => _numLabel(v, config.yAxis.unit, config.yAxis.boolean),
          tickConfig: cs.TickConfig(
              simpleLinear: true,
              integersOnly: config.yAxis.integersOnly,
              ticks: config.yAxis.boolean ? [0.0, 1.0] : null),
          title: config.yAxis.title,
        )
        .interaction(
          pan: panConfig,
        )
        .animate(duration: Duration.zero)
        .legend(
            position: cs.LegendPosition.right,
            interactive: true,
            showTitles: true);

    for (final yaxis in [
      cs.YAxis.primary,
      if (config.yAxis2 != null) cs.YAxis.secondary
    ]) {
      switch (config.type) {
        case GraphType.line:
        case GraphType.timeseries:
          chart.geomLine(strokeWidth: config.width, yAxis: yaxis, alpha: 1.0);
          break;
        case GraphType.bar:
        case GraphType.barTimeseries:
          chart.geomBar(
              width: config.width,
              yAxis: yaxis,
              alpha: 1.0,
              style: cs.BarStyle.grouped);
          break;
        case GraphType.scatter:
          chart.geomPoint(size: config.width, yAxis: yaxis, alpha: 1.0);
          break;
        case GraphType.pie:
          chart.geomPie(strokeWidth: config.width);
          break;
      }
    }

    _setXAxis(chart);

    if (config.yAxis2 != null) {
      chart.mappingY2('y2').scaleY2Continuous(
            min: config.yAxis2?.min,
            max: config.yAxis2?.max,
            labels: (v) => _numLabel(
                v, config.yAxis2?.unit ?? '', config.yAxis2?.boolean ?? false),
            tickConfig: cs.TickConfig(
                simpleLinear: true,
                integersOnly: config.yAxis2?.integersOnly ?? false,
                ticks: config.yAxis2?.boolean ?? false ? [0.0, 1.0] : null),
            title: config.yAxis2?.title,
          );
    }
    return chart;
  }

  void addAll(List<Map<String, dynamic>> input) {
    _data.addAll(input);
    _sliceAndRedraw(_lastPanInfo);
  }

  void removeWhere(bool Function(Map<String, dynamic>) predicate) {
    _data.removeWhere(predicate);
    _sliceAndRedraw(_lastPanInfo);
  }

  Widget build(BuildContext context) {
    DateTimeRange? currentDateRange;
    if (_lastPanInfo.visibleMinX != null && _lastPanInfo.visibleMaxX != null) {
      currentDateRange = DateTimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(
            _lastPanInfo.visibleMinX!.toInt()),
        end: DateTime.fromMillisecondsSinceEpoch(
            _lastPanInfo.visibleMaxX!.toInt()),
      );
    } else if (config.xSpan != null) {
      currentDateRange = DateTimeRange(
        start: DateTime.now().subtract(config.xSpan!),
        end: DateTime.now(),
      );
    }

    Widget? noData;
    if (_data.isEmpty && !_isLoading) {
      var txt =
          "No data from: ${_lastPanInfo.visibleMinX} to: ${_lastPanInfo.visibleMaxX}";
      if (config.type == GraphType.timeseries ||
          config.type == GraphType.barTimeseries) {
        txt =
            "No data from: ${DateTime.fromMillisecondsSinceEpoch(_lastPanInfo.visibleMinX!.toInt())} to: ${DateTime.fromMillisecondsSinceEpoch(_lastPanInfo.visibleMaxX!.toInt())}";
      }
      noData = Center(
        child: Text(txt),
      );
    }

    return Column(
      children: [
        Expanded(child: _chartWidget),
        if (noData != null) noData,
        if (noData != null)
          SizedBox(
            height: 10,
          ),
        if (!_isLoading && showButtons)
          ButtonGraph(
              dateRange: currentDateRange,
              nowDisabled: _nowDisabled,
              onSetDatePressed: () {
                onSetDatePressed?.call();
              },
              onSetDateResult: (dateRange) {
                _panController.panTo(cs.PanInfo(
                  visibleMinX:
                      dateRange?.start.millisecondsSinceEpoch.toDouble(),
                  visibleMaxX: dateRange?.end.millisecondsSinceEpoch.toDouble(),
                  state: cs.PanState.end,
                ));
              },
              onNow: () {
                double window = 0;
                if (config.xSpan != null) {
                  window = config.xSpan!.inMilliseconds.toDouble();
                }
                if (_lastPanInfo.visibleMinX != null &&
                    _lastPanInfo.visibleMaxX != null) {
                  window =
                      _lastPanInfo.visibleMaxX! - _lastPanInfo.visibleMinX!;
                }
                if (config.type == GraphType.timeseries ||
                    config.type == GraphType.barTimeseries && window > 0) {
                  _panController.panTo(cs.PanInfo(
                    visibleMinX:
                        DateTime.now().millisecondsSinceEpoch.toDouble() -
                            window,
                    visibleMaxX:
                        DateTime.now().millisecondsSinceEpoch.toDouble(),
                    state: cs.PanState.end,
                  ));
                }
                onNowPressed?.call();
              },
              onZoomOut: () {
                if (config.type == GraphType.timeseries ||
                    config.type == GraphType.barTimeseries &&
                        config.xSpan != null) {
                  final visibleMinX = _lastPanInfo.visibleMinX;
                  final visibleMaxX = _lastPanInfo.visibleMaxX;
                  if (visibleMinX != null && visibleMaxX != null) {
                    final windowSize = visibleMaxX - visibleMinX;
                    final delta = windowSize * -1 / 10;
                    // lets just zoom to right side
                    final newVisibleMinX = visibleMinX + delta;
                    final newVisibleMaxX = visibleMaxX;

                    _panController.panTo(cs.PanInfo(
                      visibleMinX: newVisibleMinX,
                      visibleMaxX: newVisibleMaxX,
                      state: cs.PanState.end,
                    ));
                  } else {
                    // dont know
                  }
                }
              },
              onZoomIn: () {
                if (config.type == GraphType.timeseries ||
                    config.type == GraphType.barTimeseries &&
                        config.xSpan != null) {
                  final visibleMinX = _lastPanInfo.visibleMinX;
                  final visibleMaxX = _lastPanInfo.visibleMaxX;
                  if (visibleMinX != null && visibleMaxX != null) {
                    final windowSize = visibleMaxX - visibleMinX;
                    final delta = windowSize * 1 / 10;
                    // lets just zoom out from the left side
                    final newVisibleMinX = visibleMinX + delta;
                    final newVisibleMaxX = visibleMaxX;

                    _panController.panTo(cs.PanInfo(
                      visibleMinX: newVisibleMinX,
                      visibleMaxX: newVisibleMaxX,
                      state: cs.PanState.end,
                    ));
                  } else {
                    // dont know
                  }
                }
              }),
      ],
    );
  }

  void _onPanStart(cs.PanInfo info) {
    _lastPanInfo = info;
    onPanStart?.call(GraphPanEvent(info));
  }

  void _onPanUpdate(cs.PanInfo info) {
    _lastPanInfo = info;
    _sliceAndRedraw(info);
    onPanUpdate?.call(GraphPanEvent(info));
  }

  void _onPanEnd(cs.PanInfo info) {
    _lastPanInfo = info;
    if (config.type == GraphType.timeseries ||
        config.type == GraphType.barTimeseries) {
      final now = DateTime.now();
      if (info.visibleMinX != null && info.visibleMaxX != null) {
        _showDate = now.day !=
                DateTime.fromMillisecondsSinceEpoch(info.visibleMinX!.toInt())
                    .day ||
            now.day !=
                DateTime.fromMillisecondsSinceEpoch(info.visibleMaxX!.toInt())
                    .day;
      }
    }
    _sliceAndRedraw(info);

    onPanEnd?.call(GraphPanEvent(info));
  }

  void _sliceAndRedraw(cs.PanInfo info) {
    if (info.visibleMinX == null || info.visibleMaxX == null) return;
    final visibleMinX = info.visibleMinX!;
    final visibleMaxX = info.visibleMaxX!;
    final windowSize = info.visibleMaxX! - info.visibleMinX!;

    final slicedData = _data
        .where((e) =>
            e['x'] >= visibleMinX - windowSize &&
            e['x'] <= visibleMaxX + windowSize)
        .toList();

    _chart.data(slicedData);
    if (categoryColors.isNotEmpty) {
      _chart.customPalette(categoryColors: categoryColors);
    }
    _isLoading = false;
    _chartWidget = _chart.build();

    redraw();
  }

  static String _numLabel(num v, String unit, bool boolean) {
    if (boolean) {
      return v == 0.0
          ? 'False'
          : v == 1.0
              ? 'True'
              : '';
    }
    final text =
        (v == v.roundToDouble()) ? v.toInt().toString() : v.toStringAsFixed(1);
    return unit.isEmpty ? text : '$text $unit';
  }

  static String _formatTime(DateTime dt, {required bool showDate}) {
    return _fmt(dt, showDate ? 'MM/dd HH:mm:ss' : 'HH:mm:ss');
  }

  static String _fmt(DateTime dt, String pattern) {
    return DateFormat(pattern).format(dt);
  }
}

/// -------------------- Chart theme (Riverpod) --------------------

@riverpod
class ChartThemeNotifier extends _$ChartThemeNotifier {
  @override
  cs.ChartTheme build() {
    // Watch the theme mode
    final themeMode = ref.watch(themeNotifierProvider);

    return themeMode.when(
      data: (mode) => _createChartTheme(mode),
      loading: () => _createChartTheme(ThemeMode.system),
      error: (_, __) => _createChartTheme(ThemeMode.system),
    );
  }

  cs.ChartTheme _createChartTheme(ThemeMode mode) {
    final isDark = mode == ThemeMode.dark;
    return isDark ? _createDarkChartTheme() : _createLightChartTheme();
  }

  cs.ChartTheme _createDarkChartTheme() {
    return cs.ChartTheme(
      backgroundColor: SolarizedColors.base03,
      plotBackgroundColor: SolarizedColors.base02,
      primaryColor: SolarizedColors.blue,
      borderColor: Colors.transparent,
      gridColor: SolarizedColors.base01.withAlpha(75),
      axisColor: SolarizedColors.base01,
      gridWidth: 0.5,
      axisWidth: 1.0,
      pointSizeDefault: 0,
      pointSizeMin: 0,
      pointSizeMax: 0,
      colorPalette: [
        SolarizedColors.blue,
        SolarizedColors.red,
        SolarizedColors.green,
        SolarizedColors.yellow,
        SolarizedColors.orange,
        SolarizedColors.magenta,
        SolarizedColors.violet,
        SolarizedColors.cyan,
      ],
      padding: const EdgeInsets.only(left: 20, right: 0, top: 0, bottom: 0),
      axisTextStyle: const TextStyle(
        color: SolarizedColors.base01,
        fontSize: 12,
        fontFamily: 'roboto-mono',
      ),
      axisLabelStyle: const TextStyle(
        color: SolarizedColors.base00,
        fontSize: 12,
        fontFamily: 'roboto-mono',
      ),
    );
  }

  cs.ChartTheme _createLightChartTheme() {
    return cs.ChartTheme(
      backgroundColor: SolarizedColors.base3,
      plotBackgroundColor: SolarizedColors.base2,
      primaryColor: SolarizedColors.green,
      borderColor: Colors.transparent,
      gridColor: SolarizedColors.base00.withAlpha(75),
      axisColor: SolarizedColors.base00,
      gridWidth: 0.5,
      axisWidth: 1.0,
      pointSizeDefault: 0,
      pointSizeMin: 0,
      pointSizeMax: 0,
      colorPalette: [
        SolarizedColors.green,
        SolarizedColors.red,
        SolarizedColors.blue,
        SolarizedColors.orange,
        SolarizedColors.magenta,
        SolarizedColors.violet,
        SolarizedColors.cyan,
        SolarizedColors.yellow,
      ],
      // (Padding could be computed from label sizes if needed)
      padding: const EdgeInsets.only(left: 80, right: 20, top: 20, bottom: 40),
      axisTextStyle: const TextStyle(
        color: SolarizedColors.base00,
        fontSize: 12,
        fontFamily: 'roboto-mono',
      ),
      axisLabelStyle: const TextStyle(
        color: SolarizedColors.base01,
        fontSize: 12,
        fontFamily: 'roboto-mono',
      ),
    );
  }
}

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cristalyse/cristalyse.dart' as cs;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:board_datetime_picker/board_datetime_picker.dart';

import '../theme.dart';
import '../providers/theme.dart';
import '../converter/color_converter.dart';

part 'graph.g.dart';

/// -------------------- Data models --------------------

@JsonSerializable(explicitToJson: true)
class GraphDataConfig {
  final String label;

  /// true => primary Y axis (left); false => secondary Y axis (right)
  final bool mainAxis;
  @OptionalColorConverter()
  final Color? color;

  const GraphDataConfig({
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
  pie,
  // real-time / time on X
  timeseries,
  barTimeseries,
}

@JsonSerializable(explicitToJson: true)
class GraphAxisConfig {
  final String unit;
  final double? min;
  final double? max;
  final bool boolean;

  const GraphAxisConfig({
    required this.unit,
    this.min,
    this.max,
    this.boolean = false,
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
  final int width;

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

  /// Panning callbacks
  final void Function(GraphPanEvent event)? onPanStart;
  final void Function(GraphPanEvent event)? onPanUpdate;
  final void Function(GraphPanEvent event)? onPanEnd;
  final void Function() redraw;

  Graph({
    required this.config,
    required this.data,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    required this.redraw,
  })  : _data = data,
        _chartWidget = Center(child: const CircularProgressIndicator()) {
    _chart = _createChart();
    if (config.type == GraphType.timeseries ||
        config.type == GraphType.barTimeseries && config.xSpan != null) {
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
  }

  late final List<Map<String, dynamic>> _data;
  late cs.CristalyseChart _chart;
  Widget _chartWidget;
  bool _showDate = false; // if viewport is not today, show date
  late cs.PanInfo _lastPanInfo;
  bool _isLoading = true;
  final cs.PanController _panController = cs.PanController();

  void theme(cs.ChartTheme theme) {
    _chart.theme(theme);
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
            labels: xLabels);
      } else if (config.xSpan != null) {
        chart.scaleXContinuous(
            min: DateTime.now()
                .subtract(config.xSpan!)
                .millisecondsSinceEpoch
                .toDouble(),
            max: DateTime.now().millisecondsSinceEpoch.toDouble(),
            labels: xLabels);
      } else {
        chart.scaleXContinuous(
            min: config.xAxis.min, max: config.xAxis.max, labels: xLabels);
      }
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
      );
    }

    final chart = cs.CristalyseChart()
        .mapping(x: 'x', y: 'y', color: 's')
        .scaleYContinuous(
          min: config.yAxis.min,
          max: config.yAxis.max,
          labels: (v) => _numLabel(v, config.yAxis.unit, config.yAxis.boolean),
        )
        .interaction(
          pan: panConfig,
        )
        .animate(duration: Duration.zero)
        .legend(position: cs.LegendPosition.right, interactive: true);

    // TODO custom color palette !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    for (final yaxis in [
      cs.YAxis.primary,
      if (config.yAxis2 != null) cs.YAxis.secondary
    ]) {
      switch (config.type) {
        case GraphType.line:
        case GraphType.timeseries:
          chart.geomLine(
              strokeWidth: config.width.toDouble(), yAxis: yaxis, alpha: 1.0);
          break;
        case GraphType.bar:
        case GraphType.barTimeseries:
          chart.geomBar(
              width: config.width.toDouble(), yAxis: yaxis, alpha: 1.0);
          break;
        case GraphType.scatter:
          chart.geomPoint(
              size: config.width.toDouble(), yAxis: yaxis, alpha: 1.0);
          break;
        case GraphType.pie:
          chart.geomPie(strokeWidth: config.width.toDouble());
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
          );
    }
    return chart;
  }

  void addAll(List<Map<String, dynamic>> input) {
    _data.addAll(input);
    _sliceAndRedraw(_lastPanInfo);
  }

  Widget build(BuildContext context) {
    // Overlay the button in the bottom-right corner. This avoids touching Cristalyse internals
    // and visually places the control beneath the right-side legend.
    return Column(
      children: [
        Expanded(child: _chartWidget),
        if (!_isLoading)
          Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Theme.of(context).colorScheme.onSurface, width: 1),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Zoom out button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (config.type == GraphType.timeseries ||
                            config.type == GraphType.barTimeseries &&
                                config.xSpan != null) {
                          final visibleMinX = _lastPanInfo.visibleMinX;
                          final visibleMaxX = _lastPanInfo.visibleMaxX;
                          if (visibleMinX != null && visibleMaxX != null) {
                            final windowSize = visibleMaxX - visibleMinX;
                            final delta = windowSize * -1 / 10;
                            final newVisibleMinX = visibleMinX + delta;
                            final newVisibleMaxX = visibleMaxX - delta;

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
                      borderRadius:
                          BorderRadius.horizontal(left: Radius.circular(20)),
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Icon(Icons.zoom_out, size: 20),
                      ),
                    ),
                  ),
                  // Divider
                  Container(
                    height: 30,
                    width: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  // Set date button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        DateTimeRange? currentDateRange;
                        if (_lastPanInfo.visibleMinX != null &&
                            _lastPanInfo.visibleMaxX != null) {
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
                        final result = await showBoardDateTimeMultiPicker(
                          context: context,
                          startDate: currentDateRange?.start,
                          endDate: currentDateRange?.end,
                          maximumDate: DateTime.now(),
                          pickerType: DateTimePickerType.datetime,
                          options: BoardDateTimeOptions(
                            languages: BoardPickerLanguages(
                              locale: 'en',
                              today: 'Today',
                              tomorrow: 'Tomorrow',
                              now: 'Now',
                            ),
                            boardTitle: 'Select Date & Time Range',
                            showDateButton: true,
                            inputable: true,
                            // withSecond: true, // todo !!!!! fix upstream
                            pickerSubTitles: BoardDateTimeItemTitles(
                              year: 'Year',
                              month: 'Month',
                              day: 'Day',
                              hour: 'Hour',
                              minute: 'Minute',
                              second: 'Second', // todo !!!!! fix upstream
                            ),
                            // looks weird
                            separators: BoardDateTimePickerSeparators(
                              date: PickerSeparator.slash,
                              dateSeparatorBuilder: (context, textStyle) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 30),
                                    child: Text(
                                      '/',
                                      style: textStyle,
                                    ),
                                  ),
                                );
                              },
                              time: PickerSeparator.colon,
                              timeSeparatorBuilder: (context, textStyle) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 30),
                                    child: Text(
                                      ':',
                                      style: textStyle,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );

                        if (result != null) {
                          _panController.panTo(cs.PanInfo(
                            visibleMinX:
                                result.start.millisecondsSinceEpoch.toDouble(),
                            visibleMaxX:
                                result.end.millisecondsSinceEpoch.toDouble(),
                            state: cs.PanState.end,
                          ));
                        }
                      },
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_month, size: 20),
                            SizedBox(width: 8),
                            Text("Set date"),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Divider
                  Container(
                    height: 30,
                    width: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  // Now button (NEW)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        double window = 0;
                        if (config.xSpan != null) {
                          window = config.xSpan!.inMilliseconds.toDouble();
                        }
                        if (_lastPanInfo.visibleMinX != null &&
                            _lastPanInfo.visibleMaxX != null) {
                          window = _lastPanInfo.visibleMaxX! -
                              _lastPanInfo.visibleMinX!;
                        }
                        if (config.type == GraphType.timeseries ||
                            config.type == GraphType.barTimeseries &&
                                window > 0) {
                          _panController.panTo(cs.PanInfo(
                            visibleMinX: DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toDouble() -
                                window,
                            visibleMaxX: DateTime.now()
                                .millisecondsSinceEpoch
                                .toDouble(),
                            state: cs.PanState.end,
                          ));
                        }
                      },
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule, size: 20),
                            SizedBox(width: 8),
                            Text("Now"),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Divider
                  Container(
                    height: 30,
                    width: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  // Zoom in button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (config.type == GraphType.timeseries ||
                            config.type == GraphType.barTimeseries &&
                                config.xSpan != null) {
                          final visibleMinX = _lastPanInfo.visibleMinX;
                          final visibleMaxX = _lastPanInfo.visibleMaxX;
                          if (visibleMinX != null && visibleMaxX != null) {
                            final windowSize = visibleMaxX - visibleMinX;
                            final delta = windowSize * 1 / 10;
                            final newVisibleMinX = visibleMinX + delta;
                            final newVisibleMaxX = visibleMaxX - delta;

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
                      borderRadius:
                          BorderRadius.horizontal(right: Radius.circular(20)),
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Icon(Icons.zoom_in, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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

    if (_data.isEmpty) return;

    final slicedData = _data
        .where((e) =>
            e['x'] >= visibleMinX - windowSize &&
            e['x'] <= visibleMaxX + windowSize)
        .toList();

    _chart.data(slicedData);
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

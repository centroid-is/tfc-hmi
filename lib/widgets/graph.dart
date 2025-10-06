// graph.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cristalyse/cristalyse.dart' as cs;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../theme.dart';
import '../providers/theme.dart';
import '../converter/color_converter.dart';

part 'graph.g.dart';

/// -------------------- Data models (kept compatible) --------------------

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
  timeseries, // real-time / time on X
  barTimeseries,
}

@JsonSerializable(explicitToJson: true)
class GraphAxisConfig {
  final String unit;
  final double? min;
  final double? max;
  final double? step; // not used by Cristalyse, kept for compat

  const GraphAxisConfig({
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

  /// For timeseries: window width to show (e.g. last 10s/5m/1h)
  final Duration? xSpan;

  /// For timeseries: explicit viewport
  @JsonKey(includeFromJson: false, includeToJson: false)
  final DateTimeRange? xRange;

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
  });

  factory GraphConfig.fromJson(Map<String, dynamic> json) =>
      _$GraphConfigFromJson(json);
  Map<String, dynamic> toJson() => _$GraphConfigToJson(this);
}

/// -------------------- Pan event surface --------------------

class GraphPanEvent {
  /// Raw double X-range (same units as the chart domain for this widget).
  /// For timeseries this will be **relative ms from viewport start**.
  final double? minX;
  final double? maxX;

  /// Absolute time (only for timeseries)
  final DateTime? minTime;
  final DateTime? maxTime;

  /// Original Cristalyse pan payload
  final cs.PanInfo info;

  GraphPanEvent({
    required this.info,
    this.minX,
    this.maxX,
    this.minTime,
    this.maxTime,
  });
}

/// -------------------- Graph (Cristalyse-only) --------------------

class Graph extends ConsumerStatefulWidget {
  final GraphConfig config;

  /// Each map = one series.
  /// Key = GraphDataConfig (label/color/axis); Value = list of [x, y] points.
  /// For timeseries: x is milliseconds (or seconds) since epoch.
  final List<Map<GraphDataConfig, List<List<double>>>> data;

  /// Panning callbacks (propagate visible X range)
  final void Function(GraphPanEvent event)? onPanUpdate;
  final void Function(GraphPanEvent event)? onPanEnd;

  /// Legacy: called when pan ends (kept to avoid breaking downstream)
  final Function()? onPanCompleted;

  /// Show date on time-axis ticks (vs time only)
  final bool showDate;

  const Graph({
    super.key,
    required this.config,
    required this.data,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCompleted,
    this.showDate = false,
  });

  @override
  ConsumerState<Graph> createState() => _GraphState();
}

class _GraphState extends ConsumerState<Graph> {
  @override
  Widget build(BuildContext context) {
    // Early out keeps rebuilds cheap for RT charts
    if (widget.data.isEmpty || widget.data.every((m) => m.isEmpty)) {
      return const SizedBox.shrink();
    }

    final flattened = _flatten(widget.data);
    final palette = _buildCategoryPalette(flattened.order, widget.data);

    // If timeseries, prepare viewport, transform & label formatter
    _Viewport? tsViewport;
    _TimeDomainTransform? tsTransform;
    String Function(num)? timeLabeler;

    if (widget.config.type == GraphType.timeseries) {
      final vp = _computeTimeViewport(flattened.rows);
      tsViewport = vp;

      if (tsViewport != null) {
        tsTransform = _TimeDomainTransform(
          originMs: tsViewport.start.millisecondsSinceEpoch,
          spanMs: tsViewport.end.difference(tsViewport.start).inMilliseconds,
        );
        timeLabeler = (num relMs) {
          final dt = tsTransform!.toAbsoluteTime(relMs);
          return _formatTimeBySpan(
            dt,
            tsViewport!.end.difference(tsViewport.start),
            showDate: widget.showDate,
          );
        };
      }
    }

    switch (widget.config.type) {
      case GraphType.line:
        return _buildLine(flattened, palette);
      case GraphType.timeseries:
        return _buildTimeseries(
            flattened, palette, tsViewport, tsTransform!, timeLabeler!);
      case GraphType.barTimeseries:
        return const Text("Bar Timeseries");
    }
  }

  /// ---------- Data → Cristalyse rows ----------
  /// Each row:
  /// {'x': double, 'y': double?, 'y2': double?, 'series': String}
  _Flattened _flatten(
    List<Map<GraphDataConfig, List<List<double>>>> data,
  ) {
    final rows = <Map<String, dynamic>>[];
    final order = <String>[];

    for (final seriesMap in data) {
      seriesMap.forEach((cfg, points) {
        if (!order.contains(cfg.label)) order.add(cfg.label);
        final isPrimary = cfg.mainAxis;
        for (final p in points) {
          if (p.length != 2) continue;
          final x = p[0];
          final y = p[1];
          if (!_isFinite(x) || !_isFinite(y)) continue;
          rows.add({
            'x': x,
            'y': isPrimary ? y : null,
            'y2': isPrimary ? null : y,
            'series': cfg.label,
          });
        }
      });
    }
    return _Flattened(rows: rows, order: order);
  }

  Map<String, Color> _buildCategoryPalette(
    List<String> order,
    List<Map<GraphDataConfig, List<List<double>>>> source,
  ) {
    final map = <String, Color>{};
    var idx = 0;

    // Respect explicit colors first
    for (final seriesMap in source) {
      for (final entry in seriesMap.entries) {
        final label = entry.key.label;
        if (map.containsKey(label)) continue;
        map[label] = entry.key.color ??
            GraphConfig.colors[idx % GraphConfig.colors.length];
        idx++;
      }
    }
    // Ensure all labels have a color
    for (final label in order) {
      map.putIfAbsent(
          label, () => GraphConfig.colors[idx++ % GraphConfig.colors.length]);
    }
    return map;
  }

  /// ---------- Timeseries viewport (absolute) ----------
  _Viewport? _computeTimeViewport(List<Map<String, dynamic>> rows) {
    DateTime? start;
    DateTime? end;

    if (widget.config.xRange != null) {
      start = widget.config.xRange!.start;
      end = widget.config.xRange!.end;
    } else if (widget.config.xSpan != null) {
      // Anchor to NOW: guarantees exact span
      end = DateTime.now();
      start = end.subtract(widget.config.xSpan!);
    } else {
      // Auto-fit data
      if (rows.isNotEmpty) {
        num minRaw = double.infinity;
        num maxRaw = -double.infinity;
        for (final r in rows) {
          final x = r['x'] as num;
          if (x < minRaw) minRaw = x;
          if (x > maxRaw) maxRaw = x;
        }
        if (maxRaw.isFinite && minRaw.isFinite && maxRaw > minRaw) {
          // Detect seconds vs milliseconds
          final bool isSeconds = maxRaw < 3e10; // ~year 2968 in ms; safe cut
          final minMs = isSeconds ? (minRaw * 1000).toInt() : minRaw.toInt();
          final maxMs = isSeconds ? (maxRaw * 1000).toInt() : maxRaw.toInt();
          start = DateTime.fromMillisecondsSinceEpoch(minMs);
          end = DateTime.fromMillisecondsSinceEpoch(maxMs);
        }
      }
    }

    if (start != null && end != null) {
      return _Viewport(start: start, end: end);
    }
    return null;
  }

  /// ---------- Chart builders ----------

  Widget _buildLine(_Flattened f, Map<String, Color> palette) {
    final tooltipBuilder = _tooltipBuilder(isTimeseries: false);
    final chartTheme = ref.watch(chartThemeNotifierProvider);

    final hasY2 = f.rows.any((row) => row['y2'] != null);

    final chart = cs.CristalyseChart()
        .data(f.rows)
        .mapping(x: 'x', y: 'y', color: 'series')
        .geomLine(strokeWidth: 2.0, yAxis: cs.YAxis.primary, alpha: 1.0)
        .geomLine(strokeWidth: 2.0, yAxis: cs.YAxis.secondary, alpha: 1.0)
        .geomPoint(size: 2.5, alpha: 0.85, yAxis: cs.YAxis.primary)
        .geomPoint(size: 2.5, alpha: 0.85, yAxis: cs.YAxis.secondary)
        .scaleXContinuous(
          min: widget.config.xAxis.min,
          max: widget.config.xAxis.max,
          labels: (v) => _numLabel(v, widget.config.xAxis.unit),
        )
        .scaleYContinuous(
          min: widget.config.yAxis.min,
          max: widget.config.yAxis.max,
          labels: (v) => _numLabel(v, widget.config.yAxis.unit),
        )
        .customPalette(categoryColors: palette)
        .interaction(
          pan: cs.PanConfig(
            enabled: true,
            updateXDomain: true,
            updateYDomain: false,
            throttle: const Duration(milliseconds: 32), // ~30 FPS
            onPanUpdate: _relayPan(isTimeseries: false, end: false),
            onPanEnd: _relayPan(isTimeseries: false, end: true),
          ),
          tooltip: cs.TooltipConfig(
            builder: tooltipBuilder,
            showDelay: Duration.zero,
            hideDelay: const Duration(milliseconds: 200),
            followPointer: true,
          ),
        )
        .theme(chartTheme)
        .animate(duration: Duration.zero);
    if (hasY2) {
      return chart
          .mappingY2('y2')
          .scaleY2Continuous(
            min: widget.config.yAxis2?.min,
            max: widget.config.yAxis2?.max,
            labels: (v) => _numLabel(v, widget.config.yAxis2?.unit ?? ''),
          )
          .build();
    }
    return chart.build();
  }

  Widget _buildTimeseries(
    _Flattened f,
    Map<String, Color> palette,
    _Viewport? viewport,
    _TimeDomainTransform transform,
    String Function(num) timeLabeler,
  ) {
    final chartTheme = ref.watch(chartThemeNotifierProvider);
    // Normalize X to "relative ms from start" to keep the domain small & consistent
    // Also auto-detect seconds input and upscale to ms.
    final bool sourceIsSeconds =
        f.rows.isNotEmpty && ((f.rows.first['x'] as num) < 3e10);
    var hasY2 = false;
    final rowsRel = List<Map<String, dynamic>>.generate(
      f.rows.length,
      (i) {
        final r = f.rows[i];
        if (r['y2'] != null) {
          hasY2 = true;
        }
        final raw = r['x'] as num;
        final absMs = sourceIsSeconds ? (raw * 1000.0) : raw.toDouble();
        return {
          'x': transform.toRelative(absMs),
          'y': r['y'],
          'y2': r['y2'],
          'series': r['series'],
        };
      },
      growable: false,
    );

    final tooltipBuilder = _tooltipBuilder(
      isTimeseries: true,
      timeTransform: transform,
    );

    final chart = cs.CristalyseChart()
        .data(rowsRel)
        .mapping(x: 'x', y: 'y', color: 'series')
        .geomLine(strokeWidth: 2.0, yAxis: cs.YAxis.primary, alpha: 1.0)
        .geomPoint(size: 2.0, alpha: 0.85, yAxis: cs.YAxis.primary)
        .scaleXContinuous(
          // Force exact window: [0 .. spanMs]
          min: 0,
          max: transform.spanMs.toDouble(),
          labels: timeLabeler, // relMs -> absolute time label
        )
        .scaleYContinuous(
          min: widget.config.yAxis.min,
          max: widget.config.yAxis.max,
          labels: (v) => _numLabel(v, widget.config.yAxis.unit),
        )
        .customPalette(categoryColors: palette)
        .interaction(
          pan: cs.PanConfig(
            enabled: true,
            updateXDomain: true,
            updateYDomain: false,
            throttle: const Duration(milliseconds: 32),
            onPanUpdate: _relayPan(
                isTimeseries: true, end: false, timeTransform: transform),
            onPanEnd: (info) {
              _relayPan(
                  isTimeseries: true,
                  end: true,
                  timeTransform: transform)(info);
              widget.onPanCompleted?.call();
            },
          ),
          tooltip: cs.TooltipConfig(
            builder: tooltipBuilder,
            showDelay: const Duration(milliseconds: 500),
            hideDelay: const Duration(milliseconds: 500),
            followPointer: false,
          ),
        )
        .theme(chartTheme)
        .animate(duration: Duration.zero)
        .legend();
    if (hasY2) {
      return chart
          .geomLine(strokeWidth: 2.0, yAxis: cs.YAxis.secondary, alpha: 1.0)
          .geomPoint(size: 2.0, alpha: 0.85, yAxis: cs.YAxis.secondary)
          .mappingY2('y2')
          .scaleY2Continuous(
            min: widget.config.yAxis2?.min,
            max: widget.config.yAxis2?.max,
            labels: (v) => _numLabel(v, widget.config.yAxis2?.unit ?? ''),
          )
          .build();
    }
    return chart.build();
  }

  /// ---------- Tooltip builders ----------
  cs.TooltipBuilder _tooltipBuilder({
    required bool isTimeseries,
    _TimeDomainTransform? timeTransform,
  }) {
    return (pt) {
      final series = pt.getDisplayValue('series');
      final xRaw = double.tryParse(pt.getDisplayValue('x'));
      final y1 = pt.getDisplayValue('y');
      final y2 = pt.getDisplayValue('y2');

      String xLine = '';
      if (xRaw != null) {
        if (isTimeseries && timeTransform != null) {
          final dt = timeTransform.toAbsoluteTime(xRaw);
          xLine = _formatTime(dt, showDate: widget.showDate);
        } else {
          xLine = xRaw.toString();
        }
      }

      final valueLine = y1 ?? y2 ?? '';

      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$series',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (xLine.isNotEmpty)
                Text(isTimeseries ? 'Time: $xLine' : 'X: $xLine'),
              Text('Value: $valueLine'),
            ],
          ),
        ),
      );
    };
  }

  /// ---------- Pan relay ----------
  cs.PanCallback _relayPan({
    required bool isTimeseries,
    required bool end,
    _TimeDomainTransform? timeTransform,
  }) {
    return (info) {
      if (widget.onPanUpdate == null &&
          widget.onPanEnd == null &&
          widget.onPanCompleted == null) {
        return;
      }

      DateTime? minTime, maxTime;
      if (isTimeseries && timeTransform != null) {
        if (info.visibleMinX != null) {
          minTime = timeTransform.toAbsoluteTime(info.visibleMinX!);
        }
        if (info.visibleMaxX != null) {
          maxTime = timeTransform.toAbsoluteTime(info.visibleMaxX!);
        }
      }

      final ev = GraphPanEvent(
        info: info,
        minX: info.visibleMinX,
        maxX: info.visibleMaxX,
        minTime: minTime,
        maxTime: maxTime,
      );

      if (end) {
        widget.onPanEnd?.call(ev);
      } else {
        widget.onPanUpdate?.call(ev);
      }
    };
  }

  /// ---------- Formatting helpers ----------
  static bool _isFinite(num v) => v.isFinite;

  static String _numLabel(num v, String unit) {
    final text =
        (v == v.roundToDouble()) ? v.toInt().toString() : v.toStringAsFixed(1);
    return unit.isEmpty ? text : '$text $unit';
  }

  static String _formatTimeBySpan(DateTime dt, Duration span,
      {required bool showDate}) {
    if (span <= const Duration(minutes: 1)) {
      return showDate ? _fmt(dt, 'MM/dd HH:mm:ss') : _fmt(dt, 'HH:mm:ss');
    } else if (span <= const Duration(hours: 2)) {
      return showDate ? _fmt(dt, 'MM/dd HH:mm') : _fmt(dt, 'HH:mm');
    } else if (span <= const Duration(days: 2)) {
      return showDate ? _fmt(dt, 'MM/dd HH:mm') : _fmt(dt, 'HH:mm');
    } else if (span <= const Duration(days: 60)) {
      return _fmt(dt, 'MM/dd');
    } else {
      return _fmt(dt, 'yyyy-MM-dd');
    }
  }

  static String _formatTime(DateTime dt, {required bool showDate}) {
    return _fmt(dt, showDate ? 'MM/dd HH:mm:ss' : 'HH:mm:ss');
  }

  // Minimal formatter (no intl) for the patterns we need
  static String _fmt(DateTime dt, String pattern) {
    String two(int n) => n < 10 ? '0$n' : '$n';
    final yyyy = dt.year.toString();
    final MM = two(dt.month);
    final dd = two(dt.day);
    final HH = two(dt.hour);
    final mm = two(dt.minute);
    final ss = two(dt.second);
    return pattern
        .replaceAll('yyyy', yyyy)
        .replaceAll('MM', MM)
        .replaceAll('dd', dd)
        .replaceAll('HH', HH)
        .replaceAll('mm', mm)
        .replaceAll('ss', ss);
  }
}

/// -------------------- small privates --------------------

class _Flattened {
  final List<Map<String, dynamic>> rows;
  final List<String> order;
  _Flattened({required this.rows, required this.order});
}

class _Viewport {
  final DateTime start;
  final DateTime end;
  const _Viewport({required this.start, required this.end});
}

class _TimeDomainTransform {
  final int originMs; // absolute start in ms since epoch
  final int spanMs; // width of the window in ms
  const _TimeDomainTransform({required this.originMs, required this.spanMs});

  double toRelative(num absMs) => absMs.toDouble() - originMs.toDouble();
  int toAbsoluteMs(num relMs) => originMs + relMs.toInt();
  DateTime toAbsoluteTime(num relMs) =>
      DateTime.fromMillisecondsSinceEpoch(toAbsoluteMs(relMs));
}

/// Chart theme provider that integrates with the app's theme system
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
    // For system mode, we'll default to light theme
    // The actual brightness will be handled by the MaterialApp
    final isDark = mode == ThemeMode.dark;

    if (isDark) {
      return _createDarkChartTheme();
    } else {
      return _createLightChartTheme();
    }
  }

  cs.ChartTheme _createDarkChartTheme() {
    return cs.ChartTheme(
      backgroundColor: SolarizedColors.base03,
      plotBackgroundColor: SolarizedColors.base02,
      primaryColor: SolarizedColors.blue,
      borderColor: SolarizedColors.base01,
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
      padding: EdgeInsets.only(left: 80, right: 20, top: 20, bottom: 40),
      axisTextStyle: const TextStyle(
        color: SolarizedColors.base01,
        fontSize: 12,
        fontFamily: 'roboto-mono',
      ),
      axisLabelStyle: const TextStyle(
        color: SolarizedColors.base00,
        fontSize: 10,
        fontFamily: 'roboto-mono',
      ),
    );
  }

  cs.ChartTheme _createLightChartTheme() {
    return cs.ChartTheme(
      backgroundColor: SolarizedColors.base3,
      plotBackgroundColor: SolarizedColors.base2,
      primaryColor: SolarizedColors.green,
      borderColor: SolarizedColors.base00,
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
      // todo padding needs to be calculated based on the label size
      // it needs to be taken into account if y2 is used
      // todo implement functions
      padding: EdgeInsets.only(left: 80, right: 20, top: 20, bottom: 40),
      axisTextStyle: const TextStyle(
        color: SolarizedColors.base00,
        fontSize: 12,
        fontFamily: 'roboto-mono',
      ),
      axisLabelStyle: const TextStyle(
        color: SolarizedColors.base01,
        fontSize: 10,
        fontFamily: 'roboto-mono',
      ),
    );
  }
}

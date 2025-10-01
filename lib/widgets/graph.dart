// graph.dart
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cristalyse/cristalyse.dart' as cs;

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
  /// Raw double X-range (same units as X domain)
  final double? minX;
  final double? maxX;

  /// If timeseries: mapped to DateTime from ms since epoch
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

class Graph extends StatefulWidget {
  final GraphConfig config;

  /// Each map = one series.
  /// Key = GraphDataConfig (label/color/axis); Value = list of [x, y] points.
  /// For timeseries: x is milliseconds since epoch.
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
  State<Graph> createState() => _GraphState();
}

class _GraphState extends State<Graph> {
  // Build-once theme; no rebuild churn
  late final cs.ChartTheme _theme = cs.ChartTheme.defaultTheme();

  @override
  Widget build(BuildContext context) {
    // Early out keeps rebuilds cheap for RT charts
    if (widget.data.isEmpty || widget.data.every((m) => m.isEmpty)) {
      return const SizedBox.shrink();
    }

    final flattened = _flatten(widget.data);
    final palette = _buildCategoryPalette(flattened.order, widget.data);

    // If timeseries, prepare viewport & label formatter
    _Viewport? tsViewport;
    String Function(num)? timeLabeler;
    if (widget.config.type == GraphType.timeseries) {
      final vpAndFmt = _computeTimeViewportAndFormatter(flattened.rows);
      tsViewport = vpAndFmt.viewport;
      timeLabeler = vpAndFmt.formatter;
    }

    switch (widget.config.type) {
      case GraphType.line:
        return _buildLine(flattened, palette);
      case GraphType.timeseries:
        return _buildTimeseries(flattened, palette, tsViewport, timeLabeler!);
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

  /// ---------- Timeseries viewport + formatter (ms → labels) ----------
  _ViewportAndFormatter _computeTimeViewportAndFormatter(
      List<Map<String, dynamic>> rows) {
    DateTime? start;
    DateTime? end;

    if (widget.config.xRange != null) {
      // Hard range wins
      start = widget.config.xRange!.start;
      end = widget.config.xRange!.end;
    } else if (widget.config.xSpan != null) {
      // Anchor to NOW (fix: guarantees exact span even if last point < now)
      end = DateTime.now();
      start = end.subtract(widget.config.xSpan!);
    } else {
      // Fallback: auto-fit to data (rare for RT boards; keeps old behavior)
      if (rows.isNotEmpty) {
        int minMs = 1 << 62;
        int maxMs = 0;
        for (final r in rows) {
          final x = (r['x'] as num).toInt();
          if (x < minMs) minMs = x;
          if (x > maxMs) maxMs = x;
        }
        if (maxMs > 0 && minMs < maxMs) {
          start = DateTime.fromMillisecondsSinceEpoch(minMs);
          end = DateTime.fromMillisecondsSinceEpoch(maxMs);
        }
      }
    }

    final formatter = _timeFormatter(
      start: start,
      end: end,
      showDate: widget.showDate,
    );
    print("rows: $rows");
    print("start: $start, end: $end");

    return _ViewportAndFormatter(
      viewport: (start != null && end != null)
          ? _Viewport(start: start, end: end)
          : null,
      formatter: formatter,
    );
  }

  /// ---------- Chart builders ----------

  Widget _buildLine(_Flattened f, Map<String, Color> palette) {
    final tooltipBuilder = _tooltipBuilder(isTimeseries: false);

    return cs.CristalyseChart()
        .data(f.rows)
        .mapping(x: 'x', y: 'y', color: 'series')
        .mappingY2('y2')
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
        .scaleY2Continuous(
          min: widget.config.yAxis2?.min,
          max: widget.config.yAxis2?.max,
          labels: (v) => _numLabel(v, widget.config.yAxis2?.unit ?? ''),
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
        .theme(_theme)
        .animate(duration: Duration.zero) // real-time friendly
        .build();
  }

  // 2) Ensure your timeseries builder uses that viewport strictly
  Widget _buildTimeseries(
    _Flattened f,
    Map<String, Color> palette,
    _Viewport? viewport,
    String Function(num) timeLabeler,
  ) {
    return cs.CristalyseChart()
        .data(f.rows)
        .mapping(x: 'x', y: 'y', color: 'series')
        .mappingY2('y2')
        .geomLine(strokeWidth: 2.0, yAxis: cs.YAxis.primary, alpha: 1.0)
        .geomLine(strokeWidth: 2.0, yAxis: cs.YAxis.secondary, alpha: 1.0)
        .geomPoint(size: 2.0, alpha: 0.85, yAxis: cs.YAxis.primary)
        .geomPoint(size: 2.0, alpha: 0.85, yAxis: cs.YAxis.secondary)
        .scaleXContinuous(
          // X = ms since epoch; force exact window:
          min: viewport != null
              ? viewport.start.millisecondsSinceEpoch.toDouble()
              : widget.config.xAxis.min,
          max: viewport != null
              ? viewport.end.millisecondsSinceEpoch.toDouble()
              : widget.config.xAxis.max,
          labels: timeLabeler, // drives tick text for the span
        )
        .scaleYContinuous(
          min: widget.config.yAxis.min,
          max: widget.config.yAxis.max,
          labels: (v) => _numLabel(v, widget.config.yAxis.unit),
        )
        .scaleY2Continuous(
          min: widget.config.yAxis2?.min,
          max: widget.config.yAxis2?.max,
          labels: (v) => _numLabel(v, widget.config.yAxis2?.unit ?? ''),
        )
        .customPalette(categoryColors: palette)
        .interaction(
          pan: cs.PanConfig(
            enabled: true,
            updateXDomain: true,
            updateYDomain: false,
            throttle: const Duration(milliseconds: 32),
            onPanUpdate: _relayPan(isTimeseries: true, end: false),
            onPanEnd: (info) {
              _relayPan(isTimeseries: true, end: true)(info);
              widget.onPanCompleted?.call();
            },
          ),
          tooltip: cs.TooltipConfig(
            builder: _tooltipBuilder(isTimeseries: true),
            showDelay: Duration.zero,
            hideDelay: const Duration(milliseconds: 200),
            followPointer: true,
          ),
        )
        .theme(_theme)
        .animate(duration: Duration.zero)
        .build();
  }

  /// ---------- Tooltip builders ----------
  cs.TooltipBuilder _tooltipBuilder({required bool isTimeseries}) {
    return (pt) {
      final series = pt.getDisplayValue('series');
      final xRaw = pt.getDisplayValue('x') as num?;
      final y1 = pt.getDisplayValue('y');
      final y2 = pt.getDisplayValue('y2');

      String xLine;
      if (isTimeseries && xRaw != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(xRaw.toInt());
        xLine = _formatTime(dt, showDate: widget.showDate);
      } else {
        xLine = xRaw?.toString() ?? '';
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
  cs.PanCallback _relayPan({required bool isTimeseries, required bool end}) {
    return (info) {
      if (widget.onPanUpdate == null &&
          widget.onPanEnd == null &&
          widget.onPanCompleted == null) {
        return;
      }

      DateTime? minTime, maxTime;
      if (isTimeseries) {
        if (info.visibleMinX != null) {
          minTime =
              DateTime.fromMillisecondsSinceEpoch(info.visibleMinX!.toInt());
        }
        if (info.visibleMaxX != null) {
          maxTime =
              DateTime.fromMillisecondsSinceEpoch(info.visibleMaxX!.toInt());
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

  static String Function(num) _timeFormatter({
    DateTime? start,
    DateTime? end,
    required bool showDate,
  }) {
    String fmt(DateTime dt, Duration span) {
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

    final span = (start != null && end != null)
        ? end.difference(start)
        : const Duration(hours: 1);

    return (num value) {
      final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
      return fmt(dt, span);
    };
  }

  static String _formatTime(DateTime dt, {required bool showDate}) {
    return showDate ? _fmt(dt, 'MM/dd HH:mm:ss') : _fmt(dt, 'HH:mm:ss');
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

class _ViewportAndFormatter {
  final _Viewport? viewport;
  final String Function(num) formatter;
  _ViewportAndFormatter({required this.viewport, required this.formatter});
}

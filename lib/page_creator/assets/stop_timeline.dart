import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/alarm_interval.dart';
import 'package:tfc_dart/core/alarm_tree.dart';
import 'package:tfc_dart/core/stop_interval_source.dart';

import '../../providers/alarm.dart';
import '../../widgets/alarm.dart' show formatAlarmGroup, parseAlarmGroup;
import 'common.dart';
import 'stop_timeline_geometry.dart';
import 'stop_timeline_painter.dart';

part 'stop_timeline.g.dart';

/// A stop-analysis timeline: the alarm system on a time axis.
///
/// The tree it draws is the alarm definitions themselves, grouped by
/// [AlarmConfig.group], so this asset has almost nothing to configure — it
/// picks which part of that tree to show. Severity colours, what a leaf
/// means, how deep it nests: none of that is the asset's to decide, which is
/// why a page can never drift out of step with the alarm system.
@JsonSerializable(explicitToJson: true)
class StopTimelineConfig extends BaseAsset {
  @override
  String get displayName => 'Stop Analysis';
  @override
  String get category => 'Visualization';
  @override
  List<String> get searchKeywords =>
      const ['downtime', 'stops', 'gantt', 'timeline', 'availability', 'oee'];

  /// Which groups to draw. Empty is the whole alarm tree.
  ///
  /// A list rather than a single address, because "Line 1 and Line 2 but not
  /// Infrastructure" is an obvious thing to want on a comparison page and
  /// there is otherwise no way to say it.
  @JsonKey(defaultValue: <List<String>>[])
  List<List<String>> groups;

  /// How much history the asset loads and the overview strip covers.
  @JsonKey(name: 'period_hours', defaultValue: 12)
  int periodHours;

  /// Header text, or null for the default.
  @JsonKey(name: 'header_text')
  String? headerText;

  StopTimelineConfig({
    List<List<String>>? groups,
    this.periodHours = 12,
    this.headerText,
  }) : groups = groups ?? [];

  StopTimelineConfig.preview()
      : groups = [],
        periodHours = 12,
        headerText = null;

  // The asset binds to alarms, not to OPC UA keys, so it contributes nothing
  // to the page's key set.
  @override
  List<String> get allKeys => const [];

  factory StopTimelineConfig.fromJson(Map<String, dynamic> json) =>
      _$StopTimelineConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$StopTimelineConfigToJson(this);

  @override
  Widget build(BuildContext context) => StopTimeline(config: this);

  @override
  Widget configure(BuildContext context) =>
      StopTimelineConfigForm(config: this);
}

/// What one row of the timeline draws, resolved once per data change.
class _Lane {
  _Lane({
    required this.row,
    required this.series,
    required this.depth,
  });

  final AlarmTreeRow row;

  /// Prepared once per (data, filter) change — never per frame.
  final AlarmIntervalSeries series;
  final int depth;

  bool get isGroup => row.isGroup;
  String get label => row.label;
}

/// Loads the alarm tree and its history, then hands both to
/// [StopTimelineView].
///
/// The split is what makes the timeline testable: everything below this class
/// is pure presentation over data it is given, so a golden can render a whole
/// shift without an `AlarmMan`, a `StateMan` or a database behind it.
class StopTimeline extends ConsumerStatefulWidget {
  const StopTimeline({super.key, required this.config});

  final StopTimelineConfig config;

  @override
  ConsumerState<StopTimeline> createState() => _StopTimelineState();
}

class _StopTimelineState extends ConsumerState<StopTimeline> {
  StopIntervalSource _source = StopIntervalSource.empty;
  AlarmTree? _tree;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final man = await ref.read(alarmManProvider.future);
      final history = await man.getRecentAlarms(limit: 2000);
      final active = await man.activeAlarms().first;
      if (!mounted) return;
      setState(() {
        _tree = AlarmTree.fromConfigs(man.config.alarms);
        _source =
            StopIntervalSource.fromAlarms(history: history, active: active);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Could not load alarms.\n$_error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return StopTimelineView(
      config: widget.config,
      tree: _tree!,
      source: _source,
    );
  }
}

/// The timeline proper: lanes, collapse, pan, zoom, the overview strip and the
/// detail row, over data it is handed.
class StopTimelineView extends StatefulWidget {
  const StopTimelineView({
    super.key,
    required this.config,
    required this.tree,
    required this.source,
    this.clock,
  });

  final StopTimelineConfig config;
  final AlarmTree tree;
  final StopIntervalSource source;

  /// Fixed clock for tests and goldens. Live when null, which also stops the
  /// per-second repaint that keeps a standing alarm growing.
  final DateTime? clock;

  @override
  State<StopTimelineView> createState() => _StopTimelineViewState();
}

class _StopTimelineViewState extends State<StopTimelineView> {
  /// Panning writes here rather than calling setState: the painters listen to
  /// it directly, so a drag repaints the lanes without rebuilding the tree
  /// above them.
  late final ValueNotifier<TimelineWindow> _window;

  final Set<String> _expanded = {};
  final Set<AlarmLevel> _levels = {...AlarmLevel.values};
  AlarmInterval? _selected;
  String? _selectedLabel;

  /// Frozen per frame so every lane and every statistic agrees about "now".
  late DateTime _now;
  Timer? _tick;

  static const double _labelWidth = 210;
  static const double _groupRowHeight = 38;
  static const double _alarmRowHeight = 30;

  TimelineWindow get _period => TimelineWindow(
      _now.subtract(Duration(hours: widget.config.periodHours)), _now);

  @override
  void initState() {
    super.initState();
    _now = widget.clock ?? DateTime.now();
    _window = ValueNotifier(TimelineWindow(
        _now.subtract(const Duration(hours: 3)),
        _now.add(const Duration(minutes: 10))));
    // The live edge really is live: an alarm still standing keeps growing.
    // A repaint only, never a refetch. A fixed clock means a test or a
    // golden, where a ticking timer would only cause flake.
    if (widget.clock == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _window.dispose();
    super.dispose();
  }

  /// Lanes for the rows currently visible, with their series prepared.
  List<_Lane> _visibleLanes() {
    final rows = widget.tree.rows(groups: widget.config.groups);

    final lanes = <_Lane>[];
    var hiddenBelow = -1; // depth of the collapsed group we are inside
    for (final row in rows) {
      if (hiddenBelow >= 0) {
        if (row.depth > hiddenBelow) continue;
        hiddenBelow = -1;
      }
      lanes.add(_Lane(row: row, series: _seriesFor(row), depth: row.depth));
      if (row.isGroup && !_expanded.contains(_keyOf(row))) {
        hiddenBelow = row.depth;
      }
    }
    return lanes;
  }

  /// Every alarm the configured groups actually cover.
  ///
  /// The header counts and the overview strip are about what this asset is
  /// showing, not about the whole plant — an asset scoped to Multivac that
  /// reports the site's alarm counts is lying about its own subject.
  Set<String> _scopedUids() {
    final uids = <String>{};
    for (final row in widget.tree.rows(groups: widget.config.groups)) {
      if (row.isGroup) {
        uids.addAll(row.group!.subtreeAlarms.map((a) => a.uid));
      } else {
        uids.add(row.alarm!.uid);
      }
    }
    return uids;
  }

  String _keyOf(AlarmTreeRow row) =>
      row.isGroup ? 'g:${row.group!.path.join('/')}' : 'a:${row.alarm!.uid}';

  AlarmIntervalSeries _seriesFor(AlarmTreeRow row) {
    if (!row.isGroup) {
      final alarm = row.alarm!;
      if (!_levels.contains(alarm.rules.isEmpty
          ? AlarmLevel.info
          : alarm.rules.first.level)) {
        return AlarmIntervalSeries(const [], now: _now);
      }
      return widget.source.seriesFor(alarm.uid, now: _now);
    }
    final uids = row.group!.subtreeAlarms
        .where((a) => _levels.contains(
            a.rules.isEmpty ? AlarmLevel.info : a.rules.first.level))
        .map((a) => a.uid);
    return AlarmIntervalSeries(widget.source.mergedFor(uids, now: _now),
        now: _now);
  }

  void _pan(double dx, double width) {
    _window.value = _window.value.panBy(dx, width).clampTo(_period);
  }

  void _zoom(double factor, double anchor) {
    _window.value = _window.value.zoomBy(factor, anchor).clampTo(_period);
  }

  Map<AlarmLevel, Color> _levelColors(BuildContext context) => {
        for (final level in AlarmLevel.values)
          level: colorForLevel(context, level)
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lanes = _visibleLanes();
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 260;
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(3),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            _header(context, compact: compact),
            _axis(context),
            Expanded(child: _lanes(context, lanes)),
            if (!compact) _brush(context),
            if (!compact) _detail(context),
          ],
        ),
      );
    });
  }

  Widget _header(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final scoped = _scopedUids();
    final counts = <AlarmLevel, int>{for (final l in AlarmLevel.values) l: 0};
    var standing = 0;
    for (final activation in widget.source.all) {
      if (!scoped.contains(activation.alarmUid)) continue;
      final level = activation.level;
      counts[level] = (counts[level] ?? 0) + 1;
      if (activation.isOpen) standing++;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      // The asset is sized on a page canvas, so the header has to survive any
      // width. The title ellipsises and the chips scroll rather than
      // overflowing -- and the window readout, the one thing that is never
      // guessable from the lanes, keeps its space.
      child: Row(
        children: [
          Flexible(
            child: Text(
              widget.config.headerText ?? 'Stop analysis',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 12),
          if (!compact)
            Flexible(
              flex: 3,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(children: [
                  for (final level in [
                    AlarmLevel.error,
                    AlarmLevel.warning,
                    AlarmLevel.info
                  ])
                    _levelChip(context, level, counts[level] ?? 0),
                ]),
              ),
            ),
          const Spacer(),
          if (standing > 0) ...[
            Icon(Icons.circle,
                size: 8, color: colorForLevel(context, AlarmLevel.error)),
            const SizedBox(width: 4),
            Text('$standing standing',
                maxLines: 1, style: theme.textTheme.labelSmall),
            const SizedBox(width: 10),
          ],
          ValueListenableBuilder(
            valueListenable: _window,
            builder: (context, window, _) => Text(
              '${_hhmm(window.start)} – ${_hhmm(window.end)}',
              maxLines: 1,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelChip(BuildContext context, AlarmLevel level, int count) {
    final on = _levels.contains(level);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        key: ValueKey('stop-timeline-level-${level.name}'),
        onTap: () => setState(() {
          if (!_levels.remove(level)) _levels.add(level);
        }),
        child: Opacity(
          opacity: on ? 1 : 0.35,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: colorForLevel(context, level),
                    borderRadius: BorderRadius.circular(1))),
            const SizedBox(width: 4),
            Text('${_levelLabel(level)} $count',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }

  String _levelLabel(AlarmLevel level) => switch (level) {
        AlarmLevel.error => 'Error',
        AlarmLevel.warning => 'Warning',
        AlarmLevel.info => 'Info',
      };

  Widget _axis(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 22,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(children: [
        SizedBox(
          width: _labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 3),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text('ALARM GROUP',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(letterSpacing: 1.1, fontSize: 9)),
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: _window,
            builder: (context, window, _) => LayoutBuilder(
              builder: (context, c) => Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final tick in timelineTicks(window, c.maxWidth))
                    Positioned(
                      left: tick.x - 20,
                      bottom: 3,
                      width: 40,
                      child: Text(
                        _hhmm(tick.at),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight:
                              tick.isHour ? FontWeight.w600 : FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _lanes(BuildContext context, List<_Lane> lanes) {
    final theme = Theme.of(context);
    if (lanes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            widget.config.groups.isEmpty
                ? 'No alarms are configured yet.'
                : 'No alarms are defined under '
                    '${widget.config.groups.map(formatAlarmGroup).join(' or ')}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return Stack(children: [
      // The lane ground runs the full height, so the area below the last row
      // still reads as part of the chart rather than as blank page.
      Positioned.fill(
        left: _labelWidth,
        child: ColoredBox(color: _laneColor(theme, isGroup: false)),
      ),
      ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: lanes.length,
        itemBuilder: (context, i) => _laneRow(context, lanes[i]),
      ),
      // One overlay for gridlines, the hatch and the future, rather than
      // eleven elements per row repainted on every pan frame.
      Positioned.fill(
        left: _labelWidth,
        child: IgnorePointer(
          child: CustomPaint(
            painter: StopTimelineChromePainter(
              window: _window,
              now: () => _now,
              excluded: const [],
              lineColor: theme.dividerColor.withValues(alpha: 0.35),
              hourLineColor: theme.dividerColor.withValues(alpha: 0.7),
              hatchColor: theme.colorScheme.onSurface.withValues(alpha: 0.09),
              futureColor:
                  theme.colorScheme.surface.withValues(alpha: 0.55),
              nowColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              repaint: _window,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ]);
  }

  Widget _laneRow(BuildContext context, _Lane lane) {
    final theme = Theme.of(context);
    final height = lane.isGroup ? _groupRowHeight : _alarmRowHeight;
    final stats = lane.series.statsIn(_window.value.start, _window.value.end);

    return SizedBox(
      height: height,
      child: Row(children: [
        SizedBox(
          width: _labelWidth,
          child: _laneLabel(context, lane, stats),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => _pan(d.delta.dx, c.maxWidth),
              onTapUp: (d) => _selectAt(lane, d.localPosition.dx, c.maxWidth),
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final anchor =
                        (event.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                    _zoom(event.scrollDelta.dy > 0 ? 1.15 : 0.87, anchor);
                  }
                },
                child: CustomPaint(
                  size: Size(c.maxWidth, height),
                  painter: StopLanePainter(
                    series: lane.series,
                    window: _window,
                    now: () => _now,
                    colors: _levelColors(context),
                    isGroup: lane.isGroup,
                    selectedInterval: _selected,
                    selectionColor: theme.colorScheme.primary,
                    laneColor: _laneColor(theme, isGroup: lane.isGroup),
                    repaint: _window,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  Widget _laneLabel(BuildContext context, _Lane lane, IntervalStats stats) {
    final theme = Theme.of(context);
    final row = lane.row;
    final expandable = row.isGroup && row.group!.hasChildren;
    final open = _expanded.contains(_keyOf(row));

    return InkWell(
      key: ValueKey('stop-timeline-row-${_keyOf(row)}'),
      onTap: expandable
          ? () => setState(() {
                if (!_expanded.remove(_keyOf(row))) _expanded.add(_keyOf(row));
              })
          : null,
      child: Container(
        padding: EdgeInsets.only(left: 6 + lane.depth * 14.0, right: 6),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(children: [
          SizedBox(
            width: 16,
            child: expandable
                ? Icon(open ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 16)
                : null,
          ),
          if (!row.isGroup)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: _levelMark(context, row),
            )
          else if (row.group!.bound != null)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: _boundMark(context, row.group!.bound!),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: row.isGroup
                      ? theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w600)
                      : theme.textTheme.labelSmall,
                ),
                if (lane.isGroup || stats.count > 0)
                  Text(
                    _statLine(stats, isGroup: lane.isGroup),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: stats.isOpen
                          ? colorForLevel(context, AlarmLevel.error)
                          : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// A filled square: an alarm, one diagnosis among several.
  Widget _levelMark(BuildContext context, AlarmTreeRow row) {
    final level = row.alarm!.rules.isEmpty
        ? AlarmLevel.info
        : row.alarm!.rules.first.level;
    if (row.isBound) return _boundMark(context, row.alarm!);
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
          color: colorForLevel(context, level),
          borderRadius: BorderRadius.circular(1)),
    );
  }

  /// A hollow ring: the alarm that *is* this group, not one inside it.
  Widget _boundMark(BuildContext context, AlarmConfig alarm) {
    final level =
        alarm.rules.isEmpty ? AlarmLevel.info : alarm.rules.first.level;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorForLevel(context, level), width: 1.5),
      ),
    );
  }

  String _statLine(IntervalStats stats, {required bool isGroup}) {
    final buffer = StringBuffer();
    if (stats.isOpen) buffer.write('now · ');
    buffer.write('${_durShort(stats.total)} · ${stats.count}×');
    return buffer.toString();
  }

  void _selectAt(_Lane lane, double x, double width) {
    final runs = laneRuns(lane.series, _window.value, width, now: _now);
    for (final run in runs) {
      if (x >= run.x1 - 2 && x <= run.x2 + 2) {
        if (run.merged > 1) {
          // A comb of activations too close to tell apart: zoom into it
          // rather than pretending to have picked one.
          final centre =
              _window.value.timeAt((run.x1 + run.x2) / 2, width);
          final span = Duration(
              microseconds:
                  (_window.value.span.inMicroseconds * 0.3).round());
          _window.value = TimelineWindow(
                  centre.subtract(span ~/ 2), centre.add(span ~/ 2))
              .clampTo(_period);
          return;
        }
        setState(() {
          _selected = run.interval;
          _selectedLabel = lane.label;
        });
        return;
      }
    }
    setState(() {
      _selected = null;
      _selectedLabel = null;
    });
  }

  Widget _brush(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(children: [
        SizedBox(
          width: _labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_dayLabel(_now),
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 9)),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _centreOn(d.localPosition.dx, c.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _centreOn(d.localPosition.dx, c.maxWidth),
              child: CustomPaint(
                size: Size(c.maxWidth, 30),
                painter: StopTimelineBrushPainter(
                  period: _period,
                  window: _window,
                  intervals:
                      widget.source.mergedFor(_scopedUids(), now: _now),
                  now: () => _now,
                  colors: _levelColors(context),
                  trackColor: _laneColor(theme, isGroup: true),
                  windowColor: theme.colorScheme.primary,
                  shadeColor:
                      theme.colorScheme.surface.withValues(alpha: 0.55),
                  repaint: _window,
                ),
                child: const SizedBox.expand(),
              ),
            );
          }),
        ),
      ]),
    );
  }

  void _centreOn(double x, double width) {
    final t = _period.timeAt(x, width);
    final span = _window.value.span;
    _window.value =
        TimelineWindow(t.subtract(span ~/ 2), t.add(span ~/ 2))
            .clampTo(_period);
  }

  Widget _detail(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      alignment: Alignment.centerLeft,
      child: selected == null
          ? Text('Select an activation to inspect it.',
              style: theme.textTheme.labelSmall)
          : Row(children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: colorForLevel(context, selected.level),
                    borderRadius: BorderRadius.circular(1)),
              ),
              const SizedBox(width: 6),
              Text(_selectedLabel ?? '',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selected.isOpen
                      ? 'Since ${_hhmmss(selected.start)} · still standing · '
                          '${_durShort(selected.lengthAt(_now))}'
                      : '${_hhmmss(selected.start)} – '
                          '${_hhmmss(selected.end!)} · '
                          '${_durShort(selected.lengthAt(_now))}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ]),
    );
  }
}

/// The lane ground. Derived from the surface rather than taken from a
/// Material container role, because those land almost on top of the surface in
/// the light scheme and the lanes then have no edge at all.
Color _laneColor(ThemeData theme, {required bool isGroup}) {
  final ink = theme.colorScheme.onSurface;
  return Color.alphaBlend(
      ink.withValues(alpha: isGroup ? 0.09 : 0.05), theme.colorScheme.surface);
}

String _two(int n) => n.toString().padLeft(2, '0');
String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
String _hhmmss(DateTime t) => '${_hhmm(t)}:${_two(t.second)}';
String _dayLabel(DateTime t) => '${_two(t.day)}/${_two(t.month)}';

String _durShort(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  return '${d.inHours}h ${_two(d.inMinutes % 60)}m';
}

/// The page-editor form: which groups to show, and how far back to look.
class StopTimelineConfigForm extends ConsumerStatefulWidget {
  const StopTimelineConfigForm({super.key, required this.config});

  final StopTimelineConfig config;

  @override
  ConsumerState<StopTimelineConfigForm> createState() =>
      _StopTimelineConfigFormState();
}

class _StopTimelineConfigFormState
    extends ConsumerState<StopTimelineConfigForm> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = widget.config.groups;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Groups to show', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Leave empty for the whole alarm tree. Each entry is an alarm '
          'group, outermost first — "Line 3 / Multivac".',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < groups.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('stop-timeline-group-$i'),
                  initialValue: formatAlarmGroup(groups[i]),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'Line 3 / Multivac',
                  ),
                  onChanged: (v) => groups[i] = parseAlarmGroup(v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove',
                onPressed: () => setState(() => groups.removeAt(i)),
              ),
            ]),
          ),
        TextButton.icon(
          key: const ValueKey('stop-timeline-add-group'),
          icon: const Icon(Icons.add),
          label: const Text('Add group'),
          onPressed: () => setState(() => groups.add(const [])),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('stop-timeline-period'),
          initialValue: widget.config.periodHours.toString(),
          decoration: const InputDecoration(
            labelText: 'History to load (hours)',
            helperText: 'Also the span the overview strip covers.',
          ),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final parsed = int.tryParse(v);
            if (parsed != null && parsed > 0) {
              widget.config.periodHours = parsed;
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('stop-timeline-header'),
          initialValue: widget.config.headerText ?? '',
          decoration: const InputDecoration(labelText: 'Header text'),
          onChanged: (v) =>
              widget.config.headerText = v.isEmpty ? null : v,
        ),
      ]),
    );
  }
}

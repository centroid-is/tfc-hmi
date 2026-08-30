import 'dart:math' as math;

import 'package:tfc_dart/core/alarm.dart' show AlarmLevel;
import 'package:tfc_dart/core/alarm_interval.dart';

/// The slice of time a lane is showing.
///
/// Immutable so a pan is a new value rather than a mutation, which is what
/// lets the painter repaint off a `ValueNotifier` without rebuilding widgets.
class TimelineWindow {
  final DateTime start;
  final DateTime end;

  const TimelineWindow(this.start, this.end);

  Duration get span => end.difference(start);

  /// Never zoom past this: below a few minutes the axis labels collide and
  /// there is nothing left to see that the detail row does not say better.
  static const minSpan = Duration(minutes: 2);

  /// Where [t] falls across a lane [width] pixels wide.
  double xOf(DateTime t, double width) =>
      t.difference(start).inMicroseconds /
      span.inMicroseconds *
      width;

  /// The instant at pixel [x] across a lane [width] pixels wide.
  DateTime timeAt(double x, double width) => start.add(Duration(
      microseconds: (x / width * span.inMicroseconds).round()));

  /// Slides the window by [dx] pixels, keeping its span.
  TimelineWindow panBy(double dx, double width) {
    final dt = Duration(
        microseconds: -(dx / width * span.inMicroseconds).round());
    return TimelineWindow(start.add(dt), end.add(dt));
  }

  /// Zooms by [factor] about the point [anchor] (0..1 across the lane).
  ///
  /// Anchoring on the cursor rather than the centre is what makes a scroll
  /// zoom feel like it is pointing at something.
  TimelineWindow zoomBy(double factor, double anchor) {
    final micros = math.max(
        minSpan.inMicroseconds, (span.inMicroseconds * factor).round());
    final pivot = start.add(
        Duration(microseconds: (span.inMicroseconds * anchor).round()));
    final newStart =
        pivot.subtract(Duration(microseconds: (micros * anchor).round()));
    return TimelineWindow(newStart, newStart.add(Duration(microseconds: micros)));
  }

  /// Keeps the window inside [bounds], preserving its span where it can.
  ///
  /// A span wider than the period is clamped to the period rather than
  /// left hanging off both ends.
  TimelineWindow clampTo(TimelineWindow bounds) {
    var micros = span.inMicroseconds;
    final limit = bounds.span.inMicroseconds;
    if (micros > limit) micros = limit;
    if (micros < minSpan.inMicroseconds) micros = minSpan.inMicroseconds;

    var s = start;
    if (s.isBefore(bounds.start)) s = bounds.start;
    var e = s.add(Duration(microseconds: micros));
    if (e.isAfter(bounds.end)) {
      e = bounds.end;
      s = e.subtract(Duration(microseconds: micros));
      if (s.isBefore(bounds.start)) s = bounds.start;
    }
    return TimelineWindow(s, e);
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimelineWindow($start .. $end)';
}

/// One drawn bar: a stretch of pixels, and what it stands for.
///
/// [merged] above one means several activations were closer together than a
/// pixel and were coalesced — the run then reports the worst severity among
/// them, and the UI offers to zoom rather than pretending to identify one.
class LaneRun {
  final double x1;
  final double x2;
  final AlarmLevel level;
  final bool isOpen;
  final int activations;
  final int merged;

  /// The single interval this run stands for, when it stands for one.
  final AlarmInterval? interval;

  const LaneRun({
    required this.x1,
    required this.x2,
    required this.level,
    required this.isOpen,
    required this.activations,
    required this.merged,
    this.interval,
  });

  double get width => x2 - x1;

  @override
  String toString() =>
      'LaneRun(${x1.toStringAsFixed(1)}..${x2.toStringAsFixed(1)}, '
      '${level.name}${isOpen ? ', open' : ''}, x$activations)';
}

/// The narrowest a bar is allowed to get.
///
/// Over a five-hour window a forty-second alarm is a fifth of a pixel. Without
/// a floor the chattering alarms — the ones the analysis is usually looking
/// for — are the ones that vanish.
const double minRunWidth = 2.0;

/// Runs to draw for one lane, in pixel space.
///
/// Two things keep this cheap regardless of how much history is loaded: the
/// visible slice comes from [AlarmIntervalSeries.sliceIn] (two binary
/// searches over a sorted disjoint list), and intervals landing within a pixel
/// of each other are coalesced, so the number of runs is bounded by [width]
/// rather than by the data.
List<LaneRun> laneRuns(
  AlarmIntervalSeries series,
  TimelineWindow window,
  double width, {
  required DateTime now,
}) {
  if (width <= 0 || series.isEmpty) return const [];
  final (lo, hi) = series.sliceIn(window.start, window.end);
  if (hi < lo) return const [];

  final runs = <LaneRun>[];
  LaneRun? current;
  for (var i = lo; i <= hi; i++) {
    final iv = series.intervals[i];
    final x1 = window.xOf(iv.start, width);
    var x2 = window.xOf(iv.endAt(now), width);
    if (x2 - x1 < minRunWidth) x2 = x1 + minRunWidth;

    if (current != null && x1 <= current.x2 + 1) {
      runs[runs.length - 1] = current = LaneRun(
        x1: current.x1,
        x2: math.max(current.x2, x2),
        level: current.level.worst(iv.level),
        isOpen: current.isOpen || iv.isOpen,
        activations: current.activations + iv.count,
        merged: current.merged + 1,
        interval: null,
      );
      continue;
    }
    current = LaneRun(
      x1: x1,
      x2: x2,
      level: iv.level,
      isOpen: iv.isOpen,
      activations: iv.count,
      merged: 1,
      interval: iv,
    );
    runs.add(current);
  }
  return runs;
}

/// A labelled gridline on the time axis.
class TimelineTick {
  final DateTime at;
  final double x;

  /// Whole hours are drawn heavier and labelled more strongly — they are what
  /// an operator actually navigates by.
  final bool isHour;

  const TimelineTick(this.at, this.x, {required this.isHour});
}

const _tickSteps = <Duration>[
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 3),
  Duration(hours: 6),
  Duration(hours: 12),
  Duration(days: 1),
];

/// The step between axis ticks: the smallest round interval that leaves at
/// most nine labels across the window.
Duration tickStep(Duration span) {
  for (final step in _tickSteps) {
    if (span.inMicroseconds / step.inMicroseconds <= 9) return step;
  }
  return _tickSteps.last;
}

/// Ticks across [window], positioned for a lane [width] pixels wide.
List<TimelineTick> timelineTicks(TimelineWindow window, double width) {
  if (width <= 0) return const [];
  final step = tickStep(window.span);
  final stepMicros = step.inMicroseconds;

  // Align to the step from midnight, so ticks land on 08:00 rather than
  // wherever the window happens to begin.
  final midnight = DateTime(
      window.start.year, window.start.month, window.start.day);
  final sinceMidnight =
      window.start.difference(midnight).inMicroseconds;
  final firstOffset = (sinceMidnight / stepMicros).ceil() * stepMicros;

  final ticks = <TimelineTick>[];
  for (var t = midnight.add(Duration(microseconds: firstOffset));
      !t.isAfter(window.end);
      t = t.add(step)) {
    ticks.add(TimelineTick(t, window.xOf(t, width),
        isHour: t.minute == 0 && t.second == 0));
  }
  return ticks;
}

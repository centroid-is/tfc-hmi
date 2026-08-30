import 'alarm.dart' show AlarmLevel;

/// Ranks the alarm severities so intervals can be merged without losing the
/// worst thing that happened inside them.
extension AlarmLevelSeverity on AlarmLevel {
  /// Higher is worse. Only the ordering is meaningful, not the values.
  int get severity => switch (this) {
        AlarmLevel.info => 1,
        AlarmLevel.warning => 2,
        AlarmLevel.error => 3,
      };

  /// The worse of the two levels; ties return this one.
  AlarmLevel worst(AlarmLevel other) =>
      other.severity > severity ? other : this;
}

/// A half-open span of wall-clock time, `[start, end)`.
class TimeRange {
  final DateTime start;
  final DateTime end;

  const TimeRange(this.start, this.end);

  Duration get duration => end.difference(start);

  /// How much of this range falls inside `[from, to)`. Never negative.
  Duration overlap(DateTime from, DateTime to) {
    final lo = start.isAfter(from) ? start : from;
    final hi = end.isBefore(to) ? end : to;
    return hi.isAfter(lo) ? hi.difference(lo) : Duration.zero;
  }

  @override
  String toString() => 'TimeRange($start .. $end)';
}

/// One stretch of time during which an alarm — or, once merged, anything
/// underneath a node — was standing.
///
/// A null [end] means it has not cleared yet. That is not an edge case here:
/// `AlarmMan` only writes a history row when an alarm clears, so the alarm an
/// operator is standing in front of is *always* the open one, and dropping it
/// would omit the single stop they came to look at.
class AlarmInterval {
  final DateTime start;

  /// When it cleared, or null while it is still standing.
  final DateTime? end;

  /// For a merged interval, the worst severity standing inside it.
  final AlarmLevel level;

  /// How many activations were merged into this interval. One when it came
  /// straight from a single activation.
  final int count;

  const AlarmInterval({
    required this.start,
    required this.end,
    required this.level,
    this.count = 1,
  });

  bool get isOpen => end == null;

  /// Where this interval ends on a clock reading [now]. An open interval is
  /// still growing, so it ends at [now] rather than nowhere.
  DateTime endAt(DateTime now) => end ?? now;

  /// How long it ran, on a clock reading [now].
  Duration lengthAt(DateTime now) => endAt(now).difference(start);

  AlarmInterval copyWith({
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
    AlarmLevel? level,
    int? count,
  }) =>
      AlarmInterval(
        start: start ?? this.start,
        end: clearEnd ? null : (end ?? this.end),
        level: level ?? this.level,
        count: count ?? this.count,
      );

  @override
  String toString() =>
      'AlarmInterval($start .. ${end ?? 'open'}, ${level.name}, x$count)';
}

/// Unions overlapping or touching intervals into a sorted, disjoint list.
///
/// Each merged interval carries the worst severity standing inside it and the
/// number of activations it absorbed, which is what lets a collapsed group
/// lane answer "was anything under here standing, and how bad" without
/// walking its children again.
///
/// [now] resolves open intervals for the overlap test; an open interval in the
/// input keeps the interval containing it open.
List<AlarmInterval> mergeIntervals(
  Iterable<AlarmInterval> intervals, {
  required DateTime now,
}) {
  final sorted = intervals.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  if (sorted.isEmpty) return const [];

  final merged = <AlarmInterval>[];
  var current = sorted.first;
  for (final next in sorted.skip(1)) {
    final currentEnd = current.endAt(now);
    // `!isBefore` rather than `isAfter`: intervals that merely touch are one
    // stretch of downtime, not two.
    if (!next.start.isAfter(currentEnd)) {
      final nextEnd = next.endAt(now);
      final open = current.isOpen || next.isOpen;
      current = current.copyWith(
        end: open ? null : (nextEnd.isAfter(currentEnd) ? nextEnd : currentEnd),
        clearEnd: open,
        level: current.level.worst(next.level),
        count: current.count + next.count,
      );
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

/// What a lane reports for one time window.
class IntervalStats {
  /// Standing time inside the window, with excluded (unscheduled) time removed.
  final Duration total;

  /// Activations touching the window. An activation clipped by an edge still
  /// counts once — it did happen.
  final int count;

  /// True when something in the window is still standing.
  final bool isOpen;

  const IntervalStats({
    required this.total,
    required this.count,
    required this.isOpen,
  });

  static const empty =
      IntervalStats(total: Duration.zero, count: 0, isOpen: false);

  @override
  String toString() =>
      'IntervalStats($total, x$count${isOpen ? ', open' : ''})';
}

/// A lane's intervals, prepared once so that panning is cheap.
///
/// The intervals are kept sorted and disjoint, which buys two things the
/// timeline leans on hard: the slice visible in a window is two binary
/// searches away, and — because every interval strictly between the two edge
/// ones is wholly inside the window — a prefix sum turns the window total into
/// `O(log n)` instead of a scan. Panning must never re-derive this; build it
/// once per (data, filter) change and query it per frame.
class AlarmIntervalSeries {
  /// Sorted by start, disjoint.
  final List<AlarmInterval> intervals;

  /// Time that does not count as production — breaks, unscheduled shifts.
  /// Subtracted from every duration this class reports.
  final List<TimeRange> excluded;

  /// The clock open intervals are measured against.
  final DateTime now;

  /// `_prefix[i]` is the scheduled standing time of intervals `[0, i)`.
  ///
  /// An open interval is always the last one and its length depends on [now],
  /// so it contributes zero here and is added back when the window is read.
  final List<int> _prefix;

  /// `_countPrefix[i]` is the activation count of intervals `[0, i)`.
  final List<int> _countPrefix;

  AlarmIntervalSeries(
    List<AlarmInterval> intervals, {
    required this.now,
    this.excluded = const [],
  })  : intervals = List.unmodifiable(intervals),
        _prefix = List.filled(intervals.length + 1, 0),
        _countPrefix = List.filled(intervals.length + 1, 0) {
    for (var i = 0; i < intervals.length; i++) {
      final iv = intervals[i];
      final micros = iv.isOpen
          ? 0
          : _scheduled(iv.start, iv.end!).inMicroseconds;
      _prefix[i + 1] = _prefix[i] + micros;
      _countPrefix[i + 1] = _countPrefix[i] + iv.count;
    }
    assert(
        () {
          final open = intervals.indexWhere((e) => e.isOpen);
          return open < 0 || open == intervals.length - 1;
        }(),
        'an open interval must be the last one — it runs to now, so anything '
        'starting after it overlaps and should have been merged into it');
  }

  bool get isEmpty => intervals.isEmpty;

  /// Wall-clock time between [from] and [to] that counts as production.
  Duration scheduledBetween(DateTime from, DateTime to) =>
      _scheduled(from, to);

  Duration _scheduled(DateTime from, DateTime to) {
    var span = to.isAfter(from) ? to.difference(from) : Duration.zero;
    for (final range in excluded) {
      span -= range.overlap(from, to);
    }
    return span < Duration.zero ? Duration.zero : span;
  }

  /// The inclusive index range of intervals overlapping `[from, to)`.
  ///
  /// `hi < lo` means nothing overlaps. An interval that merely touches an edge
  /// does not overlap.
  (int, int) sliceIn(DateTime from, DateTime to) {
    if (intervals.isEmpty) return (0, -1);
    return (_firstEndAfter(from), _lastStartBefore(to));
  }

  /// First index whose end is strictly after [t]. Ends increase across a
  /// disjoint sorted list, so this is a binary search.
  int _firstEndAfter(DateTime t) {
    var lo = 0, hi = intervals.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (intervals[mid].endAt(now).isAfter(t)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Last index whose start is strictly before [t].
  int _lastStartBefore(DateTime t) {
    var lo = 0, hi = intervals.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (intervals[mid].start.isBefore(t)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }

  /// Standing time and activation count inside `[from, to)`.
  IntervalStats statsIn(DateTime from, DateTime to) {
    final (lo, hi) = sliceIn(from, to);
    if (hi < lo) return IntervalStats.empty;

    var micros = 0;
    // Everything strictly between the edges is wholly inside the window,
    // because the list is sorted and disjoint — so it comes from the prefix
    // sum rather than a walk.
    if (hi - lo >= 2) micros += _prefix[hi] - _prefix[lo + 1];

    var isOpen = false;
    for (final i in lo == hi ? [lo] : [lo, hi]) {
      final iv = intervals[i];
      final start = iv.start.isAfter(from) ? iv.start : from;
      final ivEnd = iv.endAt(now);
      final end = ivEnd.isBefore(to) ? ivEnd : to;
      if (end.isAfter(start)) micros += _scheduled(start, end).inMicroseconds;
    }
    // Leaving the open interval out of the prefix sum is only safe because it
    // can never be interior: it runs to `now`, so anything starting after it
    // would overlap and have been merged into it. The constructor asserts it.
    for (var i = lo; i <= hi; i++) {
      if (intervals[i].isOpen) isOpen = true;
    }

    return IntervalStats(
      total: Duration(microseconds: micros),
      count: _countPrefix[hi + 1] - _countPrefix[lo],
      isOpen: isOpen,
    );
  }
}

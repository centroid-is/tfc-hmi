import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/stop_timeline_geometry.dart';
import 'package:tfc_dart/core/alarm.dart' show AlarmLevel;
import 'package:tfc_dart/core/alarm_interval.dart';

final base = DateTime(2026, 8, 29, 6);
DateTime at(int minutes) => base.add(Duration(minutes: minutes));

TimelineWindow win(int from, int to) => TimelineWindow(at(from), at(to));

AlarmInterval iv(int from, int? to,
        {AlarmLevel level = AlarmLevel.error, int count = 1}) =>
    AlarmInterval(
        start: at(from),
        end: to == null ? null : at(to),
        level: level,
        count: count);

AlarmIntervalSeries series(List<AlarmInterval> intervals, {int now = 1000}) =>
    AlarmIntervalSeries(intervals, now: at(now));

void main() {
  group('TimelineWindow mapping', () {
    final w = win(0, 100);

    test('maps time to pixels across the lane', () {
      expect(w.xOf(at(0), 200), 0);
      expect(w.xOf(at(50), 200), 100);
      expect(w.xOf(at(100), 200), 200);
    });

    test('maps pixels back to time', () {
      expect(w.timeAt(0, 200), at(0));
      expect(w.timeAt(100, 200), at(50));
    });

    test('a time outside the window maps outside the lane', () {
      expect(w.xOf(at(-50), 200), -100);
      expect(w.xOf(at(150), 200), 300);
    });
  });

  group('TimelineWindow pan', () {
    test('dragging right moves the window earlier', () {
      // content follows the finger, so the window goes back in time
      final panned = win(0, 100).panBy(50, 200);
      expect(panned.start, at(-25));
      expect(panned.span, const Duration(minutes: 100));
    });

    test('dragging left moves the window later', () {
      expect(win(0, 100).panBy(-50, 200).start, at(25));
    });
  });

  group('TimelineWindow zoom', () {
    test('zooming out about the middle grows both edges', () {
      final z = win(0, 100).zoomBy(2, 0.5);
      expect(z.span, const Duration(minutes: 200));
      expect(z.start, at(-50));
    });

    test('zooming in about the left edge keeps that edge still', () {
      final z = win(0, 100).zoomBy(0.5, 0);
      expect(z.start, at(0));
      expect(z.span, const Duration(minutes: 50));
    });

    test('zooming in about the right edge keeps that edge still', () {
      final z = win(0, 100).zoomBy(0.5, 1);
      expect(z.end, at(100));
    });

    test('will not zoom past the minimum span', () {
      final z = win(0, 100).zoomBy(0.0001, 0.5);
      expect(z.span, TimelineWindow.minSpan);
    });
  });

  group('TimelineWindow clamping', () {
    final bounds = win(0, 100);

    test('leaves a window already inside alone', () {
      expect(win(10, 20).clampTo(bounds), win(10, 20));
    });

    test('slides a window off the start back in, keeping its span', () {
      final c = win(-30, -10).clampTo(bounds);
      expect(c.start, at(0));
      expect(c.span, const Duration(minutes: 20));
    });

    test('slides a window off the end back in, keeping its span', () {
      final c = win(110, 130).clampTo(bounds);
      expect(c.end, at(100));
      expect(c.span, const Duration(minutes: 20));
    });

    test('a window wider than the bounds becomes the bounds', () {
      expect(win(-50, 200).clampTo(bounds), bounds);
    });
  });

  group('laneRuns', () {
    test('one interval becomes one run at the right pixels', () {
      final runs = laneRuns(series([iv(25, 50)]), win(0, 100), 200,
          now: at(1000));
      expect(runs, hasLength(1));
      expect(runs.single.x1, 50);
      expect(runs.single.x2, 100);
      expect(runs.single.merged, 1);
      expect(runs.single.interval, isNotNull);
    });

    test('intervals outside the window are not drawn', () {
      final runs = laneRuns(
          series([iv(-50, -40), iv(200, 210)]), win(0, 100), 200,
          now: at(1000));
      expect(runs, isEmpty);
    });

    test('a sub-pixel interval is widened to the minimum, not dropped', () {
      // 6 seconds over a 100 minute window across 200px is 0.2px
      final runs = laneRuns(
          series([
            AlarmInterval(
                start: at(50),
                end: at(50).add(const Duration(seconds: 6)),
                level: AlarmLevel.error)
          ]),
          win(0, 100),
          200,
          now: at(1000));
      expect(runs, hasLength(1));
      expect(runs.single.width, minRunWidth);
    });

    test('intervals within a pixel of each other coalesce into one run', () {
      // three one-second alarms a few seconds apart, over 100 minutes
      final chatter = [
        for (var s = 0; s < 3; s++)
          AlarmInterval(
              start: at(50).add(Duration(seconds: s * 4)),
              end: at(50).add(Duration(seconds: s * 4 + 1)),
              level: AlarmLevel.warning)
      ];
      final runs =
          laneRuns(series(chatter), win(0, 100), 200, now: at(1000));
      expect(runs, hasLength(1));
      expect(runs.single.merged, 3);
      expect(runs.single.activations, 3);
      // a coalesced run cannot claim to be one interval
      expect(runs.single.interval, isNull);
    });

    test('a coalesced run reports the worst severity inside it', () {
      final mixed = [
        AlarmInterval(
            start: at(50),
            end: at(50).add(const Duration(seconds: 1)),
            level: AlarmLevel.info),
        AlarmInterval(
            start: at(50).add(const Duration(seconds: 4)),
            end: at(50).add(const Duration(seconds: 5)),
            level: AlarmLevel.error),
      ];
      final runs = laneRuns(series(mixed), win(0, 100), 200, now: at(1000));
      expect(runs.single.level, AlarmLevel.error);
    });

    test('separated intervals stay separate runs', () {
      final runs = laneRuns(series([iv(0, 10), iv(60, 70)]), win(0, 100), 200,
          now: at(1000));
      expect(runs, hasLength(2));
    });

    test('an open interval runs to now and is marked open', () {
      final runs =
          laneRuns(series([iv(20, null)], now: 60), win(0, 100), 200,
              now: at(60));
      expect(runs.single.isOpen, isTrue);
      expect(runs.single.x2, 120);
    });

    test('run count is bounded by the lane width, not the data', () {
      // 600 one-second alarms across the window: at 200px they cannot all
      // be separate runs
      final many = [
        for (var i = 0; i < 600; i++)
          AlarmInterval(
              start: at(0).add(Duration(seconds: i * 10)),
              end: at(0).add(Duration(seconds: i * 10 + 1)),
              level: AlarmLevel.warning)
      ];
      final runs = laneRuns(series(many), win(0, 100), 200, now: at(1000));
      expect(runs.length, lessThan(200));
      expect(runs.fold<int>(0, (n, r) => n + r.activations),
          greaterThan(500));
    });

    test('an empty series draws nothing', () {
      expect(laneRuns(series(const []), win(0, 100), 200, now: at(1000)),
          isEmpty);
    });

    test('a zero-width lane draws nothing', () {
      expect(laneRuns(series([iv(0, 10)]), win(0, 100), 0, now: at(1000)),
          isEmpty);
    });
  });

  group('axis ticks', () {
    test('picks a step that leaves at most nine labels', () {
      for (final span in [
        const Duration(minutes: 5),
        const Duration(hours: 1),
        const Duration(hours: 8),
        const Duration(days: 2),
      ]) {
        final step = tickStep(span);
        expect(span.inMicroseconds / step.inMicroseconds, lessThanOrEqualTo(9),
            reason: 'span $span chose step $step');
      }
    });

    test('ticks align to the clock, not to the window edge', () {
      // window starts at 06:07, so the first tick should be a round 06:10
      final w = TimelineWindow(
          base.add(const Duration(minutes: 7)),
          base.add(const Duration(minutes: 67)));
      final ticks = timelineTicks(w, 600);
      expect(ticks.first.at.minute % 10, 0);
    });

    test('whole hours are marked as hours', () {
      final ticks = timelineTicks(win(0, 180), 600);
      final hours = ticks.where((t) => t.isHour).toList();
      expect(hours, isNotEmpty);
      expect(hours.every((t) => t.at.minute == 0), isTrue);
    });

    test('every tick sits inside the lane', () {
      final ticks = timelineTicks(win(0, 180), 600);
      for (final tick in ticks) {
        expect(tick.x, inInclusiveRange(-1, 601));
      }
    });

    test('a zero-width lane has no ticks', () {
      expect(timelineTicks(win(0, 100), 0), isEmpty);
    });
  });

  paretoTests();
}

ParetoRow prow(String label, {required int minutes, required int count}) =>
    ParetoRow(
      key: label,
      label: label,
      context: null,
      level: AlarmLevel.error,
      total: Duration(minutes: minutes),
      count: count,
      isOpen: false,
    );

void paretoTests() {
  group('rankPareto', () {
    final rows = [
      prow('cheap but chronic', minutes: 3, count: 40),
      prow('expensive', minutes: 33, count: 2),
      prow('middling', minutes: 12, count: 5),
    ];

    test('by lost time finds what is expensive', () {
      expect(rankPareto(rows, byCount: false).map((r) => r.label),
          ['expensive', 'middling', 'cheap but chronic']);
    });

    test('by count finds what is chronic — a different answer', () {
      expect(rankPareto(rows, byCount: true).map((r) => r.label),
          ['cheap but chronic', 'middling', 'expensive']);
    });

    test('rows that never fired in the window are dropped', () {
      final withZero = [...rows, prow('never', minutes: 0, count: 0)];
      expect(rankPareto(withZero, byCount: false).map((r) => r.label),
          isNot(contains('never')));
    });

    test('ties break stably so the order does not flicker', () {
      final tied = [
        prow('b', minutes: 5, count: 1),
        prow('a', minutes: 5, count: 1),
      ];
      expect(rankPareto(tied, byCount: false).map((r) => r.label), ['a', 'b']);
    });
  });

  group('paretoShares', () {
    test('shares are each row over the total', () {
      final ranked = rankPareto([
        prow('a', minutes: 30, count: 1),
        prow('b', minutes: 10, count: 1),
      ], byCount: false);
      final shares = paretoShares(ranked);
      expect(shares[0].$1, closeTo(0.75, 1e-9));
      expect(shares[1].$1, closeTo(0.25, 1e-9));
    });

    test('the cumulative column runs to one', () {
      final ranked = rankPareto([
        prow('a', minutes: 30, count: 1),
        prow('b', minutes: 10, count: 1),
        prow('c', minutes: 10, count: 1),
      ], byCount: false);
      final shares = paretoShares(ranked);
      expect(shares[0].$2, closeTo(0.6, 1e-9));
      expect(shares.last.$2, closeTo(1.0, 1e-9));
    });

    test('shares sum to one', () {
      final ranked = rankPareto([
        for (var i = 1; i <= 7; i++) prow('r$i', minutes: i * 3, count: i),
      ], byCount: false);
      final sum = paretoShares(ranked).fold<double>(0, (n, s) => n + s.$1);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('all-zero totals do not divide by zero', () {
      final shares = paretoShares([prow('a', minutes: 0, count: 1)]);
      expect(shares.single.$1, 0);
    });
  });
}

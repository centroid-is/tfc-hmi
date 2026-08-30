import 'package:test/test.dart';
import 'package:tfc_dart/core/alarm.dart' show AlarmLevel;
import 'package:tfc_dart/core/alarm_interval.dart';

/// 2026-08-29 06:00 local, the sample day the design mockup uses.
final base = DateTime(2026, 8, 29, 6);
DateTime at(int minutes) => base.add(Duration(minutes: minutes));

AlarmInterval iv(int from, int? to,
        {AlarmLevel level = AlarmLevel.error, int count = 1}) =>
    AlarmInterval(
        start: at(from),
        end: to == null ? null : at(to),
        level: level,
        count: count);

void main() {
  group('AlarmLevel severity', () {
    test('orders error above warning above info', () {
      expect(AlarmLevel.error.severity, greaterThan(AlarmLevel.warning.severity));
      expect(AlarmLevel.warning.severity, greaterThan(AlarmLevel.info.severity));
    });

    test('worst picks the higher severity either way round', () {
      expect(AlarmLevel.info.worst(AlarmLevel.error), AlarmLevel.error);
      expect(AlarmLevel.error.worst(AlarmLevel.info), AlarmLevel.error);
      expect(AlarmLevel.warning.worst(AlarmLevel.warning), AlarmLevel.warning);
    });
  });

  group('AlarmInterval', () {
    test('an open interval ends at now', () {
      final open = iv(10, null);
      expect(open.isOpen, isTrue);
      expect(open.endAt(at(25)), at(25));
    });

    test('a closed interval ignores now', () {
      final closed = iv(10, 20);
      expect(closed.isOpen, isFalse);
      expect(closed.endAt(at(999)), at(20));
    });
  });

  group('mergeIntervals', () {
    test('leaves disjoint intervals alone, sorted by start', () {
      final merged = mergeIntervals([iv(30, 40), iv(0, 10)], now: at(100));
      expect(merged.map((e) => e.start), [at(0), at(30)]);
      expect(merged.map((e) => e.end), [at(10), at(40)]);
    });

    test('unions overlapping intervals and sums their counts', () {
      final merged = mergeIntervals([iv(0, 20), iv(10, 30)], now: at(100));
      expect(merged, hasLength(1));
      expect(merged.single.start, at(0));
      expect(merged.single.end, at(30));
      expect(merged.single.count, 2);
    });

    test('a contained interval does not shorten the one containing it', () {
      final merged = mergeIntervals([iv(0, 60), iv(10, 20)], now: at(100));
      expect(merged.single.end, at(60));
    });

    test('touching intervals merge', () {
      final merged = mergeIntervals([iv(0, 10), iv(10, 20)], now: at(100));
      expect(merged, hasLength(1));
      expect(merged.single.end, at(20));
    });

    test('a merged interval takes the worst severity inside it', () {
      final merged = mergeIntervals([
        iv(0, 20, level: AlarmLevel.info),
        iv(10, 30, level: AlarmLevel.error),
        iv(15, 25, level: AlarmLevel.warning),
      ], now: at(100));
      expect(merged.single.level, AlarmLevel.error);
    });

    test('an open interval keeps the result open and runs to now', () {
      final merged = mergeIntervals([iv(0, 20), iv(10, null)], now: at(40));
      expect(merged, hasLength(1));
      expect(merged.single.isOpen, isTrue);
      expect(merged.single.endAt(at(40)), at(40));
    });

    test('an open interval swallows a closed one it overlaps', () {
      final merged = mergeIntervals([iv(10, null), iv(20, 30)], now: at(60));
      expect(merged, hasLength(1));
      expect(merged.single.isOpen, isTrue);
    });

    test('empty in, empty out', () {
      expect(mergeIntervals(const [], now: at(0)), isEmpty);
    });
  });

  group('AlarmIntervalSeries statistics', () {
    // three ten-minute intervals at 0-10, 30-40 and 60-70
    final series = AlarmIntervalSeries(
        [iv(0, 10), iv(30, 40), iv(60, 70)],
        now: at(200));

    test('totals a window that covers everything', () {
      final s = series.statsIn(at(-10), at(100));
      expect(s.total, const Duration(minutes: 30));
      expect(s.count, 3);
      expect(s.isOpen, isFalse);
    });

    test('clips intervals at both window edges', () {
      // 5-35 catches half of the first and half of the second
      final s = series.statsIn(at(5), at(35));
      expect(s.total, const Duration(minutes: 10));
      expect(s.count, 2);
    });

    test('a window inside one interval reports just that slice', () {
      final s = series.statsIn(at(2), at(6));
      expect(s.total, const Duration(minutes: 4));
      expect(s.count, 1);
    });

    test('a window in a gap reports nothing', () {
      final s = series.statsIn(at(15), at(25));
      expect(s.total, Duration.zero);
      expect(s.count, 0);
    });

    test('a window past the end reports nothing', () {
      expect(series.statsIn(at(500), at(600)).count, 0);
    });

    test('an empty series reports nothing', () {
      final empty = AlarmIntervalSeries(const [], now: at(0));
      expect(empty.statsIn(at(0), at(100)).total, Duration.zero);
      expect(empty.statsIn(at(0), at(100)).count, 0);
    });

    test('the prefix-sum path agrees with a naive sum over many intervals', () {
      // 200 intervals, one minute long, every five minutes
      final many = AlarmIntervalSeries(
          [for (var i = 0; i < 200; i++) iv(i * 5, i * 5 + 1)],
          now: at(5000));
      for (final window in [
        [7, 333],
        [0, 1000],
        [12, 13],
        [498, 502],
      ]) {
        final from = at(window[0]), to = at(window[1]);
        var naive = Duration.zero;
        for (var i = 0; i < 200; i++) {
          final s = at(i * 5), e = at(i * 5 + 1);
          final lo = s.isAfter(from) ? s : from;
          final hi = e.isBefore(to) ? e : to;
          if (hi.isAfter(lo)) naive += hi.difference(lo);
        }
        expect(many.statsIn(from, to).total, naive,
            reason: 'window ${window[0]}..${window[1]}');
      }
    });
  });

  group('AlarmIntervalSeries with an open interval', () {
    test('an open interval is measured up to now', () {
      final series = AlarmIntervalSeries([iv(0, 10), iv(50, null)], now: at(70));
      final s = series.statsIn(at(0), at(100));
      expect(s.total, const Duration(minutes: 30)); // 10 + (70-50)
      expect(s.isOpen, isTrue);
    });

    test('now advancing lengthens the open interval', () {
      final ivs = [iv(50, null)];
      expect(AlarmIntervalSeries(ivs, now: at(60)).statsIn(at(0), at(100)).total,
          const Duration(minutes: 10));
      expect(AlarmIntervalSeries(ivs, now: at(90)).statsIn(at(0), at(100)).total,
          const Duration(minutes: 40));
    });

    test('a window ending before now clips the open interval', () {
      final series = AlarmIntervalSeries([iv(50, null)], now: at(90));
      expect(series.statsIn(at(0), at(60)).total, const Duration(minutes: 10));
    });
  });

  group('excluded (unscheduled) time', () {
    // one long interval 0-60 with a 20-30 break excluded from the clock
    final series = AlarmIntervalSeries([iv(0, 60)],
        now: at(200), excluded: [TimeRange(at(20), at(30))]);

    test('is subtracted from the total', () {
      expect(series.statsIn(at(0), at(60)).total, const Duration(minutes: 50));
    });

    test('is subtracted only where it overlaps the window', () {
      expect(series.statsIn(at(0), at(25)).total, const Duration(minutes: 20));
    });

    test('does not change the activation count', () {
      expect(series.statsIn(at(0), at(60)).count, 1);
    });

    test('scheduledBetween removes excluded time from a plain window', () {
      expect(series.scheduledBetween(at(0), at(60)),
          const Duration(minutes: 50));
      expect(series.scheduledBetween(at(0), at(10)),
          const Duration(minutes: 10));
    });
  });

  group('AlarmIntervalSeries.sliceIn', () {
    final series = AlarmIntervalSeries(
        [iv(0, 10), iv(30, 40), iv(60, 70)],
        now: at(200));

    test('returns the index range that overlaps the window', () {
      expect(series.sliceIn(at(-5), at(100)), (0, 2));
      expect(series.sliceIn(at(32), at(38)), (1, 1));
      expect(series.sliceIn(at(5), at(35)), (0, 1));
    });

    test('returns an empty range for a gap', () {
      final (lo, hi) = series.sliceIn(at(15), at(25));
      expect(hi, lessThan(lo));
    });

    test('an interval merely touching the window edge is excluded', () {
      // the first interval ends exactly at 10, so a window starting at 10
      // begins after it
      final (lo, _) = series.sliceIn(at(10), at(20));
      expect(lo, 1);
    });
  });
}

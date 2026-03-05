import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/helper/timeseries_cache.dart';

void main() {
  late TimeseriesCache cache;

  setUp(() {
    cache = TimeseriesCache();
  });

  group('TimeseriesCache', () {
    test('empty cache returns 0 for countSince', () {
      cache.init(['a']);
      final since = DateTime.now().subtract(const Duration(minutes: 5));
      expect(cache.countSince('a', since), 0);
    });

    test('addTimestamp adds to correct key', () {
      cache.init(['a', 'b']);
      final t = DateTime.now();
      cache.addTimestamp('a', t);
      expect(cache.timestamps('a'), {t});
      expect(cache.timestamps('b'), isEmpty);
    });

    test('addAll bulk loads timestamps for a key', () {
      cache.init(['a']);
      final times = List.generate(
          5, (i) => DateTime.now().subtract(Duration(seconds: i)));
      cache.addAll('a', times);
      expect(cache.timestamps('a').length, 5);
    });

    test('countSince counts only timestamps after cutoff', () {
      cache.init(['a']);
      final now = DateTime.now();
      cache.addAll('a', [
        now.subtract(const Duration(minutes: 10)),
        now.subtract(const Duration(minutes: 3)),
        now.subtract(const Duration(minutes: 1)),
        now,
      ]);
      final since = now.subtract(const Duration(minutes: 5));
      // minutes 3, 1, and 0 are after 5-minute cutoff
      expect(cache.countSince('a', since), 3);
    });

    test('countSince with exact boundary (isAfter is exclusive)', () {
      cache.init(['a']);
      final boundary = DateTime(2025, 1, 1, 12, 0, 0);
      cache.addAll('a', [
        boundary, // exactly on boundary — isAfter is exclusive, so NOT counted
        boundary.add(const Duration(seconds: 1)),
      ]);
      expect(cache.countSince('a', boundary), 1);
    });

    test('prune removes timestamps older than max window', () {
      cache.init(['a']);
      final now = DateTime.now();
      cache.addAll('a', [
        now.subtract(const Duration(minutes: 20)),
        now.subtract(const Duration(minutes: 3)),
        now,
      ]);
      cache.prune(5);
      expect(cache.timestamps('a').length, 2);
    });

    test('prune preserves recent timestamps', () {
      cache.init(['a']);
      final now = DateTime.now();
      final recent = now.subtract(const Duration(seconds: 30));
      cache.addTimestamp('a', recent);
      cache.prune(1);
      expect(cache.timestamps('a'), {recent});
    });

    test('multiple keys are independent', () {
      cache.init(['x', 'y']);
      final now = DateTime.now();
      cache.addTimestamp('x', now);
      cache.addTimestamp('y', now.subtract(const Duration(minutes: 1)));
      expect(cache.timestamps('x').length, 1);
      expect(cache.timestamps('y').length, 1);
      cache.clearKey('x');
      expect(cache.timestamps('x'), isEmpty);
      expect(cache.timestamps('y').length, 1);
    });

    test('duplicate timestamps are deduplicated (Set semantics)', () {
      cache.init(['a']);
      final t = DateTime(2025, 6, 15, 10, 30, 0);
      cache.addTimestamp('a', t);
      cache.addTimestamp('a', t);
      cache.addAll('a', [t, t, t]);
      expect(cache.timestamps('a').length, 1);
    });

    test('clear removes all data', () {
      cache.init(['a', 'b']);
      final now = DateTime.now();
      cache.addTimestamp('a', now);
      cache.addTimestamp('b', now);
      cache.clear();
      expect(cache.timestamps('a'), isEmpty);
      expect(cache.timestamps('b'), isEmpty);
    });

    test('clearKey removes only one key', () {
      cache.init(['a', 'b']);
      final now = DateTime.now();
      cache.addTimestamp('a', now);
      cache.addTimestamp('b', now);
      cache.clearKey('a');
      expect(cache.timestamps('a'), isEmpty);
      expect(cache.timestamps('b').length, 1);
    });

    test('countSince on unknown key returns 0', () {
      expect(cache.countSince('nonexistent', DateTime.now()), 0);
    });

    test('prune with changing maxMinutes', () {
      cache.init(['a']);
      final now = DateTime.now();
      cache.addAll('a', [
        now.subtract(const Duration(minutes: 15)),
        now.subtract(const Duration(minutes: 8)),
        now.subtract(const Duration(minutes: 3)),
        now,
      ]);
      // Prune at 20min — all survive
      cache.prune(20);
      expect(cache.timestamps('a').length, 4);
      // Prune at 10min — drops 15min-old
      cache.prune(10);
      expect(cache.timestamps('a').length, 3);
      // Prune at 5min — drops 8min-old too
      cache.prune(5);
      expect(cache.timestamps('a').length, 2);
    });

    test('addTimestamp on uninitialized key auto-creates it', () {
      final t = DateTime.now();
      cache.addTimestamp('new_key', t);
      expect(cache.timestamps('new_key'), {t});
    });

    test('addAll on uninitialized key auto-creates it', () {
      final times = [DateTime.now(), DateTime.now()];
      cache.addAll('new_key', times);
      expect(cache.timestamps('new_key').length, 1); // same instant → 1
    });
  });
}

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

  group('oldestAfter', () {
    test('returns null for empty cache', () {
      cache.init(['a']);
      final since = DateTime.now().subtract(const Duration(minutes: 5));
      expect(cache.oldestAfter(['a'], since), isNull);
    });

    test('returns null when all events are before cutoff', () {
      cache.init(['a']);
      final now = DateTime.now();
      cache.addAll('a', [
        now.subtract(const Duration(minutes: 10)),
        now.subtract(const Duration(minutes: 8)),
      ]);
      expect(cache.oldestAfter(['a'], now.subtract(const Duration(minutes: 5))), isNull);
    });

    test('returns oldest event after cutoff across keys', () {
      cache.init(['a', 'b']);
      final now = DateTime.now();
      final oldest = now.subtract(const Duration(minutes: 4));
      final newer = now.subtract(const Duration(minutes: 2));
      cache.addTimestamp('a', newer);
      cache.addTimestamp('b', oldest);
      cache.addTimestamp('b', now.subtract(const Duration(minutes: 8))); // before cutoff
      final result = cache.oldestAfter(['a', 'b'], now.subtract(const Duration(minutes: 5)));
      expect(result, oldest);
    });

    test('expiry delay matches when oldest event ages out of window', () {
      cache.init(['a']);
      final now = DateTime(2026, 3, 5, 12, 0, 0);
      final oldest = now.subtract(const Duration(minutes: 4, seconds: 30));
      cache.addTimestamp('a', oldest);
      cache.addTimestamp('a', now.subtract(const Duration(minutes: 1)));

      final result = cache.oldestAfter(['a'], now.subtract(const Duration(minutes: 5)));
      expect(result, oldest);
      // oldest expires from a 5-min window in 30 seconds
      final expiresAt = oldest.add(const Duration(minutes: 5));
      expect(expiresAt.difference(now).inSeconds, 30);
    });
  });

  group('Value cache', () {
    test('addEntry stores value alongside timestamp', () {
      cache.init(['a']);
      final t = DateTime.now();
      cache.addEntry('a', t, 42.5);
      expect(cache.latestValue('a'), (t, 42.5));
    });

    test('addEntries bulk adds from TimeseriesData-like list', () {
      cache.init(['a']);
      final now = DateTime.now();
      final entries = [
        (now.subtract(const Duration(seconds: 3)), 10),
        (now.subtract(const Duration(seconds: 2)), 20),
        (now.subtract(const Duration(seconds: 1)), 30),
      ];
      cache.addEntries('a', entries);
      // latestValue returns the most recent
      expect(cache.latestValue('a')?.$2, 30);
    });

    test('latestValue returns most recent entry', () {
      cache.init(['a']);
      final t1 = DateTime(2026, 1, 1, 12, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 0, 5);
      final t3 = DateTime(2026, 1, 1, 12, 0, 10);
      cache.addEntry('a', t1, 'first');
      cache.addEntry('a', t3, 'third');
      cache.addEntry('a', t2, 'second');
      final result = cache.latestValue('a');
      expect(result?.$1, t3);
      expect(result?.$2, 'third');
    });

    test('latestValue returns null for empty key', () {
      cache.init(['a']);
      expect(cache.latestValue('a'), isNull);
    });

    test('latestValue returns null for unknown key', () {
      expect(cache.latestValue('nonexistent'), isNull);
    });

    test('valuesSince returns entries after boundary', () {
      cache.init(['a']);
      final t1 = DateTime(2026, 1, 1, 12, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 3, 0);
      final t3 = DateTime(2026, 1, 1, 12, 5, 0);
      cache.addEntry('a', t1, 100);
      cache.addEntry('a', t2, 200);
      cache.addEntry('a', t3, 300);
      final boundary = DateTime(2026, 1, 1, 12, 2, 0);
      final results = cache.valuesSince('a', boundary);
      expect(results.length, 2);
      expect(results.first.$2, 200);
      expect(results.last.$2, 300);
    });

    test('valuesSince returns empty for unknown key', () {
      expect(cache.valuesSince('nonexistent', DateTime.now()), isEmpty);
    });

    test('sumSince sums numeric values after boundary', () {
      cache.init(['a']);
      final t1 = DateTime(2026, 1, 1, 12, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 3, 0);
      final t3 = DateTime(2026, 1, 1, 12, 5, 0);
      cache.addEntry('a', t1, 10.0);
      cache.addEntry('a', t2, 20.0);
      cache.addEntry('a', t3, 30.0);
      final boundary = DateTime(2026, 1, 1, 12, 2, 0);
      // t2 + t3 = 50.0
      expect(cache.sumSince('a', boundary), 50.0);
    });

    test('sumSince returns 0 for empty/unknown key', () {
      expect(cache.sumSince('nonexistent', DateTime.now()), 0.0);
      cache.init(['a']);
      expect(cache.sumSince('a', DateTime.now().subtract(const Duration(hours: 1))), 0.0);
    });

    test('sumSince handles string numeric values', () {
      cache.init(['a']);
      final t1 = DateTime(2026, 1, 1, 12, 1, 0);
      final t2 = DateTime(2026, 1, 1, 12, 2, 0);
      cache.addEntry('a', t1, '15.5');
      cache.addEntry('a', t2, '4.5');
      final boundary = DateTime(2026, 1, 1, 12, 0, 0);
      expect(cache.sumSince('a', boundary), 20.0);
    });

    test('prune also removes old values', () {
      cache.init(['a']);
      final now = DateTime.now();
      cache.addEntry('a', now.subtract(const Duration(minutes: 20)), 'old');
      cache.addEntry('a', now.subtract(const Duration(minutes: 3)), 'recent');
      cache.addEntry('a', now, 'now');
      cache.prune(5);
      final all = cache.valuesSince(
          'a', now.subtract(const Duration(minutes: 30)));
      expect(all.length, 2);
    });

    test('clearKey clears values too', () {
      cache.init(['a', 'b']);
      final now = DateTime.now();
      cache.addEntry('a', now, 1);
      cache.addEntry('b', now, 2);
      cache.clearKey('a');
      expect(cache.latestValue('a'), isNull);
      expect(cache.latestValue('b'), isNotNull);
    });

    test('clear clears all values', () {
      cache.init(['a', 'b']);
      final now = DateTime.now();
      cache.addEntry('a', now, 1);
      cache.addEntry('b', now, 2);
      cache.clear();
      expect(cache.latestValue('a'), isNull);
      expect(cache.latestValue('b'), isNull);
    });

    test('addEntry auto-creates key if missing', () {
      final t = DateTime.now();
      cache.addEntry('new_key', t, 99);
      expect(cache.latestValue('new_key'), (t, 99));
    });

    test('existing countSince/addTimestamp still work (no regression)', () {
      cache.init(['a']);
      final now = DateTime.now();
      cache.addTimestamp('a', now);
      cache.addTimestamp('a', now.subtract(const Duration(minutes: 1)));
      final since = now.subtract(const Duration(minutes: 2));
      expect(cache.countSince('a', since), 2);
      // Value cache should be empty — addTimestamp doesn't add values
      expect(cache.latestValue('a'), isNull);
    });
  });

  group('NOTIFY failure regression', () {
    // Reproduces production bug: BPM widgets with broken NOTIFY show
    // decaying counts because the refresh timer only prunes — never
    // re-fetches from DB.
    //
    // Production evidence (debug.log):
    //   weigher1v: cache=20 forever, count: 15→13→11→9→8→7
    //   batcher1:  cache≈160 declining, count: 29→26→22→18→15
    //   (healthy weigher4v: cache fluctuates 183-185, count stable)

    test('stale cache count decays to zero without re-fetch', () {
      // Matches production: initial fetch = 20 events, then nothing.
      const key = 'weigher1v.acceptWeight';
      cache.init([key]);

      final t0 = DateTime(2026, 3, 5, 12, 0, 0);
      for (var i = 0; i < 20; i++) {
        cache.addTimestamp(key, t0.subtract(Duration(seconds: i * 15)));
      }
      expect(cache.countSince(key, t0.subtract(const Duration(minutes: 5))), 20);

      // --- Only prune runs (no NOTIFY, no re-fetch) ---

      // 2 min later: 8 events aged out of 5-min window (120s / 15s)
      cache.prune(60);
      expect(cache.countSince(
        key,
        t0.add(const Duration(minutes: 2)).subtract(const Duration(minutes: 5)),
      ), 12);

      // 4 min later: only 4 remain
      expect(cache.countSince(
        key,
        t0.add(const Duration(minutes: 4)).subtract(const Duration(minutes: 5)),
      ), 4);

      // 6 min later: all gone
      expect(cache.countSince(
        key,
        t0.add(const Duration(minutes: 6)).subtract(const Duration(minutes: 5)),
      ), 0);
    });

    test('periodic re-fetch keeps count healthy', () {
      // After fix: refresh timer re-fetches from DB every 30s.
      // Even without NOTIFY, fresh data enters the cache.
      const key = 'weigher1v.acceptWeight';
      cache.init([key]);

      final t0 = DateTime(2026, 3, 5, 12, 0, 0);
      for (var i = 0; i < 20; i++) {
        cache.addTimestamp(key, t0.subtract(Duration(seconds: i * 15)));
      }
      expect(cache.countSince(key, t0.subtract(const Duration(minutes: 5))), 20);

      // 3 min later: re-fetch adds 12 new events (machine rate ~4/min)
      final t3 = t0.add(const Duration(minutes: 3));
      for (var i = 0; i < 12; i++) {
        cache.addTimestamp(key, t3.subtract(Duration(seconds: i * 15)));
      }
      cache.prune(60);

      final count = cache.countSince(
        key,
        t3.subtract(const Duration(minutes: 5)),
      );
      // With re-fetched data, count stays healthy
      expect(count, greaterThanOrEqualTo(16));
    });
  });
}

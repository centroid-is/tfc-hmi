// The cache is filled from two sources describing the same rows: the
// historical query, whose DateTimes come from the driver, and NOTIFY
// payloads, parsed from the trigger's JSON. `DateTime.==` is false for the
// same instant in different zones, so without normalising, a row that arrived
// both ways counted twice — and the reconciling sweep, which merges the
// database's view over the cache's, would re-add every row it checked.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/helper/timeseries_cache.dart';

void main() {
  const key = 'line/packs';
  final instant = DateTime.utc(2026, 8, 30, 10, 15, 30, 123, 456);

  test('the same instant in UTC and local time is one row', () {
    final cache = TimeseriesCache()..init([key]);

    expect(cache.addTimestamp(key, instant), isTrue);
    expect(cache.addTimestamp(key, instant.toLocal()), isFalse);

    expect(
        cache.countSince(key, instant.subtract(const Duration(hours: 1))), 1);
    expect(cache.contains(key, instant.toLocal()), isTrue);
  });

  test('addAll reports only what was new', () {
    final cache = TimeseriesCache()..init([key]);
    final later = instant.add(const Duration(seconds: 1));

    expect(cache.addAll(key, [instant]), 1);
    expect(cache.addAll(key, [instant.toLocal(), later, later.toLocal()]), 1);
    expect(cache.timestamps(key), hasLength(2));
  });

  test('values are keyed by the same normalised instant', () {
    final cache = TimeseriesCache()..init([key]);

    expect(cache.addEntry(key, instant, 1), isTrue);
    expect(cache.addEntries(key, [(instant.toLocal(), 2)]), 0);

    expect(cache.timestamps(key), hasLength(1));
    expect(cache.sumSince(key, instant.subtract(const Duration(hours: 1))), 2,
        reason: 'the later write wins, not both');
    expect(cache.latestValue(key)?.$2, 2);
  });

  test('contains is false for a key never seen', () {
    final cache = TimeseriesCache();
    expect(cache.contains('nope', instant), isFalse);
  });
}

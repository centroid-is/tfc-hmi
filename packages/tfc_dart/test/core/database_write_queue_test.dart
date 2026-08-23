import 'dart:async';

import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';

import 'fake_write_backend.dart';

/// What happens to samples produced while the database is unreachable.
///
/// Before this, the answer was: all but the last hundred per table were thrown
/// away, oldest first, and the only trace was a `logger.w` in the acquisition
/// isolate — which package:logger's default filter drops entirely unless
/// asserts are enabled, so in production there was no trace at all.
/// `getStats()` reported writes and waits and nothing about discards, and a
/// grep for tests of the overflow path returned nothing.
///
/// Oldest-first is the worst possible choice of victim: it discards the
/// *beginning* of the incident, which is the part anybody investigating the
/// outage would want.
void main() {
  late FakeWriteBackend backend;
  late Database db;

  // A simulated outage produces one "batch failed, retrying" line per flush,
  // which drowns the test output. The assertions here are on the counters;
  // the one test that cares about the log turns it back on for itself.
  final realLevel = Logger.level;
  setUpAll(() => Logger.level = Level.off);
  tearDownAll(() => Logger.level = realLevel);

  setUp(() {
    backend = FakeWriteBackend();
    db = Database(backend);
  });

  tearDown(() => db.close());

  /// Produce [n] samples with value 1..n while the backend is down.
  Future<void> produceDuringOutage(String table, int n) async {
    backend.down = true;
    for (var i = 1; i <= n; i++) {
      await db.insertTimeseriesData(
          table, DateTime.utc(2026).add(Duration(seconds: i)), i.toDouble());
    }
    await db.flush();
  }

  /// Let the five-second retry loop drain the queue after recovery.
  Future<void> recoverAndDrain() async {
    backend.down = false;
    await Future<void>.delayed(const Duration(seconds: 7));
    await db.flush();
    await Future<void>.delayed(const Duration(seconds: 7));
  }

  group('an outage shorter than the buffer', () {
    test('loses nothing — 300 samples across an outage all arrive', () async {
      // The exact case that was measured against a real TimescaleDB and came
      // back count=100, minv=201, maxv=300: two hundred rows gone, and the two
      // hundred that went were the first two hundred.
      await produceDuringOutage('t', 300);
      await recoverAndDrain();

      final values = backend.storedValues;
      expect(values, hasLength(300));
      expect(values.reduce((a, b) => a < b ? a : b), 1,
          reason: 'The start of the outage is the part that used to be '
              'discarded, and the part worth having.');
      expect(values.reduce((a, b) => a > b ? a : b), 300);
      expect(db.getStats()['dropped_rows'], 0);
    });
  });

  group('an outage longer than the buffer', () {
    test('counts every row it discards, per table', () async {
      // Deliberately over the per-table cap so trimming has to happen.
      const produced = 10000 + 250;
      await produceDuringOutage('t', produced);

      final stats = db.getStats();
      expect(stats['dropped_rows'], greaterThan(0),
          reason: 'Rows were discarded; the count must say so.');
      expect(stats['dropped_rows_by_table'], contains('t'));
      expect(stats['dropped_rows'] as int, produced - db.queuedRowCount,
          reason: 'Every row is either still queued or counted as dropped. '
              'A row that is neither is a row that vanished.');
    });

    test('keeps the cap it advertises', () async {
      await produceDuringOutage('t', 10000 + 250);
      expect(db.queuedRowCount, lessThanOrEqualTo(10000));
      expect(db.getStats()['max_queued_rows_per_table'], 10000);
    });

    test('the surviving rows are the newest, and are contiguous', () async {
      const produced = 10000 + 250;
      await produceDuringOutage('t', produced);
      await recoverAndDrain();

      final values = backend.storedValues;
      expect(values, isNotEmpty);
      final lowest = values.reduce((a, b) => a < b ? a : b);
      final highest = values.reduce((a, b) => a > b ? a : b);
      expect(highest, produced);
      expect(values.length, highest - lowest + 1,
          reason: 'Trimming must take a prefix, not punch holes.');
    });
  });

  group('the queue depth is visible before anything is lost', () {
    test('getStats reports what is waiting, per table', () async {
      await produceDuringOutage('t', 120);
      final stats = db.getStats();
      expect(stats['queued_rows'], 120);
      expect(stats['queued_rows_by_table'], {'t': 120});
      expect(stats['dropped_rows'], 0,
          reason: 'Nothing lost yet — this is the warning, not the funeral.');
    });

    test('depth returns to zero once the outage ends', () async {
      await produceDuringOutage('t', 120);
      await recoverAndDrain();
      expect(db.getStats()['queued_rows'], 0);
    });
  });

  group('the global cap', () {
    test('is reported', () {
      expect(db.getStats()['max_queued_rows_total'], 200000);
    });

    test('a discard is announced at error level, with the table and a total',
        () async {
      // The original discard sites logged at *warning*, one line per row, in
      // the middle of the "database is down, retrying" chatter — the same
      // level and the same place as the noise. Nobody finds that.
      Logger.level = Level.trace;
      final lines = <String>[];
      try {
        await runZoned(
          () async => produceDuringOutage('t', 10000 + 10),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => lines.add(line),
          ),
        );
      } finally {
        Logger.level = Level.off;
      }
      final lost = lines.where((l) => l.contains('DATA LOST')).toList();
      expect(lost, isNotEmpty,
          reason: 'A discard the operator cannot see is the whole defect.');
      expect(lost.join('\n'), contains('"t"'),
          reason: 'It has to say which tag stopped recording.');
      expect(lost.join('\n'), contains('Total discarded for this table:'),
          reason: 'A running total, so one line shows the scale.');
    });

    test('a stats reset does not erase a record of lost data', () async {
      await produceDuringOutage('t', 10000 + 250);
      final dropped = db.getStats()['dropped_rows'] as int;
      expect(dropped, greaterThan(0));
      db.resetStats();
      expect(db.getStats()['dropped_rows'], dropped,
          reason: 'Those rows are gone from the world. A UI convenience must '
              'not be able to clear the evidence.');
      expect(db.getStats()['total_writes'], 0, reason: 'but writes do reset');
    });
  });
}

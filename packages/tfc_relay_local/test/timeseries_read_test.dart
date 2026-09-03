/// The four timeseries methods against a **real TimescaleDB** — the read leg.
///
/// 8b's `db` lane, not a second one: the same tag, the same env-addressed
/// fixture, the same CI step. Every table name carries a per-run random suffix
/// and every case drops what it created, so a Phase 10 read case and an 8b
/// `side_by_side_test.dart` case can share one database without either seeing
/// the other's rows.
///
/// Seeding goes through a bare `Database` doing `registerRetentionPolicy` then
/// `insertTimeseriesData` into the **prefixed** name — literally what
/// `TimescaleSink` does per entry, and the reason the rows here have the
/// shapes 8b-03 measured (a scalar table is `("value", "time")`; a struct
/// table is one column per named member plus `time`).
///
/// **Nothing in this file writes through the reader**, and nothing can: the
/// reader has no insert path and no retention path, which `freeze_test.dart`
/// asserts by sweeping `lib/src/data/`.
@TestOn('vm')
@Tags(['db'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:math';

import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_relay_local/src/data/timescale_reader.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart'
    show ResolvedSeries, SeriesAddress, SeriesResolver;

import 'support/timescale_fixture.dart';

late TimescaleFixture fx;
late pg.Connection admin;

/// The per-run suffix every table name carries.
final String suffix =
    Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');

final Set<String> createdTables = <String>{};
final List<Database> writers = <Database>[];

const RetentionPolicy keepEverything =
    RetentionPolicy(dropAfter: Duration.zero);

int _serial = 0;

/// A name no other case in this run will use.
///
/// The serial is not decoration: several cases in a group seed the same
/// logical series from `setUp`, and a name that was only unique per RUN would
/// have each case appending to the previous one's rows — which reads as a
/// query returning twice what it should rather than as a fixture reusing a
/// table.
String freshTable(String base) {
  final name = 'gw_${base}_${suffix}_${_serial++}';
  createdTables.add(name);
  return name;
}

DatabaseConfig dbConfig() => DatabaseConfig(
      postgres: pg.Endpoint(
        host: fx.host,
        port: fx.port,
        database: fx.database,
        username: fx.username,
        password: fx.password,
      ),
      sslMode: pg.SslMode.disable,
      connectTimeout: const Duration(seconds: 5),
      // **Set explicitly, and this is the first of the three bounds.** A
      // badly-planned query dies in the database rather than in a send
      // buffer; `DatabaseConfig.queryTimeout` (database.dart:107, default at
      // :129) is threaded to the pool by drift at database_drift.dart:503 and
      // :552. Five seconds here because every window in this file is minutes
      // wide over tens of rows.
      queryTimeout: const Duration(seconds: 5),
      applicationName: 'relay-read-test',
    );

Future<Database> openWriter() async {
  final db = Database(await AppDatabase.create(dbConfig()));
  await db.open();
  writers.add(db);
  return db;
}

/// The resolver the reader is given: the plan, expressed directly. A wire
/// name is a plant key; the table is what the collection plan computed.
final class FixtureResolver implements SeriesResolver {
  FixtureResolver(this._tables);

  final Map<String, String> _tables;

  @override
  ResolvedSeries? resolve(String wireName) {
    final address = SeriesAddress.parse(wireName);
    final table = _tables[address.series];
    if (table == null) return null;
    return ResolvedSeries(
        table: table, member: address.member, plantKey: address.series);
  }

  @override
  String? keyForTable(String table) => _tables.entries
      .where((e) => e.value == table)
      .map((e) => e.key)
      .firstOrNull;

  @override
  String? keyForNode(String nodeId) => null;
}

/// The instant every window in this file is anchored on — fixed, so a case
/// measures rows rather than the machine's idea of now.
final DateTime anchor = DateTime.utc(2026, 9, 3, 12);

Future<void> seed(Database db, String table, List<(DateTime, Object?)> rows,
    {bool complex = false}) async {
  await db.registerRetentionPolicy(table, keepEverything);
  for (final (time, value) in rows) {
    await db.insertTimeseriesData(table, time, value);
  }
  await db.flush();
}

void main() {
  setUpAll(() async {
    fx = await TimescaleFixture.start();
    admin = await fx.connect();
  });

  tearDownAll(() async {
    for (final db in writers) {
      try {
        await db.close();
      } catch (_) {
        // A writer already closed by its own case is not a failure here.
      }
    }
    for (final table in createdTables) {
      await admin.execute('DROP TABLE IF EXISTS "$table" CASCADE');
    }
    await admin.close();
    await fx.stop();
  });

  group('a scalar series', () {
    late String table;
    late Database db;
    late TimescaleReader reader;

    setUp(() async {
      table = freshTable('speed');
      db = await openWriter();
      reader = TimescaleReader(
        database: () => db,
        resolver: FixtureResolver({'Line1.Motor1': table}),
      );
      await seed(db, table, [
        for (var i = 0; i < 10; i++)
          (anchor.subtract(Duration(minutes: 10 - i)), 1400 + i * 10),
      ]);
    });

    test('rows inside the window come back oldest first, num, UTC', () async {
      final samples = await reader.queryTimeseriesData('Line1.Motor1', anchor,
          from: anchor.subtract(const Duration(minutes: 11)));

      expect(samples, hasLength(10));
      expect(samples.map((s) => s.value), [
        for (var i = 0; i < 10; i++) 1400 + i * 10,
      ]);
      expect(samples.every((s) => s.value is num), isTrue,
          reason: 'the wire\'s sample type is num, and the client decodes '
              'every point as TimeseriesData<num>');
      expect(samples.every((s) => s.time.isUtc), isTrue,
          reason: 'an instant that is not absolute puts a chart an hour out '
              'twice a year, silently');
      expect(samples.first.time.isBefore(samples.last.time), isTrue);
    });

    test('a window that contains nothing is empty, not an error', () async {
      final samples = await reader.queryTimeseriesData('Line1.Motor1',
          anchor.subtract(const Duration(days: 30)),
          from: anchor.subtract(const Duration(days: 31)));

      expect(samples, isEmpty,
          reason: 'a chart scrolled past the start of the data does this on '
              'every frame of the scroll');
    });

    test('downsampled honours maxPoints and reaches both ends of the window',
        () async {
      final samples = await reader.queryTimeseriesDataDownsampled(
          'Line1.Motor1', anchor.subtract(const Duration(minutes: 11)), anchor,
          maxPoints: 9);

      expect(samples, isNotEmpty);
      expect(samples.length, lessThanOrEqualTo(9 + 3),
          reason: 'three points per bucket (min, max, last) and '
              '(maxPoints / 3).floor() buckets — the shipped arithmetic, '
              'with one bucket of slack for the boundary');
      final values = samples.map((s) => (s.value as num)).toList();
      expect(values.reduce(min), 1400,
          reason: 'the oldest sample must survive downsampling: a chart '
              'whose left edge is missing is a chart that lies about when '
              'the run started');
      expect(values.reduce(max), 1490);
    });
  });

  group('a struct series', () {
    late String table;
    late Database db;
    late TimescaleReader reader;

    setUp(() async {
      table = freshTable('drive');
      db = await openWriter();
      reader = TimescaleReader(
        database: () => db,
        resolver: FixtureResolver({'Line1.Motor2': table}),
      );
      await seed(db, table, [
        for (var i = 0; i < 6; i++)
          (
            anchor.subtract(Duration(minutes: 6 - i)),
            <String, dynamic>{
              'speed': 40.0 + i,
              'current': 3.0 + i,
              'temp': 60.0 + i,
            }
          ),
      ]);
    });

    test('one member is served as a scalar series of that column', () async {
      final samples = await reader.queryTimeseriesData(
          'Line1.Motor2:speed', anchor,
          from: anchor.subtract(const Duration(minutes: 7)));

      expect(samples, hasLength(6));
      expect(samples.map((s) => s.value), [40.0, 41.0, 42.0, 43.0, 44.0, 45.0]);
      expect(samples.every((s) => s.value is num), isTrue);
    });

    test('a different member is a different series over the same table',
        () async {
      final samples = await reader.queryTimeseriesData(
          'Line1.Motor2:current', anchor,
          from: anchor.subtract(const Duration(minutes: 7)));

      expect(samples.map((s) => s.value), [3.0, 4.0, 5.0, 6.0, 7.0, 8.0]);
    });

    test('the unaddressed struct is a refusal naming the members', () async {
      await expectLater(
          reader.queryTimeseriesData('Line1.Motor2', anchor),
          throwsA(isA<StructSeriesUnaddressed>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('speed'), contains('current'),
                  contains('temp')))),
          reason: 'ninety of the live file\'s 140 collected keys are whole '
              'drive structs. Serving one unaddressed would put a Map where '
              'the client decodes a num, and the CastError arrives at the '
              'panel as a chart with no data');
    });

    test('a member series downsamples without falling back to the raw query',
        () async {
      final samples = await reader.queryTimeseriesDataDownsampled(
          'Line1.Motor2:speed',
          anchor.subtract(const Duration(minutes: 7)),
          anchor,
          maxPoints: 6);

      expect(samples, isNotEmpty);
      final values = samples.map((s) => s.value as num).toList();
      expect(values.reduce(min), 40.0);
      expect(values.reduce(max), 45.0);
      expect(samples.length, lessThanOrEqualTo(6 + 3),
          reason: 'Database.queryTimeseriesDataDownsampled looks for a '
              'column literally named `value` and silently returns the '
              'UNBOUNDED raw query when it finds none — which is every '
              'struct table there is. The member path must bucket for '
              'itself or a month-long struct chart is a month of raw rows');
    });
  });

  group('several series in one call', () {
    test('scalar and member-projected series answer in one map, empty '
        'entries included', () async {
      final scalar = freshTable('multi_scalar');
      final struct = freshTable('multi_struct');
      final silent = freshTable('multi_silent');
      final db = await openWriter();
      final reader = TimescaleReader(
        database: () => db,
        resolver: FixtureResolver({
          'A.Scalar': scalar,
          'B.Struct': struct,
          'C.Silent': silent,
        }),
      );

      await seed(db, scalar, [
        (anchor.subtract(const Duration(minutes: 2)), 11),
        (anchor.subtract(const Duration(minutes: 1)), 12),
      ]);
      await seed(db, struct, [
        (
          anchor.subtract(const Duration(minutes: 2)),
          <String, dynamic>{'speed': 21.0, 'current': 1.0}
        ),
      ]);
      await seed(db, silent, [
        (anchor.subtract(const Duration(days: 40)), 99),
      ]);

      final answer = await reader.queryTimeseriesDataMultiple(
          ['A.Scalar', 'B.Struct:speed', 'C.Silent'], anchor,
          from: anchor.subtract(const Duration(minutes: 5)));

      expect(answer.keys, containsAll(['A.Scalar', 'B.Struct:speed', 'C.Silent']),
          reason: 'one entry per REQUESTED series, keyed by the name the '
              'caller used — a member address is its own series name');
      expect(answer['A.Scalar']!.map((s) => s.value), [11, 12]);
      expect(answer['B.Struct:speed']!.map((s) => s.value), [21.0]);
      expect(answer['C.Silent'], isEmpty,
          reason: 'an absent key and a key with no rows are different '
              'claims, and a chart drawing a gap where there was silence is '
              'the line that stops in mid-air');
    });
  });

  group('counting buckets', () {
    test('every bucket is present, and an empty one is 0 rather than absent',
        () async {
      final table = freshTable('counts');
      final db = await openWriter();
      final reader = TimescaleReader(
        database: () => db,
        resolver: FixtureResolver({'D.Counted': table}),
      );

      // Four one-minute buckets ending at `anchor`; the SECOND-oldest is
      // deliberately empty.
      await seed(db, table, [
        (anchor.subtract(const Duration(seconds: 200)), 1),
        (anchor.subtract(const Duration(seconds: 190)), 2),
        (anchor.subtract(const Duration(seconds: 100)), 3),
        (anchor.subtract(const Duration(seconds: 40)), 4),
        (anchor.subtract(const Duration(seconds: 20)), 5),
      ]);

      final counts = await reader.countTimeseriesDataMultiple(
          'D.Counted', const Duration(minutes: 1), 4,
          since: anchor);

      expect(counts, hasLength(4),
          reason: 'howMany buckets come back, contiguous, oldest first');
      final ordered = counts.keys.toList()..sort();
      expect(counts[ordered[0]], 2);
      expect(counts[ordered[1]], 0,
          reason: 'the empty middle bucket must be PRESENT with zero. An '
              'absent bucket and a bucket with no rows are different claims, '
              'and the "is this series still recording?" strip renders them '
              'differently');
      expect(counts[ordered[2]], 1);
      expect(counts[ordered[3]], 2);
      expect(ordered.every((t) => t.isUtc), isTrue);

      // The arm that makes the assertion above mean something. `since` is
      // UTC everywhere it arrives from the wire (`data_handlers.dart` decodes
      // epoch milliseconds), so a UTC-only case cannot tell whether anything
      // normalises it — and this machine's own zone decides whether the bug
      // is even visible. A LOCAL instant is the state a contract leg or an
      // embedder produces, and it is what the interpolation at
      // `database.dart:1642-1646` mishandles: the bucket bounds go into the
      // statement as bare ISO strings with NO zone, so Postgres reads them in
      // the session's TimeZone and every bucket shifts by the caller's offset
      // with no error anywhere.
      final fromLocal = await reader.countTimeseriesDataMultiple(
          'D.Counted', const Duration(minutes: 1), 4,
          since: anchor.toLocal());

      expect(fromLocal.keys.every((t) => t.isUtc), isTrue,
          reason: 'a bucket key that is not an absolute instant puts the '
              '"is this series still recording?" strip an hour out twice a '
              'year, silently');
      expect(fromLocal, counts,
          reason: 'the same instant asked for two ways is the same four '
              'buckets holding the same five rows');
    });
  });

  group('when the database goes away', () {
    test('the reader fails fast and answers again when it returns', () async {
      final table = freshTable('outage');
      final seeder = await openWriter();
      await seed(seeder, table, [(anchor.subtract(const Duration(minutes: 1)), 5)]);

      var current = await openWriter();
      final reader = TimescaleReader(
        database: () => current,
        resolver: FixtureResolver({'E.Outage': table}),
      );

      expect(
          (await reader.queryTimeseriesData('E.Outage', anchor,
                  from: anchor.subtract(const Duration(minutes: 5))))
              .single
              .value,
          5);

      await current.close();

      final watch = Stopwatch()..start();
      await expectLater(
          reader.queryTimeseriesData('E.Outage', anchor,
              from: anchor.subtract(const Duration(minutes: 5))),
          throwsA(anything),
          reason: 'an outage is handlerFailed (-32011, documented as '
              'possibly transient) at the wire, which is what a chart should '
              'retry. It is never a refusal — the request was fine — and '
              'never a hang: queryTimeout is what bounds it');
      expect(watch.elapsed, lessThan(const Duration(seconds: 30)));

      current = await openWriter();
      expect(
          (await reader.queryTimeseriesData('E.Outage', anchor,
                  from: anchor.subtract(const Duration(minutes: 5))))
              .single
              .value,
          5,
          reason: 'the supplier is the seam: the reader borrows whatever '
              'Database the composition currently holds rather than pinning '
              'one at construction, so a reconnect underneath it is '
              'invisible');
    });
  });
}

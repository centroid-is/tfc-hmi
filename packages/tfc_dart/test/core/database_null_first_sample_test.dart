import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// Needs a postgres on 15499:
///
///   docker run -d --rm -e POSTGRES_PASSWORD=pw -e POSTGRES_USER=pg \
///     -e POSTGRES_DB=hmi -p 15499:5432 --name tfc-review-pg \
///     timescale/timescaledb:latest-pg17
///
/// Skipped by default so CI, which has no such server, stays green. Run with
/// `dart test test/core/database_null_first_sample_test.dart --run-skipped`.
const skipReason = 'needs a postgres on 15499 (see the header)';

DatabaseConfig cfg() => DatabaseConfig(
      postgres: pg.Endpoint(
        host: 'localhost',
        port: 15499,
        database: 'hmi',
        username: 'pg',
        password: 'pw',
      ),
      sslMode: pg.SslMode.disable,
      applicationName: 'null_first_sample',
    );

void main() {
  late AppDatabase appDb;
  late Database db;

  setUp(() async {
    appDb = await AppDatabase.create(cfg());
    await appDb.open();
    db = Database(appDb);
  });
  tearDown(() => db.close());

  Future<String?> valueColumnType(String table) async {
    final rows = await appDb.customSelect(
      "SELECT data_type FROM information_schema.columns "
      "WHERE table_name = '$table' AND column_name = 'value'",
    ).get();
    return rows.isEmpty ? null : rows.first.data['data_type'] as String?;
  }

  Future<void> policyFor(String table) => db.registerRetentionPolicy(
      table, const RetentionPolicy(dropAfter: Duration(days: 1)));

  test('a null first sample does not type the column, and the real value that '
      'follows still records', () async {
    // The Modbus first-failed-poll case: the device is unreachable on the
    // first poll and the stream publishes null.
    const t = 'null_then_double';
    await appDb.customStatement('DROP TABLE IF EXISTS "$t"');
    await policyFor(t);

    await db.insertTimeseriesData(t, DateTime.now().toUtc(), null);
    await db.flush();

    expect(await valueColumnType(t), isNull,
        reason: 'A null must not bring the table into existence — there is '
            'no type to give the column.');

    // Device comes back.
    await db.insertTimeseriesData(t, DateTime.now().toUtc(), 42.5);
    await db.flush();

    expect(await valueColumnType(t), 'double precision',
        reason: 'The first real value is what types the column.');

    final rows = await db.queryTimeseriesData(
        t, DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
    stdout.writeln('rows: ${rows.map((r) => r.value).toList()}');
    expect(rows.map((r) => r.value), contains(42.5),
        reason: 'and it must come back as a double, not the string "42.5".');
  }, timeout: const Timeout(Duration(seconds: 90)), skip: skipReason);

  test('the dropped null sample is not queued for retry', () async {
    // The trap: refusing to create the table must not leave the sample in the
    // buffer, or the insert fails 42P01, `_isPermanentDbError` re-raises it,
    // and it is retried every five seconds forever — worse than the TEXT
    // column the guard exists to prevent.
    const t = 'null_not_queued';
    await appDb.customStatement('DROP TABLE IF EXISTS "$t"');
    await policyFor(t);

    for (var i = 0; i < 5; i++) {
      await db.insertTimeseriesData(t, DateTime.now().toUtc(), null);
    }
    await db.flush();
    // Two retry cycles' worth. A queued batch would be retried in here.
    await Future<void>.delayed(const Duration(seconds: 11));
    await db.flush();

    expect(await valueColumnType(t), isNull);
    // Nothing pending means nothing to retry.
    await db.insertTimeseriesData(t, DateTime.now().toUtc(), 7.0);
    await db.flush();
    final rows = await db.queryTimeseriesData(
        t, DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
    expect(rows.map((r) => r.value).toList(), [7.0],
        reason: 'The five nulls are gone, not replayed ahead of the 7.0.');
  }, timeout: const Timeout(Duration(seconds: 120)), skip: skipReason);

  test('a struct whose members are partly null types the ones it can, and '
      'picks the rest up later', () async {
    const t = 'null_struct_member';
    await appDb.customStatement('DROP TABLE IF EXISTS "$t"');
    await policyFor(t);

    // `sample_members` shape: one member resolved, one did not.
    await db.insertTimeseriesData(
        t, DateTime.now().toUtc(), {'a': 1.5, 'b': null});
    await db.flush();

    var cols = await appDb.customSelect(
      "SELECT column_name, data_type FROM information_schema.columns "
      "WHERE table_name = '$t' ORDER BY column_name",
    ).get();
    stdout.writeln('after partly-null struct: '
        '${cols.map((c) => "${c.data['column_name']}:${c.data['data_type']}").toList()}');
    expect(cols.map((c) => c.data['column_name']), isNot(contains('b')),
        reason: 'b had no value, so it must not be created as TEXT.');

    // b shows up for real.
    await db.insertTimeseriesData(
        t, DateTime.now().toUtc(), {'a': 2.5, 'b': 9.0});
    await db.flush();

    cols = await appDb.customSelect(
      "SELECT column_name, data_type FROM information_schema.columns "
      "WHERE table_name = '$t' AND column_name = 'b'",
    ).get();
    stdout.writeln('b after a real value: ${cols.map((c) => c.data)}');
    expect(cols.single.data['data_type'], 'double precision',
        reason: 'Schema evolution must type b from the value, not from the '
            'null it first saw.');
  }, timeout: const Timeout(Duration(seconds: 90)), skip: skipReason);

  test('a database that was down while the tag was null still types the '
      'table from the first real value', () async {
    // The pending-creation path. `tableExists` throwing puts the table in
    // `_pendingTableCreation` and the sample IS buffered, so the guard in
    // `insertTimeseriesData` never sees it -- `_ensureTableAndInsert` has to
    // catch it instead, and it used to type the table from `writes.first`,
    // which on this path is a null. This is the plant-floor case exactly: the
    // database is unreachable at startup and so is the PLC.
    const t = 'pending_null_first';
    await appDb.customStatement('DROP TABLE IF EXISTS "$t"');
    await policyFor(t);

    await Process.run('docker', ['stop', 'tfc-review-pg']);
    await db.insertTimeseriesData(t, DateTime.now().toUtc(), null);
    await db.insertTimeseriesData(t, DateTime.now().toUtc(), null);
    await Process.run('docker', [
      'run', '-d', '--rm', '-e', 'POSTGRES_PASSWORD=pw', '-e',
      'POSTGRES_USER=pg', '-e', 'POSTGRES_DB=hmi', '-p', '15499:5432',
      '--name', 'tfc-review-pg', 'timescale/timescaledb:latest-pg17',
    ]);
    for (var i = 0; i < 40; i++) {
      final r = await Process.run(
          'docker', ['exec', 'tfc-review-pg', 'pg_isready', '-U', 'pg']);
      if (r.exitCode == 0) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    // Let the retry queue drain the buffered nulls against the live server.
    await Future<void>.delayed(const Duration(seconds: 8));
    await db.flush();
    expect(await valueColumnType(t), isNull,
        reason: 'The buffered nulls must not type the table on the way back.');

    await db.insertTimeseriesData(t, DateTime.now().toUtc(), 3.25);
    await db.flush();
    expect(await valueColumnType(t), 'double precision');
  }, timeout: const Timeout(Duration(seconds: 180)), skip: skipReason);

  test('an always-null tag records nothing, and says so once', () async {
    // Documented behaviour change, not an accident: such a tag previously got
    // a TEXT table full of nulls. It now gets no table. Neither records
    // anything usable; this way nothing downstream is mistyped.
    const t = 'always_null';
    await appDb.customStatement('DROP TABLE IF EXISTS "$t"');
    await policyFor(t);

    for (var i = 0; i < 10; i++) {
      await db.insertTimeseriesData(t, DateTime.now().toUtc(), null);
      await db.flush();
    }
    expect(await valueColumnType(t), isNull);
  }, timeout: const Timeout(Duration(seconds: 90)), skip: skipReason);
}

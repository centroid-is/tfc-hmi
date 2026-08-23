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
/// Skipped by default so CI, which has no such server, stays green.
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
  test('a null first sample must not decide the column type for good',
      () async {
    // The Modbus `_onPollTick` case: the device is unreachable on the first
    // poll, the stream publishes null, and the collector inserts it because
    // `Collector.insertValue` does not filter nulls.
    const t = 'null_first_sample';
    final appDb = await AppDatabase.create(cfg());
    await appDb.open();
    await appDb.customStatement('DROP TABLE IF EXISTS "$t"');

    final db = Database(appDb);
    addTearDown(db.close);
    await db.registerRetentionPolicy(
        t, const RetentionPolicy(dropAfter: Duration(days: 1)));

    // First poll fails -> null.
    await db.insertTimeseriesData(t, DateTime.now().toUtc(), null);
    await db.flush();

    final colType = (await appDb.customSelect(
      "SELECT data_type FROM information_schema.columns "
      "WHERE table_name = '$t' AND column_name = 'value'",
    ).getSingle())
        .data['data_type'];
    stdout.writeln('value column type after the null sample: $colType');

    // Device comes back; every later sample is a real double.
    await db.insertTimeseriesData(t, DateTime.now().toUtc(), 42.5);
    await db.flush();
    await Future<void>.delayed(const Duration(seconds: 1));

    final rows = await db.queryTimeseriesData(
        t, DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
    stdout.writeln('rows: ${rows.map((r) => r.value).toList()}');

    expect(rows.map((r) => r.value), contains(42.5),
        reason: 'A null on the first poll must not leave the table unable to '
            'record the real values that follow.');
  }, timeout: const Timeout(Duration(seconds: 90)), skip: skipReason);
}

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
      applicationName: 'ragged_test',
    );

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.create(cfg());
    await db.open();
  });
  tearDown(() => db.close());

  test('a batch whose rows have different member sets still inserts',
      () async {
    // Exactly what `sample_members` produces: "Members missing from a sample
    // are omitted from its row".
    const t = 'ragged_members';
    await db.customStatement('DROP TABLE IF EXISTS "$t"');
    await db.createTable(t, {
      'time': 'TIMESTAMPTZ',
      'a': 'DOUBLE PRECISION',
      'b': 'DOUBLE PRECISION',
    });

    final now = DateTime.now().toUtc();
    await db.tableInsertBatch(t, [
      {'time': now.toIso8601String(), 'a': 1.0, 'b': 2.0},
      // Second sample: `b` did not resolve, so it is omitted.
      {'time': now.add(const Duration(seconds: 1)).toIso8601String(), 'a': 3.0},
    ]);

    final rows = await db.tableQuery(t, orderBy: 'time');
    stdout.writeln(rows.map((r) => r.data).toList());
    expect(rows, hasLength(2));
  }, timeout: const Timeout(Duration(seconds: 60)), skip: skipReason);

  test('a batch whose rows have the same arity but different members does not '
      'put values in the wrong columns', () async {
    const t = 'ragged_swap';
    await db.customStatement('DROP TABLE IF EXISTS "$t"');
    await db.createTable(t, {
      'time': 'TIMESTAMPTZ',
      'a': 'DOUBLE PRECISION',
      'b': 'DOUBLE PRECISION',
    });

    final now = DateTime.now().toUtc();
    await db.tableInsertBatch(t, [
      {'time': now.toIso8601String(), 'a': 1.0},
      // Same number of fields, different field: `a` missing, `b` present.
      {'time': now.add(const Duration(seconds: 1)).toIso8601String(), 'b': 9.0},
    ]);

    final rows = await db.tableQuery(t, orderBy: 'time');
    stdout.writeln(rows.map((r) => r.data).toList());
    expect(rows[1].data['b'], 9.0,
        reason: 'The column list must be the union of every row, not just the '
            "first, or the second row's b lands in column a.");
    expect(rows[1].data['a'], isNull);
  }, timeout: const Timeout(Duration(seconds: 60)), skip: skipReason);
}

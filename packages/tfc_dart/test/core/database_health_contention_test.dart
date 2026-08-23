import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

int? poolSize;
int sleepSeconds = 25;

/// UNFIXED FINDING. Needs a postgres on 15499:
///
///   docker run -d --rm -e POSTGRES_PASSWORD=pw -e POSTGRES_USER=pg \
///     -e POSTGRES_DB=hmi -p 15499:5432 --name tfc-review-pg \
///     timescale/timescaledb:latest-pg17
///
/// Run with `SLEEP=25 dart test ... --run-skipped`. Passes at POOL=2, fails at
/// the shipped default of 1.
const skipReason = 'needs a postgres on 15499; documents an unfixed finding';
DatabaseConfig cfg() => DatabaseConfig(
      postgres: pg.Endpoint(
        host: 'localhost',
        port: 15499,
        database: 'hmi',
        username: 'pg',
        password: 'pw',
      ),
      sslMode: pg.SslMode.disable,
      applicationName: 'contention_test',
      maxPoolConnections: poolSize,
    );

void main() {
  test('a slow user query must not make the health monitor report a dead '
      'database', () async {
    poolSize = int.tryParse(Platform.environment['POOL'] ?? '');
    sleepSeconds = int.parse(Platform.environment['SLEEP'] ?? '25');
    final db = await AppDatabase.create(cfg());
    addTearDown(db.close);
    await db.open();

    final events = <bool>[];
    final sub = db.connectionHealth!.listen(events.add);
    addTearDown(sub.cancel);

    // Let the first good beat land.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(events, isNotEmpty, reason: 'monitor should have beaten once');
    expect(events.last, isTrue);
    events.clear();

    // The operator opens a year-long history chart. One slow query, on a
    // database that is perfectly healthy.
    final sw = Stopwatch()..start();
    await db.customSelect('SELECT pg_sleep($sleepSeconds)').get();
    sw.stop();
    stdout.writeln('slow query took ${sw.elapsedMilliseconds} ms; '
        'health events during it: $events');

    expect(events, isNot(contains(false)),
        reason: 'The pool is sized to 1, so the health beat has to queue '
            'behind the chart query. If the beat times out the UI flips to '
            '"database disconnected" while the database is fine.');
  }, timeout: const Timeout(Duration(seconds: 120)), skip: skipReason);
}

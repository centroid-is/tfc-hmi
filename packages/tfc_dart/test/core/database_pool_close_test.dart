// Closing an [AppDatabase] has to take its pool with it.
//
// `git grep pool.close` found nothing before this: the pool was created in
// `AppDatabase.create` and never closed by anyone. `PgDatabase.opened` passes
// `closeUnderlyingWhenClosed: false` and only ever closes a bare `Connection`
// anyway, so `super.close()` walked past it, and the pool health monitor --
// which by design sits inside `pool.withConnection` for the whole life of the
// pool -- kept its connection until the process exited.
//
// On the `useIsolate: false` path (every collector acquisition isolate) there
// is no DriftIsolate whose `shutdownAll` would incidentally take the sockets
// down, so that connection was simply lost. `connectWithRetry` closes every
// attempt it throws away, which meant one lost connection per failed attempt
// against a server that was already refusing them.
//
// These tests need no server: `pg.Pool.withEndpoints` does not connect, so the
// pool object exists and can be watched from the moment it is built.

@TestOn('vm')
library;

import 'dart:async';

import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// A port nothing is listening on, so the health monitor's connect attempts
/// fail immediately instead of waiting out a timeout.
DatabaseConfig _unreachableConfig() => DatabaseConfig(
      postgres: pg.Endpoint(
        host: '127.0.0.1',
        port: 1,
        database: 'nowhere',
        username: 'nobody',
        password: 'nothing',
      ),
      sslMode: pg.SslMode.disable,
      connectTimeout: const Duration(milliseconds: 200),
      queryTimeout: const Duration(milliseconds: 200),
    );

void main() {
  test('close releases the pool the health monitor is standing in', () async {
    final db = await AppDatabase.create(_unreachableConfig());
    final pool = db.poolForTest;

    expect(pool, isNotNull,
        reason: 'the in-isolate path must keep the pool it built, or nothing '
            'is left that can close it');
    expect(pool!.isOpen, isTrue);

    await db.close().timeout(const Duration(seconds: 10));

    expect(pool.isOpen, isFalse,
        reason: 'an open pool here is the monitor connection outliving the '
            'database that made it');
  });

  test('close does not wait on the monitor to give its connection back',
      () async {
    // A graceful `pool.close()` waits for every borrowed connection, and the
    // monitor only returns its own when the socket underneath it dies. On the
    // retry path that wait would stall reconnection outright.
    final db = await AppDatabase.create(_unreachableConfig());
    final stopwatch = Stopwatch()..start();
    await db.close().timeout(const Duration(seconds: 10));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('closing twice is not an error', () async {
    // connectWithRetry disposes attempts it throws away, and callers close
    // their database as well; the second close must be a no-op, not a crash.
    final db = await AppDatabase.create(_unreachableConfig());
    await db.close().timeout(const Duration(seconds: 10));
    await db.close().timeout(const Duration(seconds: 10));
    expect(db.poolForTest!.isOpen, isFalse);
  });

  test('concurrent closes share one teardown', () async {
    final db = await AppDatabase.create(_unreachableConfig());
    await Future.wait([db.close(), db.close()])
        .timeout(const Duration(seconds: 10));
    expect(db.poolForTest!.isOpen, isFalse);
  });

  test('a sqlite database has no pool and still closes', () async {
    final db = AppDatabase.inMemoryForTest();
    expect(db.poolForTest, isNull);
    await db.close().timeout(const Duration(seconds: 10));
  });
}

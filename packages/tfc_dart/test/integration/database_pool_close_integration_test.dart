// The pool leak, measured at the server.
//
// `AppDatabase.close()` never closed its pool, so the health monitor's
// standing connection -- one per database, by design, held inside
// `pool.withConnection` for the pool's whole life -- survived the database
// that made it. The unit tests next door watch `pool.isOpen`; this one asks
// Postgres, because a pool object marked closed while the backend still has a
// live session would be exactly the bug wearing a disguise.
//
// The `useIsolate: false` path is the one that matters: it is what every
// collector acquisition isolate uses, and it has no DriftIsolate whose
// `shutdownAll` would take the sockets down as a side effect.

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'docker_compose.dart';

/// Sessions the server currently has open on the test database.
Future<int> _backendCount(Connection control) async {
  final result = await control.execute(
      "SELECT count(*)::int FROM pg_stat_activity WHERE datname = 'testdb'");
  return result.first.first as int;
}

/// Polls [read] until it satisfies [done], or gives up after [timeout].
Future<int> _waitForCount(
  Future<int> Function() read,
  bool Function(int) done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  var last = await read();
  while (!done(last)) {
    if (DateTime.now().isAfter(deadline)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    last = await read();
  }
  return last;
}

void main() {
  group('pool close (integration)', () {
    late Connection control;

    setUpAll(() async {
      await startDockerCompose();
      await waitForDatabaseReady();
      control = await getTestConnection();
    });

    tearDownAll(() async {
      await control.close();
      await stopDockerCompose();
    });

    test('closing an in-isolate database hands every connection back',
        () async {
      final baseline = await _backendCount(control);

      final db = await AppDatabase.create(getTestConfig());
      await db.open();

      // The monitor takes its connection asynchronously, so wait for the
      // server to actually show the database holding more than the control
      // connection before claiming anything about what close gives back.
      final busy = await _waitForCount(
          () => _backendCount(control), (n) => n > baseline);
      expect(busy, greaterThan(baseline),
          reason: 'the database opened without taking a connection, so this '
              'test is not measuring what it thinks it is');

      await db.close().timeout(const Duration(seconds: 30));

      final after =
          await _waitForCount(() => _backendCount(control), (n) => n <= baseline);
      expect(after, lessThanOrEqualTo(baseline),
          reason: 'connections left behind after close are the leak: the '
              'health monitor holds one for as long as the pool is open, and '
              'nothing used to close the pool');
      expect(db.poolForTest!.isOpen, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a thrown-away connect attempt costs nothing, repeatedly', () async {
      // connectWithRetry closes every attempt whose open fails. Before the
      // fix each of those leaked its monitor's connection, and the loop runs
      // every couple of seconds for as long as the server is unreachable --
      // which is how one backend ended up on 75 of 100 connections.
      final baseline = await _backendCount(control);

      for (var i = 0; i < 5; i++) {
        final db = await AppDatabase.create(getTestConfig());
        await db.open();
        await db.close().timeout(const Duration(seconds: 30));
      }

      final after =
          await _waitForCount(() => _backendCount(control), (n) => n <= baseline);
      expect(after, lessThanOrEqualTo(baseline),
          reason: 'five discarded attempts must cost five nothings');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

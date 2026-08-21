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

/// One line per session on the test database, for failure messages.
///
/// A count on its own cannot tell a leaked pool connection from a TimescaleDB
/// background worker, and the two are not the same bug -- one is ours, the
/// other is the server deciding to run a job. Every failure of this file has
/// so far been a bare number, which is not enough to act on.
Future<String> _describeBackends(Connection control) async {
  try {
    final rows = await control.execute(
      "SELECT pid, state, backend_type, application_name, "
      "  to_char(backend_start, 'HH24:MI:SS') AS started, "
      "  coalesce(left(query, 60), '') AS query "
      "FROM pg_stat_activity WHERE datname = 'testdb' "
      "ORDER BY backend_start",
    );
    return rows
        .map((r) => '  ${r.map((v) => v ?? '').join(' | ')}')
        .join('\n');
  } catch (error) {
    return '  <could not read pg_stat_activity: $error>';
  }
}

/// Backends that may still be on their way out when a close has returned.
///
/// `pool.close()` awaits its semaphore, and `withConnection`'s `finally`
/// calls `resource.release()` *before* it awaits `connection._dispose()`. So
/// the close can complete while a socket is still being torn down, and the
/// server reaps the backend a moment after that. This is slack for teardown in
/// flight, not for leaking: the leak this file exists to catch is two backends
/// *per database*, which on the repeated test below is ten, well clear of it.
const int _settling = 2;

/// Polls [read] until it satisfies [done], or gives up after [timeout].
///
/// Generous, because these run on shared CI runners alongside Docker: a slow
/// reap must not read as a leak.
Future<int> _waitForCount(
  Future<int> Function() read,
  bool Function(int) done, {
  Duration timeout = const Duration(seconds: 60),
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
              'nothing used to close the pool.\n'
              'baseline was $baseline, still open:\n'
              '${await _describeBackends(control)}');
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

      // The leak was two backends per attempt, so five attempts cost ten and
      // the count never comes back down. Anything inside [_settling] is
      // teardown still in flight, and does not grow with the attempt count.
      final after = await _waitForCount(
          () => _backendCount(control), (n) => n <= baseline + _settling);
      expect(after, lessThanOrEqualTo(baseline + _settling),
          reason: 'the cost of a discarded attempt must not scale with how '
              'many were discarded.\n'
              'baseline was $baseline, still open:\n'
              '${await _describeBackends(control)}');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

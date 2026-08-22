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
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'docker_compose.dart';

/// A name no other suite in this `dart test` invocation can be using.
///
/// Each test tags the databases it opens with one of these and counts only
/// backends wearing it. See [_clientBackends].
var _appNameSeq = 0;
String _uniqueAppName(String label) => 'pool-close-$label-${_appNameSeq++}';

/// [getTestConfig], tagged so the server can tell this database's connections
/// apart from everything else on `testdb`.
DatabaseConfig _taggedConfig(String appName) =>
    getTestConfig()..applicationName = appName;

/// Client connections the server currently has on the test database *that this
/// test opened*, not counting the one asking.
///
/// Deliberately narrower than "rows in `pg_stat_activity` for this database",
/// twice over.
///
/// `backend_type = 'client backend'` drops TimescaleDB's background worker
/// scheduler, which is attached to every database the extension is installed
/// in and starts more workers when it has jobs to run -- on a database the
/// other integration files have left hypertables and retention policies in,
/// those come and go on the extension's own schedule.
///
/// `application_name` drops the other suites. Every file in this directory
/// shares one `dart test` process and one server, and a health monitor from a
/// suite that has already finished goes on beating for the rest of the run.
/// Counting those made this test report a leak whenever the runner was loaded
/// enough for the timing to line up -- a backend that was born after
/// [baseline] was taken and belonged to nobody here. Since `create` and
/// `spawn` both pass the config's [DatabaseConfig.applicationName] down to
/// `PoolSettings`, a per-database tag is exact: the count starts at zero, and
/// anything it sees is ours.
///
/// A leaked pool connection is always a tagged `client backend`, so nothing
/// this test exists to catch can hide behind either filter.
Future<int> _clientBackends(Connection control, String appName) async {
  final result = await control.execute(
      Sql.named("SELECT count(*)::int FROM pg_stat_activity "
          "WHERE datname = 'testdb' AND backend_type = 'client backend' "
          "AND pid <> pg_backend_pid() AND application_name = @app"),
      parameters: {'app': appName});
  return result.first.first as int;
}

/// Who those connections are, for a failure that explains itself.
Future<String> _describeBackends(Connection control) async {
  // `port` and the gap between backend_start and state_change are what say
  // *which* connection this is. An empty query means it never ran a statement,
  // which no drift connection can manage -- only the health monitor, which
  // borrows one purely to watch it. Distinct ports spread across the run say
  // they came from separate databases rather than one pool.
  final result = await control.execute(
      "SELECT coalesce(state,'?'), coalesce(nullif(application_name,''),'-'), "
      "round(extract(epoch from (now()-backend_start)))::int, "
      "coalesce(client_port, -1), "
      "round(extract(epoch from (state_change-backend_start)))::int, "
      "coalesce(left(query, 60),'-') "
      "FROM pg_stat_activity WHERE datname = 'testdb' "
      "AND backend_type = 'client backend' AND pid <> pg_backend_pid() "
      "ORDER BY backend_start");
  if (result.isEmpty) return 'none (proxy pairs: $proxyLivePairs)';
  return 'proxy still holding $proxyLivePairs pair(s); ${result.map((r) => '[state=${r[0]} app=${r[1]} age=${r[2]}s port=${r[3]} '
      'idleAfter=${r[4]}s q=${r[5]}]').join(' ')}';
}

/// Polls [read] until it satisfies [done], or gives up after [timeout].
///
/// Generous, because these run on shared CI runners alongside Docker: a slow
/// reap must not read as a leak. It costs nothing when the close was clean,
/// because the first read already satisfies [done].
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
      final appName = _uniqueAppName('in-isolate');
      final baseline = await _clientBackends(control, appName);
      expect(baseline, 0,
          reason: 'a tag nothing has used yet must start at zero; anything '
              'else means the name is not unique to this test');

      final db = await AppDatabase.create(_taggedConfig(appName));
      await db.open();

      // The monitor takes its connection asynchronously, so wait for the
      // server to actually show the database holding more than the control
      // connection before claiming anything about what close gives back.
      final busy = await _waitForCount(
          () => _clientBackends(control, appName), (n) => n > baseline);
      expect(busy, greaterThan(baseline),
          reason: 'the database opened without taking a connection, so this '
              'test is not measuring what it thinks it is');

      await db.close().timeout(const Duration(seconds: 30));

      final after = await _waitForCount(
          () => _clientBackends(control, appName), (n) => n <= baseline);
      expect(after, lessThanOrEqualTo(baseline),
          reason: 'connections left behind after close are the leak: the '
              'health monitor holds one for as long as the pool is open, and '
              'nothing used to close the pool. Still connected: '
              '${await _describeBackends(control)}');
      expect(db.poolForTest!.isOpen, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a thrown-away connect attempt costs nothing, repeatedly', () async {
      // connectWithRetry closes every attempt whose open fails. Before the
      // fix each of those leaked its monitor's connection, and the loop runs
      // every couple of seconds for as long as the server is unreachable --
      // which is how one backend ended up on 75 of 100 connections.
      final appName = _uniqueAppName('discarded');
      final baseline = await _clientBackends(control, appName);
      expect(baseline, 0,
          reason: 'a tag nothing has used yet must start at zero; anything '
              'else means the name is not unique to this test');

      for (var i = 0; i < 5; i++) {
        final db = await AppDatabase.create(_taggedConfig(appName));
        await db.open();
        await db.close().timeout(const Duration(seconds: 30));
      }

      // No slack. The monitor is asked to let go before the pool is closed, so
      // every connection is returned and closed with a Terminate and the
      // backend is gone by the time close() returns -- there is no reaping to
      // wait out. The leak this catches was two backends per attempt, so five
      // attempts cost ten and the count never came back down at all.
      final after = await _waitForCount(
          () => _clientBackends(control, appName), (n) => n <= baseline);
      expect(after, lessThanOrEqualTo(baseline),
          reason: 'the cost of a discarded attempt must not scale with how '
              'many were discarded. Still connected: '
              '${await _describeBackends(control)}');
    }, timeout: const Timeout(Duration(minutes: 5)));

    // The two tests above are only worth their assertions if the tag actually
    // narrows what they see. This is the measurement's own test: a database
    // that is open the whole time, under a different name, must be invisible.
    //
    // Without it the filter could be silently matching everything -- a typo in
    // the parameter, a name that collides -- and both tests would keep passing
    // for the wrong reason, which is exactly the failure mode they had before.
    test('the count ignores connections belonging to another tag', () async {
      final mine = _uniqueAppName('mine');
      final theirs = _uniqueAppName('theirs');

      final other = await AppDatabase.create(_taggedConfig(theirs));
      await other.open();
      addTearDown(() => other.close().timeout(const Duration(seconds: 30)));

      // Wait until the server can actually see the other database, so a zero
      // below cannot just mean it had not connected yet.
      final visible = await _waitForCount(
          () => _clientBackends(control, theirs), (n) => n > 0);
      expect(visible, greaterThan(0),
          reason: 'the other database never took a connection, so this test '
              'is not proving anything about the filter');

      expect(await _clientBackends(control, mine), 0,
          reason: 'a live connection under another application_name leaked '
              'into this tag\'s count. Still connected: '
              '${await _describeBackends(control)}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

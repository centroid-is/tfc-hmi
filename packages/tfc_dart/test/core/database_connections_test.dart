// Connection lifetime around bringing the database up.
//
// On 2026-08-21 Postgres refused every write with `53300: sorry, too many
// clients already`. `centroidx-backend` held 75 of 100 connections after 19
// hours; even the superuser reserved slots were gone, so the server could not
// be inspected while it was failing. Saving a page in the HMI failed with the
// same error.
//
// Two leaks in the connect path caused it, and there is a group here for each:
//
//   1. `connectWithRetry` builds a database, and if opening it throws, loops
//      without disposing what it built. Each spawned DriftIsolate carries a
//      `pg.Pool` and a health monitor that holds a connection open by design,
//      so every failed attempt permanently costs at least one server slot --
//      and the loop retries every two seconds, forever.
//
//   2. `probe` races `Connection.open` against a five second timeout. The open
//      keeps running after the timeout gives up, so a slow server hands back a
//      live connection that nobody closes.
//
// Both make pressure self-reinforcing: the tighter the pool, the slower the
// opens, the more orphans get created.

@TestOn('vm')
library;

import 'dart:async';

import 'package:tfc_dart/core/database_connections.dart';
import 'package:test/test.dart';

void main() {
  group('retryUntilOpen', () {
    test('disposes an attempt whose open fails', () async {
      // The leak: the attempt was built, so it is holding resources, and the
      // loop must hand them back before trying again.
      final disposed = <int>[];
      var built = 0;

      final result = await retryUntilOpen<int>(
        probe: () async {},
        build: () async => ++built,
        open: (h) async {
          if (h < 3) throw StateError('too many clients');
        },
        dispose: (h) async => disposed.add(h),
        delay: (_) => Duration.zero,
        sleep: (_) async {},
      );

      expect(result, 3);
      expect(disposed, [1, 2], reason: 'both failed attempts must be disposed');
    });

    test('does not dispose the attempt it returns', () async {
      final disposed = <int>[];
      final result = await retryUntilOpen<int>(
        probe: () async {},
        build: () async => 7,
        open: (_) async {},
        dispose: (h) async => disposed.add(h),
        delay: (_) => Duration.zero,
        sleep: (_) async {},
      );
      expect(result, 7);
      expect(disposed, isEmpty);
    });

    test('a failing probe builds nothing, so there is nothing to dispose',
        () async {
      var built = 0, probes = 0;
      final disposed = <int>[];
      await retryUntilOpen<int>(
        probe: () async {
          if (++probes < 3) throw StateError('unreachable');
        },
        build: () async => ++built,
        open: (_) async {},
        dispose: (h) async => disposed.add(h),
        delay: (_) => Duration.zero,
        sleep: (_) async {},
      );
      expect(built, 1);
      expect(disposed, isEmpty);
    });

    test('a dispose that throws does not stop the retry loop', () async {
      // Disposing a half-open database can itself fail. Giving up there would
      // strand the caller with no database at all.
      var built = 0;
      final result = await retryUntilOpen<int>(
        probe: () async {},
        build: () async => ++built,
        open: (h) async {
          if (h < 2) throw StateError('nope');
        },
        dispose: (_) async => throw StateError('dispose blew up'),
        delay: (_) => Duration.zero,
        sleep: (_) async {},
      );
      expect(result, 2);
    });

    test('waits longer after each failure instead of hammering', () async {
      // A flat two second retry is what let one unreachable database produce
      // hundreds of connection attempts an hour.
      final waits = <Duration>[];
      var built = 0;
      await retryUntilOpen<int>(
        probe: () async {},
        build: () async => ++built,
        open: (h) async {
          if (h < 4) throw StateError('nope');
        },
        dispose: (_) async {},
        delay: backoffForAttempt,
        sleep: (d) async => waits.add(d),
      );
      expect(waits.length, 3);
      expect(waits[1], greaterThan(waits[0]));
      expect(waits[2], greaterThan(waits[1]));
    });

    test('backoff is capped so a long outage still reconnects promptly', () {
      expect(backoffForAttempt(99), backoffForAttempt(50));
      expect(backoffForAttempt(99), lessThanOrEqualTo(kMaxConnectBackoff));
    });
  });

  group('openThenClose', () {
    test('closes a connection that arrives after the timeout gave up',
        () async {
      // The probe leak. `Connection.open` does not stop when we stop waiting.
      final pending = Completer<String>();
      final closed = <String>[];

      await expectLater(
        openThenClose<String>(
          pending.future,
          (c) async => closed.add(c),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(closed, isEmpty, reason: 'nothing has opened yet');

      pending.complete('late-connection');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(closed, ['late-connection'],
          reason: 'the orphan must be closed once it finally opens');
    });

    test('closes a connection that arrives in time', () async {
      final closed = <String>[];
      await openThenClose<String>(
        Future.value('prompt'),
        (c) async => closed.add(c),
        timeout: const Duration(seconds: 5),
      );
      expect(closed, ['prompt']);
    });

    test('a failed open needs no close and surfaces its own error', () async {
      final closed = <String>[];
      await expectLater(
        openThenClose<String>(
          Future<String>.error(StateError('refused')),
          (c) async => closed.add(c),
          timeout: const Duration(seconds: 5),
        ),
        throwsA(isA<StateError>()),
      );
      expect(closed, isEmpty);
    });

    test('a close that throws does not mask the successful open', () async {
      await openThenClose<String>(
        Future.value('ok'),
        (_) async => throw StateError('close failed'),
        timeout: const Duration(seconds: 5),
      );
    });
  });

  group('pool sizing', () {
    // The dominant cause. `AppDatabase.spawn` and `.create` both hardcode
    // `maxConnectionCount: 20`, while the postgres package's own default is 1.
    // Jon's expectation for the plant is one connection per UI client and
    // fewer than ten for the collector -- one per OPC UA server, with the
    // m2400 weighers sharing one. Observed instead: 13 and 12 for the two UI
    // clients, 16 for the collector. Five processes at 20 exhaust a default
    // server on their own.
    test('a client that is not configured holds one connection', () {
      expect(resolvePoolSize(null), 1);
    });

    test('an explicit size is honoured', () {
      expect(resolvePoolSize(8), 8);
    });

    test('nonsense sizes cannot take the server down', () {
      expect(resolvePoolSize(0), 1);
      expect(resolvePoolSize(-4), 1);
      expect(resolvePoolSize(10000), kMaxPoolConnections);
    });

    test('the default is small enough that many clients still fit', () {
      // 200 max_connections, minus reserved, divided by the default: there has
      // to be room for far more clients than the plant will ever run.
      expect(poolConnectionCount(null) * 20, lessThan(195));
    });

    // The pool health monitor sits inside `pool.withConnection` for as long as
    // the pool is open -- that is how it notices a socket dying. So the pool
    // has to be opened one connection wider than the work it is sized for. A
    // pool of exactly one gave the monitor the only connection there was, and
    // the very first query -- drift asking Postgres its version while opening
    // -- waited out the pool lock and threw `Failed to acquire pool lock`.
    test('the pool is opened wider than the work, for the health monitor', () {
      expect(poolConnectionCount(null),
          greaterThan(resolvePoolSize(null)),
          reason: 'the monitor holds one connection and never gives it back');
    });

    test('an unconfigured client can still run a query while monitored', () {
      expect(poolConnectionCount(null) - kHealthMonitorConnections,
          greaterThanOrEqualTo(1));
    });

    test('a configured size is the work budget, not the total', () {
      // A collector asking for eight upstream drains gets eight to drain with;
      // the monitor is not allowed to eat one of them.
      expect(poolConnectionCount(8) - kHealthMonitorConnections, 8);
    });

    test('the ceiling still holds once the monitor is added', () {
      // One wider than kMaxPoolConnections on purpose: the cap is on the work
      // budget, and taking the monitor's connection out of it would give a
      // maxed-out collector one drain fewer than it asked for.
      expect(poolConnectionCount(10000),
          kMaxPoolConnections + kHealthMonitorConnections);
    });
  });

  group('pool size from the environment', () {
    // The field, its cap and its doc comment all shipped without a way to set
    // it: `fromPrefs` does not, and `fromEnv` did not read anything for it. The
    // collector is configured from the environment and is the process the doc
    // says should raise it, so the environment is where the hatch belongs.
    test('an unset variable leaves the default of one alone', () {
      expect(maxPoolConnectionsFromEnv(const {}), isNull);
      expect(resolvePoolSize(maxPoolConnectionsFromEnv(const {})), 1);
    });

    test('a collector can raise its budget', () {
      final size = maxPoolConnectionsFromEnv(
          const {kMaxPoolConnectionsEnv: '8'});
      expect(size, 8);
      expect(poolConnectionCount(size) - kHealthMonitorConnections, 8);
    });

    test('surrounding whitespace is not a typo worth failing over', () {
      expect(maxPoolConnectionsFromEnv(const {kMaxPoolConnectionsEnv: ' 4 '}),
          4);
    });

    test('a value that is not a number costs the raise, not the start', () {
      expect(maxPoolConnectionsFromEnv(const {kMaxPoolConnectionsEnv: 'lots'}),
          isNull);
      expect(maxPoolConnectionsFromEnv(const {kMaxPoolConnectionsEnv: ''}),
          isNull);
    });

    test('the cap still applies to whatever the environment asks for', () {
      expect(
          resolvePoolSize(maxPoolConnectionsFromEnv(
              const {kMaxPoolConnectionsEnv: '9999'})),
          kMaxPoolConnections);
      expect(
          resolvePoolSize(
              maxPoolConnectionsFromEnv(const {kMaxPoolConnectionsEnv: '0'})),
          1);
    });
  });

  group('monitorStopTimeout', () {
    // The close used to wait a flat two seconds for the monitor to hand its
    // connection back. The monitor races its *waits* against the stop signal,
    // but it cannot race `pool.withConnection`'s acquire -- the stop flag is
    // only read inside the callback, which does not run until the connection
    // is open. So a monitor asked to stop mid-acquire answers only when that
    // acquire lands, and the close gave up first, swallowed the timeout, and
    // force-closed the pool with a socket still on its way in. That socket
    // arrived untracked by a pool that no longer existed, and stayed idle on
    // the server forever.
    //
    // In the integration config those two numbers were *identical* -- a 2s
    // connect timeout and a 2s stop wait -- so it came down to a coin flip,
    // which is why it only ever failed on a loaded CI runner.
    test('leaves room for an acquire that takes the whole connect timeout', () {
      expect(monitorStopTimeout(const Duration(seconds: 2)),
          greaterThan(const Duration(seconds: 2)));
    });

    test('scales with the connect timeout rather than being flat', () {
      expect(monitorStopTimeout(const Duration(seconds: 8)),
          const Duration(seconds: 9));
    });

    test('never drops below the floor, however impatient the pool', () {
      expect(monitorStopTimeout(Duration.zero), kMonitorStopTimeout);
      expect(monitorStopTimeout(const Duration(milliseconds: 100)),
          kMonitorStopTimeout);
    });

    test('is capped, because a close must not hang', () {
      // A patiently configured pool must not turn shutdown into a stall.
      expect(monitorStopTimeout(const Duration(minutes: 5)),
          kMonitorStopCeiling);
    });
  });

  group('releasePool', () {
    // The pool was never closed anywhere in the repo. `PgDatabase.opened` does
    // not own what it is handed, so `AppDatabase.close()` left the pool -- and
    // the health monitor's standing connection inside it -- running for the
    // life of the process. On the `useIsolate: false` path, which is every
    // collector acquisition isolate, there was no DriftIsolate to take it down
    // either, so each thrown-away connect attempt cost a server slot.
    test('asks politely first, and stops there when that works', () async {
      // Returning a connection closes it with a Terminate and the backend
      // exits on the spot. Forcing destroys the socket and leaves the server
      // to notice -- which on a busy server is the slot staying taken.
      final forced = <bool>[];
      await releasePool(({bool force = false}) async => forced.add(force));
      expect(forced, [false],
          reason: 'a graceful close that succeeds must not be followed by a '
              'forced one');
    });

    test('forces the close when the polite one will not finish', () async {
      // Something is still holding a connection -- a monitor that did not stop
      // in time -- so the graceful close cannot complete. The pool still has
      // to go away.
      final forced = <bool>[];
      await releasePool(
        ({bool force = false}) {
          forced.add(force);
          return force ? Future<void>.value() : Completer<void>().future;
        },
        timeout: const Duration(milliseconds: 50),
      );
      expect(forced, [false, true]);
    });

    test('a close that hangs both ways is abandoned, not waited on', () async {
      // connectWithRetry closes every attempt it throws away, against a
      // database that is by definition already misbehaving.
      final errors = <Object>[];
      final stopwatch = Stopwatch()..start();
      await releasePool(
        ({bool force = false}) => Completer<void>().future,
        timeout: const Duration(milliseconds: 50),
        onError: errors.add,
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(errors, hasLength(2));
      expect(errors.every((e) => e is TimeoutException), isTrue);
    });

    test('a close that throws does not become the caller\'s problem', () async {
      final errors = <Object>[];
      await releasePool(
        ({bool force = false}) async => throw StateError('socket already gone'),
        onError: errors.add,
      );
      expect(errors, hasLength(2), reason: 'graceful threw, so force was tried');
      expect(errors.every((e) => e is StateError), isTrue);
    });
  });

  group('connection census', () {
    // Jon asked to be able to watch this: a total alone does not say who is
    // holding the connections, and during the incident the whole answer was a
    // single peer sitting on three quarters of the server.
    //
    // Every address here is invented. This repository is public and the plant's
    // real addresses do not belong in it.
    test('reads the peers and the server totals out of one query', () {
      final census = parseConnectionCensus(const [
        {'peer': '10.0.0.1', 'app': 'app-a', 'n': 16, 'total': 51, 'max_conn': 200},
        {'peer': '10.0.0.2', 'app': 'app-b', 'n': 13, 'total': 51, 'max_conn': 200},
        {'peer': 'local', 'app': '-', 'n': 22, 'total': 51, 'max_conn': 200},
      ]);
      expect(census.total, 51);
      expect(census.max, 200);
      expect(census.percentUsed, 26);
      expect(census.peers.map((p) => p.peer),
          containsAll(<String>['10.0.0.1', '10.0.0.2', 'local']));
      expect(census.peers.firstWhere((p) => p.peer == '10.0.0.1').count, 16);
      expect(census.peers.firstWhere((p) => p.peer == '10.0.0.1').app, 'app-a');
    });

    test('a server that counted nothing is reported as nothing', () {
      final census = parseConnectionCensus(const []);
      expect(census.total, 0);
      expect(census.max, 0);
      expect(census.peers, isEmpty);
      expect(census.percentUsed, 0);
      expect(censusIsAlarming(census), isFalse);
    });

    test('orders peers by how many connections they hold', () {
      final census = parseConnectionCensus(const [
        {'peer': 'small', 'app': '-', 'n': 2, 'total': 30, 'max_conn': 200},
        {'peer': 'big', 'app': '-', 'n': 28, 'total': 30, 'max_conn': 200},
      ]);
      expect(census.peersByShare.first.peer, 'big',
          reason: 'the biggest holder is the one worth seeing first');
      expect(census.peersByShare.last.peer, 'small');
    });

    test('flags the census when the server is nearly full', () {
      expect(
          censusIsAlarming(
              const ConnectionCensus(total: 20, max: 200, peers: [])),
          isFalse);
      expect(
          censusIsAlarming(
              const ConnectionCensus(total: 190, max: 200, peers: [])),
          isTrue);
    });
  });
}

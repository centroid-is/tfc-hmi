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
      expect(poolConnectionCount(10000),
          kMaxPoolConnections + kHealthMonitorConnections);
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

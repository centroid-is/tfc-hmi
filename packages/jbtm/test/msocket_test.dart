import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:test/test.dart';

/// Drive the reconnect loop with a connector that always fails and a delay
/// that returns instantly, and return the first [count] backoff durations the
/// loop asked for.
///
/// No socket is opened and no time passes, so the result is the same on every
/// machine. The backoff contract is "the loop waits 500ms, then 1s, 2s, 4s and
/// then 5s forever" -- that is a statement about the durations it requests, and
/// this reads them directly instead of inferring them from how long a loaded CI
/// runner took to deliver them.
Future<List<Duration>> recordBackoffLadder(int count) async {
  final delays = <Duration>[];
  final enough = Completer<void>();
  final socket = MSocket(
    'injected.invalid',
    1,
    connector: (_, __, ___) =>
        Future<Socket>.error(const SocketException('injected refusal')),
    delay: (d) {
      delays.add(d);
      if (delays.length >= count) {
        if (!enough.isCompleted) enough.complete();
        // Park the loop on a future that never completes: we have what we
        // came for, and letting it spin would only add noise.
        return Completer<void>().future;
      }
      return Future<void>.value();
    },
  );
  socket.connect();
  await enough.future.timeout(const Duration(seconds: 10));
  socket.dispose();
  return delays;
}

void main() {
  late TestTcpServer server;

  setUp(() async {
    server = TestTcpServer();
  });

  tearDown(() async {
    await server.shutdown();
  });

  group('connect and data', () {
    test('connects to server and emits connected status', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      expect(socket.status, equals(ConnectionStatus.connected));

      socket.dispose();
    });

    test('receives data from server as Uint8List', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      // Small delay to ensure server sees the client
      await Future.delayed(const Duration(milliseconds: 50));

      server.sendToAll([1, 2, 3]);
      final data = await socket.dataStream.first;

      expect(data, isA<Uint8List>());
      expect(data, equals([1, 2, 3]));

      socket.dispose();
    });

    test('receives multiple data chunks in order', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      await Future.delayed(const Duration(milliseconds: 50));

      final chunks = <Uint8List>[];
      final sub = socket.dataStream.listen(chunks.add);

      server.sendToAll([1]);
      await Future.delayed(const Duration(milliseconds: 50));
      server.sendToAll([2]);
      await Future.delayed(const Duration(milliseconds: 50));
      server.sendToAll([3]);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(chunks.length, equals(3));
      expect(chunks[0], equals([1]));
      expect(chunks[1], equals([2]));
      expect(chunks[2], equals([3]));

      await sub.cancel();
      socket.dispose();
    });

    test('connect returns void and is non-blocking', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      // connect() returns void (no Future to await)
      socket.connect();

      // Immediately after connect(), status should be disconnected or
      // connecting -- not yet connected (connection is async)
      expect(
        socket.status,
        anyOf(
          equals(ConnectionStatus.disconnected),
          equals(ConnectionStatus.connecting),
        ),
      );

      // Wait for connection to complete before cleanup
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      socket.dispose();
    });
  });

  group('status stream', () {
    test('emits disconnected -> connecting -> connected on connect', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      final statuses = <ConnectionStatus>[];
      socket.statusStream.listen(statuses.add);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      // The initial seed is disconnected, then connecting, then connected
      expect(statuses, contains(ConnectionStatus.disconnected));
      expect(statuses, contains(ConnectionStatus.connecting));
      expect(statuses, contains(ConnectionStatus.connected));

      // Verify ordering: disconnected before connecting before connected
      final idxDisconnected =
          statuses.indexOf(ConnectionStatus.disconnected);
      final idxConnecting = statuses.indexOf(ConnectionStatus.connecting);
      final idxConnected = statuses.indexOf(ConnectionStatus.connected);
      expect(idxDisconnected, lessThan(idxConnecting));
      expect(idxConnecting, lessThan(idxConnected));

      socket.dispose();
    });

    test('new listener gets current status immediately (replay)', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      // Subscribe a NEW listener after connection is established
      final firstEvent = await socket.statusStream.first;
      expect(firstEvent, equals(ConnectionStatus.connected));

      socket.dispose();
    });

    test('synchronous status getter returns current state', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      // Before connect: should be disconnected
      expect(socket.status, equals(ConnectionStatus.disconnected));

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      // After connect: should be connected
      expect(socket.status, equals(ConnectionStatus.connected));

      socket.dispose();
    });

    test('emits disconnected when server drops connection', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      // Collect all statuses before disconnect happens
      final statuses = <ConnectionStatus>[];
      final sawDisconnected = Completer<void>();
      var seenConnected = false;
      socket.statusStream.listen((s) {
        statuses.add(s);
        // After seeing connected, look for disconnected
        if (s == ConnectionStatus.connected) seenConnected = true;
        if (seenConnected && s == ConnectionStatus.disconnected) {
          if (!sawDisconnected.isCompleted) sawDisconnected.complete();
        }
      });

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      // Wait for the server to register the client before disconnecting
      await server.waitForClient();

      // Server disconnects all clients
      server.disconnectAll();

      // Wait for disconnected status to be observed
      await sawDisconnected.future.timeout(const Duration(seconds: 5));

      // Verify disconnected was emitted after connected
      final connectedIdx = statuses.indexOf(ConnectionStatus.connected);
      final disconnectedIdx =
          statuses.lastIndexOf(ConnectionStatus.disconnected);
      expect(disconnectedIdx, greaterThan(connectedIdx));

      socket.dispose();
    });
  });

  group('keepalive', () {
    test('configures keepalive without error', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();

      // If keepalive configuration fails, connect would throw or
      // the socket would not reach connected status.
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 5));

      expect(socket.status, equals(ConnectionStatus.connected));

      socket.dispose();
    });
  });

  group('dispose', () {
    test('dispose closes data stream', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      final dataCompleter = Completer<void>();
      socket.dataStream.listen(
        null,
        onDone: () => dataCompleter.complete(),
      );

      socket.dispose();

      await dataCompleter.future.timeout(const Duration(seconds: 2));
    });

    test('dispose closes status stream', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      final statusCompleter = Completer<void>();
      socket.statusStream.listen(
        null,
        onDone: () => statusCompleter.complete(),
      );

      socket.dispose();

      await statusCompleter.future.timeout(const Duration(seconds: 2));
    });

    test('no events after dispose', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      await Future.delayed(const Duration(milliseconds: 50));

      // Subscribe BEFORE dispose to catch any lingering events
      final events = <Uint8List>[];
      socket.dataStream.listen(events.add);

      socket.dispose();

      // Try sending data from server (may throw since client socket is destroyed)
      try {
        server.sendToAll([99, 98, 97]);
      } catch (_) {
        // Expected -- server-side socket may already be destroyed
      }
      await Future.delayed(const Duration(milliseconds: 200));

      expect(events, isEmpty);
    });
  });

  group('reconnect', () {
    test('auto-reconnects after server disconnect', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();

      // Server disconnects all clients
      server.disconnectAll();

      // Wait for disconnected
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);

      // Wait for auto-reconnect (backoff is 500ms, so 3s timeout is generous)
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Server should have a new client
      await server.waitForClient();
      expect(server.clientCount, equals(1));

      socket.dispose();
    });

    test('data stream continues after reconnect', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      // Capture stream reference before connect
      final stream = socket.dataStream;

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();
      await Future.delayed(const Duration(milliseconds: 50));

      // Send data before disconnect
      server.sendToAll([1, 2, 3]);
      final data1 = await stream.first;
      expect(data1, equals([1, 2, 3]));

      // Disconnect and wait for reconnect
      server.disconnectAll();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));
      await server.waitForClient();
      await Future.delayed(const Duration(milliseconds: 50));

      // Send data after reconnect -- same stream reference
      server.sendToAll([4, 5, 6]);
      final data2 = await stream.first;
      expect(data2, equals([4, 5, 6]));

      socket.dispose();
    });

    test('status transitions through full reconnect cycle', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      final statuses = <ConnectionStatus>[];
      socket.statusStream.listen(statuses.add);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();

      // Disconnect
      server.disconnectAll();

      // Wait for reconnect
      await socket.statusStream
          .where((s) => s == ConnectionStatus.connected)
          .skip(1) // Skip the first connected we already got
          .first
          .timeout(const Duration(seconds: 3));

      // Verify full cycle: disconnected (seed), connecting, connected,
      // disconnected, connecting, connected
      expect(statuses, containsAllInOrder([
        ConnectionStatus.disconnected, // initial seed
        ConnectionStatus.connecting,
        ConnectionStatus.connected,
        ConnectionStatus.disconnected, // after server disconnect
        ConnectionStatus.connecting,   // reconnect attempt
        ConnectionStatus.connected,    // reconnected
      ]));

      socket.dispose();
    });

    test('backoff resets after successful reconnect', () async {
      final port = await server.start();

      // Record what the loop asks to wait for, then actually wait it. The
      // socket work is real; only the assertion is freed from the clock. The
      // old version timed the reconnect with a Stopwatch and asserted "under
      // 1000ms", which on a slow runner is indistinguishable from a backoff
      // that never reset.
      final delays = <Duration>[];
      final socket = MSocket('localhost', port, delay: (d) {
        delays.add(d);
        return Future<void>.delayed(d);
      });

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();

      // First disconnect + reconnect
      server.disconnectAll();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 10));
      await server.waitForClient();

      // Second disconnect + reconnect
      server.disconnectAll();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 10));

      socket.dispose();

      expect(
          delays,
          orderedEquals(const [
            Duration(milliseconds: 500),
            Duration(milliseconds: 500),
          ]),
          reason: 'The second retry must wait another 500ms. A second wait of '
              '1s would mean the successful reconnect never reset the ladder. '
              'Got $delays');
    });

    test('dispose during backoff cancels reconnect', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();

      // Shut down server so reconnect will fail
      await server.shutdown();

      // Wait for disconnected
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);

      // Small delay -- MSocket is now in backoff wait
      await Future.delayed(const Duration(milliseconds: 100));

      // Collect status events after dispose
      final postDisposeStatuses = <ConnectionStatus>[];
      socket.statusStream.listen(
        postDisposeStatuses.add,
        onError: (_) {},
        onDone: () {},
      );

      socket.dispose();

      // Wait to see if any further events arrive
      await Future.delayed(const Duration(seconds: 2));

      // After dispose, no connecting/connected events should appear
      // (the done event from stream close is ok, but no state transitions)
      final reconnectAttempts = postDisposeStatuses
          .where((s) => s == ConnectionStatus.connecting ||
                        s == ConnectionStatus.connected)
          .length;
      expect(reconnectAttempts, equals(0),
          reason: 'No reconnect attempts should occur after dispose');
    });

    test('dispose during active connection stops loop', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      // Collect events
      final postDisposeStatuses = <ConnectionStatus>[];
      final sub = socket.statusStream.listen(postDisposeStatuses.add);

      socket.dispose();
      await Future.delayed(const Duration(milliseconds: 500));

      // No connecting event should appear after dispose
      final connectingAfterDispose = postDisposeStatuses
          .where((s) => s == ConnectionStatus.connecting)
          .length;
      expect(connectingAfterDispose, equals(0),
          reason: 'No reconnect should be attempted after dispose');

      await sub.cancel();
    });

    test('connect to unreachable host retries', () async {
      // A real socket against a port nobody is listening on, so the real
      // failure path runs -- but with the backoff waits neutralised, because
      // how long an OS takes to refuse a connection is not this test's
      // subject. (It was, implicitly, the old version's subject: it slept a
      // fixed 3s and counted whatever had happened, which on Windows was one
      // retry fewer than it demanded.) The backoff durations themselves are
      // covered by the 'backoff timing' group.
      final socket =
          MSocket('localhost', 59999, delay: (_) => Future<void>.value());

      final statuses = <ConnectionStatus>[];
      final sawThreeAttempts = Completer<void>();
      socket.statusStream.listen((s) {
        statuses.add(s);
        if (statuses.where((x) => x == ConnectionStatus.connecting).length >=
                3 &&
            !sawThreeAttempts.isCompleted) {
          sawThreeAttempts.complete();
        }
      });

      socket.connect();

      // Event-driven: as fast as this machine can refuse three connections.
      await sawThreeAttempts.future.timeout(const Duration(seconds: 30));
      socket.dispose();

      // The loop must cycle, not just fail once and stop.
      expect(
          statuses,
          containsAllInOrder(const [
            ConnectionStatus.disconnected, // seed
            ConnectionStatus.connecting,
            ConnectionStatus.disconnected, // attempt 1 failed
            ConnectionStatus.connecting,
            ConnectionStatus.disconnected, // attempt 2 failed
            ConnectionStatus.connecting,
          ]),
          reason: 'Each failed attempt must be followed by another one. '
              'Got $statuses');
    });
  });

  group('backoff timing', () {
    test('initial backoff is 500ms', () async {
      final port = await server.start();

      final firstDelay = Completer<Duration>();
      final socket = MSocket('localhost', port, delay: (d) {
        if (!firstDelay.isCompleted) firstDelay.complete(d);
        return Future<void>.delayed(d);
      });

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();

      // Shut the server down so the loop drops into its backoff wait.
      await server.shutdown();

      expect(await firstDelay.future.timeout(const Duration(seconds: 10)),
          const Duration(milliseconds: 500));

      socket.dispose();
    });

    test('backoff doubles each retry and caps at 5 seconds', () async {
      // 8 retries: 500, 1s, 2s, 4s, then 5s forever. Without the cap the 5th
      // would be 8s and the 8th 64s.
      final delays = await recordBackoffLadder(8);

      expect(
          delays,
          orderedEquals(const [
            Duration(milliseconds: 500),
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 4),
            Duration(seconds: 5),
            Duration(seconds: 5),
            Duration(seconds: 5),
            Duration(seconds: 5),
          ]));
    });

    test('an uninjected socket waits real time before retrying', () async {
      // The tests above hand MSocket a delay function, so on their own they
      // would still pass if the production default became an instant retry.
      // This one uses the real constructor. It asserts a lower bound only: a
      // slow machine can only make the gap longer, never shorter.
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();
      await server.shutdown();

      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);
      final sw = Stopwatch()..start();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connecting)
          .timeout(const Duration(seconds: 10));
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(300),
          reason: 'The default backoff must be a real wait (500ms), not an '
              'instant retry. Got ${sw.elapsedMilliseconds}ms');

      socket.dispose();
    });
  });
}

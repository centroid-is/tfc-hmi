import 'dart:async';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:test/test.dart';

import 'test_tcp_server.dart';

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
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();

      // First disconnect + reconnect
      server.disconnectAll();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);
      final sw1 = Stopwatch()..start();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));
      sw1.stop();
      await server.waitForClient();

      // Second disconnect + reconnect -- should also be ~500ms (not 1s)
      server.disconnectAll();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);
      final sw2 = Stopwatch()..start();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));
      sw2.stop();

      // Both reconnects should be approximately 500ms (backoff reset)
      // Use generous tolerance for CI stability
      expect(sw2.elapsedMilliseconds, lessThan(1000),
          reason: 'Second reconnect should be ~500ms (reset backoff), '
              'not 1s+ (doubled backoff). Got ${sw2.elapsedMilliseconds}ms');

      socket.dispose();
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

    test('connect to unreachable host retries with backoff', () async {
      // Use a port where no server is listening
      final socket = MSocket('localhost', 59999);

      final statuses = <ConnectionStatus>[];
      socket.statusStream.listen(statuses.add);

      socket.connect();

      // Wait for at least 2 retry cycles
      await Future.delayed(const Duration(seconds: 3));

      // Should see connecting, disconnected pattern repeated
      final connectingCount =
          statuses.where((s) => s == ConnectionStatus.connecting).length;
      final disconnectedCount =
          statuses.where((s) => s == ConnectionStatus.disconnected).length;

      expect(connectingCount, greaterThanOrEqualTo(2),
          reason: 'Should have at least 2 connecting events (retries)');
      // disconnected count: 1 seed + at least 2 failures = at least 3
      expect(disconnectedCount, greaterThanOrEqualTo(3),
          reason: 'Should have at least 3 disconnected events '
              '(1 seed + 2 failures)');

      socket.dispose();
    });
  });

  group('backoff timing', () {
    test('initial backoff is approximately 500ms', () async {
      final port = await server.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);
      await server.waitForClient();

      // Shut down server so reconnect attempt fails, then times the gap
      await server.shutdown();

      // Wait for disconnected
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected);
      final sw = Stopwatch()..start();

      // Wait for the next connecting event (after backoff delay)
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connecting)
          .timeout(const Duration(seconds: 3));
      sw.stop();

      // Initial backoff should be ~500ms (tolerance: 300ms-900ms for CI)
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(300),
          reason: 'Backoff should be at least 300ms');
      expect(sw.elapsedMilliseconds, lessThanOrEqualTo(900),
          reason: 'Initial backoff should not exceed 900ms');

      socket.dispose();
    });

    test('backoff caps at 5 seconds', () async {
      // Connect to unreachable port to trigger repeated failures
      final socket = MSocket('localhost', 59998);

      final connectingTimestamps = <int>[];
      socket.statusStream.listen((s) {
        if (s == ConnectionStatus.connecting) {
          connectingTimestamps.add(DateTime.now().millisecondsSinceEpoch);
        }
      });

      socket.connect();

      // Wait long enough for at least 5 cycles:
      // 500 + 1000 + 2000 + 4000 + 5000 = 12500ms, plus connect timeouts
      // With 3s connect timeout per attempt, we need much more time.
      // Actually, connect to localhost should fail fast (connection refused).
      // So: 500 + 1000 + 2000 + 4000 + 5000 ~= 12.5s + fast fails
      await Future.delayed(const Duration(seconds: 16));

      socket.dispose();

      // Need at least 6 timestamps (initial + 5 retries) to check capping
      expect(connectingTimestamps.length, greaterThanOrEqualTo(6),
          reason: 'Need at least 6 connecting events to verify cap. '
              'Got ${connectingTimestamps.length}');

      // Check deltas between connecting events
      final deltas = <int>[];
      for (var i = 1; i < connectingTimestamps.length; i++) {
        deltas.add(connectingTimestamps[i] - connectingTimestamps[i - 1]);
      }

      // Expected approximate deltas: 500, 1000, 2000, 4000, 5000, 5000...
      // Use generous tolerance (0.5x to 2.0x) for CI stability.
      // The last few deltas should be capped at ~5000ms (not growing beyond)
      if (deltas.length >= 5) {
        // The 5th+ deltas should be close to 5s (capped), not 8s or 16s
        for (var i = 4; i < deltas.length; i++) {
          expect(deltas[i], lessThanOrEqualTo(8000),
              reason: 'Delta[$i]=${deltas[i]}ms should be capped at ~5s');
        }
      }
    });
  });
}

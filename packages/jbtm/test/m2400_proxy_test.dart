import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:test/test.dart';

void main() {
  // TestTcpServer acts as the fake upstream M2400 device.
  late TestTcpServer upstream;

  // The proxy under test.
  late M2400Proxy proxy;

  // Track downstream sockets for cleanup.
  final downstreamSockets = <Socket>[];

  setUp(() async {
    upstream = TestTcpServer();
    await upstream.start();

    proxy = M2400Proxy(
      upstreamHost: 'localhost',
      upstreamPort: upstream.port,
      listenPort: 0, // OS-assigned
      listenAddress: InternetAddress.loopbackIPv4,
    );
  });

  tearDown(() async {
    for (final s in downstreamSockets) {
      s.destroy();
    }
    downstreamSockets.clear();
    await proxy.shutdown();
    await upstream.shutdown();
  });

  /// Connect a raw downstream client to the proxy.
  Future<Socket> connectClient(int port) async {
    final socket = await Socket.connect('localhost', port);
    downstreamSockets.add(socket);
    return socket;
  }

  /// Collect all data from a socket into a list of byte chunks.
  List<Uint8List> collectData(Socket socket) {
    final chunks = <Uint8List>[];
    socket.listen(
      (data) => chunks.add(Uint8List.fromList(data)),
      onError: (_) {},
    );
    return chunks;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  group('lifecycle', () {
    test('start() binds listen port and connects upstream', () async {
      await proxy.start();

      // Upstream should see the proxy connect
      await upstream.waitForClient();
      expect(upstream.clientCount, equals(1));
    });

    test('shutdown() closes all downstream clients', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));

      final disconnected = Completer<void>();
      client.listen((_) {}, onDone: () {
        if (!disconnected.isCompleted) disconnected.complete();
      }, onError: (_) {
        if (!disconnected.isCompleted) disconnected.complete();
      });

      await proxy.shutdown();
      await disconnected.future.timeout(const Duration(seconds: 2));
    });

    test('shutdown() is safe to call multiple times', () async {
      await proxy.start();
      await proxy.shutdown();
      await proxy.shutdown(); // should not throw
    });
  });

  // ---------------------------------------------------------------------------
  // Fan-out
  // ---------------------------------------------------------------------------
  group('fan-out', () {
    test('upstream data reaches a single downstream client', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      final chunks = collectData(client);
      final payload = [1, 2, 3, 4, 5];
      upstream.sendToAll(payload);

      await Future.delayed(const Duration(milliseconds: 100));
      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals(payload));
    });

    test('upstream data reaches multiple clients simultaneously', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client1 = await connectClient(proxy.listenPort);
      final client2 = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      final chunks1 = collectData(client1);
      final chunks2 = collectData(client2);

      final payload = [10, 20, 30];
      upstream.sendToAll(payload);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(chunks1.expand((c) => c).toList(), equals(payload));
      expect(chunks2.expand((c) => c).toList(), equals(payload));
    });

    test('new client receives only data sent after connection (no replay)',
        () async {
      await proxy.start();
      await upstream.waitForClient();

      // Send data before any client connects
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Now connect a client
      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send new data
      upstream.sendToAll([4, 5, 6]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Client should only see [4, 5, 6], not [1, 2, 3]
      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals([4, 5, 6]));
    });
  });

  // ---------------------------------------------------------------------------
  // Client management
  // ---------------------------------------------------------------------------
  group('client management', () {
    test('clientCount tracks connections accurately', () async {
      await proxy.start();
      await upstream.waitForClient();
      expect(proxy.clientCount, equals(0));

      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));

      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(2));
    });

    test('handles client disconnect gracefully', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client1 = await connectClient(proxy.listenPort);
      final client2 = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(2));

      // Disconnect client1
      client1.destroy();
      downstreamSockets.remove(client1);
      // Wait for the server-side done handler to fire
      await Future.delayed(const Duration(milliseconds: 300));
      expect(proxy.clientCount, equals(1));

      // client2 should still receive data
      final chunks = collectData(client2);
      upstream.sendToAll([7, 8, 9]);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(chunks.expand((c) => c).toList(), equals([7, 8, 9]));
    });
  });

  // ---------------------------------------------------------------------------
  // Network loss — upstream
  // ---------------------------------------------------------------------------
  group('upstream network loss', () {
    test('downstream clients stay connected when upstream disconnects',
        () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      // Simulate upstream device reboot
      upstream.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 200));

      // Client should still be connected (proxy doesn't drop clients on
      // upstream loss)
      expect(proxy.clientCount, equals(1));

      // Verify client socket is still writable (not errored)
      expect(() => client.add([0]), returnsNormally);
    });

    test('data resumes flowing after upstream reconnects', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send initial data
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Disconnect upstream
      upstream.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 200));

      // MSocket will auto-reconnect — wait for it
      await upstream.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      // Send data on the new upstream connection
      upstream.sendToAll([4, 5, 6]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Client should have received both payloads
      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, containsAllInOrder([1, 2, 3]));
      expect(allBytes, containsAllInOrder([4, 5, 6]));
    });

    test('proxy stays up when upstream never connects', () async {
      // Create proxy pointing at a port nothing is listening on
      final nowhereProxy = M2400Proxy(
        upstreamHost: 'localhost',
        upstreamPort: 59999, // nothing here
        listenPort: 0,
        listenAddress: InternetAddress.loopbackIPv4,
      );

      await nowhereProxy.start();

      // Clients can still connect to the proxy
      final client =
          await Socket.connect('localhost', nowhereProxy.listenPort);
      downstreamSockets.add(client);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(nowhereProxy.clientCount, equals(1));

      await nowhereProxy.shutdown();
    });
  });

  // ---------------------------------------------------------------------------
  // Network loss — downstream
  // ---------------------------------------------------------------------------
  group('downstream network loss', () {
    test('abrupt client disconnect handled without error', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));

      // Abrupt disconnect
      client.destroy();
      downstreamSockets.remove(client);

      // Send data — proxy should handle the dead client without crashing
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 100));

      // No crash, clientCount updated
      expect(proxy.clientCount, equals(0));
    });

    test('all clients disconnect, proxy continues', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client1 = await connectClient(proxy.listenPort);
      final client2 = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      client1.destroy();
      client2.destroy();
      downstreamSockets.clear();
      // Wait for the server-side done handlers to fire
      await Future.delayed(const Duration(milliseconds: 300));

      expect(proxy.clientCount, equals(0));

      // New client can still connect
      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));
    });

    test('client connects during upstream disconnect, receives data on recovery',
        () async {
      await proxy.start();
      await upstream.waitForClient();

      // Disconnect upstream
      upstream.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 100));

      // Client connects while upstream is down
      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      expect(proxy.clientCount, equals(1));

      // Wait for upstream to reconnect
      await upstream.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      // Send data on the new upstream connection
      upstream.sendToAll([10, 20, 30]);
      await Future.delayed(const Duration(milliseconds: 100));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals([10, 20, 30]));
    });
  });

  // ---------------------------------------------------------------------------
  // Packet fragmentation / chunking
  // ---------------------------------------------------------------------------
  group('packet handling', () {
    test('large payload forwarded correctly', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send a large payload (64KB)
      final bigPayload = List<int>.generate(65536, (i) => i % 256);
      upstream.sendToAll(bigPayload);

      // Wait enough for all data to arrive
      await Future.delayed(const Duration(milliseconds: 500));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals(bigPayload));
    });

    test('rapid burst of small packets all forwarded', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send 100 tiny packets rapidly
      for (var i = 0; i < 100; i++) {
        upstream.sendToAll([i]);
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, hasLength(100));
      for (var i = 0; i < 100; i++) {
        expect(allBytes[i], equals(i));
      }
    });

    test('partial M2400 frames forwarded transparently', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send a partial frame (STX but no ETX) — proxy shouldn't care
      final partialFrame = [0x02, 0x41, 0x42, 0x43]; // STX + "ABC"
      upstream.sendToAll(partialFrame);

      await Future.delayed(const Duration(milliseconds: 100));

      // Then send the rest
      final rest = [0x44, 0x45, 0x03]; // "DE" + ETX
      upstream.sendToAll(rest);

      await Future.delayed(const Duration(milliseconds: 100));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals([...partialFrame, ...rest]));
    });
  });

  // ---------------------------------------------------------------------------
  // Stress / edge cases
  // ---------------------------------------------------------------------------
  group('edge cases', () {
    test('client connects and immediately disconnects', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      client.destroy();
      downstreamSockets.remove(client);

      // Send data — should not crash
      await Future.delayed(const Duration(milliseconds: 100));
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Proxy still operational
      expect(proxy.clientCount, equals(0));
    });

    test('multiple clients connect simultaneously', () async {
      await proxy.start();
      await upstream.waitForClient();

      // Connect 10 clients at once
      final futures = List.generate(
        10,
        (_) => connectClient(proxy.listenPort),
      );
      await Future.wait(futures);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(proxy.clientCount, equals(10));

      // All should receive data
      final allChunks = <List<Uint8List>>[];
      for (final client in downstreamSockets) {
        allChunks.add(collectData(client));
      }

      upstream.sendToAll([42]);
      await Future.delayed(const Duration(milliseconds: 100));

      for (final chunks in allChunks) {
        final bytes = chunks.expand((c) => c).toList();
        expect(bytes, equals([42]));
      }
    });

    test('shutdown during active data flow', () async {
      await proxy.start();
      await upstream.waitForClient();

      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      // Start sending data and immediately shutdown — should not crash
      upstream.sendToAll([1, 2, 3]);
      await proxy.shutdown();
      // If we get here without exception, the test passes
    });
  });
}

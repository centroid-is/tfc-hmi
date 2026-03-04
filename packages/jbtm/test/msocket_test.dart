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

      socket.connect();
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.connected);

      // Server disconnects all clients
      server.disconnectAll();

      // Wait for disconnected status
      await socket.statusStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 5));

      expect(socket.status, equals(ConnectionStatus.disconnected));

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

      socket.dispose();

      // After dispose, subscribe and send data -- no events should arrive
      final events = <Uint8List>[];
      socket.dataStream.listen(events.add);

      server.sendToAll([99, 98, 97]);
      await Future.delayed(const Duration(milliseconds: 200));

      expect(events, isEmpty);
    });
  });
}

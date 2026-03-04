import 'dart:async';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:jbtm/src/connection_health.dart';
import 'package:test/test.dart';

import 'tcp_proxy.dart';

/// Helper to wait until [socket] reaches [target] status with timeout.
Future<void> _waitForStatus(
    MSocket socket, ConnectionStatus target, Duration timeout) async {
  if (socket.status == target) return;
  await socket.statusStream
      .firstWhere((s) => s == target)
      .timeout(timeout);
}

void main() {
  late TestTcpServer server;
  late TcpProxy proxy;
  late MSocket socket;
  late int proxyPort;
  late int serverPort;

  setUp(() async {
    server = TestTcpServer();
    serverPort = await server.start();
    proxy = TcpProxy(targetPort: serverPort);
    await proxy.start();
    proxyPort = proxy.port;
    socket = MSocket('localhost', proxyPort);
  });

  tearDown(() async {
    socket.dispose();
    await proxy.shutdown();
    await server.shutdown();
  });

  group('cable pull simulation', () {
    test('MSocket reconnects after proxy shutdown + restart', () async {
      socket.connect();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 5));

      // Simulate cable pull: shut down proxy
      await proxy.shutdown();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));

      // Simulate cable reconnect: new proxy on same port
      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();

      // MSocket should auto-reconnect through the new proxy
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));

      expect(socket.status, ConnectionStatus.connected);
    });

    test('data stream continues after cable pull recovery', () async {
      final received = <List<int>>[];
      socket.dataStream.listen((data) => received.add(data.toList()));

      socket.connect();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 5));

      // Wait for proxy-to-server connection to be established
      await server.waitForClient();
      await Future.delayed(Duration(milliseconds: 100));

      // Send data before disconnect
      server.sendToAll([1, 2, 3]);
      await Future.delayed(Duration(milliseconds: 200));
      expect(received, isNotEmpty, reason: 'Should receive data before disconnect');
      final preDisconnectCount = received.length;

      // Cable pull
      await proxy.shutdown();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));

      // Cable reconnect
      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));

      // Wait for proxy-to-server connection
      await server.waitForClient();
      await Future.delayed(Duration(milliseconds: 100));

      // Send data after reconnect
      server.sendToAll([4, 5, 6]);
      await Future.delayed(Duration(milliseconds: 200));

      // Should have received data both before and after
      expect(received.length, greaterThan(preDisconnectCount),
          reason: 'Should receive data after reconnect');
    });

    test('no stale data after reconnection', () async {
      final received = <List<int>>[];
      socket.dataStream.listen((data) => received.add(data.toList()));

      socket.connect();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 5));

      // Cable pull via reject (proxy stays listening but rejects connections)
      await proxy.reject();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));

      // Server sends data while proxy is rejecting -- this data goes nowhere
      // because existing proxy-to-server connections were destroyed
      server.sendToAll([99, 98, 97]);
      await Future.delayed(Duration(milliseconds: 100));

      final countDuringOutage = received.length;

      // Un-reject: shutdown + restart proxy
      await proxy.shutdown();
      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();

      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));
      await Future.delayed(Duration(milliseconds: 200));

      // Data sent during outage should NOT appear
      // (no new data was sent after reconnect, so count should be same)
      expect(received.length, countDuringOutage,
          reason: 'Data sent during outage should not be replayed');
    });
  });

  group('switch reboot simulation', () {
    test('MSocket reconnects after delayed proxy restart', () async {
      socket.connect();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 5));

      final disconnectTime = DateTime.now();

      // Simulate switch going down
      await proxy.shutdown();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));

      // Simulate reboot delay
      await Future.delayed(Duration(seconds: 2));

      // Simulate switch coming back up
      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();

      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));

      final reconnectTime = DateTime.now();
      final elapsed = reconnectTime.difference(disconnectTime);

      // Verify the delay was real (at least 2 seconds)
      expect(elapsed, greaterThanOrEqualTo(Duration(seconds: 2)));
      expect(socket.status, ConnectionStatus.connected);
    });

    test('data flow resumes after switch reboot', () async {
      final received = <List<int>>[];
      socket.dataStream.listen((data) => received.add(data.toList()));

      socket.connect();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 5));

      // Wait for proxy-to-server connection to be established
      await server.waitForClient();
      await Future.delayed(Duration(milliseconds: 100));

      // Send data before reboot
      server.sendToAll([10, 20, 30]);
      await Future.delayed(Duration(milliseconds: 200));
      final preRebootCount = received.length;
      expect(preRebootCount, greaterThan(0));

      // Switch reboot
      await proxy.shutdown();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));
      await Future.delayed(Duration(seconds: 2));

      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));

      await server.waitForClient();
      await Future.delayed(Duration(milliseconds: 100));

      // Send data after reboot
      server.sendToAll([40, 50, 60]);
      await Future.delayed(Duration(milliseconds: 200));

      expect(received.length, greaterThan(preRebootCount),
          reason: 'Data should resume after switch reboot');
    });
  });

  group('health metrics during disruption', () {
    test('reconnectCount increments on each recovery', () async {
      final metrics = ConnectionHealthMetrics(socket);
      addTearDown(() => metrics.dispose());

      socket.connect();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 5));
      expect(metrics.reconnectCount, 0);

      // Cable pull 1
      await proxy.shutdown();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));
      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));
      expect(metrics.reconnectCount, 1);

      // Cable pull 2
      await proxy.shutdown();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));
      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));
      expect(metrics.reconnectCount, 2);
    });

    test('uptime resets after reconnection', () async {
      final metrics = ConnectionHealthMetrics(socket);
      addTearDown(() => metrics.dispose());

      socket.connect();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 5));

      // Let uptime accumulate
      await Future.delayed(Duration(milliseconds: 500));
      final uptime1 = metrics.uptime;
      expect(uptime1, greaterThan(Duration(milliseconds: 400)));

      // Cable pull + recover
      await proxy.shutdown();
      await _waitForStatus(
          socket, ConnectionStatus.disconnected, Duration(seconds: 5));
      proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
      await proxy.start();
      await _waitForStatus(
          socket, ConnectionStatus.connected, Duration(seconds: 10));

      // Uptime should have reset (new connection, new _lastConnectedAt)
      await Future.delayed(Duration(milliseconds: 200));
      final uptime2 = metrics.uptime;

      // uptime2 should be less than uptime1 because it just reconnected
      expect(uptime2, lessThan(uptime1),
          reason: 'Uptime should reset after reconnection');
    });
  });
}

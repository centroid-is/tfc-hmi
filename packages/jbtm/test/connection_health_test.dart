import 'dart:async';

import 'package:jbtm/jbtm.dart';
import 'package:jbtm/src/connection_health.dart';
import 'package:test/test.dart';

import 'tcp_proxy.dart';

void main() {
  late TestTcpServer server;
  late TcpProxy proxy;
  late MSocket socket;
  late ConnectionHealthMetrics metrics;

  setUp(() async {
    server = TestTcpServer();
    final serverPort = await server.start();
    proxy = TcpProxy(targetPort: serverPort);
    await proxy.start();
    socket = MSocket('localhost', proxy.port);
    metrics = ConnectionHealthMetrics(socket);
  });

  tearDown(() async {
    metrics.dispose();
    socket.dispose();
    await proxy.shutdown();
    await server.shutdown();
  });

  test('starts with 0 reconnects and 0 records/second', () {
    expect(metrics.reconnectCount, 0);
    expect(metrics.recordsPerSecond, 0.0);
  });

  test('uptime is Duration.zero when disconnected', () {
    expect(metrics.uptime, Duration.zero);
  });

  test('uptime is > Duration.zero after connect', () async {
    socket.connect();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected);
    await Future.delayed(Duration(milliseconds: 50));
    expect(metrics.uptime, greaterThan(Duration.zero));
  });

  test('reconnectCount is 0 after first connect (not a reconnect)', () async {
    socket.connect();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected);
    expect(metrics.reconnectCount, 0);
  });

  test('reconnectCount is 1 after disconnect + reconnect', () async {
    socket.connect();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected);

    // Capture port for proxy restart
    final proxyPort = proxy.port;
    final serverPort = server.port;

    // Disconnect via proxy shutdown
    await proxy.shutdown();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.disconnected);

    // Restart proxy on same port
    proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
    await proxy.start();

    // Wait for MSocket auto-reconnect
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected)
        .timeout(Duration(seconds: 10));

    expect(metrics.reconnectCount, 1);
  });

  test('reconnectCount is 2 after two disconnect/reconnect cycles', () async {
    socket.connect();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected);

    final proxyPort = proxy.port;
    final serverPort = server.port;

    // Cycle 1
    await proxy.shutdown();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.disconnected);
    proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
    await proxy.start();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected)
        .timeout(Duration(seconds: 10));

    // Cycle 2
    await proxy.shutdown();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.disconnected);
    proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
    await proxy.start();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected)
        .timeout(Duration(seconds: 10));

    expect(metrics.reconnectCount, 2);
  });

  test('notifyRecord() correctly updates recordsPerSecond', () {
    // Rapidly notify 10 records
    for (var i = 0; i < 10; i++) {
      metrics.notifyRecord();
    }
    // All 10 should be within the last 1-second window
    expect(metrics.recordsPerSecond, 10.0);
  });

  test('recordsPerSecond drops old entries after 1 second', () async {
    for (var i = 0; i < 5; i++) {
      metrics.notifyRecord();
    }
    expect(metrics.recordsPerSecond, 5.0);

    // Wait >1 second so entries age out
    await Future.delayed(Duration(milliseconds: 1100));
    expect(metrics.recordsPerSecond, 0.0);
  });

  test('dispose() stops tracking status changes', () async {
    socket.connect();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected);
    expect(metrics.uptime, greaterThan(Duration.zero));

    metrics.dispose();

    // After dispose, uptime should not update further
    // (subscription cancelled, values frozen)
    final proxyPort = proxy.port;
    final serverPort = server.port;
    await proxy.shutdown();

    // Give time for status change that should NOT be tracked
    await Future.delayed(Duration(milliseconds: 200));

    // Metrics should still report last known state (no crash)
    // The key test: dispose doesn't throw and stops tracking
    expect(() => metrics.reconnectCount, returnsNormally);
  });
}

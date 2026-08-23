import 'package:jbtm/jbtm.dart';
import 'package:jbtm/src/connection_health.dart';
import 'package:test/test.dart';

import 'tcp_proxy.dart';

void main() {
  late TestTcpServer server;
  late TcpProxy proxy;
  late MSocket socket;
  late ConnectionHealthMetrics metrics;
  late TestClock clock;

  setUp(() async {
    server = TestTcpServer();
    final serverPort = await server.start();
    proxy = TcpProxy(targetPort: serverPort);
    await proxy.start();
    socket = MSocket('localhost', proxy.port);
    // Drive the metrics off a clock the test moves by hand. Both uptime and
    // recordsPerSecond are differences between two clock reads, and Windows
    // ticks its clock in ~15.6ms steps, so anything measured by sleeping is
    // either flaky or has to sleep long enough to be slow.
    clock = TestClock();
    metrics = ConnectionHealthMetrics(socket, now: clock.now);
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

  test('uptime counts from the moment of connect', () async {
    socket.connect();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected);

    expect(metrics.uptime, Duration.zero,
        reason: 'no time has passed since connecting');

    clock.advance(Duration(seconds: 42));
    expect(metrics.uptime, Duration(seconds: 42));
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

  test('recordsPerSecond drops entries older than the 1 second window', () {
    for (var i = 0; i < 5; i++) {
      metrics.notifyRecord();
    }
    expect(metrics.recordsPerSecond, 5.0);

    // Still inside the window: nothing has aged out yet.
    clock.advance(Duration(milliseconds: 900));
    expect(metrics.recordsPerSecond, 5.0,
        reason: 'entries 900ms old are still within the 1s window');

    // Now past it.
    clock.advance(Duration(milliseconds: 200));
    expect(metrics.recordsPerSecond, 0.0);
  });

  test('dispose() stops tracking status changes', () async {
    socket.connect();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected);
    clock.advance(Duration(seconds: 3));
    expect(metrics.uptime, Duration(seconds: 3));
    expect(metrics.reconnectCount, 0);

    metrics.dispose();

    // Now force a real disconnect + reconnect. A metrics object that had not
    // cancelled its subscription would count this as a reconnect and restart
    // its uptime -- which is what this test is named for, and what the old
    // version (expect(() => metrics.reconnectCount, returnsNormally)) never
    // actually checked.
    final proxyPort = proxy.port;
    final serverPort = server.port;
    await proxy.shutdown();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.disconnected);
    proxy = TcpProxy(listenPort: proxyPort, targetPort: serverPort);
    await proxy.start();
    await socket.statusStream
        .firstWhere((s) => s == ConnectionStatus.connected)
        .timeout(Duration(seconds: 10));

    expect(metrics.reconnectCount, 0,
        reason: 'a disposed metrics object must not observe the reconnect');
    clock.advance(Duration(seconds: 1));
    expect(metrics.uptime, Duration(seconds: 4),
        reason: 'uptime must still be measured from the pre-dispose connect');
  });
}

/// A clock the test moves by hand, so metrics that are differences between two
/// clock reads can be asserted exactly instead of being slept for.
class TestClock {
  DateTime _now = DateTime.utc(2026, 1, 1);

  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}

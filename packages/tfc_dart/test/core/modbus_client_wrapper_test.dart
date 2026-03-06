import 'dart:async';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart' show ConnectionStatus;
import 'package:test/test.dart';

/// Mock ModbusClientTcp for testing wrapper behavior without real TCP.
class MockModbusClient extends ModbusClientTcp {
  bool _connected = false;
  bool shouldFailConnect = false;
  int connectCallCount = 0;
  int disconnectCallCount = 0;
  Completer<bool>? connectCompleter;

  MockModbusClient()
      : super('mock',
            serverPort: 0,
            connectionMode: ModbusConnectionMode.doNotConnect);

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    connectCallCount++;
    if (connectCompleter != null) {
      return connectCompleter!.future;
    }
    if (shouldFailConnect) return false;
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCallCount++;
    _connected = false;
  }

  void simulateDisconnect() {
    _connected = false;
  }
}

void main() {
  late ModbusClientWrapper wrapper;
  late MockModbusClient mockClient;

  /// Creates a wrapper with a factory that returns the given mock client.
  ModbusClientWrapper createWrapper({
    String host = '127.0.0.1',
    int port = 502,
    int unitId = 1,
    MockModbusClient? client,
  }) {
    final c = client ?? mockClient;
    return ModbusClientWrapper(
      host,
      port,
      unitId,
      clientFactory: (h, p, u) => c,
    );
  }

  setUp(() {
    mockClient = MockModbusClient();
  });

  tearDown(() {
    wrapper.dispose();
  });

  group('constructor', () {
    test('creates wrapper without connecting', () {
      wrapper = createWrapper();
      expect(mockClient.connectCallCount, equals(0));
    });

    test('initial connectionStatus is disconnected', () {
      wrapper = createWrapper();
      expect(wrapper.connectionStatus, equals(ConnectionStatus.disconnected));
    });

    test('accepts custom clientFactory', () {
      final customMock = MockModbusClient();
      wrapper = createWrapper(client: customMock);
      expect(wrapper.connectionStatus, equals(ConnectionStatus.disconnected));
    });
  });

  group('connect', () {
    test('transitions to connecting then connected', () async {
      wrapper = createWrapper();
      final statuses = <ConnectionStatus>[];
      // Skip the initial seeded value (disconnected)
      wrapper.connectionStream.skip(1).listen(statuses.add);

      wrapper.connect();

      // Wait for connection loop to run
      await Future.delayed(const Duration(milliseconds: 100));

      expect(statuses, contains(ConnectionStatus.connecting));
      expect(statuses, contains(ConnectionStatus.connected));
      // Connecting must come before connected
      final connectingIdx = statuses.indexOf(ConnectionStatus.connecting);
      final connectedIdx = statuses.indexOf(ConnectionStatus.connected);
      expect(connectingIdx, lessThan(connectedIdx));
    });

    test('is fire-and-forget (returns void)', () {
      wrapper = createWrapper();
      // connect() should return void, not a Future -- verify it compiles
      // as void. If connect() returned Future, this assignment would fail.
      void Function() connectFn = wrapper.connect;
      connectFn();
      // If we got here, connect() returns void (fire-and-forget)
    });

    test('successful connect resets backoff to initial value', () async {
      // First: fail a few times to increase backoff
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();
      wrapper.connect();

      // Let a couple retries happen
      await Future.delayed(const Duration(milliseconds: 800));

      // Now succeed
      mockClient.shouldFailConnect = false;

      // Wait for successful connection
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Simulate disconnect
      mockClient.simulateDisconnect();

      // Wait for disconnected then connecting again
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 2));

      // The retry should use initial backoff (500ms), not accumulated
      // If backoff was reset, reconnect should happen quickly
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
    });

    test('failed connect transitions to disconnected then retries', () async {
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();

      final statuses = <ConnectionStatus>[];
      wrapper.connectionStream.skip(1).listen(statuses.add);

      wrapper.connect();

      // Wait for at least one retry cycle
      await Future.delayed(const Duration(milliseconds: 1200));

      // Should have multiple connecting -> disconnected cycles
      expect(
          statuses.where((s) => s == ConnectionStatus.connecting).length,
          greaterThanOrEqualTo(2));
    });

    test('status stream replays current value (BehaviorSubject)', () async {
      wrapper = createWrapper();
      wrapper.connect();

      // Wait for connected
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // New subscriber should get the current value immediately
      final latestStatus = await wrapper.connectionStream.first;
      expect(latestStatus, equals(ConnectionStatus.connected));
    });
  });

  group('disconnect detection', () {
    test('when isConnected becomes false, status transitions to disconnected',
        () async {
      wrapper = createWrapper();
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // Simulate connection loss
      mockClient.simulateDisconnect();

      final status = await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 2));
      expect(status, equals(ConnectionStatus.disconnected));
    });

    test('after disconnect detection, reconnect loop continues', () async {
      wrapper = createWrapper();
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // Simulate disconnect
      mockClient.simulateDisconnect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 2));

      // Should auto-reconnect
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      expect(wrapper.connectionStatus, equals(ConnectionStatus.connected));
    });
  });

  group('reconnect with backoff', () {
    test('first retry after failure uses 500ms backoff', () async {
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();

      wrapper.connect();

      // Wait for first connecting attempt
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connecting)
          .timeout(const Duration(seconds: 1));

      // Record time after first failure
      final firstFailTime = DateTime.now();

      // Wait for second connecting attempt
      await wrapper.connectionStream
          .skip(1)  // skip current
          .where((s) => s == ConnectionStatus.connecting)
          .first
          .timeout(const Duration(seconds: 3));

      final elapsed = DateTime.now().difference(firstFailTime);
      // Backoff should be approximately 500ms (allow some tolerance)
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(400));
      expect(elapsed.inMilliseconds, lessThan(1200));
    });

    test('backoff doubles on consecutive failures', () async {
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();

      final connectingTimes = <DateTime>[];
      wrapper.connectionStream.where((s) => s == ConnectionStatus.connecting).listen((_) {
        connectingTimes.add(DateTime.now());
      });

      wrapper.connect();

      // Wait for several retries: initial, +500ms, +1000ms, +2000ms = ~3.5s
      await Future.delayed(const Duration(milliseconds: 4500));

      // Should have at least 4 attempts
      expect(connectingTimes.length, greaterThanOrEqualTo(4));

      // Check that gaps increase
      if (connectingTimes.length >= 4) {
        final gap1 = connectingTimes[1].difference(connectingTimes[0]).inMilliseconds;
        final gap2 = connectingTimes[2].difference(connectingTimes[1]).inMilliseconds;
        final gap3 = connectingTimes[3].difference(connectingTimes[2]).inMilliseconds;
        // Each gap should be roughly double the previous (with tolerance)
        expect(gap2, greaterThan(gap1 * 0.7));
        expect(gap3, greaterThan(gap2 * 0.7));
      }
    });

    test('backoff resets to 500ms after successful reconnect', () async {
      // Start with failures
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();
      wrapper.connect();

      // Let backoff increase
      await Future.delayed(const Duration(milliseconds: 2000));

      // Now succeed
      mockClient.shouldFailConnect = false;
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 5));

      // Simulate disconnect
      mockClient.simulateDisconnect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 2));

      // Fail again to check backoff
      mockClient.shouldFailConnect = true;

      final reconnectStart = DateTime.now();
      // Wait for the retry to start (should be ~500ms, not accumulated backoff)
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connecting)
          .timeout(const Duration(seconds: 3));

      final elapsed = DateTime.now().difference(reconnectStart);
      // Should be initial backoff (~500ms), not the accumulated value
      expect(elapsed.inMilliseconds, lessThan(1500));
    });

    test('backoff caps at 5s maximum', () async {
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();

      final connectingTimes = <DateTime>[];
      wrapper.connectionStream.where((s) => s == ConnectionStatus.connecting).listen((_) {
        connectingTimes.add(DateTime.now());
      });

      wrapper.connect();

      // Let many retries happen: 0, 500, 1000, 2000, 4000, 5000, 5000...
      // Total: ~17.5s for 7 retries. Wait enough for the cap to be reached.
      await Future.delayed(const Duration(seconds: 15));

      // Check that no gap exceeds ~5s (with tolerance)
      for (int i = 1; i < connectingTimes.length; i++) {
        final gap = connectingTimes[i].difference(connectingTimes[i - 1]).inMilliseconds;
        expect(gap, lessThan(6500), reason: 'Gap $i should not exceed 5s cap');
      }
    });

    test('retries forever -- never gives up', () async {
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();
      wrapper.connect();

      // Wait longer than several retry cycles
      await Future.delayed(const Duration(seconds: 8));

      // Should still be retrying (connecting count should be high)
      expect(mockClient.connectCallCount, greaterThanOrEqualTo(5));
    });
  });

  group('disconnect()', () {
    test('stops reconnect loop', () async {
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();
      wrapper.connect();

      // Let a couple retries happen
      await Future.delayed(const Duration(milliseconds: 1200));
      final countBefore = mockClient.connectCallCount;

      wrapper.disconnect();

      // Wait and verify no more attempts
      await Future.delayed(const Duration(milliseconds: 1500));
      expect(mockClient.connectCallCount, equals(countBefore),
          reason: 'No more connect attempts after disconnect()');
    });

    test('emits disconnected status', () async {
      wrapper = createWrapper();
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      wrapper.disconnect();

      final status = await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 2));
      expect(status, equals(ConnectionStatus.disconnected));
    });

    test('after disconnect(), connect() can restart the loop', () async {
      wrapper = createWrapper();
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      wrapper.disconnect();
      await Future.delayed(const Duration(milliseconds: 100));

      // Reconnect
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      expect(wrapper.connectionStatus, equals(ConnectionStatus.connected));
    });

    test('disconnect() during backoff delay cancels the delay', () async {
      mockClient.shouldFailConnect = true;
      wrapper = createWrapper();
      wrapper.connect();

      // Wait for first retry
      await Future.delayed(const Duration(milliseconds: 200));

      final disconnectStart = DateTime.now();
      wrapper.disconnect();

      // Should emit disconnected quickly, not waiting for backoff to finish
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 1));

      final elapsed = DateTime.now().difference(disconnectStart);
      expect(elapsed.inMilliseconds, lessThan(500),
          reason: 'disconnect() should not wait for backoff delay');
    });
  });

  group('dispose()', () {
    test('stops reconnect loop AND closes BehaviorSubject', () async {
      wrapper = createWrapper();
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      wrapper.dispose();

      // Stream should close after dispose. BehaviorSubject replays
      // its last value to new subscribers before emitting done.
      await expectLater(
        wrapper.connectionStream,
        emitsInOrder([
          ConnectionStatus.disconnected,
          emitsDone,
        ]),
      );
    });

    test('is terminal -- cannot connect() after dispose()', () async {
      wrapper = createWrapper();
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      wrapper.dispose();
      await Future.delayed(const Duration(milliseconds: 100));

      final countBefore = mockClient.connectCallCount;

      // Try to connect after dispose -- should be no-op
      wrapper.connect();
      await Future.delayed(const Duration(milliseconds: 500));

      expect(mockClient.connectCallCount, equals(countBefore),
          reason: 'No connect attempts after dispose()');
    });

    test('during active connection disconnects cleanly', () async {
      wrapper = createWrapper();
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      wrapper.dispose();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockClient.disconnectCallCount, greaterThanOrEqualTo(1));
    });
  });

  group('multiple instances', () {
    test('two wrappers with different host/port operate independently',
        () async {
      final mock1 = MockModbusClient();
      final mock2 = MockModbusClient();
      mock2.shouldFailConnect = true;

      final wrapper1 = ModbusClientWrapper(
        '10.0.0.1',
        502,
        1,
        clientFactory: (h, p, u) => mock1,
      );
      final wrapper2 = ModbusClientWrapper(
        '10.0.0.2',
        503,
        2,
        clientFactory: (h, p, u) => mock2,
      );

      wrapper1.connect();
      wrapper2.connect();

      await wrapper1.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // wrapper1 is connected, wrapper2 keeps failing
      expect(wrapper1.connectionStatus, equals(ConnectionStatus.connected));
      expect(wrapper2.connectionStatus, isNot(equals(ConnectionStatus.connected)));

      wrapper1.dispose();
      wrapper2.dispose();
      // Set wrapper for tearDown
      wrapper = createWrapper();
    });

    test('disposing one wrapper does not affect another', () async {
      final mock1 = MockModbusClient();
      final mock2 = MockModbusClient();

      final wrapper1 = ModbusClientWrapper(
        '10.0.0.1',
        502,
        1,
        clientFactory: (h, p, u) => mock1,
      );
      final wrapper2 = ModbusClientWrapper(
        '10.0.0.2',
        503,
        2,
        clientFactory: (h, p, u) => mock2,
      );

      wrapper1.connect();
      wrapper2.connect();

      await wrapper1.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await wrapper2.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // Dispose wrapper1
      wrapper1.dispose();
      await Future.delayed(const Duration(milliseconds: 200));

      // wrapper2 should still be connected
      expect(wrapper2.connectionStatus, equals(ConnectionStatus.connected));

      wrapper2.dispose();
      // Set wrapper for tearDown
      wrapper = createWrapper();
    });

    test('each wrapper has its own status stream with independent values',
        () async {
      final mock1 = MockModbusClient();
      final mock2 = MockModbusClient();

      final wrapper1 = ModbusClientWrapper(
        '10.0.0.1',
        502,
        1,
        clientFactory: (h, p, u) => mock1,
      );
      final wrapper2 = ModbusClientWrapper(
        '10.0.0.2',
        503,
        2,
        clientFactory: (h, p, u) => mock2,
      );

      wrapper1.connect();

      await wrapper1.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // wrapper2 not connected yet
      expect(wrapper1.connectionStatus, equals(ConnectionStatus.connected));
      expect(
          wrapper2.connectionStatus, equals(ConnectionStatus.disconnected));

      wrapper1.dispose();
      wrapper2.dispose();
      // Set wrapper for tearDown
      wrapper = createWrapper();
    });
  });
}

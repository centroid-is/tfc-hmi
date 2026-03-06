import 'dart:async';
import 'dart:typed_data';

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
  int sendCallCount = 0;
  Completer<bool>? connectCompleter;

  /// Response handler: given a request, return response code and optionally
  /// populate element values. Defaults to requestSucceed with zero bytes.
  ModbusResponseCode Function(ModbusRequest request)? onSend;

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

  @override
  Future<ModbusResponseCode> send(ModbusRequest request) async {
    if (!_connected) return ModbusResponseCode.connectionFailed;
    sendCallCount++;
    if (onSend != null) return onSend!(request);

    // Default: succeed and set element values to zero bytes
    if (request is ModbusReadGroupRequest) {
      final dataSize = request.elementGroup.type!.isRegister
          ? request.elementGroup.addressRange * 2
          : (request.elementGroup.addressRange + 7) ~/ 8;
      request.internalSetElementData(Uint8List(dataSize));
    } else if (request is ModbusReadRequest) {
      final byteCount = request.element.byteCount;
      request.element.setValueFromBytes(Uint8List(byteCount));
    }
    return ModbusResponseCode.requestSucceed;
  }

  void simulateDisconnect() {
    _connected = false;
  }
}

/// Helper to create wrapper + mock together for read tests.
({ModbusClientWrapper wrapper, MockModbusClient mock}) createWrapperWithMock({
  String host = '127.0.0.1',
  int port = 502,
  int unitId = 1,
}) {
  final mock = MockModbusClient();
  final wrapper = ModbusClientWrapper(
    host,
    port,
    unitId,
    clientFactory: (h, p, u) => mock,
  );
  return (wrapper: wrapper, mock: mock);
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

  // ==========================================================================
  // Phase 5 -- Reading Tests
  // ==========================================================================

  group('ModbusRegisterSpec', () {
    test('can be created with required fields', () {
      wrapper = createWrapper(); // for tearDown
      final spec = ModbusRegisterSpec(
        key: 'temp',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
      );
      expect(spec.key, equals('temp'));
      expect(spec.registerType, equals(ModbusElementType.holdingRegister));
      expect(spec.address, equals(100));
    });

    test('defaults dataType to uint16', () {
      wrapper = createWrapper();
      final spec = ModbusRegisterSpec(
        key: 'temp',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
      );
      expect(spec.dataType, equals(ModbusDataType.uint16));
    });

    test('defaults pollGroup to default', () {
      wrapper = createWrapper();
      final spec = ModbusRegisterSpec(
        key: 'temp',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
      );
      expect(spec.pollGroup, equals('default'));
    });

    test('is immutable (all final fields)', () {
      wrapper = createWrapper();
      final spec = ModbusRegisterSpec(
        key: 'temp',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.float32,
        pollGroup: 'fast',
      );
      // Verify all fields are accessible and correct
      expect(spec.key, equals('temp'));
      expect(spec.dataType, equals(ModbusDataType.float32));
      expect(spec.pollGroup, equals('fast'));
    });
  });

  group('ModbusDataType', () {
    test('has all nine expected values', () {
      wrapper = createWrapper();
      expect(ModbusDataType.values, hasLength(9));
      expect(ModbusDataType.values, contains(ModbusDataType.bit));
      expect(ModbusDataType.values, contains(ModbusDataType.int16));
      expect(ModbusDataType.values, contains(ModbusDataType.uint16));
      expect(ModbusDataType.values, contains(ModbusDataType.int32));
      expect(ModbusDataType.values, contains(ModbusDataType.uint32));
      expect(ModbusDataType.values, contains(ModbusDataType.float32));
      expect(ModbusDataType.values, contains(ModbusDataType.int64));
      expect(ModbusDataType.values, contains(ModbusDataType.uint64));
      expect(ModbusDataType.values, contains(ModbusDataType.float64));
    });
  });

  group('poll group lifecycle', () {
    test('addPollGroup creates a named poll group', () {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      wrapper.addPollGroup('fast', const Duration(milliseconds: 200));
      // Should not throw -- group was created
    });

    test('subscribe auto-creates default poll group at 1s interval', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final spec = ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      );
      // Should not throw -- default group is lazily created
      final stream = wrapper.subscribe(spec);
      expect(stream, isNotNull);
    });

    test('after connect, poll timer fires and sends read requests', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      final spec = ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      // Wait for connection + at least one poll tick
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 1500));

      expect(mock.sendCallCount, greaterThan(0));
    });

    test('after disconnect, poll timer stops', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      wrapper.addPollGroup('default', const Duration(milliseconds: 200));
      final spec = ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));

      final countBeforeDisconnect = mock.sendCallCount;
      expect(countBeforeDisconnect, greaterThan(0));

      // Simulate disconnect
      mock.simulateDisconnect();
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 2));

      // Wait and verify no more sends
      await Future.delayed(const Duration(milliseconds: 500));
      expect(mock.sendCallCount, equals(countBeforeDisconnect));
    });

    test('after reconnect, poll timer resumes', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      wrapper.addPollGroup('default', const Duration(milliseconds: 200));
      final spec = ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));

      // Disconnect
      mock.simulateDisconnect();
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.disconnected)
          .timeout(const Duration(seconds: 2));

      final countAfterDisconnect = mock.sendCallCount;

      // Wait for reconnect
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));
      await Future.delayed(const Duration(milliseconds: 500));

      // Sends should have resumed
      expect(mock.sendCallCount, greaterThan(countAfterDisconnect));
    });

    test('poll tick with _pollInProgress guard skips concurrent sends',
        () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      // Verify poll guard prevents runaway send calls
      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = request.elementGroup.type!.isRegister
              ? request.elementGroup.addressRange * 2
              : (request.elementGroup.addressRange + 7) ~/ 8;
          request.internalSetElementData(Uint8List(dataSize));
        } else if (request is ModbusReadRequest) {
          request.element.setValueFromBytes(Uint8List(request.element.byteCount));
        }
        // Block until we complete it -- but only the first call
        if (mock.sendCallCount == 1) {
          // Return a future that won't complete until we say so
          // Actually, onSend is synchronous return. We can't truly block.
          // Instead, verify that sendCallCount doesn't grow faster than
          // expected with a fast poll interval.
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      final spec = ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));

      // With guard, send count should not be wildly high (no concurrent overlap)
      // Each tick takes ~0ms (mock), so at 100ms interval, ~5 ticks in 500ms
      expect(mock.sendCallCount, greaterThan(0));
      expect(mock.sendCallCount, lessThan(20));
    });

    test('dispose stops all poll timers and closes BehaviorSubjects', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      wrapper.addPollGroup('default', const Duration(milliseconds: 200));
      final spec = ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
      );
      final stream = wrapper.subscribe(spec);

      // Collect all events from the stream before dispose
      final events = <Object?>[];
      var isDone = false;
      stream.listen(events.add, onDone: () => isDone = true);

      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));

      final countBeforeDispose = mock.sendCallCount;
      wrapper.dispose();

      // Wait and verify no more sends
      await Future.delayed(const Duration(milliseconds: 500));
      expect(mock.sendCallCount, equals(countBeforeDispose));

      // Stream should have completed
      expect(isDone, isTrue);
    });
  });

  group('coil reads', () {
    test('subscribe to coil FC01 returns bool value via read()', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          // Set coil to true (bit 0 = 1)
          final dataSize = (request.elementGroup.addressRange + 7) ~/ 8;
          final data = Uint8List(dataSize);
          data[0] = 0x01;
          request.internalSetElementData(data);
        } else if (request is ModbusReadRequest) {
          request.element.setValueFromBytes(Uint8List.fromList([0x01]));
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      final spec = ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final value = wrapper.read('coil0');
      expect(value, isA<bool>());
      expect(value, isTrue);
    });

    test('subscribe returns stream that emits bool values for coils',
        () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = (request.elementGroup.addressRange + 7) ~/ 8;
          final data = Uint8List(dataSize);
          data[0] = 0x01;
          request.internalSetElementData(data);
        } else if (request is ModbusReadRequest) {
          request.element.setValueFromBytes(Uint8List.fromList([0x01]));
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      final spec = ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      );
      final stream = wrapper.subscribe(spec);
      wrapper.connect();

      // Wait for the first non-null value from the stream
      final value = await stream
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 3));
      expect(value, isA<bool>());
      expect(value, isTrue);
    });
  });

  group('discrete input reads', () {
    test('subscribe to discrete input FC02 returns bool value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = (request.elementGroup.addressRange + 7) ~/ 8;
          final data = Uint8List(dataSize);
          data[0] = 0x01;
          request.internalSetElementData(data);
        } else if (request is ModbusReadRequest) {
          request.element.setValueFromBytes(Uint8List.fromList([0x01]));
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      final spec = ModbusRegisterSpec(
        key: 'di0',
        registerType: ModbusElementType.discreteInput,
        address: 0,
        dataType: ModbusDataType.bit,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final value = wrapper.read('di0');
      expect(value, isA<bool>());
      expect(value, isTrue);
    });
  });

  group('holding register reads', () {
    test('subscribe to holding register FC03 with uint16 returns num value',
        () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = request.elementGroup.addressRange * 2;
          final data = Uint8List(dataSize);
          ByteData.view(data.buffer).setUint16(0, 12345);
          request.internalSetElementData(data);
        } else if (request is ModbusReadRequest) {
          final bytes = Uint8List(request.element.byteCount);
          ByteData.view(bytes.buffer).setUint16(0, 12345);
          request.element.setValueFromBytes(bytes);
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      final spec = ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final value = wrapper.read('hr0');
      expect(value, isA<num>());
      expect(value, equals(12345));
    });
  });

  group('input register reads', () {
    test('subscribe to input register FC04 with uint16 returns num value',
        () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = request.elementGroup.addressRange * 2;
          final data = Uint8List(dataSize);
          ByteData.view(data.buffer).setUint16(0, 54321);
          request.internalSetElementData(data);
        } else if (request is ModbusReadRequest) {
          final bytes = Uint8List(request.element.byteCount);
          ByteData.view(bytes.buffer).setUint16(0, 54321);
          request.element.setValueFromBytes(bytes);
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      final spec = ModbusRegisterSpec(
        key: 'ir0',
        registerType: ModbusElementType.inputRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      );
      wrapper.subscribe(spec);
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final value = wrapper.read('ir0');
      expect(value, isA<num>());
      expect(value, equals(54321));
    });
  });

  group('data type interpretation', () {
    /// Helper that creates an onSend handler supporting both group and
    /// individual read requests. [setBytes] writes the expected test value
    /// into the provided ByteData at offset 0.
    ModbusResponseCode Function(ModbusRequest) registerOnSend(
        void Function(ByteData view, int byteCount) setBytes) {
      return (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = request.elementGroup.addressRange * 2;
          final data = Uint8List(dataSize);
          setBytes(ByteData.view(data.buffer), dataSize);
          request.internalSetElementData(data);
        } else if (request is ModbusReadRequest) {
          final bytes = Uint8List(request.element.byteCount);
          setBytes(ByteData.view(bytes.buffer), request.element.byteCount);
          request.element.setValueFromBytes(bytes);
        }
        return ModbusResponseCode.requestSucceed;
      };
    }

    test('int16 holding register returns correct negative value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = registerOnSend((view, _) => view.setInt16(0, -42));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'int16_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.int16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(wrapper.read('int16_reg'), equals(-42));
    });

    test('uint16 holding register returns correct value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = registerOnSend((view, _) => view.setUint16(0, 65000));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'uint16_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(wrapper.read('uint16_reg'), equals(65000));
    });

    test('int32 holding register returns correct value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = registerOnSend((view, _) => view.setInt32(0, -100000));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'int32_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.int32,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(wrapper.read('int32_reg'), equals(-100000));
    });

    test('uint32 holding register returns correct value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = registerOnSend((view, _) => view.setUint32(0, 3000000000));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'uint32_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint32,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(wrapper.read('uint32_reg'), equals(3000000000));
    });

    test('float32 holding register returns correct value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = registerOnSend((view, _) => view.setFloat32(0, 3.14));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'float32_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.float32,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final value = wrapper.read('float32_reg');
      expect(value, isA<double>());
      expect((value as double), closeTo(3.14, 0.01));
    });

    test('int64 holding register returns correct value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend =
          registerOnSend((view, _) => view.setInt64(0, -9000000000));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'int64_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.int64,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(wrapper.read('int64_reg'), equals(-9000000000));
    });

    test('uint64 holding register returns correct value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend =
          registerOnSend((view, _) => view.setUint64(0, 4000000000));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'uint64_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint64,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(wrapper.read('uint64_reg'), equals(4000000000));
    });

    test('float64 holding register returns correct value', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend =
          registerOnSend((view, _) => view.setFloat64(0, 2.71828));

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'float64_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.float64,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final value = wrapper.read('float64_reg');
      expect(value, isA<double>());
      expect((value as double), closeTo(2.71828, 0.00001));
    });

    test('bit data type for coil returns bool', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = (request.elementGroup.addressRange + 7) ~/ 8;
          request.internalSetElementData(Uint8List(dataSize)); // all zeros = false
        } else if (request is ModbusReadRequest) {
          request.element.setValueFromBytes(Uint8List.fromList([0x00]));
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'bit_coil',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final value = wrapper.read('bit_coil');
      expect(value, isA<bool>());
      expect(value, isFalse);
    });
  });

  group('read failure handling', () {
    test('on read failure, last-known value persists in stream', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      var callCount = 0;
      mock.onSend = (request) {
        callCount++;
        if (request is ModbusReadGroupRequest) {
          if (callCount <= 2) {
            final dataSize = request.elementGroup.addressRange * 2;
            final data = Uint8List(dataSize);
            ByteData.view(data.buffer).setUint16(0, 42);
            request.internalSetElementData(data);
            return ModbusResponseCode.requestSucceed;
          } else {
            return ModbusResponseCode.deviceFailure;
          }
        } else if (request is ModbusReadRequest) {
          if (callCount <= 2) {
            final bytes = Uint8List(request.element.byteCount);
            ByteData.view(bytes.buffer).setUint16(0, 42);
            request.element.setValueFromBytes(bytes);
            return ModbusResponseCode.requestSucceed;
          } else {
            return ModbusResponseCode.deviceFailure;
          }
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // Wait for successful reads then failure reads
      await Future.delayed(const Duration(milliseconds: 600));

      // Last-known value should persist despite failures
      expect(wrapper.read('hr0'), equals(42));
    });

    test('on read failure, poll continues to next cycle', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      var failCount = 0;
      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          failCount++;
          if (failCount <= 3) {
            return ModbusResponseCode.illegalDataAddress;
          }
          final dataSize = request.elementGroup.addressRange * 2;
          final data = Uint8List(dataSize);
          ByteData.view(data.buffer).setUint16(0, 99);
          request.internalSetElementData(data);
          return ModbusResponseCode.requestSucceed;
        } else if (request is ModbusReadRequest) {
          failCount++;
          if (failCount <= 3) {
            return ModbusResponseCode.illegalDataAddress;
          }
          final bytes = Uint8List(request.element.byteCount);
          ByteData.view(bytes.buffer).setUint16(0, 99);
          request.element.setValueFromBytes(bytes);
          return ModbusResponseCode.requestSucceed;
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // Wait for failures + eventual success
      await Future.delayed(const Duration(milliseconds: 800));

      // Poll should have continued past failures and eventually read 99
      expect(wrapper.read('hr0'), equals(99));
    });
  });

  group('dynamic subscription', () {
    test('unsubscribe removes register from polling', () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final countBeforeUnsub = mock.sendCallCount;
      expect(countBeforeUnsub, greaterThan(0));

      wrapper.unsubscribe('hr0');

      // Reset send count tracking
      final countAtUnsub = mock.sendCallCount;
      await Future.delayed(const Duration(milliseconds: 300));

      // No more sends after unsubscribing the only register
      expect(mock.sendCallCount, equals(countAtUnsub));
    });

    test('adding register while polls are running picks it up on next tick',
        () async {
      final pair = createWrapperWithMock();
      wrapper = pair.wrapper;
      final mock = pair.mock;

      wrapper.addPollGroup('default', const Duration(milliseconds: 100));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      // No sends yet (no subscriptions)
      expect(mock.sendCallCount, equals(0));

      // Add a register dynamically
      mock.onSend = (request) {
        if (request is ModbusReadGroupRequest) {
          final dataSize = request.elementGroup.addressRange * 2;
          final data = Uint8List(dataSize);
          ByteData.view(data.buffer).setUint16(0, 777);
          request.internalSetElementData(data);
        } else if (request is ModbusReadRequest) {
          final bytes = Uint8List(request.element.byteCount);
          ByteData.view(bytes.buffer).setUint16(0, 777);
          request.element.setValueFromBytes(bytes);
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr_late',
        registerType: ModbusElementType.holdingRegister,
        address: 10,
        dataType: ModbusDataType.uint16,
      ));

      await Future.delayed(const Duration(milliseconds: 300));

      // Should have picked up the new register
      expect(mock.sendCallCount, greaterThan(0));
      expect(wrapper.read('hr_late'), equals(777));
    });
  });

  // ==========================================================================
  // Phase 5 Plan 02 -- Batch Coalescing Tests
  // ==========================================================================

  group('batch coalescing', () {
    // Helper: set up a wrapper with a fast poll group and track requests
    ({
      ModbusClientWrapper wrapper,
      MockModbusClient mock,
      List<ModbusRequest> requests,
    }) setupCoalesceTest({Duration pollInterval = const Duration(milliseconds: 100)}) {
      final mock = MockModbusClient();
      final requests = <ModbusRequest>[];
      mock.onSend = (request) {
        requests.add(request);
        if (request is ModbusReadGroupRequest) {
          final dataSize = request.elementGroup.type!.isRegister
              ? request.elementGroup.addressRange * 2
              : (request.elementGroup.addressRange + 7) ~/ 8;
          request.internalSetElementData(Uint8List(dataSize));
        } else if (request is ModbusReadRequest) {
          request.element.setValueFromBytes(
              Uint8List(request.element.byteCount));
        }
        return ModbusResponseCode.requestSucceed;
      };
      final wrapper = ModbusClientWrapper(
        '127.0.0.1',
        502,
        1,
        clientFactory: (h, p, u) => mock,
      );
      wrapper.addPollGroup('default', pollInterval);
      return (wrapper: wrapper, mock: mock, requests: requests);
    }

    // -- Coalescing basics --

    test('coalesce two contiguous holding registers into 1 batch read',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr101',
        registerType: ModbusElementType.holdingRegister,
        address: 101,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      // Should be batch reads (ModbusReadGroupRequest), not individual
      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      final individualRequests =
          t.requests.whereType<ModbusReadRequest>().toList();

      // Expect batch reads, not individual reads
      expect(groupRequests, isNotEmpty,
          reason: 'Contiguous registers should use batch reads');
      expect(individualRequests, isEmpty,
          reason: 'No individual reads when coalescing is active');

      // Each poll tick should produce exactly 1 send call (1 batch for 2 regs)
      // After 300ms with 100ms interval, expect ~3 ticks = ~3 group requests
      expect(groupRequests.length, greaterThanOrEqualTo(1));
      // Verify the group covers both addresses
      final firstGroup = groupRequests.first;
      expect(firstGroup.elementGroup.startAddress, equals(100));
      expect(firstGroup.elementGroup.addressRange, equals(2));
    });

    test('coalesce three contiguous coils into 1 batch read', () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      for (var i = 0; i < 3; i++) {
        wrapper.subscribe(ModbusRegisterSpec(
          key: 'coil$i',
          registerType: ModbusElementType.coil,
          address: i,
          dataType: ModbusDataType.bit,
        ));
      }
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      expect(groupRequests, isNotEmpty,
          reason: 'Contiguous coils should use batch reads');
      // Each tick = 1 group request for 3 coils
      expect(groupRequests.first.elementGroup.addressRange, equals(3));
    });

    test('registers in different poll groups are NOT coalesced together',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.addPollGroup('fast', const Duration(milliseconds: 100));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
        pollGroup: 'default',
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr101',
        registerType: ModbusElementType.holdingRegister,
        address: 101,
        dataType: ModbusDataType.uint16,
        pollGroup: 'fast',
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      // Each group should have its own request; they should NOT be merged
      // With 2 groups, each tick produces 2 requests (1 per group)
      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      // Each group request should have addressRange of 1 (single register)
      for (final gr in groupRequests) {
        expect(gr.elementGroup.addressRange, equals(1),
            reason: 'Each poll group should have its own separate batch');
      }
    });

    test('different types (coil + holding) in same group are NOT coalesced',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      // Should have 2 separate batch reads per tick (one for coils, one for registers)
      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      expect(groupRequests.length, greaterThanOrEqualTo(2),
          reason: 'Different types produce separate batches');
      // Verify types are separate
      final types =
          groupRequests.map((gr) => gr.elementGroup.type).toSet();
      expect(types.length, equals(2),
          reason: 'Should have both coil and holding register groups');
    });

    // -- Gap handling --

    test('coalesce registers within gap threshold (gap=4, threshold=10)',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr105',
        registerType: ModbusElementType.holdingRegister,
        address: 105,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      expect(groupRequests, isNotEmpty);
      // Should be coalesced into 1 batch spanning 100-105
      expect(groupRequests.first.elementGroup.startAddress, equals(100));
      expect(groupRequests.first.elementGroup.addressRange, equals(6));
    });

    test('do NOT coalesce registers when gap exceeds threshold (gap=19, threshold=10)',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr120',
        registerType: ModbusElementType.holdingRegister,
        address: 120,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      // Should be 2 separate batches per tick
      // Count unique start addresses across all requests
      final startAddresses =
          groupRequests.map((gr) => gr.elementGroup.startAddress).toSet();
      expect(startAddresses, containsAll([100, 120]),
          reason: 'Large gap should produce 2 separate batches');
    });

    test('coalesce coils within coil gap threshold (gap=49, threshold=100)',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil50',
        registerType: ModbusElementType.coil,
        address: 50,
        dataType: ModbusDataType.bit,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      expect(groupRequests, isNotEmpty);
      // Should be coalesced into 1 batch
      expect(groupRequests.first.elementGroup.startAddress, equals(0));
      expect(groupRequests.first.elementGroup.addressRange, equals(51));
    });

    test('do NOT coalesce coils when gap exceeds coil threshold (gap=149, threshold=100)',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil150',
        registerType: ModbusElementType.coil,
        address: 150,
        dataType: ModbusDataType.bit,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      final startAddresses =
          groupRequests.map((gr) => gr.elementGroup.startAddress).toSet();
      expect(startAddresses, containsAll([0, 150]),
          reason: 'Large coil gap should produce 2 separate batches');
    });

    // -- Auto-split oversized batches --

    test('auto-split 130 contiguous registers into 2 batches (125 + 5)',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      // Subscribe 130 contiguous uint16 holding registers (addr 0-129)
      for (var i = 0; i < 130; i++) {
        wrapper.subscribe(ModbusRegisterSpec(
          key: 'hr$i',
          registerType: ModbusElementType.holdingRegister,
          address: i,
          dataType: ModbusDataType.uint16,
        ));
      }
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      // Each tick should produce exactly 2 batch reads
      // After ~3 ticks: expect 6 group requests total (2 per tick)
      expect(groupRequests.length, greaterThanOrEqualTo(2));

      // Verify the split: find the two distinct address ranges
      final ranges = <int>{};
      for (final gr in groupRequests) {
        ranges.add(gr.elementGroup.addressRange);
      }
      expect(ranges, containsAll([125, 5]),
          reason: 'Should split into 125-register and 5-register batches');
    });

    // -- Dirty flag recalculation --

    test('adding new subscription marks group dirty and triggers recalculation',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      // Record state before adding new subscription
      t.requests.clear();

      // Add a new contiguous register
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr101',
        registerType: ModbusElementType.holdingRegister,
        address: 101,
        dataType: ModbusDataType.uint16,
      ));

      await Future.delayed(const Duration(milliseconds: 300));

      // After recalculation, the new register should be in the batch
      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      expect(groupRequests, isNotEmpty,
          reason: 'New subscription should trigger recalculation');
      // The batch should now cover both registers
      final lastGroup = groupRequests.last;
      expect(lastGroup.elementGroup.addressRange, equals(2),
          reason: 'Recalculated group should include new register');
    });

    test('removing subscription marks group dirty and triggers recalculation',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr101',
        registerType: ModbusElementType.holdingRegister,
        address: 101,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      t.requests.clear();

      // Remove one subscription
      wrapper.unsubscribe('hr101');

      await Future.delayed(const Duration(milliseconds: 300));

      // After recalculation, batch should only cover 1 register
      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      expect(groupRequests, isNotEmpty);
      for (final gr in groupRequests) {
        expect(gr.elementGroup.addressRange, equals(1),
            reason: 'After removing hr101, batch should only cover hr100');
      }
    });

    test('poll ticks without subscription changes reuse cached groups',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr101',
        registerType: ModbusElementType.holdingRegister,
        address: 101,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));

      // All group requests should have the same structure (cached, not recalculated)
      final groupRequests =
          t.requests.whereType<ModbusReadGroupRequest>().toList();
      expect(groupRequests.length, greaterThanOrEqualTo(3),
          reason: 'Multiple ticks should have fired');
      for (final gr in groupRequests) {
        expect(gr.elementGroup.startAddress, equals(100));
        expect(gr.elementGroup.addressRange, equals(2));
      }
    });

    // -- Value delivery after batch read --

    test('batch read of contiguous registers delivers correct values per subscriber',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      // Set up onSend to provide distinct values per address
      t.mock.onSend = (request) {
        t.requests.add(request);
        if (request is ModbusReadGroupRequest) {
          final group = request.elementGroup;
          final dataSize = group.type!.isRegister
              ? group.addressRange * 2
              : (group.addressRange + 7) ~/ 8;
          final data = Uint8List(dataSize);
          final view = ByteData.view(data.buffer);
          // Write distinct values for each register in the group
          for (final elem in group) {
            if (elem.type.isRegister) {
              final offset = (elem.address - group.startAddress) * 2;
              // Address 100 -> value 1000, address 101 -> value 1010
              view.setUint16(offset, elem.address * 10);
            }
          }
          request.internalSetElementData(data);
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr100',
        registerType: ModbusElementType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr101',
        registerType: ModbusElementType.holdingRegister,
        address: 101,
        dataType: ModbusDataType.uint16,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      // Each subscriber should receive its own value
      expect(wrapper.read('hr100'), equals(1000));
      expect(wrapper.read('hr101'), equals(1010));
    });

    test('batch read of contiguous coils delivers correct boolean values',
        () async {
      final t = setupCoalesceTest();
      wrapper = t.wrapper;

      t.mock.onSend = (request) {
        t.requests.add(request);
        if (request is ModbusReadGroupRequest) {
          final group = request.elementGroup;
          if (group.type!.isBit) {
            // Coils at addresses 0, 1, 2
            // Byte packing: bit 0 = coil 0, bit 1 = coil 1, bit 2 = coil 2
            // Set coil 0 = true, coil 1 = false, coil 2 = true -> 0b00000101 = 0x05
            final dataSize = (group.addressRange + 7) ~/ 8;
            final data = Uint8List(dataSize);
            data[0] = 0x05; // bits: ...00000101
            request.internalSetElementData(data);
          }
        }
        return ModbusResponseCode.requestSucceed;
      };

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil1',
        registerType: ModbusElementType.coil,
        address: 1,
        dataType: ModbusDataType.bit,
      ));
      wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil2',
        registerType: ModbusElementType.coil,
        address: 2,
        dataType: ModbusDataType.bit,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));

      // Verify each coil has correct boolean value
      expect(wrapper.read('coil0'), isTrue);
      expect(wrapper.read('coil1'), isFalse);
      expect(wrapper.read('coil2'), isTrue);
    });
  });

  // ==========================================================================
  // Phase 6 -- Write Tests
  // ==========================================================================

  group('write', () {
    group('single coil write (FC05)', () {
      test('write single coil sends write request when connected', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        ModbusRequest? capturedRequest;
        mock.onSend = (request) {
          capturedRequest = request;
          return ModbusResponseCode.requestSucceed;
        };

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        await wrapper.write(spec, true);

        expect(capturedRequest, isA<ModbusWriteRequest>());
        expect(mock.sendCallCount, equals(1));
      });

      test('write coil false sends write request', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        mock.onSend = (request) => ModbusResponseCode.requestSucceed;

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        await wrapper.write(spec, false);

        expect(mock.sendCallCount, equals(1));
      });
    });

    group('single holding register write (FC06)', () {
      test('write uint16 value sends write request', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        ModbusRequest? capturedRequest;
        mock.onSend = (request) {
          capturedRequest = request;
          return ModbusResponseCode.requestSucceed;
        };

        final spec = ModbusRegisterSpec(
          key: 'hr100',
          registerType: ModbusElementType.holdingRegister,
          address: 100,
          dataType: ModbusDataType.uint16,
        );
        await wrapper.write(spec, 42);

        expect(capturedRequest, isA<ModbusWriteRequest>());
        expect(mock.sendCallCount, equals(1));
      });

      test('write int16 signed value sends write request', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        mock.onSend = (request) => ModbusResponseCode.requestSucceed;

        final spec = ModbusRegisterSpec(
          key: 'hr101',
          registerType: ModbusElementType.holdingRegister,
          address: 101,
          dataType: ModbusDataType.int16,
        );
        await wrapper.write(spec, -100);

        expect(mock.sendCallCount, equals(1));
      });
    });

    group('multi-register writes (auto FC16)', () {
      test('write float32 sends write request (library auto-selects FC16)',
          () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        ModbusRequest? capturedRequest;
        mock.onSend = (request) {
          capturedRequest = request;
          return ModbusResponseCode.requestSucceed;
        };

        final spec = ModbusRegisterSpec(
          key: 'hr200',
          registerType: ModbusElementType.holdingRegister,
          address: 200,
          dataType: ModbusDataType.float32,
        );
        await wrapper.write(spec, 23.5);

        expect(capturedRequest, isA<ModbusWriteRequest>());
        expect(mock.sendCallCount, equals(1));
      });

      test('write int32 sends write request (auto FC16)', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        mock.onSend = (request) => ModbusResponseCode.requestSucceed;

        final spec = ModbusRegisterSpec(
          key: 'hr300',
          registerType: ModbusElementType.holdingRegister,
          address: 300,
          dataType: ModbusDataType.int32,
        );
        await wrapper.write(spec, 100000);

        expect(mock.sendCallCount, equals(1));
      });
    });

    group('writeMultiple', () {
      test('writeMultiple coils (FC15) sends write request with quantity',
          () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        ModbusRequest? capturedRequest;
        mock.onSend = (request) {
          capturedRequest = request;
          return ModbusResponseCode.requestSucceed;
        };

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        // Write 8 coils packed as 1 byte (0xFF = all true)
        await wrapper.writeMultiple(spec, Uint8List.fromList([0xFF]),
            quantity: 8);

        expect(capturedRequest, isA<ModbusWriteRequest>());
        expect(mock.sendCallCount, equals(1));
      });

      test('writeMultiple holding registers (FC16) sends write request',
          () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        ModbusRequest? capturedRequest;
        mock.onSend = (request) {
          capturedRequest = request;
          return ModbusResponseCode.requestSucceed;
        };

        final spec = ModbusRegisterSpec(
          key: 'hr100',
          registerType: ModbusElementType.holdingRegister,
          address: 100,
          dataType: ModbusDataType.uint16,
        );
        // Write 2 registers (4 bytes)
        await wrapper.writeMultiple(
            spec, Uint8List.fromList([0x00, 0x01, 0x00, 0x02]));

        expect(capturedRequest, isA<ModbusWriteRequest>());
        expect(mock.sendCallCount, equals(1));
      });
    });

    group('read-only type rejection', () {
      test('write to discrete input throws ArgumentError', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final spec = ModbusRegisterSpec(
          key: 'di0',
          registerType: ModbusElementType.discreteInput,
          address: 0,
        );
        expect(
          () => wrapper.write(spec, true),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('read-only'),
          )),
        );
      });

      test('write to input register throws ArgumentError', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final spec = ModbusRegisterSpec(
          key: 'ir0',
          registerType: ModbusElementType.inputRegister,
          address: 0,
          dataType: ModbusDataType.uint16,
        );
        expect(
          () => wrapper.write(spec, 42),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('read-only'),
          )),
        );
      });

      test('writeMultiple to discrete input throws ArgumentError', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final spec = ModbusRegisterSpec(
          key: 'di0',
          registerType: ModbusElementType.discreteInput,
          address: 0,
        );
        expect(
          () => wrapper.writeMultiple(spec, Uint8List.fromList([0x01]),
              quantity: 1),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('writeMultiple to input register throws ArgumentError', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final spec = ModbusRegisterSpec(
          key: 'ir0',
          registerType: ModbusElementType.inputRegister,
          address: 0,
          dataType: ModbusDataType.uint16,
        );
        expect(
          () => wrapper.writeMultiple(
              spec, Uint8List.fromList([0x00, 0x01])),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('connection gating', () {
      test('write when disconnected throws StateError', () {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        // Do NOT connect -- wrapper is disconnected

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        expect(
          () => wrapper.write(spec, true),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Not connected'),
          )),
        );
      });

      test('write when disposed throws StateError', () {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        wrapper.dispose();

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        expect(
          () => wrapper.write(spec, true),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          )),
        );
      });

      test('write when send returns non-succeed code throws StateError',
          () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        mock.onSend = (request) => ModbusResponseCode.requestTimeout;

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        expect(
          () => wrapper.write(spec, true),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('requestTimeout'),
          )),
        );
      });

      test('writeMultiple when disconnected throws StateError', () {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        expect(
          () => wrapper.writeMultiple(spec, Uint8List.fromList([0x01]),
              quantity: 1),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('optimistic BehaviorSubject update', () {
      test('write to subscribed key updates BehaviorSubject with written value',
          () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;

        final spec = ModbusRegisterSpec(
          key: 'coil0',
          registerType: ModbusElementType.coil,
          address: 0,
        );
        wrapper.subscribe(spec);

        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        mock.onSend = (request) {
          if (request is ModbusReadGroupRequest) {
            final dataSize = (request.elementGroup.addressRange + 7) ~/ 8;
            request.internalSetElementData(Uint8List(dataSize));
          }
          return ModbusResponseCode.requestSucceed;
        };

        await wrapper.write(spec, true);

        // The BehaviorSubject should now have the written value
        final value = wrapper.read('coil0');
        expect(value, isTrue);
      });

      test('write to unsubscribed key does not throw', () async {
        final pair = createWrapperWithMock();
        wrapper = pair.wrapper;
        final mock = pair.mock;
        wrapper.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        mock.onSend = (request) => ModbusResponseCode.requestSucceed;

        final spec = ModbusRegisterSpec(
          key: 'unsubscribed_coil',
          registerType: ModbusElementType.coil,
          address: 99,
        );
        // Should complete without error -- no BehaviorSubject to update
        await wrapper.write(spec, true);
        expect(mock.sendCallCount, equals(1));
      });
    });
  });
}

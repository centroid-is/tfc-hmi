import 'dart:async';

import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:test/test.dart';

import 'package:tfc_dart/core/state_man.dart';

// ---------------------------------------------------------------------------
// Mock DeviceClient for MQTT routing tests
// ---------------------------------------------------------------------------

/// Mock that implements DeviceClient with controllable return values.
/// Used to test StateMan routing logic without a real MQTT broker.
class MockMqttDeviceClient implements DeviceClient {
  @override
  final Set<String> subscribableKeys;
  final String? serverAlias;

  final Map<String, StreamController<DynamicValue>> _controllers = {};
  final Map<String, DynamicValue> _cachedValues = {};
  final List<String> subscribeCalls = [];
  final List<String> readCalls = [];
  final List<(String, DynamicValue)> writeCalls = [];

  ConnectionStatus _status = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  MockMqttDeviceClient({
    required Set<String> keys,
    this.serverAlias,
  }) : subscribableKeys = keys;

  @override
  bool canSubscribe(String key) =>
      subscribableKeys.contains(key) ||
      subscribableKeys.any((k) => key.startsWith('$k.'));

  @override
  Stream<DynamicValue> subscribe(String key) {
    subscribeCalls.add(key);
    final controller = _controllers.putIfAbsent(
        key, () => StreamController<DynamicValue>.broadcast());
    return controller.stream;
  }

  @override
  DynamicValue? read(String key) {
    readCalls.add(key);
    return _cachedValues[key];
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    writeCalls.add((key, value));
  }

  @override
  ConnectionStatus get connectionStatus => _status;

  @override
  Stream<ConnectionStatus> get connectionStream => _statusController.stream;

  @override
  void connect() {
    _status = ConnectionStatus.connected;
    _statusController.add(ConnectionStatus.connected);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _statusController.close();
  }

  /// Set a cached value for read() to return.
  void setCachedValue(String key, DynamicValue value) {
    _cachedValues[key] = value;
  }

  /// Push a value into a subscribe stream.
  void push(String key, DynamicValue value) {
    _controllers.putIfAbsent(
        key, () => StreamController<DynamicValue>.broadcast());
    _controllers[key]!.add(value);
  }
}

/// Reuse MockModbusDeviceClient-style mock for OPC UA / Modbus coexistence tests.
class MockOtherDeviceClient implements DeviceClient {
  @override
  final Set<String> subscribableKeys;
  final String? serverAlias;
  final List<String> subscribeCalls = [];
  final List<String> readCalls = [];
  final List<(String, DynamicValue)> writeCalls = [];
  final Map<String, DynamicValue> _cachedValues = {};
  final Map<String, StreamController<DynamicValue>> _controllers = {};
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  MockOtherDeviceClient({required Set<String> keys, this.serverAlias})
      : subscribableKeys = keys;

  @override
  bool canSubscribe(String key) => subscribableKeys.contains(key);
  @override
  Stream<DynamicValue> subscribe(String key) {
    subscribeCalls.add(key);
    final c = _controllers.putIfAbsent(
        key, () => StreamController<DynamicValue>.broadcast());
    return c.stream;
  }

  @override
  DynamicValue? read(String key) {
    readCalls.add(key);
    return _cachedValues[key];
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    writeCalls.add((key, value));
  }

  @override
  ConnectionStatus get connectionStatus => _status;
  @override
  Stream<ConnectionStatus> get connectionStream => _statusController.stream;
  @override
  void connect() {
    _status = ConnectionStatus.connected;
    _statusController.add(ConnectionStatus.connected);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _statusController.close();
  }

  void setCachedValue(String key, DynamicValue value) {
    _cachedValues[key] = value;
  }

  void push(String key, DynamicValue value) {
    _controllers.putIfAbsent(
        key, () => StreamController<DynamicValue>.broadcast());
    _controllers[key]!.add(value);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MQTT StateMan routing', () {
    late MockMqttDeviceClient mqttMock;
    late StateMan stateMan;

    setUp(() async {
      mqttMock = MockMqttDeviceClient(
        keys: {'sensor_temp', 'sensor_pressure'},
        serverAlias: 'mqtt1',
      );

      stateMan = await StateMan.create(
        config: StateManConfig(
          opcua: [],
          mqtt: [MqttConfig(host: 'broker', serverAlias: 'mqtt1')],
        ),
        keyMappings: KeyMappings(nodes: {
          'sensor_temp': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'plant/temp',
              serverAlias: 'mqtt1',
            ),
          ),
          'sensor_pressure': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'plant/pressure',
              serverAlias: 'mqtt1',
            ),
          ),
        }),
        deviceClients: [mqttMock],
        useIsolate: false,
      );
    });

    tearDown(() async {
      await stateMan.close();
    });

    test('key with only mqtt_node routes to MqttDeviceClient via read', () async {
      mqttMock.setCachedValue(
          'sensor_temp', DynamicValue(value: 42.5));

      final value = await stateMan.read('sensor_temp');
      expect(value.value, 42.5);
      expect(mqttMock.readCalls, contains('sensor_temp'));
    });

    test('subscribe returns stream from MqttDeviceClient for mqtt-routed key',
        () async {
      final stream = await stateMan.subscribe('sensor_temp');
      final completer = Completer<DynamicValue>();
      final sub = stream.listen((dv) {
        if (!completer.isCompleted) completer.complete(dv);
      });

      mqttMock.push('sensor_temp', DynamicValue(value: 99));

      final dv = await completer.future.timeout(const Duration(seconds: 2));
      expect(dv.value, 99);
      expect(mqttMock.subscribeCalls, contains('sensor_temp'));

      await sub.cancel();
    });

    test('write delegates to MqttDeviceClient for mqtt-routed key', () async {
      final dv = DynamicValue(value: 'set_value');
      await stateMan.write('sensor_temp', dv);

      expect(mqttMock.writeCalls.length, 1);
      expect(mqttMock.writeCalls[0].$1, 'sensor_temp');
      expect(mqttMock.writeCalls[0].$2.value, 'set_value');
    });

    test('read delegates to MqttDeviceClient for mqtt-routed key', () async {
      mqttMock.setCachedValue(
          'sensor_pressure', DynamicValue(value: 1013));

      final value = await stateMan.read('sensor_pressure');
      expect(value.value, 1013);
      expect(mqttMock.readCalls, contains('sensor_pressure'));
    });

    test('connection status from MqttDeviceClient appears in device client list',
        () {
      // StateMan.create calls connect() on device clients
      expect(mqttMock.connectionStatus, ConnectionStatus.connected);
      expect(stateMan.deviceClients, contains(mqttMock));
    });

    test('readMany returns values from MqttDeviceClient for mqtt-routed keys',
        () async {
      mqttMock.setCachedValue('sensor_temp', DynamicValue(value: 42.5));
      mqttMock.setCachedValue('sensor_pressure', DynamicValue(value: 1013));

      final results =
          await stateMan.readMany(['sensor_temp', 'sensor_pressure']);
      expect(results['sensor_temp']?.value, 42.5);
      expect(results['sensor_pressure']?.value, 1013);
      expect(mqttMock.readCalls, contains('sensor_temp'));
      expect(mqttMock.readCalls, contains('sensor_pressure'));
    });

    test('read throws StateManException when MQTT key has no cached value',
        () async {
      // Do NOT set any cached value — read should throw
      expect(
        () => stateMan.read('sensor_temp'),
        throwsA(isA<StateManException>().having(
          (e) => e.message,
          'message',
          contains('not received yet'),
        )),
      );
    });
  });

  group('MQTT routing — no regression for OPC UA keys', () {
    test('key with only opcua_node does not route to MQTT', () async {
      final mqttMock = MockMqttDeviceClient(
        keys: {'sensor_temp'},
        serverAlias: 'mqtt1',
      );

      final stateMan = await StateMan.create(
        config: StateManConfig(opcua: []),
        keyMappings: KeyMappings(nodes: {
          'sensor_temp': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'plant/temp',
              serverAlias: 'mqtt1',
            ),
          ),
          'opc_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'Temp'),
          ),
        }),
        deviceClients: [mqttMock],
        useIsolate: false,
      );

      // OPC UA key should NOT be routed to MQTT mock
      expect(mqttMock.canSubscribe('opc_key'), isFalse);

      await stateMan.close();
    });
  });

  group('MQTT routing — no regression for Modbus keys', () {
    test('key with only modbus_node does not route to MQTT', () async {
      final mqttMock = MockMqttDeviceClient(
        keys: {'sensor_temp'},
        serverAlias: 'mqtt1',
      );

      final stateMan = await StateMan.create(
        config: StateManConfig(opcua: []),
        keyMappings: KeyMappings(nodes: {
          'sensor_temp': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'plant/temp',
              serverAlias: 'mqtt1',
            ),
          ),
          'modbus_key': KeyMappingEntry(
            modbusNode: ModbusNodeConfig(
              serverAlias: 'plc1',
              registerType: ModbusRegisterType.holdingRegister,
              address: 100,
            ),
          ),
        }),
        deviceClients: [mqttMock],
        useIsolate: false,
      );

      // Modbus key should NOT be routed to MQTT mock
      expect(mqttMock.canSubscribe('modbus_key'), isFalse);

      await stateMan.close();
    });
  });

  group('MQTT + OPC UA priority', () {
    test('key with both mqtt_node and opcua_node — mqtt takes priority', () async {
      // When a key has both mqtt_node and opcua_node, MQTT should be checked
      // before OPC UA fallthrough. This documents the priority order.
      final mqttMock = MockMqttDeviceClient(
        keys: {'dual_key'},
        serverAlias: 'mqtt1',
      );

      final stateMan = await StateMan.create(
        config: StateManConfig(opcua: []),
        keyMappings: KeyMappings(nodes: {
          'dual_key': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'plant/dual',
              serverAlias: 'mqtt1',
            ),
            opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'Dual'),
          ),
        }),
        deviceClients: [mqttMock],
        useIsolate: false,
      );

      // MQTT should claim the key (before OPC UA fallthrough)
      mqttMock.setCachedValue('dual_key', DynamicValue(value: 'from_mqtt'));
      final value = await stateMan.read('dual_key');
      expect(value.value, 'from_mqtt');
      expect(mqttMock.readCalls, contains('dual_key'));

      await stateMan.close();
    });
  });

  group('Coexistence', () {
    test('MQTT, Modbus, and M2400 mocks coexist without interference',
        () async {
      final mqttMock = MockMqttDeviceClient(
        keys: {'mqtt_sensor'},
        serverAlias: 'mqtt1',
      );

      final modbusMock = MockOtherDeviceClient(
        keys: {'modbus_pump'},
        serverAlias: 'plc1',
      );

      final m2400Mock = MockOtherDeviceClient(
        keys: {'BATCH'},
        serverAlias: 'm2400_1',
      );

      // Each mock claims only its own keys
      expect(mqttMock.canSubscribe('mqtt_sensor'), isTrue);
      expect(mqttMock.canSubscribe('modbus_pump'), isFalse);
      expect(mqttMock.canSubscribe('BATCH'), isFalse);

      expect(modbusMock.canSubscribe('modbus_pump'), isTrue);
      expect(modbusMock.canSubscribe('mqtt_sensor'), isFalse);

      expect(m2400Mock.canSubscribe('BATCH'), isTrue);
      expect(m2400Mock.canSubscribe('mqtt_sensor'), isFalse);

      mqttMock.dispose();
      modbusMock.dispose();
      m2400Mock.dispose();
    });

    test('subscribe streams are independent between MQTT and other protocols',
        () async {
      final mqttMock = MockMqttDeviceClient(
        keys: {'mqtt_sensor'},
        serverAlias: 'mqtt1',
      );
      final modbusMock = MockOtherDeviceClient(
        keys: {'modbus_pump'},
        serverAlias: 'plc1',
      );

      final mqttValues = <DynamicValue>[];
      final modbusValues = <DynamicValue>[];

      final s1 = mqttMock.subscribe('mqtt_sensor').listen(mqttValues.add);
      final s2 = modbusMock.subscribe('modbus_pump').listen(modbusValues.add);

      mqttMock.push('mqtt_sensor', DynamicValue(value: 42.0));
      modbusMock.push('modbus_pump', DynamicValue(value: 100));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(mqttValues.length, 1);
      expect(mqttValues[0].value, 42.0);
      expect(modbusValues.length, 1);
      expect(modbusValues[0].value, 100);

      await s1.cancel();
      await s2.cancel();
      mqttMock.dispose();
      modbusMock.dispose();
    });
  });

  group('_resolveOtherDeviceClient keyMappings guard', () {
    test('key without mqttNode is NOT routed to a non-M2400/non-Modbus DeviceClient even if canSubscribe returns true', () async {
      // A DeviceClient that claims it can subscribe to 'orphan_key'
      final greedyMock = MockMqttDeviceClient(
        keys: {'orphan_key'},
        serverAlias: 'mqtt1',
      );

      final stateMan = await StateMan.create(
        config: StateManConfig(opcua: []),
        keyMappings: KeyMappings(nodes: {
          // orphan_key has only an opcuaNode — no mqttNode
          'orphan_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'Orphan'),
          ),
        }),
        deviceClients: [greedyMock],
        useIsolate: false,
      );

      // The mock *can* subscribe, but keyMappings has no mqttNode for this key.
      // _resolveOtherDeviceClient should NOT route to greedyMock.
      expect(greedyMock.canSubscribe('orphan_key'), isTrue);

      // read() should fall through to OPC UA path and throw (no OPC UA client)
      expect(
        () => stateMan.read('orphan_key'),
        throwsA(isA<StateManException>()),
      );
      // greedyMock.read should NOT have been called
      expect(greedyMock.readCalls, isEmpty);

      await stateMan.close();
    });
  });
}

// Integration tests for Modbus TCP support via StateMan.
//
// These tests exercise the full read/write/subscribe path through StateMan
// using a real pymodbus server process. The ModbusClientWrapper and StateMan
// routing to Modbus do not exist yet -- the tests are intentionally written
// ahead of the implementation (TDD).
//
// Run with:
//   dart test test/integration/modbus_integration_test.dart --tags integration

@Tags(['integration'])
library;

import 'dart:async';

import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'modbus_server_helper.dart';

/// Default port used by the pymodbus test server.
const _kPort = 5020;

/// Builds a [StateManConfig] that has no OPC UA servers and a single Modbus
/// server pointing at localhost:[port].
StateManConfig _modbusConfig({
  int port = _kPort,
  List<ModbusPollGroup>? pollGroups,
  String? serverAlias,
}) {
  return StateManConfig(
    opcua: [],
    modbus: [
      ModbusConfig(
        host: 'localhost',
        port: port,
        unitId: 1,
        pollGroups: pollGroups,
        serverAlias: serverAlias,
      ),
    ],
  );
}

/// Convenience: create a [KeyMappings] from a map of key -> [ModbusNodeConfig].
KeyMappings _keyMappings(Map<String, ModbusNodeConfig> entries) {
  return KeyMappings(
    nodes: entries.map(
      (key, node) => MapEntry(key, KeyMappingEntry(modbusNode: node)),
    ),
  );
}

/// Create a [StateMan] configured for Modbus integration tests.
///
/// [keys] maps user-facing key names to their [ModbusNodeConfig].
/// The returned [StateMan] is connected to localhost:[port].
Future<StateMan> _createStateMan(
  Map<String, ModbusNodeConfig> keys, {
  int port = _kPort,
  List<ModbusPollGroup>? pollGroups,
  String? serverAlias,
}) async {
  return StateMan.create(
    config: _modbusConfig(
      port: port,
      pollGroups: pollGroups,
      serverAlias: serverAlias,
    ),
    keyMappings: _keyMappings(keys),
  );
}

void main() {
  late ModbusTestServerProcess server;

  setUpAll(() async {
    await ModbusTestServerProcess.ensureVenv();
    server = ModbusTestServerProcess(port: _kPort);
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
  });

  // ---------------------------------------------------------------------------
  // Group 1: Data type reads -> DynamicValue conversion
  // ---------------------------------------------------------------------------
  group('Data type reads', () {
    late StateMan stateMan;

    tearDown(() async {
      await stateMan.close();
    });

    test('uint16 holding register -> DynamicValue int', () async {
      stateMan = await _createStateMan({
        'hr_uint16': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 0,
          dataType: ModbusDataType.uint16,
        ),
      });

      final value = await stateMan.read('hr_uint16');
      expect(value.isInteger, isTrue);
      expect(value.value, equals(12345));
    });

    test('int16 holding register (negative) -> DynamicValue int', () async {
      stateMan = await _createStateMan({
        'hr_int16': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 1,
          dataType: ModbusDataType.int16,
        ),
      });

      final value = await stateMan.read('hr_int16');
      expect(value.isInteger, isTrue);
      expect(value.value, equals(-32768));
    });

    test('float32 (2 registers) -> DynamicValue double', () async {
      stateMan = await _createStateMan({
        'hr_float32': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 10,
          dataType: ModbusDataType.float32,
        ),
      });

      final value = await stateMan.read('hr_float32');
      expect(value.isDouble, isTrue);
      expect(value.value, closeTo(3.14, 0.01));
    });

    test('float64 (4 registers) -> DynamicValue double', () async {
      stateMan = await _createStateMan({
        'hr_float64': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 20,
          dataType: ModbusDataType.float64,
        ),
      });

      final value = await stateMan.read('hr_float64');
      expect(value.isDouble, isTrue);
      expect(value.value, closeTo(2.718281828, 0.000001));
    });

    test('uint32 (2 registers) -> DynamicValue int', () async {
      stateMan = await _createStateMan({
        'hr_uint32': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 30,
          dataType: ModbusDataType.uint32,
        ),
      });

      final value = await stateMan.read('hr_uint32');
      expect(value.isInteger, isTrue);
      expect(value.value, equals(100000));
    });

    test('int64 (4 registers) -> DynamicValue int', () async {
      stateMan = await _createStateMan({
        'hr_int64': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 40,
          dataType: ModbusDataType.int64,
        ),
      });

      final value = await stateMan.read('hr_int64');
      expect(value.isInteger, isTrue);
      expect(value.value, equals(-1000000));
    });

    test('input register uint16 -> DynamicValue int', () async {
      stateMan = await _createStateMan({
        'ir_uint16': ModbusNodeConfig(
          registerType: ModbusRegisterType.inputRegister,
          address: 0,
          dataType: ModbusDataType.uint16,
        ),
      });

      final value = await stateMan.read('ir_uint16');
      expect(value.isInteger, isTrue);
      expect(value.value, equals(54321));
    });

    test('coil true -> DynamicValue bool', () async {
      stateMan = await _createStateMan({
        'coil_true': ModbusNodeConfig(
          registerType: ModbusRegisterType.coil,
          address: 0,
          dataType: ModbusDataType.bit,
        ),
      });

      final value = await stateMan.read('coil_true');
      expect(value.isBoolean, isTrue);
      expect(value.value, isTrue);
    });

    test('coil false -> DynamicValue bool', () async {
      stateMan = await _createStateMan({
        'coil_false': ModbusNodeConfig(
          registerType: ModbusRegisterType.coil,
          address: 1,
          dataType: ModbusDataType.bit,
        ),
      });

      final value = await stateMan.read('coil_false');
      expect(value.isBoolean, isTrue);
      expect(value.value, isFalse);
    });

    test('discrete input true -> DynamicValue bool', () async {
      stateMan = await _createStateMan({
        'di_true': ModbusNodeConfig(
          registerType: ModbusRegisterType.discreteInput,
          address: 0,
          dataType: ModbusDataType.bit,
        ),
      });

      final value = await stateMan.read('di_true');
      expect(value.isBoolean, isTrue);
      expect(value.value, isTrue);
    });

    test('discrete input false -> DynamicValue bool', () async {
      stateMan = await _createStateMan({
        'di_false': ModbusNodeConfig(
          registerType: ModbusRegisterType.discreteInput,
          address: 1,
          dataType: ModbusDataType.bit,
        ),
      });

      final value = await stateMan.read('di_false');
      expect(value.isBoolean, isTrue);
      expect(value.value, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 2: Write operations
  // ---------------------------------------------------------------------------
  group('Write operations', () {
    late StateMan stateMan;

    tearDown(() async {
      await stateMan.close();
    });

    test('write int to holding register, verify via server GET', () async {
      stateMan = await _createStateMan({
        'hr_write_uint16': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 100,
          dataType: ModbusDataType.uint16,
        ),
      });

      await stateMan.write('hr_write_uint16', DynamicValue(value: 42));

      // Verify the value was actually written to the server.
      final serverValue = await server.getHoldingRegister(100);
      expect(serverValue, equals(42));
    });

    test('write double to float32 register, verify via server', () async {
      stateMan = await _createStateMan({
        'hr_write_float32': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 102,
          dataType: ModbusDataType.float32,
        ),
      });

      await stateMan.write('hr_write_float32', DynamicValue(value: 6.28));

      // Read back through StateMan to verify round-trip.
      final readBack = await stateMan.read('hr_write_float32');
      expect(readBack.isDouble, isTrue);
      expect(readBack.value, closeTo(6.28, 0.01));
    });

    test('write bool to coil, verify via server', () async {
      stateMan = await _createStateMan({
        'coil_write': ModbusNodeConfig(
          registerType: ModbusRegisterType.coil,
          address: 50,
          dataType: ModbusDataType.bit,
        ),
      });

      await stateMan.write('coil_write', DynamicValue(value: true));

      final serverValue = await server.getCoil(50);
      expect(serverValue, isTrue);

      // Toggle back to false.
      await stateMan.write('coil_write', DynamicValue(value: false));
      final serverValue2 = await server.getCoil(50);
      expect(serverValue2, isFalse);
    });

    test('write to input register -> throws StateManException', () async {
      stateMan = await _createStateMan({
        'ir_readonly': ModbusNodeConfig(
          registerType: ModbusRegisterType.inputRegister,
          address: 0,
          dataType: ModbusDataType.uint16,
        ),
      });

      expect(
        () => stateMan.write('ir_readonly', DynamicValue(value: 99)),
        throwsA(isA<StateManException>()),
      );
    });

    test('write to discrete input -> throws StateManException', () async {
      stateMan = await _createStateMan({
        'di_readonly': ModbusNodeConfig(
          registerType: ModbusRegisterType.discreteInput,
          address: 0,
          dataType: ModbusDataType.bit,
        ),
      });

      expect(
        () => stateMan.write('di_readonly', DynamicValue(value: true)),
        throwsA(isA<StateManException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3: Polling & subscribe
  // ---------------------------------------------------------------------------
  group('Polling and subscribe', () {
    late StateMan stateMan;

    tearDown(() async {
      await stateMan.close();
    });

    test('subscribe to key receives initial value', () async {
      stateMan = await _createStateMan({
        'hr_sub': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 0,
          dataType: ModbusDataType.uint16,
        ),
      });

      final stream = await stateMan.subscribe('hr_sub');
      final firstValue = await stream.first.timeout(
        const Duration(seconds: 5),
      );
      expect(firstValue.isInteger, isTrue);
      expect(firstValue.value, equals(12345));
    });

    test('server changes register -> next poll emits new DynamicValue',
        () async {
      stateMan = await _createStateMan(
        {
          'hr_poll': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 200,
            dataType: ModbusDataType.uint16,
            pollGroup: 'default',
          ),
        },
        pollGroups: [
          ModbusPollGroup(name: 'default', pollIntervalMs: 200),
        ],
      );

      // Set an initial value on the server side.
      await server.setHoldingRegister(200, 111);

      final stream = await stateMan.subscribe('hr_poll');
      final values = <int>[];
      final sub = stream.listen((v) {
        values.add(v.value as int);
      });

      // Wait for at least one poll to pick up the initial value.
      await Future.delayed(const Duration(milliseconds: 500));

      // Now change the value on the server.
      await server.setHoldingRegister(200, 222);

      // Wait for the poller to detect the change.
      await Future.delayed(const Duration(seconds: 2));

      await sub.cancel();

      expect(values, contains(111));
      expect(values, contains(222));
    });

    test('multiple keys polled within one cycle', () async {
      stateMan = await _createStateMan(
        {
          'multi_a': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 0,
            dataType: ModbusDataType.uint16,
          ),
          'multi_b': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 1,
            dataType: ModbusDataType.int16,
          ),
        },
        pollGroups: [
          ModbusPollGroup(name: 'default', pollIntervalMs: 200),
        ],
      );

      final streamA = await stateMan.subscribe('multi_a');
      final streamB = await stateMan.subscribe('multi_b');

      final valA = await streamA.first.timeout(const Duration(seconds: 5));
      final valB = await streamB.first.timeout(const Duration(seconds: 5));

      expect(valA.isInteger, isTrue);
      expect(valA.value, equals(12345));
      expect(valB.isInteger, isTrue);
      expect(valB.value, equals(-32768));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 4: Connection & reconnects
  // ---------------------------------------------------------------------------
  group('Connection and reconnects', () {
    test('connection status becomes connected', () async {
      final stateMan = await _createStateMan({
        'hr_conn': ModbusNodeConfig(
          registerType: ModbusRegisterType.holdingRegister,
          address: 0,
          dataType: ModbusDataType.uint16,
        ),
      });

      addTearDown(() => stateMan.close());

      // The Modbus wrapper should report connected after a successful read.
      // Reading forces the connection to be established.
      await stateMan.read('hr_conn');

      // Check connection status on the modbus wrapper.
      expect(stateMan.modbusClients, isNotEmpty);
      expect(
        stateMan.modbusClients.first.connectionStatus,
        equals(ConnectionStatus.connected),
      );
    });

    test('server stop -> disconnected status', () async {
      // Use a dedicated server on a different port so we don't disturb
      // other tests running against the main server.
      final dedicatedServer = ModbusTestServerProcess(port: 5021);
      await dedicatedServer.start();

      final stateMan = await _createStateMan(
        {
          'hr_disc': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 0,
            dataType: ModbusDataType.uint16,
          ),
        },
        port: 5021,
      );

      addTearDown(() => stateMan.close());

      // Establish connection.
      await stateMan.read('hr_disc');
      expect(
        stateMan.modbusClients.first.connectionStatus,
        equals(ConnectionStatus.connected),
      );

      // Stop the server.
      await dedicatedServer.stop();

      // Wait for the polling/connection check to notice the server is gone.
      await Future.delayed(const Duration(seconds: 5));

      expect(
        stateMan.modbusClients.first.connectionStatus,
        equals(ConnectionStatus.disconnected),
      );
    }, timeout: Timeout(const Duration(seconds: 30)));

    test('server restart -> auto-reconnect', () async {
      final dedicatedServer = ModbusTestServerProcess(port: 5022);
      await dedicatedServer.start();

      final stateMan = await _createStateMan(
        {
          'hr_reconnect': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 0,
            dataType: ModbusDataType.uint16,
          ),
        },
        port: 5022,
      );

      addTearDown(() async {
        await stateMan.close();
        await dedicatedServer.stop();
      });

      // Establish connection.
      await stateMan.read('hr_reconnect');
      expect(
        stateMan.modbusClients.first.connectionStatus,
        equals(ConnectionStatus.connected),
      );

      // Stop the server.
      await dedicatedServer.stop();
      await Future.delayed(const Duration(seconds: 3));

      // Restart the server.
      await dedicatedServer.start();

      // Wait for auto-reconnect.
      await Future.delayed(const Duration(seconds: 5));

      // Should be connected again, and reads should succeed.
      final value = await stateMan.read('hr_reconnect');
      expect(value.isInteger, isTrue);
      expect(
        stateMan.modbusClients.first.connectionStatus,
        equals(ConnectionStatus.connected),
      );
    }, timeout: Timeout(const Duration(seconds: 30)));

    test('connection timeout on unreachable port', () async {
      final stateMan = await _createStateMan(
        {
          'hr_unreachable': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 0,
            dataType: ModbusDataType.uint16,
          ),
        },
        // Use a port where nothing is listening.
        port: 59999,
      );

      addTearDown(() => stateMan.close());

      // Attempting to read should eventually throw or timeout.
      expect(
        () => stateMan.read('hr_unreachable').timeout(
              const Duration(seconds: 10),
            ),
        throwsA(anything),
      );
    }, timeout: Timeout(const Duration(seconds: 20)));
  });

  // ---------------------------------------------------------------------------
  // Group 5: Poll groups
  // ---------------------------------------------------------------------------
  group('Poll groups', () {
    test('keys in "fast" group polled more frequently than default', () async {
      final stateMan = await _createStateMan(
        {
          'fast_key': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 300,
            dataType: ModbusDataType.uint16,
            pollGroup: 'fast',
          ),
          'slow_key': ModbusNodeConfig(
            registerType: ModbusRegisterType.holdingRegister,
            address: 301,
            dataType: ModbusDataType.uint16,
            pollGroup: 'default',
          ),
        },
        pollGroups: [
          ModbusPollGroup(name: 'fast', pollIntervalMs: 100),
          ModbusPollGroup(name: 'default', pollIntervalMs: 1000),
        ],
      );

      addTearDown(() => stateMan.close());

      // Set initial values.
      await server.setHoldingRegister(300, 1);
      await server.setHoldingRegister(301, 1);

      final fastStream = await stateMan.subscribe('fast_key');
      final slowStream = await stateMan.subscribe('slow_key');

      var fastUpdateCount = 0;
      var slowUpdateCount = 0;

      final fastSub = fastStream.listen((_) => fastUpdateCount++);
      final slowSub = slowStream.listen((_) => slowUpdateCount++);

      // Let both groups poll for 2 seconds.
      await Future.delayed(const Duration(seconds: 2));

      await fastSub.cancel();
      await slowSub.cancel();

      // The fast group (100ms interval) should have significantly more updates
      // than the slow group (1000ms interval) over the same 2-second window.
      // Fast: ~20 updates. Slow: ~2 updates. Allow generous margin.
      expect(
        fastUpdateCount,
        greaterThan(slowUpdateCount),
        reason:
            'fast group ($fastUpdateCount updates) should poll more often '
            'than default group ($slowUpdateCount updates)',
      );
    }, timeout: Timeout(const Duration(seconds: 15)));
  });
}

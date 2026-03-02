@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/aggregator_server.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'test_timing.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Variable definition for a simulated PLC.
class VarDef {
  final String keySuffix; // human-readable suffix → key = "${alias}_$keySuffix"
  final String identifier; // OPC UA identifier (numeric string → NodeId.fromNumeric)
  final dynamic initialValue;
  final NodeId typeId;

  VarDef(this.keySuffix, this.identifier, this.initialValue, this.typeId);

  /// Build the server-side NodeId (namespace 1).
  NodeId get nodeId {
    final numId = int.tryParse(identifier);
    return numId != null
        ? NodeId.fromNumeric(1, numId)
        : NodeId.fromString(1, identifier);
  }
}

/// One simulated PLC with alias + variables.
class PlcDef {
  final String alias;
  final List<VarDef> variables;
  PlcDef(this.alias, this.variables);
}

String _key(String alias, String suffix) => '${alias}_$suffix';

// ---------------------------------------------------------------------------
// PLC definitions – 10 PLCs, ~30 variables, all four scalar types + numeric IDs
// ---------------------------------------------------------------------------

final plcDefs = [
  // PLC 1 – Temperature control (doubles)
  PlcDef('plc1', [
    VarDef('temperature', 'temperature', 23.5, NodeId.double),
    VarDef('setpoint', 'setpoint', 25.0, NodeId.double),
  ]),
  // PLC 2 – Motor drive (bool + doubles)
  PlcDef('plc2', [
    VarDef('motor_running', 'motor_running', true, NodeId.boolean),
    VarDef('motor_speed', 'motor_speed', 1500.0, NodeId.double),
    VarDef('motor_current', 'motor_current', 3.2, NodeId.double),
  ]),
  // PLC 3 – Display panel (string + int)
  PlcDef('plc3', [
    VarDef('message', 'message', 'System OK', NodeId.uastring),
    VarDef('status_code', 'status_code', 0, NodeId.int32),
  ]),
  // PLC 4 – Pressure sensors (multiple doubles)
  PlcDef('plc4', [
    VarDef('pressure_1', 'pressure_1', 101.3, NodeId.double),
    VarDef('pressure_2', 'pressure_2', 98.7, NodeId.double),
    VarDef('pressure_3', 'pressure_3', 102.1, NodeId.double),
  ]),
  // PLC 5 – Counters (numeric node IDs)
  PlcDef('plc5', [
    VarDef('count', '100', 42, NodeId.int32),
    VarDef('total', '101', 10000, NodeId.int32),
  ]),
  // PLC 6 – Safety system (booleans)
  PlcDef('plc6', [
    VarDef('e_stop', 'e_stop', false, NodeId.boolean),
    VarDef('guard_closed', 'guard_closed', true, NodeId.boolean),
    VarDef('safety_ok', 'safety_ok', true, NodeId.boolean),
  ]),
  // PLC 7 – Valve control (doubles)
  PlcDef('plc7', [
    VarDef('valve_position', 'valve_position', 75.0, NodeId.double),
    VarDef('valve_target', 'valve_target', 80.0, NodeId.double),
  ]),
  // PLC 8 – Conveyor (double + bool)
  PlcDef('plc8', [
    VarDef('conveyor_speed', 'conveyor_speed', 2.5, NodeId.double),
    VarDef('conveyor_running', 'conveyor_running', true, NodeId.boolean),
  ]),
  // PLC 9 – Mixed IO (double + bool + string + int)
  PlcDef('plc9', [
    VarDef('analog_in', 'analog_in', 4.2, NodeId.double),
    VarDef('digital_out', 'digital_out', false, NodeId.boolean),
    VarDef('label', 'label', 'Sensor A', NodeId.uastring),
    VarDef('error_count', 'error_count', 0, NodeId.int32),
  ]),
  // PLC 10 – Environmental (doubles + int)
  PlcDef('plc10', [
    VarDef('humidity', 'humidity', 45.0, NodeId.double),
    VarDef('ambient_temp', 'ambient_temp', 22.1, NodeId.double),
    VarDef('air_quality', 'air_quality', 95, NodeId.int32),
  ]),
];

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  enableTestTiming();
  final plcServers = <Server>[];
  var plcRunning = true;
  StateMan? directSM;
  AggregatorServer? aggregator;
  ClientIsolate? aggClient;
  StateMan? aggModeSM;
  late KeyMappings keyMappings;
  late List<int> ports;

  // -------------------------------------------------------------------------
  // Setup: 10 PLC servers + direct StateMan + AggregatorServer + clients
  // -------------------------------------------------------------------------
  setUpAll(() async {
    // 11 ports: 10 PLCs + 1 aggregator
    ports = allocatePorts(5, 11);
    final aggregatorPort = ports[10];

    // 1. Spin up 10 OPC UA servers
    for (var i = 0; i < plcDefs.length; i++) {
      final plc = plcDefs[i];
      final port = ports[i];
      final server =
          Server(port: port, logLevel: LogLevel.UA_LOGLEVEL_ERROR);

      for (final v in plc.variables) {
        server.addVariableNode(
          v.nodeId,
          DynamicValue(value: v.initialValue, typeId: v.typeId, name: v.keySuffix),
          accessLevel: const AccessLevelMask(read: true, write: true),
        );
      }
      server.start();
      unawaited(() async {
        while (plcRunning && server.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }());
      plcServers.add(server);
    }

    // 2. Build key mappings (all PLCs, all variables)
    final nodes = <String, KeyMappingEntry>{};
    for (final plc in plcDefs) {
      for (final v in plc.variables) {
        nodes[_key(plc.alias, v.keySuffix)] = KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(
            namespace: 1,
            identifier: v.identifier,
          )..serverAlias = plc.alias,
        );
      }
    }
    keyMappings = KeyMappings(nodes: nodes);

    // 3. Build StateManConfig pointing to all 10 servers
    final opcuaConfigs = <OpcUAConfig>[];
    for (var i = 0; i < plcDefs.length; i++) {
      opcuaConfigs.add(OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:${ports[i]}'
        ..serverAlias = plcDefs[i].alias);
    }
    final config = StateManConfig(
      opcua: opcuaConfigs,
      aggregator: AggregatorConfig(enabled: true, port: aggregatorPort),
    );

    // 4. Create direct StateMan (one ClientIsolate per PLC)
    directSM = await StateMan.create(
      config: config,
      keyMappings: keyMappings,
      useIsolate: true,
      alias: 'test-direct',
    );

    // 5. Wait for all 10 connections
    for (final wrapper in directSM!.clients) {
      if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
      await wrapper.connectionStream
          .firstWhere((event) => event.$1 == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 30));
    }

    // 6. Create and start AggregatorServer
    aggregator = AggregatorServer(
      config: config.aggregator!,
      sharedStateMan: directSM!,
    );
    await aggregator!.initialize(skipTls: true);
    unawaited(aggregator!.runLoop());
    await aggregator!.waitForPending();

    // 7. Raw client to aggregator (for browse/read/write tests)
    aggClient = await ClientIsolate.create();
    unawaited(aggClient!.runIterate().catchError((_) {}));
    unawaited(aggClient!.connect('opc.tcp://localhost:$aggregatorPort'));
    await aggClient!.awaitConnect();

    // 8. Aggregation-mode StateMan (single connection to aggregator)
    aggModeSM = await StateMan.create(
      config: config,
      keyMappings: keyMappings,
      aggregationMode: true,
      useIsolate: true,
      alias: 'test-agg',
    );
    for (final wrapper in aggModeSM!.clients) {
      if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
      await wrapper.connectionStream
          .firstWhere((event) => event.$1 == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 15));
    }
  });

  // -------------------------------------------------------------------------
  // Teardown
  // -------------------------------------------------------------------------
  tearDownAll(timed('ten-plc tearDownAll', () async {
    if (aggModeSM != null) await aggModeSM!.close();
    if (aggClient != null) await aggClient!.delete();
    if (aggregator != null) await aggregator!.shutdown();
    if (directSM != null) await directSM!.close();
    await Future.delayed(const Duration(milliseconds: 50));
    plcRunning = false;
    await Future.delayed(const Duration(milliseconds: 20));
    for (final server in plcServers) {
      server.shutdown();
      server.delete();
    }
  }));

  // =========================================================================
  // 1. Connection tests
  // =========================================================================
  group('Connection', () {
    test('direct StateMan has 10 connected clients', () {
      expect(directSM!.clients.length, 10);
      for (final wrapper in directSM!.clients) {
        expect(wrapper.connectionStatus, ConnectionStatus.connected);
      }
    });

    test('aggregation-mode StateMan has single connected client', () {
      expect(aggModeSM!.clients.length, 1);
      expect(
          aggModeSM!.clients.first.connectionStatus, ConnectionStatus.connected);
    });

    test('aggregator server is running', () {
      expect(aggregator!.isRunning, isTrue);
    });
  });

  // =========================================================================
  // 2. Direct StateMan – reads
  // =========================================================================
  group('Direct StateMan reads', () {
    test('read double (PLC 1 temperature)', () async {
      final v = await directSM!.read('plc1_temperature');
      expect(v.value, 23.5);
    });

    test('read bool (PLC 2 motor_running)', () async {
      final v = await directSM!.read('plc2_motor_running');
      expect(v.value, true);
    });

    test('read string (PLC 3 message)', () async {
      final v = await directSM!.read('plc3_message');
      expect(v.value, 'System OK');
    });

    test('read int via numeric NodeId (PLC 5 count)', () async {
      final v = await directSM!.read('plc5_count');
      expect(v.value, 42);
    });

    test('read multiple doubles from one PLC (PLC 4 pressures)', () async {
      final p1 = await directSM!.read('plc4_pressure_1');
      final p2 = await directSM!.read('plc4_pressure_2');
      final p3 = await directSM!.read('plc4_pressure_3');
      expect(p1.value, 101.3);
      expect(p2.value, 98.7);
      expect(p3.value, 102.1);
    });

    test('read one key from every PLC', () async {
      final sampleKeys = [
        'plc1_temperature', 'plc2_motor_running', 'plc3_message',
        'plc4_pressure_1', 'plc5_count', 'plc6_e_stop',
        'plc7_valve_position', 'plc8_conveyor_speed',
        'plc9_analog_in', 'plc10_humidity',
      ];
      for (final key in sampleKeys) {
        final v = await directSM!.read(key);
        expect(v.value, isNotNull, reason: '$key should be readable');
      }
    });

    test('concurrent reads across all PLCs', () async {
      final futures = <Future<DynamicValue>>[];
      for (final plc in plcDefs) {
        for (final v in plc.variables) {
          futures.add(directSM!.read(_key(plc.alias, v.keySuffix)));
        }
      }
      final results = await Future.wait(futures);
      expect(results.length, greaterThanOrEqualTo(25));
      for (final r in results) {
        expect(r.value, isNotNull);
      }
    });
  });

  // =========================================================================
  // 3. Direct StateMan – writes
  // =========================================================================
  group('Direct StateMan writes', () {
    test('write double and read-back', () async {
      await directSM!.write(
          'plc7_valve_target', DynamicValue(value: 90.0, typeId: NodeId.double));
      await Future.delayed(const Duration(milliseconds: 100));
      final v = await directSM!.read('plc7_valve_target');
      expect(v.value, 90.0);
    });

    test('write bool and read-back', () async {
      await directSM!.write('plc9_digital_out',
          DynamicValue(value: true, typeId: NodeId.boolean));
      await Future.delayed(const Duration(milliseconds: 100));
      final v = await directSM!.read('plc9_digital_out');
      expect(v.value, true);
    });

    test('write string and read-back', () async {
      await directSM!.write(
          'plc3_message', DynamicValue(value: 'Alert!', typeId: NodeId.uastring));
      await Future.delayed(const Duration(milliseconds: 100));
      final v = await directSM!.read('plc3_message');
      expect(v.value, 'Alert!');
    });

    test('write int and read-back', () async {
      await directSM!.write(
          'plc9_error_count', DynamicValue(value: 5, typeId: NodeId.int32));
      await Future.delayed(const Duration(milliseconds: 100));
      final v = await directSM!.read('plc9_error_count');
      expect(v.value, 5);
    });

    test('write to numeric NodeId PLC and read-back', () async {
      await directSM!.write(
          'plc5_count', DynamicValue(value: 99, typeId: NodeId.int32));
      await Future.delayed(const Duration(milliseconds: 100));
      final v = await directSM!.read('plc5_count');
      expect(v.value, 99);
    });
  });

  // =========================================================================
  // 4. Direct StateMan – subscriptions
  // =========================================================================
  group('Direct StateMan subscriptions', () {
    test('subscribe returns stream with initial value', () async {
      final stream = await directSM!.subscribe('plc1_setpoint');
      final value = await stream.first.timeout(const Duration(seconds: 5));
      expect(value.value, isA<double>());
    });

    test('subscribe detects upstream value change', () async {
      final stream = await directSM!.subscribe('plc4_pressure_1');
      final received = <double>[];
      final sub = stream.listen((v) {
        if (v.value is double) received.add(v.value as double);
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // Simulate PLC value change
      plcServers[3].write(
        NodeId.fromString(1, 'pressure_1'),
        DynamicValue(value: 150.0, typeId: NodeId.double),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      expect(received, contains(150.0));
      await sub.cancel();
    });

    test('multiple simultaneous subscriptions across different PLCs', () async {
      final streams = await Future.wait([
        directSM!.subscribe('plc1_temperature'),
        directSM!.subscribe('plc6_safety_ok'),
        directSM!.subscribe('plc10_humidity'),
      ]);

      final values = await Future.wait(
        streams.map((s) => s.first.timeout(const Duration(seconds: 5))),
      );

      expect(values.length, 3);
      for (final v in values) {
        expect(v.value, isNotNull);
      }
    });
  });

  // =========================================================================
  // 5. Aggregator – browse
  // =========================================================================
  group('Aggregator browse', () {
    test('OpcUa variables folder contains all 10 alias folders', () async {
      final opcuaFolder = NodeId.fromString(1, 'Servers/Variables/OpcUa');
      final results = await aggClient!.browse(opcuaFolder);
      final names = results.map((r) => r.browseName).toSet();

      for (final plc in plcDefs) {
        expect(names, contains(plc.alias),
            reason: 'Missing folder for ${plc.alias}');
      }
    });

    test('each alias folder contains expected variable browse names', () async {
      for (final plc in plcDefs) {
        final folderId = AggregatorNodeId.folderNodeId(plc.alias);
        final results = await aggClient!.browse(folderId);
        final browseNames = results.map((r) => r.browseName).toSet();

        for (final v in plc.variables) {
          final expectedKey = _key(plc.alias, v.keySuffix);
          expect(browseNames, contains(expectedKey),
              reason: '${plc.alias} folder missing $expectedKey');
        }
      }
    });

    test('variable nodes use namespace 1 with encoded string IDs', () async {
      final folderId = AggregatorNodeId.folderNodeId('plc1');
      final results = await aggClient!.browse(folderId);

      // Filter to only our variable nodes (skip standard OPC UA reference nodes)
      final expectedKeys = plcDefs[0]
          .variables
          .map((v) => _key('plc1', v.keySuffix))
          .toSet();
      final varResults =
          results.where((r) => expectedKeys.contains(r.browseName));

      expect(varResults, isNotEmpty);
      for (final result in varResults) {
        expect(result.nodeId.namespace, 1);
        expect(result.nodeId.isString(), isTrue);
        expect(result.nodeId.string, startsWith('plc1:'));
      }
    });
  });

  // =========================================================================
  // 6. Aggregator – reads via raw client
  // =========================================================================
  group('Aggregator reads (raw client)', () {
    test('read double through aggregator', () async {
      final nodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'temperature'));
      final v = await aggClient!.read(nodeId);
      expect(v.value, isA<double>());
    });

    test('read bool through aggregator', () async {
      final nodeId = AggregatorNodeId.encode(
          'plc2', NodeId.fromString(1, 'motor_running'));
      final v = await aggClient!.read(nodeId);
      expect(v.value, isA<bool>());
    });

    test('read string through aggregator', () async {
      final nodeId = AggregatorNodeId.encode(
          'plc3', NodeId.fromString(1, 'message'));
      final v = await aggClient!.read(nodeId);
      expect(v.value, isA<String>());
    });

    test('read int (numeric upstream NodeId) through aggregator', () async {
      final nodeId = AggregatorNodeId.encode(
          'plc5', NodeId.fromNumeric(1, 100));
      final v = await aggClient!.read(nodeId);
      expect(v.value, isA<int>());
    });

    test('read every variable from all 10 PLCs through aggregator', () async {
      for (final plc in plcDefs) {
        for (final v in plc.variables) {
          final aggNodeId = AggregatorNodeId.encode(plc.alias, v.nodeId);
          final result = await aggClient!.read(aggNodeId);
          expect(result.value, isNotNull,
              reason: 'Agg read failed: ${plc.alias}/${v.keySuffix}');
        }
      }
    });
  });

  // =========================================================================
  // 7. Aggregator – writes via raw client
  // =========================================================================
  group('Aggregator writes (raw client)', () {
    test('write through aggregator forwards to upstream PLC', () async {
      final aggNodeId = AggregatorNodeId.encode(
          'plc7', NodeId.fromString(1, 'valve_position'));

      await aggClient!.write(
          aggNodeId, DynamicValue(value: 95.0, typeId: NodeId.double));

      // Wait for: aggregator monitorVariable → forwardWrite → StateMan → PLC
      await Future.delayed(const Duration(seconds: 1));

      final v = await directSM!.read('plc7_valve_position');
      expect(v.value, 95.0);
    });

    test('write bool through aggregator', () async {
      final aggNodeId = AggregatorNodeId.encode(
          'plc6', NodeId.fromString(1, 'e_stop'));

      await aggClient!.write(
          aggNodeId, DynamicValue(value: true, typeId: NodeId.boolean));

      await Future.delayed(const Duration(seconds: 1));

      final v = await directSM!.read('plc6_e_stop');
      expect(v.value, true);
    });
  });

  // =========================================================================
  // 8. Aggregation-mode StateMan (HMI perspective)
  // =========================================================================
  group('Aggregation-mode StateMan (HMI path)', () {
    test('read double through aggregated StateMan', () async {
      final v = await aggModeSM!.read('plc1_temperature');
      expect(v.value, isA<double>());
    });

    test('read all scalar types through aggregated StateMan', () async {
      expect((await aggModeSM!.read('plc4_pressure_2')).value, isA<double>());
      expect((await aggModeSM!.read('plc6_guard_closed')).value, isA<bool>());
      expect((await aggModeSM!.read('plc9_label')).value, isA<String>());
      expect((await aggModeSM!.read('plc10_air_quality')).value, isA<int>());
    });

    test('read from all 10 PLCs through aggregated StateMan', () async {
      for (final plc in plcDefs) {
        final firstVar = plc.variables.first;
        final key = _key(plc.alias, firstVar.keySuffix);
        final v = await aggModeSM!.read(key);
        expect(v.value, isNotNull, reason: '$key should be readable via agg');
      }
    });

    test('write through aggregated StateMan reaches upstream', () async {
      await aggModeSM!.write('plc8_conveyor_speed',
          DynamicValue(value: 5.0, typeId: NodeId.double));

      // Full chain: aggModeSM → aggregator client write → monitorVariable
      // → forwardWrite → directSM → PLC
      await Future.delayed(const Duration(seconds: 1));

      final v = await directSM!.read('plc8_conveyor_speed');
      expect(v.value, 5.0);
    });

    test('subscribe through aggregated StateMan', () async {
      final stream = await aggModeSM!.subscribe('plc10_humidity');
      final value = await stream.first.timeout(const Duration(seconds: 5));
      expect(value.value, isA<double>());
    });
  });

  // =========================================================================
  // 9. End-to-end data flow
  // =========================================================================
  group('End-to-end data flow', () {
    test('upstream PLC change → aggregation client subscription', () async {
      final stream = await aggModeSM!.subscribe('plc2_motor_current');
      final received = <double>[];
      final sub = stream.listen((v) {
        if (v.value is double) received.add(v.value as double);
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // Simulate PLC 2 value change
      plcServers[1].write(
        NodeId.fromString(1, 'motor_current'),
        DynamicValue(value: 7.5, typeId: NodeId.double),
      );

      // Chain: PLC server → directSM subscription → aggregator write →
      // aggregator iteration → aggModeSM subscription
      await Future.delayed(const Duration(seconds: 2));

      expect(received, contains(7.5),
          reason: 'Value should propagate through full aggregation chain');
      await sub.cancel();
    });

    test('HMI write → upstream PLC (full write-forwarding chain)', () async {
      // Write from "HMI" (aggregation-mode StateMan)
      await aggModeSM!.write(
          'plc6_safety_ok', DynamicValue(value: false, typeId: NodeId.boolean));

      // Chain: aggModeSM write → aggregator client write → server
      // monitorVariable → forwardWrite → directSM → PLC
      await Future.delayed(const Duration(seconds: 1));

      // Verify upstream PLC has the new value
      final v = await directSM!.read('plc6_safety_ok');
      expect(v.value, false);
    });

    test('concurrent writes to different PLCs all succeed', () async {
      await Future.wait([
        aggModeSM!.write('plc1_setpoint',
            DynamicValue(value: 30.0, typeId: NodeId.double)),
        aggModeSM!.write('plc9_error_count',
            DynamicValue(value: 10, typeId: NodeId.int32)),
        aggModeSM!.write('plc3_status_code',
            DynamicValue(value: 1, typeId: NodeId.int32)),
      ]);

      await Future.delayed(const Duration(seconds: 1));

      expect((await directSM!.read('plc1_setpoint')).value, 30.0);
      expect((await directSM!.read('plc9_error_count')).value, 10);
      expect((await directSM!.read('plc3_status_code')).value, 1);
    });
  });

  // =========================================================================
  // 10. Collection-like pipeline (subscription flow that underpins Collector)
  // =========================================================================
  group('Collection pipeline (subscription-based)', () {
    test('continuous upstream changes arrive in subscription stream', () async {
      final stream = await directSM!.subscribe('plc10_ambient_temp');
      final received = <double>[];
      final sub = stream.listen((v) {
        if (v.value is double) received.add(v.value as double);
      });

      // Simulate sensor changes at PLC 10
      for (var temp = 22.0; temp <= 24.0; temp += 0.5) {
        plcServers[9].write(
          NodeId.fromString(1, 'ambient_temp'),
          DynamicValue(value: temp, typeId: NodeId.double),
        );
        await Future.delayed(const Duration(milliseconds: 200));
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // Should have received multiple updates (like a collector would)
      expect(received.length, greaterThanOrEqualTo(3),
          reason: 'Should receive continuous value updates for collection');
      await sub.cancel();
    });

    test('subscriptions to multiple PLCs receive independent updates', () async {
      final stream1 = await directSM!.subscribe('plc1_temperature');
      final stream6 = await directSM!.subscribe('plc6_guard_closed');

      final temps = <double>[];
      final guards = <bool>[];
      final sub1 = stream1.listen((v) {
        if (v.value is double) temps.add(v.value as double);
      });
      final sub6 = stream6.listen((v) {
        if (v.value is bool) guards.add(v.value as bool);
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // Change PLC 1 only
      plcServers[0].write(
        NodeId.fromString(1, 'temperature'),
        DynamicValue(value: 30.0, typeId: NodeId.double),
      );

      // Change PLC 6 only
      plcServers[5].write(
        NodeId.fromString(1, 'guard_closed'),
        DynamicValue(value: false, typeId: NodeId.boolean),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      expect(temps, contains(30.0));
      expect(guards, contains(false));

      await sub1.cancel();
      await sub6.cancel();
    });
  });

  // =========================================================================
  // 11. Alarm-like monitoring (value threshold / state-change detection)
  // =========================================================================
  group('Alarm-like value monitoring', () {
    test('detect value exceeding threshold', () async {
      final stream = await directSM!.subscribe('plc4_pressure_3');
      final highPressure = <double>[];
      final sub = stream.listen((v) {
        if (v.value is double && (v.value as double) > 200.0) {
          highPressure.add(v.value as double);
        }
      });

      await Future.delayed(const Duration(milliseconds: 200));

      // Simulate pressure spike
      plcServers[3].write(
        NodeId.fromString(1, 'pressure_3'),
        DynamicValue(value: 250.0, typeId: NodeId.double),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      expect(highPressure, isNotEmpty,
          reason: 'Should detect pressure exceeding threshold');
      expect(highPressure.first, 250.0);
      await sub.cancel();
    });

    test('detect boolean state change (emergency stop)', () async {
      // Reset conveyor to running first
      plcServers[7].write(
        NodeId.fromString(1, 'conveyor_running'),
        DynamicValue(value: true, typeId: NodeId.boolean),
      );
      await Future.delayed(const Duration(milliseconds: 300));

      final stream = await directSM!.subscribe('plc8_conveyor_running');
      final stateChanges = <bool>[];
      final sub = stream.listen((v) {
        if (v.value is bool) stateChanges.add(v.value as bool);
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // Simulate emergency stop
      plcServers[7].write(
        NodeId.fromString(1, 'conveyor_running'),
        DynamicValue(value: false, typeId: NodeId.boolean),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      expect(stateChanges, contains(false),
          reason: 'Should detect conveyor emergency stop');
      await sub.cancel();
    });

    test('threshold crossing detected through aggregated path', () async {
      final stream = await aggModeSM!.subscribe('plc4_pressure_2');
      final highPressure = <double>[];
      final sub = stream.listen((v) {
        if (v.value is double && (v.value as double) > 200.0) {
          highPressure.add(v.value as double);
        }
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // Simulate pressure spike on upstream PLC
      plcServers[3].write(
        NodeId.fromString(1, 'pressure_2'),
        DynamicValue(value: 300.0, typeId: NodeId.double),
      );

      // Full chain propagation
      await Future.delayed(const Duration(seconds: 2));

      expect(highPressure, isNotEmpty,
          reason: 'Threshold crossing should propagate through aggregator');
      await sub.cancel();
    });
  });

  // =========================================================================
  // 12. Health check reads
  // =========================================================================
  group('Health checks', () {
    test('read ServerStatus.CurrentTime from each PLC via direct StateMan',
        () async {
      // ServerStatus.CurrentTime = ns=0;i=2258
      // Read it directly through the clients to verify servers are healthy
      for (final wrapper in directSM!.clients) {
        final serverTime = NodeId.fromNumeric(0, 2258);
        final result = await wrapper.client.readAttribute({
          serverTime: [AttributeId.UA_ATTRIBUTEID_VALUE]
        });
        expect(result, isNotEmpty,
            reason:
                'Health check read should succeed for ${wrapper.config.serverAlias}');
      }
    });
  });
}

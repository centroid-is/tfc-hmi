import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/interface.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart' show ModbusDataType;

import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/pages/key_repository.dart';
import 'package:tfc/pages/server_config.dart';

/// In-memory secure storage for tests.
class FakeSecureStorage implements MySecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _store[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _store.remove(key);
  }
}

/// Creates a test [Preferences] backed by in-memory storage (no database).
Future<Preferences> createTestPreferences({
  KeyMappings? keyMappings,
  StateManConfig? stateManConfig,
}) async {
  final secureStorage = FakeSecureStorage();
  final prefs = Preferences(database: null, secureStorage: secureStorage);

  // Pre-populate key_mappings
  final km = keyMappings ?? KeyMappings(nodes: {});
  await prefs.setString('key_mappings', jsonEncode(km.toJson()));

  // Pre-populate state_man_config in secure storage (StateManConfig reads with secret: true)
  final smc = stateManConfig ?? StateManConfig(opcua: []);
  await secureStorage.write(
    key: StateManConfig.configKey,
    value: jsonEncode(smc.toJson()),
  );

  return prefs;
}

/// Creates a sample [KeyMappings] with test data.
KeyMappings sampleKeyMappings() {
  return KeyMappings(nodes: {
    'temperature_sensor': KeyMappingEntry(
      opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'Temperature')
        ..serverAlias = 'main_server',
      collect: CollectEntry(
        key: 'temperature_sensor',
        name: 'Temperature',
        sampleInterval: const Duration(microseconds: 1000000),
        retention: const RetentionPolicy(
          dropAfter: Duration(days: 30),
          scheduleInterval: null,
        ),
      ),
    ),
    'pressure_valve': KeyMappingEntry(
      opcuaNode: OpcUANodeConfig(namespace: 3, identifier: 'PressureValve')
        ..serverAlias = 'main_server',
    ),
  });
}

/// Creates a sample [StateManConfig] with test server aliases.
StateManConfig sampleStateManConfig() {
  return StateManConfig(opcua: [
    OpcUAConfig()
      ..endpoint = 'opc.tcp://localhost:4840'
      ..serverAlias = 'main_server',
    OpcUAConfig()
      ..endpoint = 'opc.tcp://localhost:4841'
      ..serverAlias = 'backup_server',
  ]);
}

/// Wraps the [KeyRepositoryContent] widget in a testable widget tree
/// with [ProviderScope] overrides for [preferencesProvider].
Widget buildTestableKeyRepository({
  KeyMappings? keyMappings,
  StateManConfig? stateManConfig,
}) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith((ref) => createTestPreferences(
            keyMappings: keyMappings,
            stateManConfig: stateManConfig,
          )),
      databaseProvider.overrideWith((ref) async => null),
      // Override stateManProvider to avoid real network connections.
      // Throwing makes valueOrNull return null and isLoading false.
      stateManProvider.overrideWith((ref) =>
          throw StateError('No StateMan in tests')),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: KeyRepositoryContent(),
      ),
    ),
  );
}

/// Creates a sample [StateManConfig] with one Modbus server for tests.
StateManConfig sampleModbusStateManConfig() {
  return StateManConfig(
    opcua: [],
    modbus: [
      ModbusConfig(
        host: '192.168.1.100',
        port: 502,
        unitId: 1,
        pollGroups: [
          ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
        ],
      )..serverAlias = 'plc_1',
    ],
  );
}

/// Creates a sample [StateManConfig] with one Modbus server that has 2 poll groups.
StateManConfig sampleModbusWithTwoPollGroups() {
  return StateManConfig(
    opcua: [],
    modbus: [
      ModbusConfig(
        host: '192.168.1.100',
        port: 502,
        unitId: 1,
        pollGroups: [
          ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
          ModbusPollGroupConfig(name: 'fast', intervalMs: 100),
        ],
      )..serverAlias = 'plc_1',
    ],
  );
}

/// Creates sample [KeyMappings] with Modbus keys for tests.
KeyMappings sampleModbusKeyMappings() {
  return KeyMappings(nodes: {
    'modbus_temp': KeyMappingEntry(
      modbusNode: ModbusNodeConfig(
        serverAlias: 'plc_1',
        registerType: ModbusRegisterType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.float32,
        pollGroup: 'default',
      ),
    ),
    'modbus_coil': KeyMappingEntry(
      modbusNode: ModbusNodeConfig(
        serverAlias: 'plc_1',
        registerType: ModbusRegisterType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
        pollGroup: 'default',
      ),
    ),
  });
}

/// Creates a sample [StateManConfig] with both OPC UA and Modbus servers.
/// Enables testing that Modbus ChoiceChip appears alongside OPC UA.
StateManConfig sampleStateManConfigWithModbus() {
  return StateManConfig(
    opcua: [
      OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..serverAlias = 'main_server',
    ],
    modbus: [
      ModbusConfig(
        host: '192.168.1.100',
        port: 502,
        unitId: 1,
        pollGroups: [
          ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
          ModbusPollGroupConfig(name: 'fast', intervalMs: 100),
        ],
      )..serverAlias = 'plc_1',
    ],
  );
}

/// Creates a sample [StateManConfig] with a UMAS-enabled Modbus server.
/// For testing Browse button visibility in key repository.
StateManConfig sampleStateManConfigWithUmas() {
  return StateManConfig(
    opcua: [],
    modbus: [
      ModbusConfig(
        host: '192.168.1.200',
        port: 502,
        unitId: 1,
        umasEnabled: true,
        pollGroups: [
          ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
        ],
      )..serverAlias = 'schneider_plc',
    ],
  );
}

/// Pumps widget and waits for async config loading to complete.
///
/// ServerConfigBody sections show CircularProgressIndicator during async
/// _loadConfig(). The indeterminate animation prevents pumpAndSettle from
/// settling. This helper uses explicit pump() calls to let Futures resolve
/// before calling pumpAndSettle.
Future<void> pumpAndLoad(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  // Pump multiple frames to let all async _loadConfig() Futures resolve.
  // Cannot use pumpAndSettle — DatabaseConfigWidget and other sections show
  // CircularProgressIndicator (indeterminate animation) that never settles.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Wraps the [ServerConfigPage] body in a testable widget tree.
///
/// Bypasses [BaseScaffold] (which requires Beamer routing context) by
/// rendering the same Column of sections that [ServerConfigPage.build]
/// produces. This tests all section widgets without needing a full router.
Widget buildTestableServerConfig({
  StateManConfig? stateManConfig,
}) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith((ref) => createTestPreferences(
            stateManConfig: stateManConfig,
          )),
      databaseProvider.overrideWith((ref) async => null),
      // Override stateManProvider to avoid real network connections.
      // Throwing makes valueOrNull return null and isLoading false,
      // so connection status shows "Not active" (grey).
      stateManProvider.overrideWith((ref) =>
          throw StateError('No StateMan in tests')),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: const ServerConfigBody(),
      ),
    ),
  );
}

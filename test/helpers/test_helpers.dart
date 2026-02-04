import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/interface.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';

import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/pages/key_repository.dart';

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
    ],
    child: MaterialApp(
      home: Scaffold(
        body: KeyRepositoryContent(),
      ),
    ),
  );
}

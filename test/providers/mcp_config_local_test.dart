import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc_dart/core/preferences.dart'
    show InMemoryPreferences, Preferences;
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    show McpConfig, McpToolToggles, writeMcpConfigToPreferences;

import '../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mirrors production: the database-backed Preferences uses the device's
  // SharedPreferences as its local cache — the same physical store the
  // device-local preferences read from.
  (Preferences, InMemoryPreferences) createStores() {
    final deviceStore = InMemoryPreferences();
    final shared = Preferences(
      database: null,
      secureStorage: FakeSecureStorage(),
      localCache: deviceStore,
    );
    return (shared, deviceStore);
  }

  ProviderContainer createContainer(
      Preferences shared, InMemoryPreferences deviceStore) {
    final container = ProviderContainer(overrides: [
      preferencesProvider.overrideWith((ref) async => shared),
      localPreferencesProvider.overrideWithValue(deviceStore),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('mcpConfigProvider (device-local)', () {
    test('migrates a shared config onto the device and cleans the shared '
        'store', () async {
      final (shared, deviceStore) = createStores();
      const config = McpConfig(
        serverEnabled: true,
        port: 9999,
        toggles: McpToolToggles(trendsEnabled: false),
      );
      // Simulates a pre-migration install: the config sits in the shared
      // (database) store and is mirrored into the device store.
      await shared.setString(McpConfig.kPrefKey, jsonEncode(config.toJson()));

      final container = createContainer(shared, deviceStore);
      final result = await container.read(mcpConfigProvider.future);

      expect(result, config);
      expect(await shared.getString(McpConfig.kPrefKey), isNull,
          reason: 'the shared store must no longer carry the MCP config');
      expect(await deviceStore.getString(McpConfig.kPrefKey), isNotNull,
          reason: 'the device store must keep the migrated config');
    });

    test('returns defaults on a fresh install', () async {
      final (shared, deviceStore) = createStores();
      final container = createContainer(shared, deviceStore);

      final result = await container.read(mcpConfigProvider.future);

      expect(result, McpConfig.defaults);
    });

    test('saving writes only to the device store', () async {
      final (shared, deviceStore) = createStores();
      final container = createContainer(shared, deviceStore);
      await container.read(mcpConfigProvider.future);

      const updated = McpConfig(serverEnabled: true, port: 4242);
      await writeMcpConfigToPreferences(
          container.read(localPreferencesProvider), updated);
      container.invalidate(mcpConfigProvider);

      expect(await container.read(mcpConfigProvider.future), updated);
      expect(await shared.getString(McpConfig.kPrefKey), isNull,
          reason: 'saving the MCP config must never touch the shared store');
    });

    test('migration re-runs when preferencesProvider is recreated '
        '(database reconnect after offline start)', () async {
      final (shared, deviceStore) = createStores();
      final container = createContainer(shared, deviceStore);
      await container.read(mcpConfigProvider.future);

      // Simulate a database coming online after startup: the recreated
      // Preferences now carries an mcp.config row that the first
      // migration pass could not delete.
      const staleDbConfig = McpConfig(serverEnabled: true, port: 1111);
      await shared.setString(
          McpConfig.kPrefKey, jsonEncode(staleDbConfig.toJson()));
      container.invalidate(preferencesProvider);

      expect(await container.read(mcpConfigProvider.future), staleDbConfig,
          reason: 'the re-run migration must adopt the synced value');
      expect(await shared.getString(McpConfig.kPrefKey), isNull,
          reason: 'the re-run migration must clean the shared store so the '
              'row cannot be re-synced over the device config again');
    });

    test('legacy database keys seed the device config and are removed',
        () async {
      final (shared, deviceStore) = createStores();
      await shared.setBool('mcp_server_enabled', true);
      await shared.setInt('mcp_server_port', 7777);

      final container = createContainer(shared, deviceStore);
      final result = await container.read(mcpConfigProvider.future);

      expect(result.serverEnabled, isTrue);
      expect(result.port, 7777);
      for (final key in McpConfig.legacyKeys) {
        expect(await shared.containsKey(key), isFalse,
            reason: 'legacy key $key must be removed from the shared store');
      }
    });
  });
}

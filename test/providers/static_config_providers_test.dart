import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tfc_dart/core/config_source.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'package:tfc/providers/static_config.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/collector.dart';
import 'package:tfc/providers/page_manager.dart';
import 'package:tfc/page_creator/page.dart';

import '../helpers/test_helpers.dart';

/// Provider-level tests verifying the static config integration path.
///
/// These test the Riverpod provider wiring — that stateManProvider
/// checks staticConfigProvider FIRST and short-circuits when present,
/// and that pageManagerProvider loads from static JSON without saving.
void main() {
  group('stateManProvider with static config', () {
    test('bypasses preferences when StaticConfig is present', () async {
      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({
          'opcua': [],
          'mqtt': [], // Empty — avoid real MqttDeviceClientAdapter in test
        }),
        keyMappingsJson: jsonEncode({
          'nodes': {
            'sensor.temp': {
              'mqtt_node': {
                'topic': 'plant/temp',
                'qos': 0,
                'server_alias': 'broker1',
              },
            },
          },
        }),
      );

      final container = ProviderContainer(
        overrides: [
          staticConfigProvider.overrideWith((ref) async => staticConfig),
          // Preferences should NOT be needed — throw if accessed
          preferencesProvider
              .overrideWith((ref) => throw StateError('Should not access preferences')),
          databaseProvider.overrideWith((ref) async => null),
          collectorProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final stateMan = await container.read(stateManProvider.future);
      expect(stateMan, isNotNull);
      // Preferences were NOT accessed — provider used static config path
      expect(stateMan.keyMappings.nodes.containsKey('sensor.temp'), isTrue);
    });

    test('falls through to preferences when StaticConfig is null', () async {
      final prefs = await createTestPreferences(
        stateManConfig: StateManConfig(opcua: []),
        keyMappings: KeyMappings(nodes: {}),
      );

      final container = ProviderContainer(
        overrides: [
          staticConfigProvider.overrideWith((ref) async => null),
          preferencesProvider.overrideWith((ref) async => prefs),
          databaseProvider.overrideWith((ref) async => null),
          collectorProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final stateMan = await container.read(stateManProvider.future);
      expect(stateMan, isNotNull);
      // Came from preferences path — opcua list is empty
      expect(stateMan.config.opcua, isEmpty);

      await stateMan.close();
    });

    test('eagerly initializes collectorProvider on static config path',
        () async {
      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({
          'opcua': [],
          'mqtt': [],
        }),
        keyMappingsJson: jsonEncode({'nodes': {}}),
      );

      var collectorAccessed = false;
      final container = ProviderContainer(
        overrides: [
          staticConfigProvider.overrideWith((ref) async => staticConfig),
          preferencesProvider
              .overrideWith((ref) => throw StateError('Should not access preferences')),
          databaseProvider.overrideWith((ref) async => null),
          collectorProvider.overrideWith((ref) async {
            collectorAccessed = true;
            return null;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(stateManProvider.future);
      // The static config path should eagerly read collectorProvider
      expect(collectorAccessed, isTrue);

      final stateMan = await container.read(stateManProvider.future);
      await stateMan.close();
    });
  });

  group('pageManagerProvider with static config', () {
    test('loads pages from static config JSON without calling save()',
        () async {
      final pageJson = jsonEncode({
        '/': {
          'menu_item': {
            'label': 'Home',
            'path': '/',
            'icon': 'home',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
        },
        '/dashboard': {
          'menu_item': {
            'label': 'Dashboard',
            'path': '/dashboard',
            'icon': 'dashboard',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
        },
      });

      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({'opcua': []}),
        keyMappingsJson: jsonEncode({'nodes': {}}),
        pageEditorJson: pageJson,
      );

      final prefs = await createTestPreferences();

      final container = ProviderContainer(
        overrides: [
          staticConfigProvider.overrideWith((ref) async => staticConfig),
          preferencesProvider.overrideWith((ref) async => prefs),
          databaseProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final pageManager = await container.read(pageManagerProvider.future);
      expect(pageManager.pages.length, 2);
      expect(pageManager.pages.containsKey('/'), isTrue);
      expect(pageManager.pages.containsKey('/dashboard'), isTrue);
      expect(pageManager.pages['/']!.menuItem.label, 'Home');

      // Verify save() was NOT called — prefs should not have page_editor_data
      final savedData = await prefs.getString(PageManager.storageKey);
      expect(savedData, isNull);
    });

    test('falls back to preferences when staticConfig is null', () async {
      final pageJson = jsonEncode({
        '/': {
          'menu_item': {
            'label': 'Prefs Home',
            'path': '/',
            'icon': 'home',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
        },
      });

      final prefs = await createTestPreferences();
      await prefs.setString(PageManager.storageKey, pageJson);

      final container = ProviderContainer(
        overrides: [
          staticConfigProvider.overrideWith((ref) async => null),
          preferencesProvider.overrideWith((ref) async => prefs),
          databaseProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final pageManager = await container.read(pageManagerProvider.future);
      expect(pageManager.pages.containsKey('/'), isTrue);
      expect(pageManager.pages['/']!.menuItem.label, 'Prefs Home');
    });

    test('falls back to prefs when staticConfig has null pageEditorJson',
        () async {
      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({'opcua': []}),
        keyMappingsJson: jsonEncode({'nodes': {}}),
        // No pageEditorJson
      );

      final pageJson = jsonEncode({
        '/': {
          'menu_item': {
            'label': 'Prefs Page',
            'path': '/',
            'icon': 'home',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
        },
      });

      final prefs = await createTestPreferences();
      await prefs.setString(PageManager.storageKey, pageJson);

      final container = ProviderContainer(
        overrides: [
          staticConfigProvider.overrideWith((ref) async => staticConfig),
          preferencesProvider.overrideWith((ref) async => prefs),
          databaseProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final pageManager = await container.read(pageManagerProvider.future);
      expect(pageManager.pages.containsKey('/'), isTrue);
      expect(pageManager.pages['/']!.menuItem.label, 'Prefs Page');
    });
  });
}

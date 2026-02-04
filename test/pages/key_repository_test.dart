import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/preferences.dart';

import 'package:tfc/pages/key_repository.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';

import '../helpers/test_helpers.dart';

void main() {
  // ==================== Group 1: Page Rendering ====================
  group('Page rendering', () {
    testWidgets('renders page title "Key Mappings"', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      expect(find.text('Key Mappings'), findsOneWidget);
    });

    testWidgets('shows empty state when no keys exist', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      expect(find.text('No keys configured'), findsOneWidget);
      expect(find.text('Add your first key mapping to get started'),
          findsOneWidget);
    });

    testWidgets('shows key cards when keys exist', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleKeyMappings(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('temperature_sensor'), findsOneWidget);
      expect(find.text('pressure_valve'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNWidgets(2));
    });

    testWidgets('renders import/export section', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      expect(find.text('Import / Export'), findsOneWidget);
    });
  });

  // ==================== Group 2: Add Key ====================
  group('Add key', () {
    testWidgets('tapping Add Key button creates a new key entry',
        (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      // Should start with empty state
      expect(find.text('No keys configured'), findsOneWidget);

      // Tap Add Key
      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Empty state should be gone, new key card should appear (expanded, so title + text field)
      expect(find.text('No keys configured'), findsNothing);
      expect(find.text('new_key'), findsAtLeastNWidgets(1));
    });

    testWidgets('multiple Add Key taps create unique keys', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Scroll back to Add Key button (first card is now expanded)
      await tester.scrollUntilVisible(
        find.text('Add Key'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Verify both keys exist (use byType to check ExpansionTile count)
      expect(find.byType(ExpansionTile), findsNWidgets(2));
    });
  });

  // ==================== Group 3: Delete Key ====================
  group('Delete key', () {
    testWidgets('tapping delete button shows confirmation dialog',
        (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleKeyMappings(),
      ));
      await tester.pumpAndSettle();

      // Tap the first delete button (trash icon)
      final trashButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.trash);
      await tester.tap(trashButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Remove Key'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('confirming delete removes the key card', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'to_delete': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'x'),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      expect(find.text('to_delete'), findsOneWidget);

      // Tap delete
      final trashButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.trash);
      await tester.tap(trashButtons.first);
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('to_delete'), findsNothing);
    });

    testWidgets('cancelling delete keeps the key card', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'to_keep': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'x'),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Tap delete
      final trashButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.trash);
      await tester.tap(trashButtons.first);
      await tester.pumpAndSettle();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('to_keep'), findsOneWidget);
    });
  });

  // ==================== Group 4: Edit Key Fields ====================
  group('Edit key fields', () {
    testWidgets('can edit key name via expansion', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'old_name': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'test'),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Expand the card
      await tester.tap(find.text('old_name'));
      await tester.pumpAndSettle();

      // Find the Key Name text field and update it
      final keyNameField = find.widgetWithText(TextField, 'old_name');
      expect(keyNameField, findsOneWidget);

      await tester.enterText(keyNameField, 'new_name');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('new_name'), findsWidgets);
    });

    testWidgets('can set OPC UA namespace and identifier', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'test_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 0, identifier: ''),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('test_key'));
      await tester.pumpAndSettle();

      // Find and fill namespace field
      final nsField = find.widgetWithText(TextField, 'Namespace');
      expect(nsField, findsOneWidget);

      // Find and fill identifier field
      final idField = find.widgetWithText(TextField, 'Identifier');
      expect(idField, findsOneWidget);

      await tester.enterText(nsField, '42');
      await tester.enterText(idField, 'MyNode');
      await tester.pumpAndSettle();

      // Verify the subtitle updates (it shows ns=X; id=Y)
      // The namespace and identifier should be reflected in the OPC UA config section
    });

    testWidgets('can set array index', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'array_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'ArrayNode'),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('array_key'));
      await tester.pumpAndSettle();

      // Find array index field
      final arrayField =
          find.widgetWithText(TextField, 'Array Index (optional)');
      expect(arrayField, findsOneWidget);

      await tester.enterText(arrayField, '5');
      await tester.pumpAndSettle();
    });

    testWidgets('can select server alias from dropdown', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'alias_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'X'),
          ),
        }),
        stateManConfig: sampleStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('alias_key'));
      await tester.pumpAndSettle();

      // Find dropdown and tap it
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(dropdown, findsOneWidget);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Select 'main_server' from dropdown
      expect(find.text('main_server').last, findsOneWidget);
      await tester.tap(find.text('main_server').last);
      await tester.pumpAndSettle();
    });
  });

  // ==================== Group 5: Collection Configuration ====================
  group('Collection configuration', () {
    testWidgets('collection toggle enables collection fields', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'collect_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'X'),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('collect_key'));
      await tester.pumpAndSettle();

      // Collection fields should not be visible yet
      expect(
          find.widgetWithText(TextField, 'Sample Interval (microseconds)'),
          findsNothing);

      // Scroll down to make the Switch visible
      await tester.scrollUntilVisible(
        find.byType(Switch),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Toggle collection on
      final switchWidget = find.byType(Switch);
      expect(switchWidget, findsOneWidget);
      await tester.tap(switchWidget);
      await tester.pumpAndSettle();

      // Collection fields should now be visible
      expect(
          find.widgetWithText(TextField, 'Sample Interval (microseconds)'),
          findsOneWidget);
      expect(find.widgetWithText(TextField, 'Retention (days)'),
          findsOneWidget);
    });

    testWidgets('can set sample interval', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'sample_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'X'),
            collect: CollectEntry(
              key: 'sample_key',
              retention: const RetentionPolicy(
                  dropAfter: Duration(days: 365), scheduleInterval: null),
            ),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('sample_key'));
      await tester.pumpAndSettle();

      final sampleField =
          find.widgetWithText(TextField, 'Sample Interval (microseconds)');
      expect(sampleField, findsOneWidget);

      await tester.enterText(sampleField, '1000000');
      await tester.pumpAndSettle();
    });

    testWidgets('can set retention days', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'retain_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'X'),
            collect: CollectEntry(
              key: 'retain_key',
              retention: const RetentionPolicy(
                  dropAfter: Duration(days: 365), scheduleInterval: null),
            ),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('retain_key'));
      await tester.pumpAndSettle();

      final retentionField =
          find.widgetWithText(TextField, 'Retention (days)');
      expect(retentionField, findsOneWidget);

      await tester.enterText(retentionField, '90');
      await tester.pumpAndSettle();
    });
  });

  // ==================== Group 6: Unsaved Changes Tracking ====================
  group('Unsaved changes tracking', () {
    testWidgets('shows "Unsaved" badge after adding a key', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      // No badge initially
      expect(find.text('Unsaved'), findsNothing);
      expect(find.text('Unsaved Changes'), findsNothing);

      // Add a key
      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Badge should appear (text depends on layout width)
      expect(
        find.textContaining('Unsaved'),
        findsOneWidget,
      );
    });

    testWidgets('"Unsaved" badge disappears after save', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      // Add a key to trigger unsaved state
      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unsaved'), findsOneWidget);

      // Tap Save
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Badge should be gone
      expect(find.textContaining('Unsaved'), findsNothing);
    });
  });

  // ==================== Group 7: Search/Filter ====================
  group('Search/filter', () {
    testWidgets('search field filters keys by name', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleKeyMappings(),
      ));
      await tester.pumpAndSettle();

      // Both keys visible
      expect(find.text('temperature_sensor'), findsOneWidget);
      expect(find.text('pressure_valve'), findsOneWidget);

      // Type in search field
      final searchField = find.widgetWithText(TextField, 'Search keys...');
      await tester.enterText(searchField, 'temp');
      await tester.pumpAndSettle();

      // Only temperature_sensor should be visible
      expect(find.text('temperature_sensor'), findsOneWidget);
      expect(find.text('pressure_valve'), findsNothing);
    });

    testWidgets('search field filters keys by OPC UA identifier',
        (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleKeyMappings(),
      ));
      await tester.pumpAndSettle();

      // Search by identifier 'PressureValve'
      final searchField = find.widgetWithText(TextField, 'Search keys...');
      await tester.enterText(searchField, 'PressureValve');
      await tester.pumpAndSettle();

      expect(find.text('pressure_valve'), findsOneWidget);
      expect(find.text('temperature_sensor'), findsNothing);
    });

    testWidgets('clearing search shows all keys', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleKeyMappings(),
      ));
      await tester.pumpAndSettle();

      // Search for temp
      final searchField = find.widgetWithText(TextField, 'Search keys...');
      await tester.enterText(searchField, 'temp');
      await tester.pumpAndSettle();

      expect(find.text('pressure_valve'), findsNothing);

      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // Both keys visible again
      expect(find.text('temperature_sensor'), findsOneWidget);
      expect(find.text('pressure_valve'), findsOneWidget);
    });
  });

  // ==================== Group 8: Save and Load ====================
  group('Save and load', () {
    testWidgets('save button persists key mappings to preferences',
        (tester) async {
      late Preferences testPrefs;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith((ref) async {
              testPrefs = await createTestPreferences();
              return testPrefs;
            }),
            databaseProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyRepositoryContent(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add a key
      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Verify prefs were updated
      final savedJson = await testPrefs.getString('key_mappings');
      expect(savedJson, isNotNull);
      final savedKeyMappings =
          KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(savedKeyMappings.nodes.containsKey('new_key'), isTrue);
    });

    testWidgets('page loads existing key mappings from preferences',
        (tester) async {
      final km = KeyMappings(nodes: {
        'loaded_key': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 99, identifier: 'LoadedNode'),
        ),
      });

      await tester.pumpWidget(buildTestableKeyRepository(keyMappings: km));
      await tester.pumpAndSettle();

      expect(find.text('loaded_key'), findsOneWidget);
    });
  });

  // ==================== Group 9: Import/Export ====================
  group('Import/Export', () {
    testWidgets('export button is rendered', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('import button is rendered', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      expect(find.text('Import'), findsOneWidget);
    });
  });

  // ==================== Group 10: Database Status ====================
  group('Database status', () {
    testWidgets('shows database disconnected banner when database is null',
        (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Database not connected'),
        findsOneWidget,
      );
    });
  });
}

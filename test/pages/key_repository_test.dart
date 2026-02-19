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

  // ==================== Group: Copy Key ====================
  group('Copy key', () {
    testWidgets('tapping copy button duplicates the key', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'original_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'MyNode')
              ..serverAlias = 'main_server',
          ),
        }),
        stateManConfig: sampleStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Tap the copy button
      final copyButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.copy);
      expect(copyButtons, findsOneWidget);
      await tester.tap(copyButtons.first);
      await tester.pumpAndSettle();

      // Should now have 2 cards
      expect(find.byType(ExpansionTile), findsNWidgets(2));
      expect(find.text('original_key'), findsOneWidget);
      expect(find.text('original_key_copy'), findsAtLeastNWidgets(1));
    });

    testWidgets('copied key is placed right after the original', (tester) async {
      late Preferences testPrefs;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith((ref) async {
              testPrefs = await createTestPreferences(
                keyMappings: KeyMappings(nodes: {
                  'first_key': KeyMappingEntry(
                    opcuaNode:
                        OpcUANodeConfig(namespace: 1, identifier: 'A'),
                  ),
                  'second_key': KeyMappingEntry(
                    opcuaNode:
                        OpcUANodeConfig(namespace: 2, identifier: 'B'),
                  ),
                  'third_key': KeyMappingEntry(
                    opcuaNode:
                        OpcUANodeConfig(namespace: 3, identifier: 'C'),
                  ),
                }),
              );
              return testPrefs;
            }),
            databaseProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: KeyRepositoryContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Copy the second key
      final copyButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.copy);
      // second_key is the 2nd card, so its copy button is at index 1
      await tester.tap(copyButtons.at(1));
      await tester.pumpAndSettle();

      // Save to inspect the order
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      final savedJson = await testPrefs.getString('key_mappings');
      final saved = KeyMappings.fromJson(jsonDecode(savedJson!));
      final keys = saved.nodes.keys.toList();
      expect(keys, [
        'first_key',
        'second_key',
        'second_key_copy',
        'third_key',
      ]);
    });

    testWidgets('copied key preserves OPC UA config', (tester) async {
      late Preferences testPrefs;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith((ref) async {
              testPrefs = await createTestPreferences(
                keyMappings: KeyMappings(nodes: {
                  'src_key': KeyMappingEntry(
                    opcuaNode:
                        OpcUANodeConfig(namespace: 5, identifier: 'SrcNode')
                          ..serverAlias = 'main_server',
                  ),
                }),
                stateManConfig: sampleStateManConfig(),
              );
              return testPrefs;
            }),
            databaseProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: KeyRepositoryContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Copy the key
      final copyButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.copy);
      await tester.tap(copyButtons.first);
      await tester.pumpAndSettle();

      // Save
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Verify the copy has the same OPC UA config
      final savedJson = await testPrefs.getString('key_mappings');
      final saved = KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(saved.nodes.containsKey('src_key_copy'), isTrue);
      final copy = saved.nodes['src_key_copy']!;
      expect(copy.opcuaNode?.namespace, 5);
      expect(copy.opcuaNode?.identifier, 'SrcNode');
      expect(copy.opcuaNode?.serverAlias, 'main_server');
    });

    testWidgets('renaming a copied key and saving persists the new name',
        (tester) async {
      late Preferences testPrefs;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith((ref) async {
              testPrefs = await createTestPreferences(
                keyMappings: KeyMappings(nodes: {
                  'original': KeyMappingEntry(
                    opcuaNode:
                        OpcUANodeConfig(namespace: 1, identifier: 'Node1'),
                  ),
                }),
              );
              return testPrefs;
            }),
            databaseProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: KeyRepositoryContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Copy the key (creates 'original_copy', auto-expanded)
      final copyButton = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.copy);
      await tester.tap(copyButton.first);
      await tester.pumpAndSettle();

      // Rename the copied key without pressing Enter
      final keyNameField =
          find.widgetWithText(TextField, 'original_copy');
      expect(keyNameField, findsOneWidget);
      await tester.enterText(keyNameField, 'my_renamed_copy');
      await tester.pumpAndSettle();

      // Save
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Verify the renamed key is saved, not 'original_copy'
      final savedJson = await testPrefs.getString('key_mappings');
      final saved = KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(saved.nodes.containsKey('my_renamed_copy'), isTrue,
          reason: 'Copied key should be saved with renamed name');
      expect(saved.nodes.containsKey('original_copy'), isFalse,
          reason: 'Old copy name should no longer exist');
      expect(saved.nodes.containsKey('original'), isTrue,
          reason: 'Original key should still exist');
    });

    testWidgets('copying multiple times creates unique names', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'my_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'X'),
          ),
        }),
      ));
      await tester.pumpAndSettle();

      // Copy twice — scroll back to the original's copy button each time
      for (var i = 0; i < 2; i++) {
        final copyButtons = find.byWidgetPredicate(
            (w) => w is FaIcon && w.icon == FontAwesomeIcons.copy);
        await tester.ensureVisible(copyButtons.first);
        await tester.pumpAndSettle();
        await tester.tap(copyButtons.first);
        await tester.pumpAndSettle();
      }

      // Should have 3 cards: my_key, my_key_copy, my_key_copy_1
      expect(find.byType(ExpansionTile), findsNWidgets(3));
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

    testWidgets('key name updates immediately as user types', (tester) async {
      late Preferences testPrefs;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith((ref) async {
              testPrefs = await createTestPreferences(
                keyMappings: KeyMappings(nodes: {
                  'original': KeyMappingEntry(
                    opcuaNode:
                        OpcUANodeConfig(namespace: 1, identifier: 'Node1'),
                  ),
                }),
              );
              return testPrefs;
            }),
            databaseProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: KeyRepositoryContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand the card
      await tester.tap(find.text('original'));
      await tester.pumpAndSettle();

      // Type a new key name (no Enter, no blur)
      final keyNameField = find.widgetWithText(TextField, 'original');
      await tester.enterText(keyNameField, 'renamed');
      await tester.pumpAndSettle();

      // The underlying data should already reflect the rename
      // Verify by saving without any focus changes
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      final savedJson = await testPrefs.getString('key_mappings');
      final saved = KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(saved.nodes.containsKey('renamed'), isTrue,
          reason: 'Key name should update as user types');
      expect(saved.nodes.containsKey('original'), isFalse,
          reason: 'Old key name should be gone');
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

      // Tap Save (scroll into view first since Browse button may push it off-screen)
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
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

      // Save (scroll into view first since Browse button may push it off-screen)
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Verify prefs were updated
      final savedJson = await testPrefs.getString('key_mappings');
      expect(savedJson, isNotNull);
      final savedKeyMappings =
          KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(savedKeyMappings.nodes.containsKey('new_key'), isTrue);
    });

    testWidgets('renaming key name and saving persists the new name',
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

      // Add a key (creates 'new_key', auto-expanded)
      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Change the key name without pressing Enter
      final keyNameField = find.widgetWithText(TextField, 'new_key');
      expect(keyNameField, findsOneWidget);
      await tester.enterText(keyNameField, 'my_sensor');
      await tester.pumpAndSettle();

      // Tap Save (this moves focus away from text field)
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Verify prefs contain the renamed key, not 'new_key'
      final savedJson = await testPrefs.getString('key_mappings');
      expect(savedJson, isNotNull);
      final savedKeyMappings =
          KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(savedKeyMappings.nodes.containsKey('my_sensor'), isTrue,
          reason: 'Key should be saved with renamed name "my_sensor"');
      expect(savedKeyMappings.nodes.containsKey('new_key'), isFalse,
          reason: 'Old name "new_key" should no longer exist');
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

  // ==================== Group 11: Modbus Key Mappings ====================
  group('Modbus key mappings', () {
    testWidgets('shows Modbus subtitle for Modbus keys', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleMixedKeyMappings(),
        stateManConfig: sampleMixedStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Modbus key subtitle: registerType@address (dataType) @ serverAlias
      expect(find.textContaining('holdingRegister@100'), findsOneWidget);
      expect(find.textContaining('coil@0'), findsOneWidget);
      // OPC UA key subtitle: ns=X; id=Y
      expect(find.textContaining('ns=2'), findsOneWidget);
    });

    testWidgets('protocol selector appears in expanded card', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleMixedKeyMappings(),
        stateManConfig: sampleMixedStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Expand an OPC UA key
      await tester.tap(find.text('temperature_sensor'));
      await tester.pumpAndSettle();

      // Protocol selector should be visible
      expect(find.text('OPC UA'), findsOneWidget);
      expect(find.text('Modbus TCP'), findsOneWidget);
    });

    testWidgets('switching protocol from OPC UA to Modbus shows Modbus config',
        (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'test_key': KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 0, identifier: ''),
          ),
        }),
        stateManConfig: sampleMixedStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('test_key'));
      await tester.pumpAndSettle();

      // Should show OPC UA fields initially
      expect(find.text('Namespace'), findsOneWidget);
      expect(find.text('Identifier'), findsOneWidget);

      // Tap "Modbus TCP" in the protocol selector
      await tester.tap(find.text('Modbus TCP'));
      await tester.pumpAndSettle();

      // Should now show Modbus fields
      expect(find.text('Modbus Node Configuration'), findsOneWidget);
      expect(find.text('Register Type'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Data Type'), findsOneWidget);
      // OPC UA fields should be gone
      expect(find.text('Namespace'), findsNothing);
      expect(find.text('Identifier'), findsNothing);
    });

    testWidgets('Modbus config section shows correct fields when expanded',
        (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'modbus_key': KeyMappingEntry(
            modbusNode: ModbusNodeConfig(
              registerType: ModbusRegisterType.holdingRegister,
              address: 42,
              dataType: ModbusDataType.float32,
              serverAlias: 'modbus_plc',
            ),
          ),
        }),
        stateManConfig: sampleMixedStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Expand the Modbus key
      await tester.tap(find.text('modbus_key'));
      await tester.pumpAndSettle();

      // All Modbus config fields should be present
      expect(find.text('Modbus Node Configuration'), findsOneWidget);
      expect(find.text('Server Alias'), findsOneWidget);
      expect(find.text('Register Type'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Data Type'), findsOneWidget);
      expect(find.text('Poll Group (optional)'), findsOneWidget);
    });

    testWidgets('Modbus server alias dropdown only shows Modbus servers',
        (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: KeyMappings(nodes: {
          'modbus_key': KeyMappingEntry(
            modbusNode: ModbusNodeConfig(
              registerType: ModbusRegisterType.holdingRegister,
              address: 0,
              dataType: ModbusDataType.uint16,
            ),
          ),
        }),
        stateManConfig: sampleMixedStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Expand the Modbus key
      await tester.tap(find.text('modbus_key'));
      await tester.pumpAndSettle();

      // Find the Server Alias dropdown and tap it
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Modbus server should appear, OPC UA server should not
      expect(find.text('modbus_plc').last, findsOneWidget);
      // The OPC UA-only server 'main_server' should NOT be in the dropdown
      // (but it might appear in the background, so check that only one 'main_server' exists)
      expect(find.text('main_server'), findsNothing);
    });

    testWidgets('saving Modbus key persists Modbus config', (tester) async {
      late Preferences testPrefs;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith((ref) async {
              testPrefs = await createTestPreferences(
                keyMappings: KeyMappings(nodes: {
                  'modbus_key': KeyMappingEntry(
                    modbusNode: ModbusNodeConfig(
                      registerType: ModbusRegisterType.holdingRegister,
                      address: 100,
                      dataType: ModbusDataType.float32,
                      serverAlias: 'modbus_plc',
                      pollGroup: 'fast',
                    ),
                  ),
                }),
                stateManConfig: sampleMixedStateManConfig(),
              );
              return testPrefs;
            }),
            databaseProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: KeyRepositoryContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Make a change to trigger unsaved state (add a key then save)
      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Save
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Verify Modbus config persisted
      final savedJson = await testPrefs.getString('key_mappings');
      final saved = KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(saved.nodes.containsKey('modbus_key'), isTrue);
      final entry = saved.nodes['modbus_key']!;
      expect(entry.isModbus, isTrue);
      expect(entry.modbusNode!.registerType,
          ModbusRegisterType.holdingRegister);
      expect(entry.modbusNode!.address, 100);
      expect(entry.modbusNode!.dataType, ModbusDataType.float32);
      expect(entry.modbusNode!.serverAlias, 'modbus_plc');
      expect(entry.modbusNode!.pollGroup, 'fast');
    });

    testWidgets('search filters by Modbus register type', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleMixedKeyMappings(),
        stateManConfig: sampleMixedStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // All keys visible
      expect(find.text('temperature_sensor'), findsOneWidget);
      expect(find.text('motor_speed'), findsOneWidget);
      expect(find.text('pump_running'), findsOneWidget);

      // Search by register type
      final searchField = find.widgetWithText(TextField, 'Search keys...');
      await tester.enterText(searchField, 'coil');
      await tester.pumpAndSettle();

      // Only coil key should match
      expect(find.text('pump_running'), findsOneWidget);
      expect(find.text('motor_speed'), findsNothing);
      expect(find.text('temperature_sensor'), findsNothing);
    });

    testWidgets('search filters by Modbus server alias', (tester) async {
      await tester.pumpWidget(buildTestableKeyRepository(
        keyMappings: sampleMixedKeyMappings(),
        stateManConfig: sampleMixedStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Search by modbus server alias
      final searchField = find.widgetWithText(TextField, 'Search keys...');
      await tester.enterText(searchField, 'modbus_plc');
      await tester.pumpAndSettle();

      // Both modbus keys should match
      expect(find.text('motor_speed'), findsOneWidget);
      expect(find.text('pump_running'), findsOneWidget);
      // OPC UA key should not
      expect(find.text('temperature_sensor'), findsNothing);
    });

    testWidgets('copied Modbus key preserves Modbus config', (tester) async {
      late Preferences testPrefs;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith((ref) async {
              testPrefs = await createTestPreferences(
                keyMappings: KeyMappings(nodes: {
                  'modbus_src': KeyMappingEntry(
                    modbusNode: ModbusNodeConfig(
                      registerType: ModbusRegisterType.inputRegister,
                      address: 50,
                      dataType: ModbusDataType.int16,
                      serverAlias: 'modbus_plc',
                    ),
                  ),
                }),
                stateManConfig: sampleMixedStateManConfig(),
              );
              return testPrefs;
            }),
            databaseProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: KeyRepositoryContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Copy the key
      final copyButton = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.copy);
      await tester.tap(copyButton.first);
      await tester.pumpAndSettle();

      // Save
      await tester.ensureVisible(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Key Mappings'));
      await tester.pumpAndSettle();

      // Verify the copy has the same Modbus config
      final savedJson = await testPrefs.getString('key_mappings');
      final saved = KeyMappings.fromJson(jsonDecode(savedJson!));
      expect(saved.nodes.containsKey('modbus_src_copy'), isTrue);
      final copy = saved.nodes['modbus_src_copy']!;
      expect(copy.isModbus, isTrue);
      expect(copy.modbusNode!.registerType, ModbusRegisterType.inputRegister);
      expect(copy.modbusNode!.address, 50);
      expect(copy.modbusNode!.dataType, ModbusDataType.int16);
      expect(copy.modbusNode!.serverAlias, 'modbus_plc');
    });
  });
}

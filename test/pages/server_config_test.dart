import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:tfc_dart/core/state_man.dart';

import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/pages/server_config.dart';

import '../helpers/test_helpers.dart';

/// Builds a testable widget tree containing only the ModbusServersSection.
/// Avoids BaseScaffold/Beamer dependencies by testing the section directly.
Widget buildTestableModbusSection({
  StateManConfig? stateManConfig,
}) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith((ref) => createTestPreferences(
            stateManConfig: stateManConfig,
          )),
      databaseProvider.overrideWith((ref) async => null),
      // Override stateManProvider to stay in loading state (no real connections).
      // Use a Completer that never completes — no pending timer.
      stateManProvider.overrideWith((ref) => Completer<StateMan>().future),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ModbusServersSection(),
        ),
      ),
    ),
  );
}

void main() {
  // ==================== Modbus TCP Servers Section ====================
  group('Modbus TCP Servers section', () {
    testWidgets('renders Modbus TCP Servers title', (tester) async {
      await tester.pumpWidget(buildTestableModbusSection());
      await tester.pumpAndSettle();

      expect(find.text('Modbus TCP Servers'), findsOneWidget);
    });

    testWidgets('shows empty state when no Modbus servers configured',
        (tester) async {
      await tester.pumpWidget(buildTestableModbusSection());
      await tester.pumpAndSettle();

      expect(find.text('No Modbus servers configured'), findsOneWidget);
      expect(find.text('Add your first Modbus TCP server to get started'),
          findsOneWidget);
    });

    testWidgets('Add Server button creates a new server card', (tester) async {
      await tester.pumpWidget(buildTestableModbusSection());
      await tester.pumpAndSettle();

      expect(find.text('No Modbus servers configured'), findsOneWidget);

      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();

      // Empty state should be gone, server card should appear
      expect(find.text('No Modbus servers configured'), findsNothing);
      // Default server shows host:port
      expect(find.text('localhost:502'), findsAtLeastNWidgets(1));
    });

    testWidgets('server card shows correct fields when expanded',
        (tester) async {
      await tester.pumpWidget(buildTestableModbusSection(
        stateManConfig: StateManConfig(opcua: [], modbus: [
          ModbusConfig(
            host: '10.0.0.1',
            port: 502,
            unitId: 1,
            serverAlias: 'test_modbus',
            pollGroups: [
              ModbusPollGroup(name: 'default', pollIntervalMs: 1000),
            ],
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      // Server card should be visible with the alias as title
      expect(find.text('test_modbus'), findsOneWidget);

      // Expand the card
      await tester.tap(find.text('test_modbus'));
      await tester.pumpAndSettle();

      // Should show the form fields
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Unit ID'), findsOneWidget);
      expect(find.text('Server Alias (optional)'), findsOneWidget);
    });

    testWidgets('server card shows subtitle with host:port and unit ID',
        (tester) async {
      await tester.pumpWidget(buildTestableModbusSection(
        stateManConfig: StateManConfig(opcua: [], modbus: [
          ModbusConfig(
            host: '192.168.1.10',
            port: 503,
            unitId: 5,
            serverAlias: 'my_plc',
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('192.168.1.10:503'), findsOneWidget);
      expect(find.textContaining('Unit 5'), findsOneWidget);
    });

    testWidgets('server card shows poll groups section', (tester) async {
      await tester.pumpWidget(buildTestableModbusSection(
        stateManConfig: StateManConfig(opcua: [], modbus: [
          ModbusConfig(
            host: 'localhost',
            port: 502,
            unitId: 1,
            serverAlias: 'pg_test',
            pollGroups: [
              ModbusPollGroup(name: 'default', pollIntervalMs: 1000),
              ModbusPollGroup(name: 'fast', pollIntervalMs: 100),
            ],
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      // Expand the server card
      await tester.tap(find.text('pg_test'));
      await tester.pumpAndSettle();

      // Poll groups title should be visible
      expect(find.text('Poll Groups'), findsOneWidget);
    });

    testWidgets('remove server shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestableModbusSection(
        stateManConfig: StateManConfig(opcua: [], modbus: [
          ModbusConfig(
            host: 'localhost',
            port: 502,
            serverAlias: 'to_remove',
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      // Find and tap the trash button
      final trashButton = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.trash);
      await tester.tap(trashButton.first);
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Remove Server'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('confirming remove deletes the server', (tester) async {
      await tester.pumpWidget(buildTestableModbusSection(
        stateManConfig: StateManConfig(opcua: [], modbus: [
          ModbusConfig(
            host: 'localhost',
            port: 502,
            serverAlias: 'bye_server',
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      // Tap delete
      final trashButton = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.trash);
      await tester.tap(trashButton.first);
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Server should be gone, empty state should appear
      expect(find.text('bye_server'), findsNothing);
      expect(find.text('No Modbus servers configured'), findsOneWidget);
    });

    testWidgets('connection status shows Loading when stateMan loading',
        (tester) async {
      await tester.pumpWidget(buildTestableModbusSection(
        stateManConfig: StateManConfig(opcua: [], modbus: [
          ModbusConfig(
            host: 'localhost',
            port: 502,
            serverAlias: 'status_test',
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      // The status chip should show Loading... since stateMan is in loading state
      expect(find.text('Loading...'), findsAtLeastNWidgets(1));
    });

    testWidgets('unsaved changes badge appears after adding server',
        (tester) async {
      await tester.pumpWidget(buildTestableModbusSection(
        stateManConfig: StateManConfig(opcua: [], modbus: []),
      ));
      await tester.pumpAndSettle();

      // Add a server to trigger unsaved state
      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();

      // Unsaved badge should appear
      expect(find.textContaining('Unsaved'), findsAtLeastNWidgets(1));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart' show ModbusDataType;

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/state_man.dart';

import '../helpers/test_helpers.dart';

/// Creates a [StateManConfig] with one OPC UA, one Modbus, and one M2400 server.
StateManConfig _multiProtocolConfig() {
  return StateManConfig(
    opcua: [
      OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..serverAlias = 'opcua_srv',
    ],
    modbus: [
      ModbusConfig(
        host: '192.168.1.100',
        port: 502,
        unitId: 1,
        pollGroups: [
          ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
        ],
      )..serverAlias = 'modbus_srv',
    ],
    jbtm: [
      M2400Config(host: '10.0.0.50', port: 52211)..serverAlias = 'm2400_srv',
    ],
  );
}

/// Wraps [KeyMappingEntryDialog] in a testable widget tree.
///
/// Overrides preferencesProvider with a StateManConfig containing all three
/// protocol server types. Also overrides stateManProvider and databaseProvider
/// to prevent real network connections.
Widget _buildTestableDialog({
  String? initialKey,
  KeyMappingEntry? initialEntry,
  StateManConfig? config,
  int? arraySize,
}) {
  final stateManConfig = config ?? _multiProtocolConfig();
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith(
          (ref) => createTestPreferences(stateManConfig: stateManConfig)),
      databaseProvider.overrideWith((ref) async => null),
      stateManProvider
          .overrideWith((ref) => throw StateError('No StateMan in tests')),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => KeyMappingEntryDialog(
                  initialKey: initialKey,
                  initialKeyMappingEntry: initialEntry,
                  arraySize: arraySize,
                ),
              );
              // Store result for verification
              if (result != null) {
                _lastDialogResult = result;
              }
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    ),
  );
}

/// Storage for the last dialog result (used to verify submit output).
Map<String, dynamic>? _lastDialogResult;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    _lastDialogResult = null;
  });

  // Helper to open the dialog
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open Dialog'));
    await settle(tester);
  }

  // ==================== Group 1: Server Dropdown Shows All Protocols ====================
  group('Server dropdown shows all protocols', () {
    testWidgets('shows OPC UA server with "(OPC UA)" label', (tester) async {
      await pumpAndLoad(tester, _buildTestableDialog());
      await openDialog(tester);

      // Open the server dropdown
      final serverDropdown = find.byType(DropdownButtonFormField<String>);
      expect(serverDropdown, findsAtLeastNWidgets(1));
      await tester.tap(serverDropdown.first);
      await settle(tester);

      // Verify OPC UA server is listed with protocol label
      expect(find.text('opcua_srv (OPC UA)'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows Modbus server with "(Modbus)" label', (tester) async {
      await pumpAndLoad(tester, _buildTestableDialog());
      await openDialog(tester);

      // Open the server dropdown
      final serverDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(serverDropdown.first);
      await settle(tester);

      // Verify Modbus server is listed with protocol label
      expect(find.text('modbus_srv (Modbus)'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows M2400 server with "(M2400)" label', (tester) async {
      await pumpAndLoad(tester, _buildTestableDialog());
      await openDialog(tester);

      // Open the server dropdown
      final serverDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(serverDropdown.first);
      await settle(tester);

      // Verify M2400 server is listed with protocol label
      expect(find.text('m2400_srv (M2400)'), findsAtLeastNWidgets(1));
    });
  });

  // ==================== Group 2: Protocol-Specific Fields ====================
  group('Protocol-specific fields', () {
    testWidgets(
        'selecting Modbus server shows register type, address, data type, poll group',
        (tester) async {
      await pumpAndLoad(tester, _buildTestableDialog());
      await openDialog(tester);

      // Open server dropdown and select Modbus server
      final serverDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(serverDropdown.first);
      await settle(tester);
      await tester.tap(find.text('modbus_srv (Modbus)').last);
      await settle(tester);

      // Verify Modbus-specific fields are visible
      expect(find.text('Register Type'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Data Type'), findsOneWidget);
      expect(find.text('Poll Group'), findsOneWidget);
    });

    testWidgets('selecting OPC UA server shows namespace and identifier fields',
        (tester) async {
      await pumpAndLoad(tester, _buildTestableDialog());
      await openDialog(tester);

      // Open server dropdown and select OPC UA server
      final serverDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(serverDropdown.first);
      await settle(tester);
      await tester.tap(find.text('opcua_srv (OPC UA)').last);
      await settle(tester);

      // Verify OPC UA-specific fields are visible
      expect(find.text('Namespace'), findsOneWidget);
      expect(find.text('Identifier'), findsOneWidget);
    });
  });

  // ==================== Group 3: Submit Behavior ====================
  group('Submit behavior', () {
    testWidgets(
        'submit with Modbus server returns KeyMappingEntry with modbusNode',
        (tester) async {
      await pumpAndLoad(tester, _buildTestableDialog(initialKey: 'test_key'));
      await openDialog(tester);

      // Enter key name
      final keyField = find.widgetWithText(TextFormField, 'Key');
      await tester.enterText(keyField, 'modbus_key');
      await settle(tester);

      // Select Modbus server
      final serverDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(serverDropdown.first);
      await settle(tester);
      await tester.tap(find.text('modbus_srv (Modbus)').last);
      await settle(tester);

      // Fill address field
      final addressField = find.widgetWithText(TextField, 'Address');
      await tester.enterText(addressField, '100');
      await settle(tester);

      // Tap OK
      await tester.tap(find.text('OK'));
      await settle(tester);

      // Verify the dialog returned a result with modbusNode
      expect(_lastDialogResult, isNotNull);
      final entry = _lastDialogResult!['entry'] as KeyMappingEntry;
      expect(entry.modbusNode, isNotNull);
      expect(entry.modbusNode!.serverAlias, 'modbus_srv');
      expect(entry.modbusNode!.address, 100);
      expect(entry.modbusNode!.registerType, ModbusRegisterType.holdingRegister);
      expect(entry.opcuaNode, isNull);
    });

    testWidgets(
        'submit with OPC UA server returns KeyMappingEntry with opcuaNode',
        (tester) async {
      await pumpAndLoad(tester, _buildTestableDialog(initialKey: 'test_key'));
      await openDialog(tester);

      // Enter key name
      final keyField = find.widgetWithText(TextFormField, 'Key');
      await tester.enterText(keyField, 'opcua_key');
      await settle(tester);

      // Select OPC UA server
      final serverDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(serverDropdown.first);
      await settle(tester);
      await tester.tap(find.text('opcua_srv (OPC UA)').last);
      await settle(tester);

      // Fill namespace and identifier
      final nsField = find.widgetWithText(TextField, 'Namespace');
      await tester.enterText(nsField, '2');
      await settle(tester);

      final idField = find.widgetWithText(TextField, 'Identifier');
      await tester.enterText(idField, 'Temperature');
      await settle(tester);

      // Tap OK
      await tester.tap(find.text('OK'));
      await settle(tester);

      // Verify the dialog returned a result with opcuaNode
      expect(_lastDialogResult, isNotNull);
      final entry = _lastDialogResult!['entry'] as KeyMappingEntry;
      expect(entry.opcuaNode, isNotNull);
      expect(entry.opcuaNode!.namespace, 2);
      expect(entry.opcuaNode!.identifier, 'Temperature');
      expect(entry.opcuaNode!.serverAlias, 'opcua_srv');
      expect(entry.modbusNode, isNull);
    });
  });

  // ==================== Group 4: Editing Existing Entry ====================
  group('Editing existing entry', () {
    testWidgets(
        'opening with existing Modbus entry pre-selects Modbus server and populates fields',
        (tester) async {
      final existingEntry = KeyMappingEntry(
        modbusNode: ModbusNodeConfig(
          serverAlias: 'modbus_srv',
          registerType: ModbusRegisterType.inputRegister,
          address: 42,
          dataType: ModbusDataType.float32,
          pollGroup: 'default',
        ),
      );

      await pumpAndLoad(tester, _buildTestableDialog(
        initialKey: 'existing_modbus',
        initialEntry: existingEntry,
      ));
      await openDialog(tester);

      // The server dropdown should show the Modbus server pre-selected
      // The address field should be pre-populated with "42"
      expect(find.text('42'), findsOneWidget);

      // The Modbus-specific fields should be visible (not OPC UA fields)
      expect(find.text('Register Type'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
    });
  });
}

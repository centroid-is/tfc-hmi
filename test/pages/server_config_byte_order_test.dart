import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:modbus_client/modbus_client.dart' show ModbusEndianness;
import 'package:tfc_dart/core/state_man.dart' show StateManConfig, ModbusConfig, ModbusPollGroupConfig;

import '../helpers/test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('Byte order dropdown', () {
    testWidgets('renders with all 4 options (ABCD, CDAB, BADC, DCBA)',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig(stateManConfig: sampleModbusStateManConfig(),));

      // Scroll to and expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('plc_1'));
      await tester.pumpAndSettle();

      // Scroll to the Byte Order dropdown
      await tester.scrollUntilVisible(
        find.text('Byte Order'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Find and tap the dropdown to open it
      final dropdown = find.byType(DropdownButtonFormField<ModbusEndianness>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // All 4 options should be visible in the dropdown menu
      expect(find.text('ABCD (Big-Endian)'), findsWidgets);
      expect(find.text('CDAB (Word Swap)'), findsWidgets);
      expect(find.text('BADC (Byte Swap)'), findsWidgets);
      expect(find.text('DCBA (Little-Endian)'), findsWidgets);
    });

    testWidgets('selecting a byte order option updates the config',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig(stateManConfig: sampleModbusStateManConfig(),));

      // Expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('plc_1'));
      await tester.pumpAndSettle();

      // Scroll to dropdown
      await tester.scrollUntilVisible(
        find.text('Byte Order'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Open dropdown
      final dropdown = find.byType(DropdownButtonFormField<ModbusEndianness>);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Select CDAB (Word Swap)
      await tester.tap(find.text('CDAB (Word Swap)').last);
      await tester.pumpAndSettle();

      // The dropdown should now show CDAB selected
      // The selected item text should be visible in the dropdown field
      expect(find.text('CDAB (Word Swap)'), findsOneWidget);
    });

    testWidgets('ABCD (Big-Endian) is the default selection',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig(stateManConfig: sampleModbusStateManConfig(),));

      // Expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('plc_1'));
      await tester.pumpAndSettle();

      // Scroll to dropdown
      await tester.scrollUntilVisible(
        find.text('Byte Order'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // The default selection should be ABCD
      expect(find.text('ABCD (Big-Endian)'), findsOneWidget);
    });

    testWidgets('pre-configured CDAB endianness shows CDAB in dropdown',
        (tester) async {
      // Create a config with CDAB endianness pre-set
      final config = StateManConfig(
        opcua: [],
        modbus: [
          ModbusConfig(
            host: '192.168.1.100',
            port: 502,
            unitId: 1,
            endianness: ModbusEndianness.CDAB,
            pollGroups: [
              ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
            ],
          )..serverAlias = 'plc_1',
        ],
      );
      await pumpAndLoad(tester, buildTestableServerConfig(stateManConfig: config,));

      // Expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('plc_1'));
      await tester.pumpAndSettle();

      // Scroll to Byte Order dropdown
      await tester.scrollUntilVisible(
        find.text('Byte Order'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // The dropdown should show CDAB (Word Swap) as the selected value
      expect(find.text('CDAB (Word Swap)'), findsOneWidget);
      // ABCD should NOT be visible (it's not selected)
      expect(find.text('ABCD (Big-Endian)'), findsNothing);
    });

    testWidgets('info icon is present next to Byte Order label',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig(stateManConfig: sampleModbusStateManConfig(),));

      // Expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('plc_1'));
      await tester.pumpAndSettle();

      // Scroll to Byte Order area
      await tester.scrollUntilVisible(
        find.text('Byte Order'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Info icon should be present
      expect(find.byIcon(Icons.info_outline), findsAtLeastNWidgets(1));
    });
  });
}

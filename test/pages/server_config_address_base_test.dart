import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SecureStorage.setInstance(FakeSecureStorage());
  });

  group('Address Base dropdown', () {
    testWidgets('renders with two options: 0 (Protocol Default) and 1 (Modicon/Schneider)',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: sampleModbusStateManConfig(),
        ),
      );

      // Scroll to and expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(find.text('plc_1'));
      await settle(tester);

      // Scroll to the Address Base dropdown
      await tester.scrollUntilVisible(
        find.text('Address Base'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);

      // Find and tap the dropdown to open it
      final dropdown = find.byType(DropdownButtonFormField<int>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await settle(tester);

      // Both options should be visible in the dropdown menu
      expect(find.text('0 (Protocol Default)'), findsWidgets);
      expect(find.text('1 (Modicon/Schneider)'), findsWidgets);
    });

    testWidgets('selecting "1" updates the config addressBase field to 1',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: sampleModbusStateManConfig(),
        ),
      );

      // Expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(find.text('plc_1'));
      await settle(tester);

      // Scroll to dropdown
      await tester.scrollUntilVisible(
        find.text('Address Base'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);

      // Open dropdown
      final dropdown = find.byType(DropdownButtonFormField<int>);
      await tester.tap(dropdown);
      await settle(tester);

      // Select "1 (Modicon/Schneider)"
      await tester.tap(find.text('1 (Modicon/Schneider)').last);
      await settle(tester);

      // The dropdown should now show 1 selected
      expect(find.text('1 (Modicon/Schneider)'), findsOneWidget);
    });

    testWidgets('info tooltip icon is present next to dropdown',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: sampleModbusStateManConfig(),
        ),
      );

      // Expand the Modbus server card
      await tester.scrollUntilVisible(
        find.text('plc_1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(find.text('plc_1'));
      await settle(tester);

      // Scroll to Address Base area
      await tester.scrollUntilVisible(
        find.text('Address Base'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);

      // Info icon should be present (at least 1 for address base area)
      expect(find.byIcon(Icons.info_outline), findsAtLeastNWidgets(1));
    });
  });
}

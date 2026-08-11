import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../helpers/test_helpers.dart';

/// Finds the enable/disable checkboxes rendered in every server card header.
///
/// Cards are collapsed in these tests, so the only checkboxes on screen are
/// the header ones — the UMAS checkbox lives inside the expanded Modbus body.
Finder _toggles() => find.byType(Checkbox);

bool _isTicked(WidgetTester tester, Finder toggle) =>
    tester.widget<Checkbox>(toggle).value ?? false;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SecureStorage.setInstance(FakeSecureStorage());
  });

  group('server enable/disable toggle', () {
    testWidgets('each configured server card shows an enable checkbox',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: StateManConfig(
            opcua: [OpcUAConfig()..serverAlias = 'plc1'],
            jbtm: [M2400Config(host: '10.0.0.1')..serverAlias = 'w1'],
            modbus: [ModbusConfig(host: '10.0.0.2', serverAlias: 'm1')],
          ),
        ),
      );

      expect(_toggles(), findsNWidgets(3));
    });

    testWidgets('an enabled server shows a ticked box and no Disabled chip',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: StateManConfig(
            opcua: [OpcUAConfig()..serverAlias = 'plc1'],
          ),
        ),
      );

      expect(_isTicked(tester, _toggles().first), isTrue);
      expect(find.text('Disabled'), findsNothing);
    });

    testWidgets('a disabled server renders unticked with a Disabled chip',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: StateManConfig(
            opcua: [
              OpcUAConfig()
                ..serverAlias = 'plc1'
                ..enabled = false
            ],
          ),
        ),
      );

      expect(_isTicked(tester, _toggles().first), isFalse);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('unticking the box disables the server and marks it unsaved',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: StateManConfig(
            opcua: [OpcUAConfig()..serverAlias = 'plc1'],
          ),
        ),
      );

      expect(find.text('Disabled'), findsNothing);

      await tester.tap(_toggles().first);
      await settle(tester);

      expect(find.text('Disabled'), findsOneWidget);
      expect(_isTicked(tester, _toggles().first), isFalse);
      // Toggling is a config change like any other, so the section must
      // offer to save it.
      expect(find.text('Save Configuration'), findsAtLeastNWidgets(1));
    });

    testWidgets('ticking the box again re-enables the server',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: StateManConfig(
            opcua: [
              OpcUAConfig()
                ..serverAlias = 'plc1'
                ..enabled = false
            ],
          ),
        ),
      );

      await tester.tap(_toggles().first);
      await settle(tester);

      expect(find.text('Disabled'), findsNothing);
      expect(_isTicked(tester, _toggles().first), isTrue);
    });

    testWidgets('editing other fields does not clear the disabled flag',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(
          stateManConfig: StateManConfig(
            opcua: [
              OpcUAConfig()
                ..serverAlias = 'plc1'
                ..enabled = false
            ],
          ),
        ),
      );

      // Expand the card and retype the endpoint — the rebuilt OpcUAConfig
      // must carry `enabled: false` through.
      await tester.tap(find.text('plc1'));
      await settle(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'opc.tcp://localhost:4840').first,
          'opc.tcp://10.0.0.9:4840');
      await settle(tester);

      expect(find.text('Disabled'), findsOneWidget);
    });
  });
}

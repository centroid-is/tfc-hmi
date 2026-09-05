import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/core/gateway_config.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../helpers/test_helpers.dart';

/// A station already switched to the gateway, as its preferences row.
Future<PreferencesApi> _gatewayStation({
  String url = 'wss://10.50.10.11:9443',
  String? caCertPath = '/pki/ca.pem',
}) async {
  final prefs = InMemoryPreferences();
  await writeGatewayConfig(
    prefs,
    GatewayConfig(
      mode: TransportMode.gateway,
      url: url,
      caCertPath: caCertPath,
    ),
  );
  return prefs;
}

/// Opens the transport card, which is collapsed on a direct-mode station.
Future<void> _expandTransport(WidgetTester tester) async {
  await tester.tap(find.text('Transport'));
  await settle(tester);
}

/// The four direct-mode sections, by the headings they render.
void _expectDirectSections(Matcher matcher) {
  expect(find.text('OPC-UA Servers'), matcher);
  expect(find.text('JBTM M2400 Servers'), matcher);
  expect(find.text('Modbus TCP Servers'), matcher);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SecureStorage.setInstance(FakeSecureStorage());
  });

  group('transport mode switch', () {
    testWidgets('a station that has never been configured is direct, and the '
        'four sections are exactly as they were', (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig());

      expect(find.text('Transport'), findsOneWidget);
      // Collapsed, so the page below it is where it always was.
      expect(find.byType(SegmentedButton<TransportMode>), findsNothing);
      expect(find.text('Direct to PLCs'), findsOneWidget,
          reason: 'the collapsed subtitle names the mode without opening it');

      await _expandTransport(tester);
      expect(
        tester
            .widget<SegmentedButton<TransportMode>>(
                find.byType(SegmentedButton<TransportMode>))
            .selected,
        {TransportMode.direct},
      );
      _expectDirectSections(findsOneWidget);
      // No gateway fields until gateway is chosen — the card is a switch, not
      // a fifth section.
      expect(find.text('Gateway address'), findsNothing);
    });

    testWidgets('choosing the gateway reveals the three things a dial needs',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig());
      await _expandTransport(tester);

      await tester.tap(find.text('Relay gateway'));
      await settle(tester);

      expect(find.text('Gateway address'), findsOneWidget);
      expect(find.text('Plant CA certificate (PEM path)'), findsOneWidget);
      expect(find.text('Station credential file (optional)'), findsOneWidget);
    });

    // Restart-to-apply: the running panel is on the saved transport, so moving
    // a radio button must not make the page claim the switch already happened.
    testWidgets('the four sections stay while the change is unsaved',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig());
      await _expandTransport(tester);
      await tester.tap(find.text('Relay gateway'));
      await settle(tester);

      _expectDirectSections(findsOneWidget);
    });

    testWidgets('a saved gateway station hides the four sections and says why',
        (tester) async {
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(localPreferences: await _gatewayStation()),
      );

      _expectDirectSections(findsNothing);
      expect(find.text('Database Configuration'), findsNothing);
      expect(
        find.textContaining('opens no connections of its own'),
        findsOneWidget,
      );
    });
  });

  group('refusing a configuration that cannot be dialled', () {
    testWidgets('wss with no CA root is refused, and save stays disabled',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig());
      await _expandTransport(tester);
      await tester.tap(find.text('Relay gateway'));
      await settle(tester);

      await tester.enterText(
          find.byType(TextField).first, 'wss://10.50.10.11:9443');
      await settle(tester);

      expect(find.textContaining('CA root'), findsOneWidget);
      // Not "All Changes Saved": there are changes, and the operator can see
      // them. The button says it will not take them yet.
      expect(find.text('Cannot save yet'), findsOneWidget);
      final save = tester.widget<ElevatedButton>(find
          .ancestor(
              of: find.text('Cannot save yet'),
              matching: find.byType(ElevatedButton))
          .first);
      expect(save.onPressed, isNull,
          reason: 'a panel that cannot dial must not be saveable: the refusal '
              'belongs here, not in a start-up error at the next boot');
    });

    testWidgets('adding the CA root clears the refusal and enables save',
        (tester) async {
      await pumpAndLoad(tester, buildTestableServerConfig());
      await _expandTransport(tester);
      await tester.tap(find.text('Relay gateway'));
      await settle(tester);

      await tester.enterText(
          find.byType(TextField).first, 'wss://10.50.10.11:9443');
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(1), '/pki/ca.pem');
      await settle(tester);

      expect(find.textContaining('CA root'), findsNothing);
      final save = tester.widget<ElevatedButton>(find
          .ancestor(
              of: find.text('Save Configuration'),
              matching: find.byType(ElevatedButton))
          .first);
      expect(save.onPressed, isNotNull);
    });
  });

  group('saving', () {
    testWidgets('writes to the device-local store, and says restart',
        (tester) async {
      final local = InMemoryPreferences();
      await pumpAndLoad(
          tester, buildTestableServerConfig(localPreferences: local));
      await _expandTransport(tester);

      await tester.tap(find.text('Relay gateway'));
      await settle(tester);
      await tester.enterText(
          find.byType(TextField).first, 'wss://10.50.10.11:9443');
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(1), '/pki/ca.pem');
      await settle(tester);

      await tester.tap(find.text('Save Configuration'));
      await settle(tester);

      final saved = await readGatewayConfig(local);
      expect(saved.mode, TransportMode.gateway);
      expect(saved.url, 'wss://10.50.10.11:9443');
      expect(saved.caCertPath, '/pki/ca.pem');

      expect(find.textContaining('Restart the HMI'), findsOneWidget);
    });

    // The one property that separates this from every other section on the
    // page: a gateway URL must not travel to the plant's other stations.
    testWidgets('never writes to the shared, DB-backed store', (tester) async {
      final local = InMemoryPreferences();
      final shared = await createTestPreferences(
          stateManConfig: StateManConfig(opcua: const []));
      await pumpAndLoad(
        tester,
        buildTestableServerConfig(localPreferences: local),
      );
      await _expandTransport(tester);

      await tester.tap(find.text('Relay gateway'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'ws://bench:9443');
      await settle(tester);
      await tester.tap(find.text('Save Configuration'));
      await settle(tester);

      expect(await local.getString(GatewayConfig.prefsKey), isNotNull);
      expect(await shared.getString(GatewayConfig.prefsKey), isNull);
    });
  });
}

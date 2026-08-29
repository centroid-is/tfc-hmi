import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/pages/server_config.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../helpers/test_helpers.dart';

Finder _intervalField() =>
    find.widgetWithText(TextField, 'Update interval (ms)');
Finder _lifetimeField() =>
    find.widgetWithText(TextField, 'Secure channel lifetime (s)');

String _textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

/// Reads the config back out of preferences, as saved.
Future<StateManConfig> _persistedConfig(WidgetTester tester) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(ServerConfigBody)));
  final prefs = await container.read(preferencesProvider.future);
  return StateManConfig.fromPrefs(prefs);
}

StateManConfig _oneServer({int? intervalMs, int? lifetimeMs}) => StateManConfig(
      opcua: [
        OpcUAConfig()
          ..endpoint = 'opc.tcp://10.104.28.11:4840'
          ..serverAlias = 'st101'
          ..publishingIntervalMs = intervalMs ?? 100
          ..secureChannelLifetimeMs = lifetimeMs ?? 60000,
      ],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SecureStorage.setInstance(FakeSecureStorage());
  });

  Future<void> pumpExpandedCard(WidgetTester tester,
      {StateManConfig? config}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpAndLoad(
      tester,
      buildTestableServerConfig(stateManConfig: config ?? _oneServer()),
    );
    await tester.tap(find.text('st101'));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Save Configuration').first, 200,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.text('Save Configuration').first);
    await settle(tester);
  }

  group('OPC-UA timing fields', () {
    testWidgets('an expanded card shows both timing fields', (tester) async {
      await pumpExpandedCard(tester);

      expect(_intervalField(), findsOneWidget);
      expect(_lifetimeField(), findsOneWidget);
    });

    testWidgets('the fields are seeded from the stored config', (tester) async {
      await pumpExpandedCard(
          tester, config: _oneServer(intervalMs: 250, lifetimeMs: 300000));

      expect(_textOf(tester, _intervalField()), '250');
      // Lifetime is entered in seconds, not the milliseconds it is stored in.
      expect(_textOf(tester, _lifetimeField()), '300');
    });

    testWidgets('a whole-second lifetime shows without a decimal point',
        (tester) async {
      await pumpExpandedCard(tester);

      expect(_textOf(tester, _lifetimeField()), '60');
    });

    testWidgets('a typed interval reaches the saved config', (tester) async {
      await pumpExpandedCard(tester);

      await tester.enterText(_intervalField(), '500');
      await settle(tester);
      await save(tester);

      expect((await _persistedConfig(tester)).opcua.single.publishingIntervalMs,
          500);
    });

    testWidgets('a typed lifetime is saved back in milliseconds',
        (tester) async {
      await pumpExpandedCard(tester);

      await tester.enterText(_lifetimeField(), '120');
      await settle(tester);
      await save(tester);

      expect(
          (await _persistedConfig(tester)).opcua.single.secureChannelLifetimeMs,
          120000);
    });

    testWidgets('a fractional lifetime rounds to milliseconds',
        (tester) async {
      await pumpExpandedCard(tester);

      await tester.enterText(_lifetimeField(), '90.5');
      await settle(tester);
      await save(tester);

      expect(
          (await _persistedConfig(tester)).opcua.single.secureChannelLifetimeMs,
          90500);
    });

    testWidgets('an out-of-range interval is clamped, not stored raw',
        (tester) async {
      await pumpExpandedCard(tester);

      // Well past the heartbeat staleness window — accepted as typed it
      // would make a healthy server report itself unhealthy.
      await tester.enterText(_intervalField(), '600000');
      await settle(tester);
      await save(tester);

      expect((await _persistedConfig(tester)).opcua.single.publishingIntervalMs,
          OpcUAConfig.publishingIntervalMaxMs);
    });

    testWidgets('a zero interval is clamped up to the minimum', (tester) async {
      await pumpExpandedCard(tester);

      await tester.enterText(_intervalField(), '0');
      await settle(tester);
      await save(tester);

      expect((await _persistedConfig(tester)).opcua.single.publishingIntervalMs,
          OpcUAConfig.publishingIntervalMinMs);
    });

    testWidgets('clearing a field keeps the stored value, not zero',
        (tester) async {
      // Mid-typing the box is empty for a frame. Treating that as a number
      // would drop the interval to 0 and the lifetime to nothing.
      await pumpExpandedCard(
          tester, config: _oneServer(intervalMs: 250, lifetimeMs: 300000));

      await tester.enterText(_intervalField(), '');
      await tester.enterText(_lifetimeField(), '');
      await settle(tester);
      // Empty boxes are not themselves a change, so nothing offers to save.
      // Touch another field to force the rebuilt config through with the
      // timing boxes still blank — the shape of the half-typed edit.
      await tester.enterText(
          find.widgetWithText(TextField, 'Endpoint URL'), 'opc.tcp://x:4840');
      await settle(tester);
      await save(tester);

      final saved = (await _persistedConfig(tester)).opcua.single;
      expect(saved.publishingIntervalMs, 250);
      expect(saved.secureChannelLifetimeMs, 300000);
    });

    testWidgets('editing the endpoint does not reset the timing values',
        (tester) async {
      await pumpExpandedCard(
          tester, config: _oneServer(intervalMs: 250, lifetimeMs: 300000));

      await tester.enterText(
          find.widgetWithText(TextField, 'Endpoint URL'), 'opc.tcp://x:4840');
      await settle(tester);
      await save(tester);

      final saved = (await _persistedConfig(tester)).opcua.single;
      expect(saved.endpoint, 'opc.tcp://x:4840');
      expect(saved.publishingIntervalMs, 250);
      expect(saved.secureChannelLifetimeMs, 300000);
    });

    testWidgets('changing a timing value counts as an unsaved change',
        (tester) async {
      await pumpExpandedCard(tester);

      await tester.enterText(_intervalField(), '500');
      await settle(tester);

      expect(find.text('Save Configuration'), findsAtLeastNWidgets(1));
    });
  });
}

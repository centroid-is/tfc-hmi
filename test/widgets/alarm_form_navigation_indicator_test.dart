import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/alarm.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

/// The alarm editor's switch for the navigation-bar pulse: it has to survive
/// the trip out of the form, because everything downstream reads it off the
/// saved [AlarmConfig].
void main() {
  const toggle = ValueKey('alarm-form-navigation-indicator');

  AlarmConfig configFx({bool navigationIndicator = false, String? key}) =>
      AlarmConfig(
        uid: 'a1',
        key: key,
        title: 'Freezer over temperature',
        description: 'desc',
        rules: [
          AlarmRule(
            level: AlarmLevel.error,
            expression: ExpressionConfig(value: Expression(formula: 'x')),
            acknowledgeRequired: false,
          ),
        ],
        navigationIndicator: navigationIndicator,
      );

  Future<AlarmConfig> submitAfter(
    WidgetTester tester,
    AlarmConfig initial,
    Future<void> Function(WidgetTester) act,
  ) async {
    AlarmConfig? submitted;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: AlarmForm(
            initialConfig: initial,
            editable: true,
            onSubmit: (c) => submitted = c,
          ),
        ),
      ),
    ));
    await act(tester);
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pump();
    return submitted!;
  }

  testWidgets('the switch is off for an alarm that has never had it on',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: AlarmForm(initialConfig: configFx())),
      ),
    ));

    expect(tester.widget<SwitchListTile>(find.byKey(toggle)).value, isFalse,
        reason: 'The navigation bar is opt-in per alarm.');
  });

  testWidgets('the switch reflects an alarm that already has it on',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: AlarmForm(initialConfig: configFx(navigationIndicator: true)),
        ),
      ),
    ));

    expect(tester.widget<SwitchListTile>(find.byKey(toggle)).value, isTrue);
  });

  testWidgets('turning it on reaches the submitted config', (tester) async {
    final submitted = await submitAfter(tester, configFx(), (t) async {
      await t.ensureVisible(find.byKey(toggle));
      await t.tap(find.byKey(toggle));
      await t.pump();
    });

    expect(submitted.navigationIndicator, isTrue);
  });

  testWidgets('turning it off reaches the submitted config', (tester) async {
    final submitted = await submitAfter(
      tester,
      configFx(navigationIndicator: true),
      (t) async {
        await t.ensureVisible(find.byKey(toggle));
        await t.tap(find.byKey(toggle));
        await t.pump();
      },
    );

    expect(submitted.navigationIndicator, isFalse);
  });

  testWidgets('editing an unrelated field leaves the setting alone',
      (tester) async {
    final submitted = await submitAfter(
      tester,
      configFx(navigationIndicator: true, key: 'ST101.CN01.TT01'),
      (t) async {
        await t.enterText(
            find.byKey(const ValueKey('alarm-form-title')), 'New title');
        await t.pump();
      },
    );

    expect(submitted.title, 'New title');
    expect(submitted.navigationIndicator, isTrue);
    expect(submitted.key, 'ST101.CN01.TT01',
        reason: 'The form must not drop fields it does not show.');
  });

  testWidgets('a read-only form cannot be toggled', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: AlarmForm(initialConfig: configFx())),
      ),
    ));

    expect(tester.widget<SwitchListTile>(find.byKey(toggle)).onChanged, isNull);
  });

  test('the setting survives a save/load round trip', () {
    // Alarm configuration is persisted as the `alarm_man_config` preference
    // JSON, so encode/decode — not toJson alone — is the actual storage path:
    // AlarmConfig is not `explicitToJson`, so its rules stay AlarmRule objects
    // until jsonEncode walks them.
    final restored = AlarmConfig.fromJson(
        jsonDecode(jsonEncode(configFx(navigationIndicator: true).toJson())));
    expect(restored.navigationIndicator, isTrue);

    expect(AlarmConfig.from(restored).navigationIndicator, isTrue,
        reason: 'AlarmConfig.from is how the editor copies a template.');
  });

  test('alarms saved before the setting existed load as off', () {
    final legacy = {
      'uid': 'a1',
      'title': 'Freezer over temperature',
      'description': 'desc',
      'rules': <dynamic>[],
    };

    expect(AlarmConfig.fromJson(legacy).navigationIndicator, isFalse);
  });
}

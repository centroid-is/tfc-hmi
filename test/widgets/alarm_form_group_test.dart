import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/alarm.dart';
import 'package:tfc/widgets/alarm.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

AlarmRule rule() => AlarmRule(
      level: AlarmLevel.error,
      expression: ExpressionConfig(value: Expression(formula: 'a > 1')),
      acknowledgeRequired: false,
    );

AlarmConfig config({
  List<String> group = const [],
  bool bindToGroup = false,
}) =>
    AlarmConfig(
      uid: 'uid-1',
      title: 'Film reel empty',
      description: 'The upper film reel ran out',
      rules: [rule()],
      group: group,
      bindToGroup: bindToGroup,
    );

/// Pumps [AlarmForm] with the alarm manager left pending, so the group
/// suggestions are simply empty — this exercises the field, not the provider
/// chain behind the suggestion list.
Future<AlarmConfig?> pumpForm(
  WidgetTester tester, {
  AlarmConfig? initial,
  bool editable = true,
}) async {
  AlarmConfig? submitted;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        alarmManProvider.overrideWith((ref) => Completer<AlarmMan>().future),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AlarmForm(
            initialConfig: initial,
            editable: editable,
            submitText: 'Save',
            onSubmit: (c) => submitted = c,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return submitted;
}

/// The form scrolls, so Save is below the fold — tapping it blind misses.
Future<void> saveForm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pump();
}

void main() {
  group('parseAlarmGroup', () {
    test('splits on the separator and trims', () {
      expect(parseAlarmGroup('Line 3 / Multivac'), ['Line 3', 'Multivac']);
      expect(parseAlarmGroup('Line 3/Multivac'), ['Line 3', 'Multivac']);
    });

    test('drops blank segments so a stray slash cannot make a nameless group',
        () {
      expect(parseAlarmGroup('Line 3 // Multivac'), ['Line 3', 'Multivac']);
      expect(parseAlarmGroup('Line 3 / '), ['Line 3']);
      expect(parseAlarmGroup('  '), isEmpty);
      expect(parseAlarmGroup(''), isEmpty);
    });

    test('round trips through formatAlarmGroup', () {
      const group = ['Line 3', 'Multivac'];
      expect(parseAlarmGroup(formatAlarmGroup(group)), group);
    });

    test('formats an empty group as an empty string', () {
      expect(formatAlarmGroup(const []), '');
    });
  });

  group('AlarmForm group field', () {
    testWidgets('shows the group an alarm already has', (tester) async {
      await pumpForm(tester,
          initial: config(group: ['Line 3', 'Multivac']));

      final field = tester.widget<TextFormField>(
          find.byKey(const ValueKey('alarm-form-group')));
      expect(field.controller?.text, 'Line 3 / Multivac');
      expect(find.text('In Line 3 › Multivac'), findsOneWidget);
    });

    testWidgets('says so when an alarm is ungrouped', (tester) async {
      await pumpForm(tester, initial: config());
      expect(find.text('Ungrouped — sits at the top of the alarm tree'),
          findsOneWidget);
    });

    testWidgets('renaming an alarm keeps its group — the regression',
        (tester) async {
      // Submitting rebuilds the AlarmConfig from the form, so a field the
      // form does not carry is a field the save silently drops -- which is
      // how an alarm ends up back at the root after a title edit.
      AlarmConfig? submitted;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alarmManProvider
                .overrideWith((ref) => Completer<AlarmMan>().future),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AlarmForm(
                initialConfig:
                    config(group: ['Line 3', 'Multivac'], bindToGroup: true),
                editable: true,
                submitText: 'Save',
                onSubmit: (c) => submitted = c,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
          find.byKey(const ValueKey('alarm-form-title')), 'Renamed');
      await tester.pump();
      await saveForm(tester);

      expect(submitted, isNotNull);
      expect(submitted!.title, 'Renamed');
      expect(submitted!.group, ['Line 3', 'Multivac']);
      expect(submitted!.bindToGroup, isTrue);
    });

    testWidgets('typing a group files the alarm under it', (tester) async {
      AlarmConfig? submitted;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alarmManProvider
                .overrideWith((ref) => Completer<AlarmMan>().future),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AlarmForm(
                initialConfig: config(),
                editable: true,
                submitText: 'Save',
                onSubmit: (c) => submitted = c,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byKey(const ValueKey('alarm-form-group')),
          'Line 3 / Multivac');
      await tester.pump();
      await saveForm(tester);

      expect(submitted!.group, ['Line 3', 'Multivac']);
    });

    testWidgets('the bind switch is disabled while the alarm is ungrouped',
        (tester) async {
      await pumpForm(tester, initial: config());
      final tile = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('alarm-form-bind-to-group')));
      expect(tile.onChanged, isNull);
    });

    testWidgets('the bind switch is enabled once a group is set',
        (tester) async {
      await pumpForm(tester, initial: config(group: ['Line 3']));
      final tile = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('alarm-form-bind-to-group')));
      expect(tile.onChanged, isNotNull);
      expect(tile.value, isFalse);
    });

    testWidgets('clearing the group also clears the bind flag', (tester) async {
      // Otherwise the flag stays set but means nothing, and a later regroup
      // would silently make the alarm the group again.
      AlarmConfig? submitted;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alarmManProvider
                .overrideWith((ref) => Completer<AlarmMan>().future),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AlarmForm(
                initialConfig: config(group: ['Line 3'], bindToGroup: true),
                editable: true,
                submitText: 'Save',
                onSubmit: (c) => submitted = c,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
          find.byKey(const ValueKey('alarm-form-group')), '');
      await tester.pump();

      final tile = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('alarm-form-bind-to-group')));
      expect(tile.value, isFalse);

      await saveForm(tester);
      expect(submitted!.group, isEmpty);
      expect(submitted!.bindToGroup, isFalse);
    });

    testWidgets('a read-only form does not let the group be edited',
        (tester) async {
      await pumpForm(tester,
          initial: config(group: ['Line 3']), editable: false);
      final field = tester.widget<TextFormField>(
          find.byKey(const ValueKey('alarm-form-group')));
      expect(field.enabled, isFalse);
    });
  });
}

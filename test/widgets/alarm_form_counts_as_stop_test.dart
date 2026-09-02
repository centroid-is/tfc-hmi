/// The "Counts as a stop" switch on the alarm form: on by default, and the
/// one place an advisory alarm is excluded from the stop analysis — the flag
/// is a property of the alarm definition, not of any screen showing it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/alarm.dart';
import 'package:tfc/widgets/alarm.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

const _switchKey = ValueKey('alarm-form-counts-as-stop');

AlarmConfig _config({bool countsAsStop = true}) => AlarmConfig(
      uid: 'uid-1',
      title: 'Door open',
      description: 'The cabinet door is open',
      countsAsStop: countsAsStop,
      rules: [
        AlarmRule(
          level: AlarmLevel.warning,
          expression: ExpressionConfig(value: Expression(formula: 'a > 1')),
          acknowledgeRequired: false,
        ),
      ],
    );

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pump();
}

SwitchListTile _tile(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byKey(_switchKey));

void main() {
  testWidgets('an untouched form saves the default: it IS a stop',
      (tester) async {
    AlarmConfig? submitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmManProvider.overrideWith((ref) => Completer<AlarmMan>().future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AlarmForm(
              initialConfig: _config(),
              editable: true,
              submitText: 'Save',
              onSubmit: (c) => submitted = c,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_tile(tester).value, isTrue, reason: 'downtime is the default');

    await _save(tester);
    expect(submitted, isNotNull);
    expect(submitted!.countsAsStop, isTrue);
  });

  testWidgets('turning the switch off survives the save', (tester) async {
    AlarmConfig? submitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmManProvider.overrideWith((ref) => Completer<AlarmMan>().future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AlarmForm(
              initialConfig: _config(),
              editable: true,
              submitText: 'Save',
              onSubmit: (c) => submitted = c,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(_switchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();
    expect(_tile(tester).value, isFalse);

    await _save(tester);
    expect(submitted, isNotNull);
    expect(submitted!.countsAsStop, isFalse);
  });

  testWidgets('an alarm saved as not-a-stop opens that way', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmManProvider.overrideWith((ref) => Completer<AlarmMan>().future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AlarmForm(
              initialConfig: _config(countsAsStop: false),
              editable: true,
              submitText: 'Save',
              onSubmit: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_tile(tester).value, isFalse);
  });

  testWidgets('read-only form shows the switch but takes no taps',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmManProvider.overrideWith((ref) => Completer<AlarmMan>().future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AlarmForm(
              initialConfig: _config(countsAsStop: false),
              editable: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_tile(tester).onChanged, isNull);
  });
}

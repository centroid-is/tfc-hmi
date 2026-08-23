import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/panes/setpoint_field.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Column(children: [child, const TextField(key: Key('other'))]),
        ),
      );

  testWidgets('Enter commits once, and the focus loss it causes does not '
      'commit again', (tester) async {
    final written = <double>[];
    await tester.pumpWidget(host(SetpointField<double>(
      fieldKey: 'f',
      label: 'Auto',
      text: '50.00',
      current: 50.0,
      parse: double.tryParse,
      onSubmitted: written.add,
    )));
    await tester.enterText(find.byKey(const Key('f')), '45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // Moving focus elsewhere afterwards must not resend 45.
    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    expect(written, [45.0]);
  });

  testWidgets('tapping away commits a changed value -- no Enter needed',
      (tester) async {
    final written = <double>[];
    await tester.pumpWidget(host(SetpointField<double>(
      fieldKey: 'f',
      label: 'Auto',
      text: '50.00',
      current: 50.0,
      parse: double.tryParse,
      onSubmitted: written.add,
    )));
    await tester.enterText(find.byKey(const Key('f')), '47');
    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    expect(written, [47.0], reason: 'focus-out is a commit on a touch HMI');
  });

  testWidgets('tapping away with the value unchanged writes nothing',
      (tester) async {
    final written = <double>[];
    await tester.pumpWidget(host(SetpointField<double>(
      fieldKey: 'f',
      label: 'Auto',
      text: '50.00',
      current: 50.0,
      parse: double.tryParse,
      onSubmitted: written.add,
    )));
    await tester.tap(find.byKey(const Key('f')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    expect(written, isEmpty, reason: 'tabbing through must not rewrite');
  });

  testWidgets('follows a new PLC value when the operator is not editing, '
      'and leaves their text alone when they are', (tester) async {
    Widget build(String text, double current) => host(SetpointField<double>(
          fieldKey: 'f',
          label: 'Auto',
          text: text,
          current: current,
          parse: double.tryParse,
          onSubmitted: (_) {},
        ));
    await tester.pumpWidget(build('50.00', 50.0));
    await tester.pumpWidget(build('55.00', 55.0));
    await tester.pump();
    expect(find.text('55.00'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('f')), '4');
    await tester.pumpWidget(build('60.00', 60.0));
    await tester.pump();
    expect(find.text('4'), findsOneWidget,
        reason: 'the PLC echo must not clobber what is being typed');
  });
}

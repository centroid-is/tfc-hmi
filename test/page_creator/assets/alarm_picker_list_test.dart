import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/alarm_visibility.dart';
import 'package:tfc_dart/core/alarm.dart';

AlarmConfig _alarmFx(String uid, String title, [String description = '']) {
  return AlarmConfig(
      uid: uid, title: title, description: description, rules: []);
}

void main() {
  // Config-pane conditions: 312px of content width inside a scroll view.
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 312, child: child),
        ),
      ),
    );
  }

  final alarms = [
    _alarmFx('u1', 'Conveyor stalled', 'CN04 drive fault'),
    _alarmFx('u2', 'Freezer door open'),
    _alarmFx('u3', 'Temperature high', 'Blast chiller over limit'),
    _alarmFx('u4', 'Weigher offline', 'M2200 not responding'),
  ];

  testWidgets('shows a search bar and every alarm sorted by title',
      (tester) async {
    await tester.pumpWidget(wrap(AlarmPickerList(
      alarms: alarms,
      selectedUids: [],
      onSelectionChanged: () {},
    )));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(4));

    final titles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, [
      'Conveyor stalled',
      'Freezer door open',
      'Temperature high',
      'Weigher offline',
    ]);
  });

  testWidgets('typing filters the list fuzzily over title and description',
      (tester) async {
    await tester.pumpWidget(wrap(AlarmPickerList(
      alarms: alarms,
      selectedUids: [],
      onSelectionChanged: () {},
    )));

    // Fuzzy: "tmp" matches "Temperature high" without being a substring.
    await tester.enterText(find.byType(TextField), 'tmp');
    await tester.pump();
    expect(find.text('Temperature high'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);

    // Description text is searched too.
    await tester.enterText(find.byType(TextField), 'M2200');
    await tester.pump();
    expect(find.text('Weigher offline'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('No alarms match the search.'), findsOneWidget);
  });

  testWidgets('a selection made under a filter survives clearing the filter',
      (tester) async {
    final selected = <String>[];
    var notified = 0;
    await tester.pumpWidget(wrap(AlarmPickerList(
      alarms: alarms,
      selectedUids: selected,
      onSelectionChanged: () => notified++,
    )));

    await tester.enterText(find.byType(TextField), 'freezer');
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    expect(selected, ['u2']);
    expect(notified, 1);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    final freezerTile = tester.widget<CheckboxListTile>(find.ancestor(
      of: find.text('Freezer door open'),
      matching: find.byType(CheckboxListTile),
    ));
    expect(freezerTile.value, isTrue);
    expect(find.text('1 of 4 selected'), findsOneWidget);
  });

  testWidgets('unchecking removes the uid; Clear empties the selection',
      (tester) async {
    final selected = <String>['u1', 'u3'];
    var notified = 0;
    await tester.pumpWidget(wrap(AlarmPickerList(
      alarms: alarms,
      selectedUids: selected,
      onSelectionChanged: () => notified++,
    )));

    await tester.tap(find.ancestor(
      of: find.text('Conveyor stalled'),
      matching: find.byType(CheckboxListTile),
    ));
    await tester.pump();
    expect(selected, ['u3']);
    expect(notified, 1);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(selected, isEmpty);
    expect(notified, 2);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('200 alarms stay inside the height cap instead of bloating '
      'the config pane', (tester) async {
    final many = [
      for (var i = 0; i < 200; i++)
        _alarmFx('uid$i', 'Alarm ${i.toString().padLeft(3, '0')}'),
    ];
    await tester.pumpWidget(wrap(AlarmPickerList(
      alarms: many,
      selectedUids: [],
      onSelectionChanged: () {},
    )));

    final listHeight = tester.getSize(find.byType(ListView)).height;
    expect(listHeight, lessThanOrEqualTo(280),
        reason: 'The alarm list must scroll internally, not stretch the '
            'config pane to 200 rows.');

    await tester.enterText(find.byType(TextField), 'Alarm 042');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });
}

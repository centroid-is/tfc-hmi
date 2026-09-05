/// The multi-select property pane: what it shows for a selection that
/// disagrees, and what typing into it does to the assets behind it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/analog_box.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/schneider.dart';
import 'package:tfc/widgets/bulk_property_editor.dart';

const String _fontSize = 'SchneiderATV320Config.labelFontSize';

SchneiderATV320Config _drive({double? fontSize, String? label}) =>
    SchneiderATV320Config(label: label, labelFontSize: fontSize);

/// Counts of the two callbacks the editor owes the page editor, so a test can
/// assert that a bulk edit opens exactly one undo entry.
class _Calls {
  int before = 0;
  int changed = 0;
}

Future<_Calls> _pump(
  WidgetTester tester,
  List<Asset> selection, {
  Listenable? revision,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 700,
          child: BulkPropertyEditor(
            selection: selection,
            revision: revision,
            onBeforeChange: () => calls.before++,
            onChanged: () => calls.changed++,
          ),
        ),
      ),
    ),
  );
  return calls;
}

/// The text field on the row for the property [id]. Addressed by id rather
/// than by label so a mixed row — which shows no value — is still findable.
Finder _fieldFor(String id) => find.descendant(
      of: find.byKey(bulkControlKey(id)),
      matching: find.byType(TextField),
    );

TextField _field(WidgetTester tester, String id) =>
    tester.widget<TextField>(_fieldFor(id));

/// Types [value] into the row for [id] and commits it with Enter.
Future<void> _enter(WidgetTester tester, String id, String value) async {
  await tester.enterText(_fieldFor(id), value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the shared value when the selection agrees',
      (tester) async {
    final drives = [_drive(fontSize: 12), _drive(fontSize: 12)];
    await _pump(tester, drives);

    expect(_fieldFor(_fontSize), findsOneWidget);
    expect(_field(tester, _fontSize).controller?.text, '12');
    expect(find.text('Multiple values'), findsNothing);
  });

  testWidgets('reports a disagreement instead of picking a winner',
      (tester) async {
    await _pump(tester, [_drive(fontSize: 12), _drive(fontSize: 18)]);

    final field = _field(tester, _fontSize);
    expect(field.controller?.text, isEmpty);
    expect(field.decoration?.hintText, 'Multiple values');
    // Neither value leaks into the box as though it were the group's.
    expect(find.text('12'), findsNothing);
    expect(find.text('18'), findsNothing);
  });

  testWidgets('typing a value makes a non-common setting common',
      (tester) async {
    final wide = _drive(fontSize: 18);
    final narrow = _drive(fontSize: 9);
    final calls = await _pump(tester, [wide, narrow]);

    await _enter(tester, _fontSize, '14');

    expect(wide.labelFontSize, 14);
    expect(narrow.labelFontSize, 14);
    // One edit, so one undo entry — not one per asset it touched.
    expect(calls.before, 1);
    expect(calls.changed, 1);
    // And the row now reads as agreed.
    expect(_field(tester, _fontSize).decoration?.hintText, isNull);
  });

  testWidgets('Enter then clicking away is one edit, not two',
      (tester) async {
    final drive = _drive(fontSize: 12);
    final calls = await _pump(tester, [drive]);

    // A field commits on Enter and again on losing focus. Both carrying the
    // same value must not push two undo entries — the operator's first
    // Ctrl+Z would appear to do nothing.
    await _enter(tester, _fontSize, '14');
    expect(calls.before, 1);

    await tester.tap(_fieldFor('width'));
    await tester.pumpAndSettle();

    expect(calls.before, 1);
    expect(drive.labelFontSize, 14);
  });

  testWidgets('focusing a field and leaving it alone is not an edit',
      (tester) async {
    final drive = _drive(fontSize: 12);
    final calls = await _pump(tester, [drive]);

    await tester.tap(_fieldFor(_fontSize));
    await tester.pumpAndSettle();
    await tester.tap(_fieldFor('width'));
    await tester.pumpAndSettle();

    expect(calls.before, 0);
    expect(calls.changed, 0);
  });

  testWidgets('a disagreeing row writes even where one asset already agrees',
      (tester) async {
    // The value typed matches what `already` holds, so a naive "has this
    // changed?" guard would skip the write and leave `other` behind.
    final already = _drive(fontSize: 14);
    final other = _drive(fontSize: 9);
    final calls = await _pump(tester, [already, other]);

    await _enter(tester, _fontSize, '14');

    expect(other.labelFontSize, 14);
    expect(calls.before, 1);
  });

  testWidgets('the width row writes a canvas percentage to every asset',
      (tester) async {
    final drives = [_drive(), _drive(), _drive()];
    await _pump(tester, drives);

    await _enter(tester, 'width', '8');

    for (final drive in drives) {
      expect(drive.size.width, closeTo(0.08, 1e-9));
    }
  });

  testWidgets('unparseable input changes nothing and is discarded',
      (tester) async {
    final drive = _drive()..size = const RelativeSize(width: .3, height: .3);
    final calls = await _pump(tester, [drive]);

    await _enter(tester, 'width', 'wide please');

    expect(drive.size.width, closeTo(0.3, 1e-9));
    expect(calls.before, 0);
    // The box goes back to the asset's value rather than sitting there
    // looking like it took.
    expect(_field(tester, 'width').controller?.text, '30');
  });

  testWidgets('a mixed checkbox resolves to on, then toggles normally',
      (tester) async {
    final boxes = [
      AnalogBoxConfig(analogKey: 'a', vertical: true),
      AnalogBoxConfig(analogKey: 'b', vertical: false),
    ];
    final calls = await _pump(tester, boxes);

    const vertical = 'AnalogBoxConfig.vertical';
    // Disagreeing: the tristate null, shown beside the words.
    expect(tester.widget<Checkbox>(find.byKey(bulkControlKey(vertical))).value,
        isNull);
    expect(find.text('Multiple values'), findsWidgets);

    // A tap on a disagreeing box resolves the whole selection to on rather
    // than to whichever value happened to come first. The analog box has
    // enough rows to push this one past the bottom of the pane.
    await tester.ensureVisible(find.byKey(bulkControlKey(vertical)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(bulkControlKey(vertical)));
    await tester.pumpAndSettle();
    expect(boxes.every((box) => box.vertical), isTrue);
    expect(calls.before, 1);

    // From there it is an ordinary checkbox.
    await tester.tap(find.byKey(bulkControlKey(vertical)));
    await tester.pumpAndSettle();
    expect(boxes.every((box) => !box.vertical), isTrue);
    expect(calls.before, 2);
  });

  testWidgets('a mixed dropdown shows no value and writes to all',
      (tester) async {
    final leds = [
      LEDConfig(key: 'a')..ledType = LEDType.circle,
      LEDConfig(key: 'b')..ledType = LEDType.square,
    ];
    final calls = await _pump(tester, leds);

    const shape = 'LEDConfig.ledType';
    // Mixed: the hint shows, and neither shape is presented as the group's.
    expect(
      find.descendant(
        of: find.byKey(bulkControlKey(shape)),
        matching: find.text('Multiple values'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(bulkControlKey(shape)));
    await tester.pumpAndSettle();
    // The open menu holds every option, not just the two in the selection —
    // a selection can be moved onto a value none of its assets held.
    expect(find.text('Circle'), findsWidgets);
    await tester.tap(find.text('Circle').last);
    await tester.pumpAndSettle();

    expect(leds.every((led) => led.ledType == LEDType.circle), isTrue);
    expect(calls.before, 1);
  });

  testWidgets('a mixed selection is reduced to the shared rows',
      (tester) async {
    await _pump(tester, [_drive(), LEDConfig(key: 'a')]);

    expect(find.text('Geometry'.toUpperCase()), findsOneWidget);
    expect(find.text('Label'.toUpperCase()), findsOneWidget);
    // Both devices' own sections are gone, in both directions.
    expect(find.text('Schneider ATV320'.toUpperCase()), findsNothing);
    expect(find.text('LED'.toUpperCase()), findsNothing);
  });

  testWidgets('a single asset gets the same rows, none of them mixed',
      (tester) async {
    await _pump(tester, [_drive(fontSize: 12)]);

    expect(find.text('Multiple values'), findsNothing);
    expect(_fieldFor(_fontSize), findsOneWidget);
  });

  testWidgets('an empty selection says so rather than rendering blank',
      (tester) async {
    await _pump(tester, []);

    expect(find.text('Nothing selected.'), findsOneWidget);
  });

  testWidgets('a canvas change under the pane refreshes the rows',
      (tester) async {
    final drive = _drive()..size = const RelativeSize(width: .1, height: .1);
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    await _pump(tester, [drive], revision: revision);

    expect(_field(tester, 'width').controller?.text, '10');

    // What an arrow-key nudge or a drag on the canvas does: the asset moves
    // without the pane being involved.
    drive.size = const RelativeSize(width: .25, height: .1);
    revision.value++;
    await tester.pump();

    expect(_field(tester, 'width').controller?.text, '25');
  });

  testWidgets('a refresh mid-edit does not snatch the caret back',
      (tester) async {
    final drive = _drive()..size = const RelativeSize(width: .1, height: .1);
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    await _pump(tester, [drive], revision: revision);

    await tester.tap(_fieldFor('width'));
    await tester.pump();
    await tester.enterText(_fieldFor('width'), '4');

    revision.value++;
    await tester.pump();

    // Still what was typed, not the asset's 10.
    expect(_field(tester, 'width').controller?.text, '4');
  });
}

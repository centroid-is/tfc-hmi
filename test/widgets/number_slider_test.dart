/// `NumberSlider` is the page editor's slider with the number beside it
/// editable.
///
/// The read-out used to be a `Text`, which made dragging the only way in —
/// fine for "a bit wider", useless for "exactly 45°" on a track a hundred-odd
/// pixels long. The parts worth pinning down are the ones that make a typed
/// number and a dragged one agree:
///
///   - typing lands on a slider stop, so the handle is never left between two;
///   - out-of-range input is clamped rather than accepted or dropped, and the
///     field shows what was actually taken;
///   - the display unit round-trips, so a setting stored 0..1 and shown as a
///     percentage reads back the way it was typed;
///   - the field follows the slider, but not while it is being typed into.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/number_slider.dart';

void main() {
  group('snapToDivisions', () {
    test('clamps into range', () {
      expect(snapToDivisions(value: -5, min: 0, max: 10, divisions: 10), 0);
      expect(snapToDivisions(value: 99, min: 0, max: 10, divisions: 10), 10);
    });

    test('rounds onto the nearest stop', () {
      // Stops every 5.
      expect(snapToDivisions(value: 37, min: 0, max: 100, divisions: 20), 35);
      expect(snapToDivisions(value: 38, min: 0, max: 100, divisions: 20), 40);
    });

    test('leaves a continuous slider alone apart from clamping', () {
      expect(snapToDivisions(value: 3.7, min: 0, max: 10), 3.7);
      expect(snapToDivisions(value: 3.7, min: 0, max: 10, divisions: 0), 3.7);
    });

    test('handles a range that starts below zero', () {
      // -180..180 in 72 steps is every 5 degrees.
      expect(
          snapToDivisions(value: -43, min: -180, max: 180, divisions: 72), -45);
    });

    test('a degenerate range cannot divide by zero', () {
      expect(snapToDivisions(value: 5, min: 2, max: 2, divisions: 10), 2);
    });
  });

  group('parseTypedNumber', () {
    test('reads a plain number', () {
      expect(parseTypedNumber('42'), 42);
      expect(parseTypedNumber('3.5'), 3.5);
      expect(parseTypedNumber('-12'), -12);
    });

    test('reads a comma as a decimal point', () {
      // What an Icelandic or German keyboard produces.
      expect(parseTypedNumber('3,5'), 3.5);
    });

    test('ignores a unit typed back over the top of the value', () {
      expect(parseTypedNumber('45°'), 45);
      expect(parseTypedNumber('80 %'), 80);
      expect(parseTypedNumber('2.0px'), 2.0);
    });

    test('returns null when there is no number to use', () {
      expect(parseTypedNumber(''), isNull);
      expect(parseTypedNumber('   '), isNull);
      expect(parseTypedNumber('%'), isNull);
      // A lone minus is what a half-typed negative looks like.
      expect(parseTypedNumber('-'), isNull);
    });
  });

  group('the widget', () {
    /// Pumps a NumberSlider that writes back into itself, the way a config
    /// editor uses it, and reports what it last emitted.
    Future<List<double>> pump(
      WidgetTester tester, {
      double initial = 0.5,
      double min = 0.0,
      double max = 1.0,
      int? divisions = 100,
      double displayScale = 100,
      int decimals = 0,
      String suffix = '%',
    }) async {
      final emitted = <double>[];
      var value = initial;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NumberSlider(
              label: 'Position:',
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              displayScale: displayScale,
              decimals: decimals,
              suffix: suffix,
              onChanged: (v) {
                emitted.add(v);
                setState(() => value = v);
              },
            ),
          ),
        ),
      ));
      return emitted;
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    /// Types [text] into the field and commits it with Enter.
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the value in the display unit', (tester) async {
      await pump(tester, initial: 0.5);
      expect(fieldText(tester), '50', reason: '0.5 shown as a percentage');
    });

    testWidgets('a typed number reaches the callback in the stored unit',
        (tester) async {
      final emitted = await pump(tester, initial: 0.5);

      await type(tester, '80');

      expect(emitted, [closeTo(0.8, 1e-9)]);
      expect(fieldText(tester), '80');
    });

    testWidgets('a typed number is clamped, and the field says so',
        (tester) async {
      final emitted = await pump(tester, initial: 0.5);

      await type(tester, '500');

      expect(emitted.single, 1.0);
      expect(fieldText(tester), '100',
          reason: 'the field should show what was actually taken');
    });

    testWidgets('a typed number lands on a slider stop', (tester) async {
      // 0..10 in 2 steps: stops at 0, 5, 10 only.
      final emitted = await pump(
        tester,
        initial: 0,
        min: 0,
        max: 10,
        divisions: 2,
        displayScale: 1,
        suffix: '',
      );

      await type(tester, '4');

      expect(emitted.single, 5, reason: 'snapped up to the nearest stop');
      expect(fieldText(tester), '5');
    });

    testWidgets('nonsense restores the previous value rather than zeroing it',
        (tester) async {
      final emitted = await pump(tester, initial: 0.5);

      await type(tester, '');

      expect(emitted, isEmpty, reason: 'nothing usable was typed');
      expect(fieldText(tester), '50');
    });

    testWidgets('re-typing the same number emits nothing', (tester) async {
      // Otherwise tabbing through a form would push a no-op onto the editor's
      // undo history for every field passed over.
      final emitted = await pump(tester, initial: 0.5);

      await type(tester, '50');

      expect(emitted, isEmpty);
    });

    testWidgets('the field follows the slider', (tester) async {
      final emitted = await pump(tester, initial: 0.5);

      // Drag the handle to the right-hand end.
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(emitted, isNotEmpty);
      expect(fieldText(tester), '100');
    });

    testWidgets('leaving the field commits what is in it', (tester) async {
      // Typing a value and clicking back onto the canvas must not drop it.
      final emitted = await pump(tester, initial: 0.5);

      await tester.enterText(find.byType(TextField), '25');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(emitted, [closeTo(0.25, 1e-9)]);
    });

    testWidgets('decimals survive the round trip', (tester) async {
      final emitted = await pump(
        tester,
        initial: 2.0,
        min: 1.0,
        max: 10.0,
        divisions: 18,
        displayScale: 1,
        decimals: 1,
        suffix: 'px',
      );

      await type(tester, '7.5');

      expect(emitted.single, closeTo(7.5, 1e-9));
      expect(fieldText(tester), '7.5');
    });

    testWidgets('a negative range accepts a negative number', (tester) async {
      final emitted = await pump(
        tester,
        initial: 0,
        min: -180,
        max: 180,
        divisions: 72,
        displayScale: 1,
        suffix: '°',
      );

      await type(tester, '-45');

      expect(emitted.single, -45);
    });
  });
}

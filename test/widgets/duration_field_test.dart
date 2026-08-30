import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/duration_field.dart';

/// [DurationField] exists so nobody has to count zeros. These cover the two
/// halves of that: reading a stored millisecond figure back in the unit a
/// person would have said it in, and typing one in without the zeros.

Finder _field() => find.byType(TextField);
Finder _unit() => find.byType(DropdownButton<DurationUnit>);

String _text(WidgetTester tester) =>
    tester.widget<TextField>(_field()).controller!.text;

DurationUnit _unitValue(WidgetTester tester) =>
    tester.widget<DropdownButton<DurationUnit>>(_unit()).value!;

void main() {
  group('formatDuration', () {
    test('picks the largest unit that divides evenly', () {
      expect(formatDuration(const Duration(milliseconds: 600000)), '10 min');
      expect(formatDuration(const Duration(milliseconds: 5000)), '5 s');
      expect(formatDuration(const Duration(hours: 24)), '1 d');
      expect(formatDuration(const Duration(microseconds: 500)), '500 µs');
    });

    test('falls back to the smallest allowed unit rather than rounding', () {
      // 90.5 s is not whole minutes; showing "2 min" would be a lie.
      expect(
        formatDuration(const Duration(milliseconds: 90500),
            units: [DurationUnit.seconds, DurationUnit.minutes]),
        '90.5 s',
      );
    });

    test('honours a restricted unit list', () {
      // Minutes are not on offer, so ten minutes reads in seconds.
      expect(
        formatDuration(const Duration(milliseconds: 600000),
            units: [DurationUnit.milliseconds, DurationUnit.seconds]),
        '600 s',
      );
    });

    test('drops a trailing .0', () {
      expect(formatDuration(const Duration(milliseconds: 2000)), '2 s');
    });
  });

  group('DurationField', () {
    Duration? emitted;

    Future<void> pump(
      WidgetTester tester, {
      required Duration value,
      Duration min = const Duration(milliseconds: 10),
      Duration max = const Duration(hours: 24),
      List<DurationUnit> units = DurationUnit.values,
    }) async {
      emitted = null;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DurationField(
            value: value,
            min: min,
            max: max,
            units: units,
            labelText: 'Interval',
            onChanged: (v) => emitted = v,
          ),
        ),
      ));
    }

    Future<void> pickUnit(WidgetTester tester, String label) async {
      await tester.tap(_unit());
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('seeds the number and the unit from the value',
        (tester) async {
      await pump(tester, value: const Duration(milliseconds: 600000));

      expect(_text(tester), '10');
      expect(_unitValue(tester), DurationUnit.minutes);
    });

    testWidgets('typing emits the number scaled by the unit', (tester) async {
      await pump(tester, value: const Duration(minutes: 10));

      await tester.enterText(_field(), '3');
      await tester.pump();

      expect(emitted, const Duration(minutes: 3));
    });

    testWidgets('an empty box emits nothing', (tester) async {
      // Half-typed input must not commit: the caller keeps its last value.
      await pump(tester, value: const Duration(minutes: 10));

      await tester.enterText(_field(), '');
      await tester.pump();

      expect(emitted, isNull);
    });

    testWidgets('a comma is read as a decimal point', (tester) async {
      // What an Icelandic or German keyboard produces.
      await pump(tester, value: const Duration(seconds: 10));

      await tester.enterText(_field(), '1,5');
      await tester.pump();

      expect(emitted, const Duration(milliseconds: 1500));
    });

    testWidgets('a typed value above the max is clamped', (tester) async {
      await pump(tester,
          value: const Duration(milliseconds: 100),
          max: const Duration(milliseconds: 5000),
          units: [DurationUnit.milliseconds]);

      await tester.enterText(_field(), '999999');
      await tester.pump();

      expect(emitted, const Duration(milliseconds: 5000));
    });

    testWidgets('a typed value below the min is clamped', (tester) async {
      await pump(tester,
          value: const Duration(milliseconds: 100),
          min: const Duration(milliseconds: 10),
          units: [DurationUnit.milliseconds]);

      await tester.enterText(_field(), '0');
      await tester.pump();

      expect(emitted, const Duration(milliseconds: 10));
    });

    testWidgets('changing the unit keeps the number, not the duration',
        (tester) async {
      await pump(tester, value: const Duration(minutes: 10));

      await pickUnit(tester, 's');

      expect(_text(tester), '10');
      expect(emitted, const Duration(seconds: 10));
    });

    testWidgets('a unit change that overshoots clamps and rewrites the box',
        (tester) async {
      await pump(tester,
          value: const Duration(milliseconds: 100),
          max: const Duration(milliseconds: 5000),
          units: [DurationUnit.milliseconds, DurationUnit.seconds]);

      // 100 ms is in range; 100 s is not.
      await pickUnit(tester, 's');

      expect(emitted, const Duration(milliseconds: 5000));
      // Leaving "100" on screen would claim a value the caller never got.
      expect(_text(tester), '5');
    });

    testWidgets('the helper line states the accepted range in its units',
        (tester) async {
      await pump(tester,
          value: const Duration(milliseconds: 100),
          min: const Duration(milliseconds: 10),
          max: const Duration(milliseconds: 5000),
          units: [DurationUnit.milliseconds, DurationUnit.seconds]);

      expect(find.text('10 ms–5 s'), findsOneWidget);
    });

    testWidgets('a new value from the parent re-seeds the box',
        (tester) async {
      await pump(tester, value: const Duration(minutes: 10));
      expect(_text(tester), '10');

      // An import, or the card rebuilt around a different server.
      await pump(tester, value: const Duration(seconds: 30));

      expect(_text(tester), '30');
      expect(_unitValue(tester), DurationUnit.seconds);
    });
  });

  group('DurationField nullable', () {
    testWidgets('a null value renders an empty box with the hint',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DurationField(
            value: null,
            min: Duration.zero,
            max: const Duration(hours: 1),
            units: const [DurationUnit.milliseconds, DurationUnit.seconds],
            labelText: 'Close time',
            hintText: 'Same as open time',
            onChanged: (_) {},
            onCleared: () {},
          ),
        ),
      ));

      expect(_text(tester), isEmpty);
      expect(find.text('Same as open time'), findsOneWidget);
      // No value to derive a unit from, so the first (smallest) is offered.
      expect(_unitValue(tester), DurationUnit.milliseconds);
    });

    testWidgets('emptying the box reports cleared exactly when opted in',
        (tester) async {
      var cleared = 0;
      Duration? emitted;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DurationField(
            value: const Duration(seconds: 2),
            min: Duration.zero,
            max: const Duration(hours: 1),
            units: const [DurationUnit.milliseconds, DurationUnit.seconds],
            labelText: 'Close time',
            onChanged: (v) => emitted = v,
            onCleared: () => cleared++,
          ),
        ),
      ));

      await tester.enterText(_field(), '');
      await tester.pump();

      expect(cleared, 1);
      expect(emitted, isNull);
    });
  });

  group('DurationField dense', () {
    testWidgets('a dense field drops the range helper but still clamps',
        (tester) async {
      Duration? emitted;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DurationField(
            value: const Duration(seconds: 1),
            min: const Duration(milliseconds: 50),
            max: const Duration(minutes: 10),
            units: const [DurationUnit.milliseconds, DurationUnit.seconds],
            labelText: 'Interval',
            isDense: true,
            onChanged: (v) => emitted = v,
          ),
        ),
      ));

      expect(find.text('50 ms–10 min'), findsNothing);

      await tester.enterText(_field(), '999999');
      await tester.pump();
      expect(emitted, const Duration(minutes: 10));
    });
  });
}

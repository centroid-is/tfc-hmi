import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/theme.dart';
import 'package:tfc/widgets/alarm_pulse.dart';
import 'package:tfc/widgets/nav_alarm_badge.dart';
import 'package:tfc_dart/core/alarm.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(extensions: [AlarmColors.light]),
        home: Scaffold(body: Center(child: child)),
      );

  Finder pulsePaint() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is AlarmPulsePainter);

  AlarmPulsePainter painter(WidgetTester tester) =>
      (tester.widget<CustomPaint>(pulsePaint()).painter as AlarmPulsePainter);

  testWidgets('a quiet entry is the icon and nothing else', (tester) async {
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(level: null, child: Icon(Icons.ac_unit)),
    ));

    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    expect(pulsePaint(), findsNothing);
    expect(
        find.descendant(
            of: find.byType(NavAlarmBadge), matching: find.byType(Stack)),
        findsNothing,
        reason: 'A quiet badge must not add layout of its own.');
  });

  testWidgets('an alarming entry badges the icon with the pulse',
      (tester) async {
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(
          level: AlarmLevel.error, child: Icon(Icons.ac_unit)),
    ));

    expect(find.byIcon(Icons.ac_unit), findsOneWidget,
        reason: 'The badge decorates the icon, it does not replace it.');
    expect(pulsePaint(), findsOneWidget);
  });

  testWidgets('the badge takes the alarm system colour for its level',
      (tester) async {
    for (final level in AlarmLevel.values) {
      await tester.pumpWidget(wrap(
        NavAlarmBadge(level: level, child: const Icon(Icons.ac_unit)),
      ));

      final expected = switch (level) {
        AlarmLevel.info => AlarmColors.light.info,
        AlarmLevel.warning => AlarmColors.light.warning,
        AlarmLevel.error => AlarmColors.light.error,
      };
      expect(painter(tester).color, expected,
          reason: '$level must match every other alarm surface.');
    }
  });

  testWidgets('the rings animate while alarming', (tester) async {
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(
          level: AlarmLevel.warning, child: Icon(Icons.ac_unit)),
    ));

    final first = painter(tester).progress;
    await tester.pump(NavAlarmBadge.period ~/ 4);
    expect(painter(tester).progress, isNot(first));

    // Leave the repeating controller stopped or the test ends with a pending
    // timer.
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(level: null, child: Icon(Icons.ac_unit)),
    ));
  });

  testWidgets('going quiet stops the ticker rather than animating unseen',
      (tester) async {
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(
          level: AlarmLevel.warning, child: Icon(Icons.ac_unit)),
    ));
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(level: null, child: Icon(Icons.ac_unit)),
    ));

    // A still-repeating controller would leave a pending timer and fail the
    // test here; an HMI idles most of a shift and must not schedule frames for
    // a navigation bar with nothing to report.
    expect(pulsePaint(), findsNothing);
  });

  testWidgets('a frozen progress renders a fixed frame with no ticker',
      (tester) async {
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(
        level: AlarmLevel.error,
        progressOverride: 0.4,
        child: Icon(Icons.ac_unit),
      ),
    ));

    expect(painter(tester).progress, 0.4);
    await tester.pump(NavAlarmBadge.period);
    expect(painter(tester).progress, 0.4);
  });

  testWidgets('the badge overhangs the icon instead of sitting on the glyph',
      (tester) async {
    await tester.pumpWidget(wrap(
      const NavAlarmBadge(
          level: AlarmLevel.error, child: Icon(Icons.ac_unit, size: 24)),
    ));

    final icon = tester.getRect(find.byIcon(Icons.ac_unit));
    final badge = tester.getRect(pulsePaint());

    expect(badge.right, greaterThan(icon.right));
    expect(badge.top, lessThan(icon.top));
    expect(badge.width, NavAlarmBadge.size);

    await tester.pumpWidget(wrap(
      const NavAlarmBadge(level: null, child: Icon(Icons.ac_unit)),
    ));
  });
}

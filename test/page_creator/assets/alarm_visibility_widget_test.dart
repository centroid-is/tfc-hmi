import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/alarm_visibility.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/widgets/alarm.dart' show alarmLevelColors;
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/alarm.dart';

import 'alarm_visibility_config_test.dart' show activeFx;

void main() {
  // ProviderScope + MaterialApp, no overrides — like the sensor tests, the
  // widget's no-AlarmMan path (provider never resolves / errors) renders the
  // idle marker and the pane falls back to its static bodies.
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  Finder pulsePaint() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is AlarmPulsePainter);
  Finder idlePaint() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is AlarmIdlePainter);

  tearDown(closeSidePane);

  group('Idle rendering', () {
    testWidgets('idle beacon is invisible in page view by default — no tap '
        'target', (tester) async {
      final config = AlarmVisibilityConfig();
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      expect(idlePaint(), findsNothing);
      expect(pulsePaint(), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AlarmVisibility),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason: 'An invisible beacon must not swallow taps.',
      );
    });

    testWidgets('showWhenInactive opts into the faint idle marker',
        (tester) async {
      final config = AlarmVisibilityConfig(showWhenInactive: true);
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      expect(idlePaint(), findsOneWidget);
      expect(pulsePaint(), findsNothing);
    });

    testWidgets('editor canvas always shows a placeholder, even when hidden',
        (tester) async {
      final config = AlarmVisibilityConfig();
      await tester.pumpWidget(wrap(
        AssetEditModeScope(
          child: SizedBox(
              width: 80, height: 80, child: AlarmVisibility(config: config)),
        ),
      ));
      await tester.pump();

      expect(idlePaint(), findsOneWidget,
          reason: 'An invisible asset cannot be found or moved in the editor.');
    });
  });

  group('Active rendering', () {
    testWidgets('active alarm shows pulsing rings and animates',
        (tester) async {
      final config = AlarmVisibilityConfig();
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      final dynamic state = tester.state(find.byType(AlarmVisibility));
      state.debugSetActive([activeFx(level: AlarmLevel.error)]);
      await tester.pump();

      expect(pulsePaint(), findsOneWidget);
      expect(idlePaint(), findsNothing);

      final p1 = (tester.widget<CustomPaint>(pulsePaint()).painter
              as AlarmPulsePainter)
          .progress;
      await tester.pump(const Duration(milliseconds: 450));
      final p2 = (tester.widget<CustomPaint>(pulsePaint()).painter
              as AlarmPulsePainter)
          .progress;
      expect(p2, isNot(p1), reason: 'The beacon must animate while active.');
    });

    testWidgets('ring colour follows the highest active level',
        (tester) async {
      final config = AlarmVisibilityConfig();
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      final dynamic state = tester.state(find.byType(AlarmVisibility));
      state.debugSetActive([
        activeFx(uid: 'w', level: AlarmLevel.warning),
        activeFx(uid: 'e', level: AlarmLevel.error),
      ]);
      await tester.pump();

      final painter = tester.widget<CustomPaint>(pulsePaint()).painter
          as AlarmPulsePainter;
      final context = tester.element(find.byType(AlarmVisibility));
      // The exact pair the alarm system renders this alarm's card with.
      final (fill, ring) = alarmLevelColors(context, AlarmLevel.error);
      expect(painter.color, fill);
      expect(painter.dotOutlineColor, ring);
    });

    testWidgets('returning to idle stops the animation', (tester) async {
      final config = AlarmVisibilityConfig(showWhenInactive: true);
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      final dynamic state = tester.state(find.byType(AlarmVisibility));
      state.debugSetActive([activeFx()]);
      await tester.pump();
      state.debugSetActive(<AlarmActive>[]);
      await tester.pump();

      expect(idlePaint(), findsOneWidget);
      // pumpAndSettle would hang if a ticker were still running.
      await tester.pumpAndSettle();
    });
  });

  group('Tap opens the side pane', () {
    testWidgets('idle marker tap opens the pane (NOT the config editor)',
        (tester) async {
      final config = AlarmVisibilityConfig(showWhenInactive: true)
        ..text = 'Pump alarms';
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      await tester.tap(find.byType(AlarmVisibility));
      await tester.pumpAndSettle();

      expect(find.byType(SidePane), findsOneWidget);
      expect(find.text('Pump alarms'), findsOneWidget,
          reason: 'The pane title is the configured label.');
      // Negative lock — no editor surface on a runtime tap.
      expect(find.text('Hide when inactive'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('active tap opens the pane too', (tester) async {
      final config = AlarmVisibilityConfig();
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      final dynamic state = tester.state(find.byType(AlarmVisibility));
      state.debugSetActive([activeFx()]);
      await tester.pump();

      await tester.tap(find.byType(AlarmVisibility));
      // Not pumpAndSettle — the beacon's ticker never settles while active.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SidePane), findsOneWidget);
    });

    testWidgets('Close button dismisses the pane', (tester) async {
      final config = AlarmVisibilityConfig(showWhenInactive: true);
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      await tester.tap(find.byType(AlarmVisibility));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing);
    });
  });

  group('Hit area matches the idle marker', () {
    // Box is 80×80, so the marker's outer ring has radius
    // (min(80,80)/2) * AlarmIdlePainter.outerRingFactor = 40 * 0.4 = 16 px.
    // The tap region is that circle's bounding box (32×32) centred in the box:
    // it spans x,y ∈ [24, 56]. A corner tap at (6, 6) is well outside it.
    const boxSize = 80.0;
    const cornerInset = 6.0;

    Future<void> pumpIdle(WidgetTester tester) async {
      final config = AlarmVisibilityConfig(showWhenInactive: true)
        ..text = 'Pump alarms';
      await tester.pumpWidget(wrap(
        SizedBox(
            width: boxSize,
            height: boxSize,
            child: AlarmVisibility(config: config)),
      ));
      await tester.pump();
    }

    testWidgets('idle: tap at the centre opens the pane', (tester) async {
      await pumpIdle(tester);
      await tester.tapAt(tester.getCenter(find.byType(AlarmVisibility)));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsOneWidget);
    });

    testWidgets('idle: tap in the empty corner falls through — no pane',
        (tester) async {
      await pumpIdle(tester);
      final origin = tester.getTopLeft(find.byType(AlarmVisibility));
      await tester.tapAt(origin + const Offset(cornerInset, cornerInset));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing,
          reason: 'A tap in the empty box around the small marker must not '
              'register — it should fall through to whatever is beneath.');
    });

    testWidgets('active: centre opens, corner falls through', (tester) async {
      final config = AlarmVisibilityConfig();
      await tester.pumpWidget(wrap(
        SizedBox(
            width: boxSize,
            height: boxSize,
            child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      final dynamic state = tester.state(find.byType(AlarmVisibility));
      state.debugSetActive([activeFx()]);
      await tester.pump();

      // Corner miss (the transient pulse rings are not a tap surface).
      final origin = tester.getTopLeft(find.byType(AlarmVisibility));
      await tester.tapAt(origin + const Offset(cornerInset, cornerInset));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SidePane), findsNothing,
          reason: 'Active beacon still only takes taps near the marker.');

      // Centre hit.
      await tester.tapAt(tester.getCenter(find.byType(AlarmVisibility)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SidePane), findsOneWidget);
    });
  });

  group('Preview', () {
    testWidgets('palette preview is a static pulse frame — settles',
        (tester) async {
      final config = AlarmVisibilityConfig.preview();
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 80, child: AlarmVisibility(config: config)),
      ));
      // Would time out if the preview ran a repeating ticker.
      await tester.pumpAndSettle();

      expect(pulsePaint(), findsOneWidget);
      final painter = tester.widget<CustomPaint>(pulsePaint()).painter
          as AlarmPulsePainter;
      expect(painter.progress, 0.35);
    });
  });
}

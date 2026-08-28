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
    // Box is 160×160, so the marker's outer ring has radius
    // (min(160,160)/2) * AlarmIdlePainter.outerRingFactor = 80 * 0.4 = 32 px —
    // a 64 px diameter, comfortably over kMinInteractiveDimension, so the
    // finger-size floor does not kick in and the region really is the
    // marker's. It is that circle's bounding box (64×64) centred in the box:
    // x,y ∈ [48, 112]. A corner tap at (6, 6) is well outside it.
    const boxSize = 160.0;
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

    testWidgets('a corner tap reaches the asset beneath, not just nothing',
        (tester) async {
      // "No pane opened" is not the same as "the tap fell through": a
      // `CustomPaint` whose painter does not override `hitTest` claims every
      // point in its box (`hitTestSelf` is `hitTest(position) ?? true`), so
      // without the `IgnorePointer` the beacon would quietly eat the tap
      // instead of passing it on — the same clutter, now silent.
      var beneath = 0;
      final config = AlarmVisibilityConfig(showWhenInactive: true);
      await tester.pumpWidget(wrap(
        SizedBox(
          width: boxSize,
          height: boxSize,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => beneath++,
                ),
              ),
              Positioned.fill(child: AlarmVisibility(config: config)),
            ],
          ),
        ),
      ));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(AlarmVisibility));
      await tester.tapAt(origin + const Offset(cornerInset, cornerInset));
      await tester.pumpAndSettle();
      expect(beneath, 1,
          reason: 'the empty box around the marker must pass taps through');
      expect(find.byType(SidePane), findsNothing);
    });

    testWidgets('a small box keeps a finger-sized target, capped by the box',
        (tester) async {
      // The default asset size (0.03 × 0.03 of the page) is ~32 px tall on a
      // 1080p panel; a marker-sized region there would be ~13 px, which no
      // finger can hit. The floor grows it to the box — safe, because a box
      // this small was never a large invisible click target.
      const small = 40.0;
      final config = AlarmVisibilityConfig(showWhenInactive: true);
      await tester.pumpWidget(wrap(
        SizedBox(
            width: small, height: small, child: AlarmVisibility(config: config)),
      ));
      await tester.pump();

      // 40 * 0.4 = 16 px marker; floored to kMinInteractiveDimension (48) and
      // then capped at the 40 px box, so the whole box takes the tap.
      final origin = tester.getTopLeft(find.byType(AlarmVisibility));
      await tester.tapAt(origin + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsOneWidget,
          reason: 'At the default asset size the marker is only a few pixels '
              'across; the tap target must not shrink with it.');
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

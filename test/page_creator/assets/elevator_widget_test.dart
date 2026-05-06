/// MANUAL SMOKE CHECKLIST — Phase 2 Elevator Foundation closeout
/// ==============================================================
///
/// Run after `flutter test test/page_creator/assets/elevator_*.dart`
/// passes 5/5. Automated tests cover:
///   - rails + platform painter (4 goldens),
///   - stream hoisting + 3 stale paths,
///   - TweenAnimationBuilder duration tracking,
///   - JSON / registry round-trip + back-compat,
///   - dialog field-presence + Tween-duration field mutation.
///
/// What automated tests CANNOT verify (operator-action items):
///
/// 1. Run the app:
///      flutter run -d macos
///    (or the device the developer normally uses).
///
/// 2. Open the page editor (TFC_GOD).
///
/// 3. Confirm "Elevator" appears in the asset palette under category
///    "Visualization" (CONTEXT 'Schema & Registration' lock — closes
///    ELEV-16 at the runtime layer; the registry test in
///    `elevator_config_test.dart` only proves the type is in the map,
///    not that the palette UI surfaces it).
///
/// 4. Drag an Elevator onto a page. Verify the visual contract:
///      - Two thin vertical rails flank the bbox at ~10% and ~90%
///        width.
///      - A horizontal platform deck rectangle (~8% of bbox height)
///        sits BETWEEN the rails.
///      - With no positionKey configured, both rails AND deck render
///        in subdued grey (CONTEXT 'Stale, Out-of-Range, & Tests'
///        — stale path 1 / ELEV-14).
///
/// 5. Tap the placed Elevator. The config dialog opens. Verify:
///      - Position State Key (0-100%)  KeyField (with autocomplete
///        dropdown — common.dart's KeyField behaviour).
///      - Tween Duration (ms)          TextFormField, default `250`,
///        digits-only input formatter (typing letters does nothing).
///      - Size                         SizeField with width / height
///        sliders (per common.dart).
///      - Coordinates                  CoordinatesField with x / y
///        sliders AND an angle slider (enableAngle: true). Verify
///        the angle slider works — set it to 90° and confirm the
///        elevator on the page rotates (sensor.dart precedent).
///      - Children: 0 (managed in Phase 3)   read-only placeholder.
///
/// 6. Set Position State Key to a known PLC 0-100% double key (any
///    real-PLC float key works — confirm one exists by browsing the
///    KeyField autocomplete; if none surface, configure a simulated
///    one via the StateMan dev panel). Save the page.
///
/// 7. Exit editor mode. Verify:
///      - The platform deck colours flip from grey to the active
///        Theme.colorScheme.primary (CONTEXT 'Visual & Position
///        Pipeline' — Plan 02-04 wires this).
///      - As the PLC value sweeps 0 → 100, the platform glides
///        smoothly (no jitter — Pitfall 4 closed by the
///        TweenAnimationBuilder pipeline) from the bottom of the
///        bbox to the top (ELEV-03 — 0% bottom, 100% top).
///      - At PLC value = 50%, the platform sits at the geometric
///        centre.
///      - Tween duration matches whatever was set in step 5; try
///        500ms vs 100ms to confirm the field is wired.
///
/// 8. Tap the elevator (in non-editor mode). The config dialog
///    reopens (GestureDetector with HitTestBehavior.opaque survives
///    the runtime Stack — closes the Phase-3 forward-compat
///    contract from CONTEXT '§GestureDetector Compat').
///
/// 9. Save the page. Quit the app. Reopen it. Confirm:
///      - The elevator is still on the page with positionKey,
///        tweenDurationMs, coordinates, and size preserved (ELEV-17
///        — JSON round-trip; the test in `elevator_config_test.dart`
///        proves it at the JSON layer, this confirms it at the
///        on-disk layer).
///      - Loading produces no errors in the console.
///
/// 10. Open an existing saved page that does NOT contain an elevator.
///     Confirm it loads cleanly with no errors (ELEV-18 — back-compat;
///     test in `elevator_config_test.dart` proves it for the LEDConfig
///     case, but on-disk pages may carry richer schemas — this is the
///     manual safeguard).
///
/// Resume signal: report "approved" or describe issues for triage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tfc/page_creator/assets/elevator.dart';
import 'package:tfc/page_creator/assets/elevator_painter.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 200, height: 300, child: child),
            ),
          ),
        ),
      );

  group('Tap to configure', () {
    testWidgets(
        'tap opens config dialog (Position State Key field is unique-to-editor finder)',
        (tester) async {
      final config = ElevatorConfig();
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();
      // _ElevatorConfigEditor is the dialog body (private — found indirectly
      // by the unique 'Position State Key (0-100%)' KeyField label which only
      // exists inside this dialog). Mirrors Plan 01-05 Task 3's swap from
      // find.byType(AlertDialog) to a unique-to-editor finder. Once Phase 3
      // adds child-management UI to the dialog, this assertion stays stable
      // because the positionKey label is in the field-ordering frozen surface.
      expect(find.text('Position State Key (0-100%)'), findsOneWidget);
    });

    testWidgets('GestureDetector exists with HitTestBehavior.opaque',
        (tester) async {
      final config = ElevatorConfig();
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      // Find the GestureDetector child of the Elevator subtree.
      final gd = tester.widget<GestureDetector>(find.byType(GestureDetector).first);
      expect(gd.behavior, HitTestBehavior.opaque);
    });

    testWidgets(
        'config dialog renders all locked Phase-2 fields + Children placeholder',
        (tester) async {
      final config = ElevatorConfig(
        positionKey: '/elev/01/position',
        tweenDurationMs: 333,
      );
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Locked field surface (mirror Plan 01-05 smoke test pattern):
      expect(find.text('Position State Key (0-100%)'), findsOneWidget);
      expect(find.text('Tween Duration (ms)'), findsOneWidget);
      // Children placeholder uses runtime length so the assertion is robust
      // to Phase 3's eventual replacement (children=0 here in Phase 2).
      expect(find.text('Children: 0 (managed in Phase 3)'), findsOneWidget);
      // Coordinates angle slider surface — CoordinatesField is unique to
      // the editor (placed widget tree does not contain it). Phase 1 used
      // the same finder (sensor_widget_test 'CoordinatesField is in the
      // config dialog' precedent). Pull the type from common.dart by name.
      final coordsField = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'CoordinatesField',
      );
      expect(coordsField, findsOneWidget);
    });

    testWidgets('editing Tween Duration field mutates config.tweenDurationMs',
        (tester) async {
      final config = ElevatorConfig(tweenDurationMs: 250);
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Find the Tween Duration TextFormField by its labelText.
      final tweenField = find.widgetWithText(TextFormField, 'Tween Duration (ms)');
      expect(tweenField, findsOneWidget);
      await tester.enterText(tweenField, '500');
      await tester.pump();
      expect(config.tweenDurationMs, 500);
    });
  });

  group('Stale paths', () {
    testWidgets('empty positionKey → painter.isStale=true', (tester) async {
      final config = ElevatorConfig(positionKey: '');
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      // Descend into the Elevator subtree so we don't pick up the
      // CustomPaint instances belonging to the MaterialApp chrome
      // (Scaffold / Overlay), which have no painter set.
      final cp = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Elevator),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(cp.painter, isA<ElevatorPainter>());
      expect((cp.painter as ElevatorPainter).isStale, isTrue);
    });
  });

  group('Stream lifecycle (Pitfall 2)', () {
    testWidgets('positionStream is non-null when positionKey is set',
        (tester) async {
      final config = ElevatorConfig(positionKey: '/elev/01/position');
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      final state = tester.state<State<Elevator>>(find.byType(Elevator))
          as dynamic;
      expect(state.debugPositionStream, isNotNull);
    });

    testWidgets('100 rebuilds with same positionKey: stream identity preserved',
        (tester) async {
      final config = ElevatorConfig(positionKey: '/elev/01/position');
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      final state = tester.state<State<Elevator>>(find.byType(Elevator))
          as dynamic;
      final streamA = state.debugPositionStream;
      for (int i = 0; i < 100; i++) {
        await tester.pumpWidget(wrap(Elevator(config: config)));
      }
      final streamB = state.debugPositionStream;
      expect(identical(streamA, streamB), isTrue,
          reason:
              'positionStream must not be re-created across rebuilds with same positionKey (Pitfall 2)');
    });

    testWidgets('changing positionKey re-hoists stream (different identity)',
        (tester) async {
      final configA = ElevatorConfig(positionKey: '/elev/01/position');
      final configB = ElevatorConfig(positionKey: '/elev/02/position');
      await tester.pumpWidget(wrap(Elevator(config: configA)));
      await tester.pump(Duration.zero);
      final state = tester.state<State<Elevator>>(find.byType(Elevator))
          as dynamic;
      final streamA = state.debugPositionStream;
      await tester.pumpWidget(wrap(Elevator(config: configB)));
      await tester.pump(Duration.zero);
      final streamB = state.debugPositionStream;
      expect(identical(streamA, streamB), isFalse,
          reason:
              'positionStream must be re-hoisted when positionKey changes');
    });

    testWidgets('unmount disposes ValueNotifier and cancels subscription',
        (tester) async {
      final config = ElevatorConfig(positionKey: '/elev/01/position');
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      // Replace with empty widget — forces unmount and dispose.
      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pump(Duration.zero);
      // No exceptions during unmount means dispose ran cleanly. The
      // framework will throw "ValueNotifier was disposed" if a listener
      // tries to read after dispose; the absence of exceptions here is
      // the regression guard.
      expect(tester.takeException(), isNull);
    });
  });

  group('Rotation', () {
    testWidgets('coordinates.angle=90° applied via LayoutRotatedBox',
        (tester) async {
      final config = ElevatorConfig(positionKey: '');
      config.coordinates.angle = 90.0;
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      // LayoutRotatedBox lives in lib/page_creator/assets/common.dart;
      // verify presence via runtimeType lookup (the type is private to
      // the assets layer — we don't import it directly here to mirror
      // the conveyor_gate_test.dart precedent).
      final lrb = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'LayoutRotatedBox',
      );
      expect(lrb, findsOneWidget);
    });
  });

  group('Animation pipeline (ELEV-06)', () {
    testWidgets('TweenAnimationBuilder<double> exists in widget tree',
        (tester) async {
      final config = ElevatorConfig(positionKey: '');
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
    });

    testWidgets('TweenAnimationBuilder duration matches config.tweenDurationMs',
        (tester) async {
      final config = ElevatorConfig(tweenDurationMs: 500);
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      final tab = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      expect(tab.duration, const Duration(milliseconds: 500));
    });

    testWidgets('default tweenDurationMs=250 → duration=250ms',
        (tester) async {
      final config = ElevatorConfig();
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      final tab = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      expect(tab.duration, const Duration(milliseconds: 250));
    });
  });
}

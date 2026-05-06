import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/sensor.dart';
import 'package:tfc/page_creator/assets/sensor_painter.dart';

void main() {
  // Wraps a widget in ProviderScope + MaterialApp so showDialog has a
  // Navigator. No provider overrides — tests use the empty-detectionKey path
  // so no real StateMan is needed for tap / stale / rotation assertions.
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('Tap to configure', () {
    testWidgets('tap on sensor with empty detectionKey opens AlertDialog',
        (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      await tester.tap(find.byType(Sensor));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Configure Sensor'), findsOneWidget);
    });

    testWidgets(
        'tap survives Transform.translate ancestor (Phase 3 forward-compat)',
        (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        Transform.translate(
          offset: const Offset(0, 100),
          child: SizedBox(
            width: 80,
            height: 40,
            child: Sensor(config: config),
          ),
        ),
      ));

      // find.byType locates the Sensor regardless of translation; the tap
      // is dispatched at the translated position because Transform.translate
      // sets transformHitTests=true by default (UI-SPEC §Interaction Contract).
      await tester.tap(find.byType(Sensor));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Configure Sensor'), findsOneWidget);
    });
  });

  group('Tag pass-through', () {
    testWidgets('config.tag is passed to painter as label', (tester) async {
      final config = SensorConfig(detectionKey: '', tag: 'PE-101A');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final cp = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect((cp.painter as RedLightBeamPainter).label, 'PE-101A');
    });

    testWidgets('null tag flows through as null label', (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final cp = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect((cp.painter as RedLightBeamPainter).label, isNull);
    });
  });

  group('Stale rendering', () {
    testWidgets('empty detectionKey causes painter to receive isStale=true',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        kind: SensorKind.redLight,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(customPaint.painter, isA<RedLightBeamPainter>());
      expect((customPaint.painter as RedLightBeamPainter).isStale, isTrue);
    });

    testWidgets(
        'opticField + empty detectionKey causes OpticFieldPainter with isStale=true',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        kind: SensorKind.opticField,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(customPaint.painter, isA<OpticFieldPainter>());
      expect((customPaint.painter as OpticFieldPainter).isStale, isTrue);
    });

    testWidgets(
        'inductiveField + empty detectionKey causes InductiveFieldPainter with isStale=true',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        kind: SensorKind.inductiveField,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(customPaint.painter, isA<InductiveFieldPainter>());
      expect((customPaint.painter as InductiveFieldPainter).isStale, isTrue);
    });
  });

  group('Rotation', () {
    testWidgets('config.coordinates.angle is honoured via LayoutRotatedBox',
        (tester) async {
      final config = SensorConfig(detectionKey: '')
        ..coordinates = Coordinates(x: 0.5, y: 0.5, angle: 90.0);
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final rotated = tester.widgetList<LayoutRotatedBox>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(LayoutRotatedBox),
        ),
      );
      expect(rotated, isNotEmpty);
      expect(
        rotated.first.angle,
        closeTo(90.0 * (3.141592653589793 / 180.0), 1e-9),
      );
    });

    testWidgets('null angle defaults to 0 radians', (tester) async {
      final config = SensorConfig(detectionKey: '')
        ..coordinates = Coordinates(x: 0.5, y: 0.5);
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final rotated = tester.widgetList<LayoutRotatedBox>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(LayoutRotatedBox),
        ),
      );
      expect(rotated, isNotEmpty);
      expect(rotated.first.angle, 0.0);
    });
  });

  group('Polarity through widget', () {
    testWidgets(
        'rawBool=true with invertActivePolarity=false yields isActive=true',
        (tester) async {
      // Use detectionKey '/k' to exercise the stream path; the test reads
      // the @visibleForTesting helper directly so the widget tree never
      // actually pumps a value (StateMan is unconfigured under ProviderScope
      // with no overrides — its provider Future never completes in this
      // synchronous test pump). The helper itself is pure.
      final config = SensorConfig(
        detectionKey: '/k',
        invertActivePolarity: false,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      expect(state.resolveIsActive(true), isTrue);
      expect(state.resolveIsActive(false), isFalse);
    });

    testWidgets('invertActivePolarity=true flips both directions',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '/k',
        invertActivePolarity: true,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      expect(state.resolveIsActive(true), isFalse);
      expect(state.resolveIsActive(false), isTrue);
    });

    test(
        'Sensor widget file contains no AnimationController or Tween references (SENS-05 immediate-flip guard)',
        () async {
      final source =
          await File('lib/page_creator/assets/sensor.dart').readAsString();
      expect(source, isNot(contains('AnimationController')));
      expect(source, isNot(contains('TweenAnimationBuilder')));
      expect(source, isNot(contains('animateTo')));
    });
  });

  group('Tooltip presence', () {
    testWidgets(
        'Sensor widget tree contains a Tooltip ancestor of GestureDetector',
        (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      // Use find.descendant rooted at Sensor to avoid matching the dialog
      // chrome's own internal Tooltip widgets if they ever appear.
      final tooltip = find.descendant(
        of: find.byType(Sensor),
        matching: find.byType(Tooltip),
      );
      expect(tooltip, findsOneWidget);
      // Tooltip must be an ancestor (outer) of GestureDetector — UI-SPEC
      // §Tooltip trigger requires Tooltip(child: GestureDetector(...)).
      final gesture = find.descendant(
        of: tooltip,
        matching: find.byType(GestureDetector),
      );
      expect(gesture, findsAtLeastNWidgets(1));
    });
  });

  group('Tooltip content (copy contract)', () {
    testWidgets(
        'Tooltip content shows "Detection key not set" when detectionKey empty',
        (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Sensor)));
      // Long-press threshold: ~500ms; pump 600 to be safe.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Detection key not set'), findsOneWidget);
      await gesture.up();
    });

    testWidgets(
        'Tooltip content shows "Rising: —\\nFalling: —" when both delay keys empty',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '/some/key',
        risingEdgeDelayKey: '',
        fallingEdgeDelayKey: '',
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Sensor)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Rising: —'), findsOneWidget);
      expect(find.text('Falling: —'), findsOneWidget);
      await gesture.up();
    });

    testWidgets(
        'Tooltip content shows "Rising: —" portion when rising key empty and falling key set',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '/some/key',
        risingEdgeDelayKey: '',
        fallingEdgeDelayKey: '/falling',
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Sensor)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      // Rising key empty → em-dash row.
      expect(find.text('Rising: —'), findsOneWidget);
      // Falling key configured but no value emitted yet → ellipsis.
      // (Without StateMan provider override the Future never completes
      // synchronously, so snapshot.hasData stays false → '…' shown.)
      expect(find.text('Falling: …'), findsOneWidget);
      await gesture.up();
    });
  });

  group('Tooltip subscription lifecycle', () {
    // Locks CONTEXT.md decision: "Edge-delay tooltip subscriptions: subscribe
    // to the rising/falling keys only while the tooltip is open; cancel on
    // close (avoids persistent per-instance subscription overhead)." The
    // implementation satisfies this implicitly — _DelayRow.build invokes
    // ref.read(stateManProvider.future)…subscribe(stateKey) only when the
    // tooltip's content widget is mounted; Flutter mounts the content widget
    // on tooltip open and unmounts on close.

    testWidgets('Tooltip content is not mounted when tooltip is closed',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        risingEdgeDelayKey: '/r',
        fallingEdgeDelayKey: '/f',
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      await tester.pumpAndSettle();

      // No long-press yet — _SensorTooltipContent must NOT be mounted, so
      // its rendered "Detection key not set" copy must be absent from the
      // widget tree.
      expect(find.text('Detection key not set'), findsNothing,
          reason:
              'Tooltip content widget must remain unmounted while the tooltip is closed');
    });

    testWidgets('Tooltip content unmounts when tooltip is dismissed',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '/d',
        risingEdgeDelayKey: '',
        fallingEdgeDelayKey: '',
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      // Open tooltip via long-press.
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Sensor)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      // Tooltip content visible.
      expect(find.text('Rising: —'), findsOneWidget);
      expect(find.text('Falling: —'), findsOneWidget);

      // Release + dismiss (Tooltip auto-dismisses after its show-duration on
      // touch; pumping past it triggers the unmount).
      await gesture.up();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Rising: —'), findsNothing,
          reason:
              'Tooltip content should unmount after dismissal (subscription scope ends here)');
      expect(find.text('Falling: —'), findsNothing);
    });
  });

  group('Stream lifecycle', () {
    testWidgets('rebuilds with same detectionKey do not re-hoist the stream',
        (tester) async {
      final config = SensorConfig(detectionKey: '/k1');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      // Stream identity at t=0 (after initState).
      final streamRef1 = state.debugDetectionStream;

      // Trigger a rebuild WITHOUT changing the config — same SensorConfig
      // instance, same detectionKey. didUpdateWidget must NOT re-hoist.
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final streamRef2 = state.debugDetectionStream;

      expect(
        identical(streamRef1, streamRef2),
        isTrue,
        reason: 'Stream identity must persist across rebuilds (Pitfall 2)',
      );
    });

    testWidgets('changing detectionKey re-hoists the stream', (tester) async {
      final config1 = SensorConfig(detectionKey: '/k1');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config1)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      final streamRef1 = state.debugDetectionStream;

      // Mutate config to a different key — this is the path the editor
      // dialog takes (config object is reused across rebuilds; keys mutate).
      config1.detectionKey = '/k2';
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config1)),
      ));
      final streamRef2 = state.debugDetectionStream;

      expect(
        identical(streamRef1, streamRef2),
        isFalse,
        reason:
            'Stream must re-hoist when detectionKey changes (didUpdateWidget guard)',
      );
    });

    test(
        'build() does not construct a stream inline (Pitfall 2 source-level guard)',
        () async {
      final source =
          await File('lib/page_creator/assets/sensor.dart').readAsString();
      // Strip line-comments to avoid false positives from doc-comments.
      final stripped = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // Find the _SensorState.build(...) method body and check no stream
      // construction expressions live inside it.
      final buildSection =
          RegExp(r'Widget build\(BuildContext context\) \{[\s\S]*?\n  \}')
                  .firstMatch(stripped)
                  ?.group(0) ??
              '';
      expect(buildSection, isNotEmpty,
          reason: 'Could not locate build() method in sensor.dart');
      expect(buildSection, isNot(contains('stateManProvider')));
      expect(buildSection, isNot(contains('subscribe(')));
    });
  });
}

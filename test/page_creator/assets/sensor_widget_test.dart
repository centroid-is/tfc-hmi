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
  Widget _wrap(Widget child) {
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
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
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

  group('Stale rendering', () {
    testWidgets('empty detectionKey causes painter to receive isStale=true',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        kind: SensorKind.redLight,
      );
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
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

  group('Stream lifecycle', () {
    testWidgets('rebuilds with same detectionKey do not re-hoist the stream',
        (tester) async {
      final config = SensorConfig(detectionKey: '/k1');
      await tester.pumpWidget(_wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      // Stream identity at t=0 (after initState).
      final streamRef1 = state.debugDetectionStream;

      // Trigger a rebuild WITHOUT changing the config — same SensorConfig
      // instance, same detectionKey. didUpdateWidget must NOT re-hoist.
      await tester.pumpWidget(_wrap(
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
      await tester.pumpWidget(_wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config1)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      final streamRef1 = state.debugDetectionStream;

      // Mutate config to a different key — this is the path the editor
      // dialog takes (config object is reused across rebuilds; keys mutate).
      config1.detectionKey = '/k2';
      await tester.pumpWidget(_wrap(
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

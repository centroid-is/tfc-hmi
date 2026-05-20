import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:tfc/page_creator/assets/start_stop_button.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc_dart/core/state_man.dart';

/// Widget tests for the manual-mode-key gating in StartStopPillButtonConfig.
///
/// The contract under test (analogous to ButtonConfig's disabled-key gate,
/// but conceptually inverted — "manual mode" semantics):
///   - manualModeKey == null                                → always interactive
///   - stream=true  + polarity=manualWhenTrue               → interactive (manual mode active)
///   - stream=false + polarity=manualWhenTrue               → INACTIVE (auto mode locked out)
///   - stream=true  + polarity=manualWhenFalse              → INACTIVE
///   - stream=false + polarity=manualWhenFalse              → interactive
///
/// "INACTIVE" means: BOTH the Start (run) and Stop GestureDetectors render
/// without their onTapDown / onTapUp callbacks AND the segment icons render
/// with the configured `inactiveColor`.
void main() {
  Widget wrap({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  /// All segment GestureDetectors inside the pill (one per segment).
  Finder segmentGestureDetectors() => find.descendant(
        of: find.byType(StartStopPillButton),
        matching: find.byType(GestureDetector),
      );

  /// The Icon widget for a given FA icon (Start = play, Stop = stop).
  Finder iconByData(IconData data) => find.byWidgetPredicate(
        (w) => w is Icon && w.icon == data,
      );

  /// Finds the inactive-state lock badge (the overlay we paint over the
  /// pill when the operator is locked out of manual control).
  Finder lockOverlay() => find.byKey(StartStopPillButton.inactiveBadgeKey);

  group('manualModeKey == null → always interactive', () {
    testWidgets('preview config has tap callbacks on every segment',
        (tester) async {
      final config = StartStopPillButtonConfig.preview();
      await tester.pumpWidget(wrap(
        child: SizedBox(
          width: 240,
          height: 80,
          child: StartStopPillButton(config),
        ),
      ));
      await tester.pump();

      final detectors = tester
          .widgetList<GestureDetector>(segmentGestureDetectors())
          .toList();
      expect(detectors, isNotEmpty,
          reason: 'pill must contain segment GestureDetectors');
      for (final d in detectors) {
        expect(d.onTapDown, isNotNull,
            reason: 'no manualModeKey → onTapDown must be wired');
        expect(d.onTapUp, isNotNull);
        expect(d.onTapCancel, isNotNull);
      }
      expect(lockOverlay(), findsNothing,
          reason: 'no manualModeKey → no inactive lock badge');
    });
  });

  group('manualModeKey set + stream true', () {
    testWidgets('polarity=manualWhenTrue + stream=true → interactive',
        (tester) async {
      final fake = _FakeStateMan();
      fake.push('mode/manual', true);

      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )
        ..manualModeKey = 'mode/manual'
        ..manualModePolarity = ManualModePolarity.manualWhenTrue
        ..inactiveColor = const Color(0xFFAABBCC);

      await tester.pumpWidget(wrap(
        overrides: [stateManProvider.overrideWith((_) async => fake)],
        child: SizedBox(
          width: 240,
          height: 80,
          child: StartStopPillButton(config),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final detectors = tester
          .widgetList<GestureDetector>(segmentGestureDetectors())
          .toList();
      expect(detectors, isNotEmpty);
      for (final d in detectors) {
        expect(d.onTapDown, isNotNull,
            reason: 'manualWhenTrue + stream=true must stay interactive');
        expect(d.onTapUp, isNotNull);
      }
      expect(lockOverlay(), findsNothing,
          reason: 'interactive pill must NOT render the lock badge');
    });

    testWidgets(
        'polarity=manualWhenFalse + stream=true → inactive + tinted icons',
        (tester) async {
      final fake = _FakeStateMan();
      fake.push('mode/manual', true);

      const tint = Color(0xFFAABBCC);
      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )
        ..manualModeKey = 'mode/manual'
        ..manualModePolarity = ManualModePolarity.manualWhenFalse
        ..inactiveColor = tint;

      await tester.pumpWidget(wrap(
        overrides: [stateManProvider.overrideWith((_) async => fake)],
        child: SizedBox(
          width: 240,
          height: 80,
          child: StartStopPillButton(config),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final detectors = tester
          .widgetList<GestureDetector>(segmentGestureDetectors())
          .toList();
      expect(detectors, isNotEmpty);
      for (final d in detectors) {
        expect(d.onTapDown, isNull,
            reason: 'inactive: onTapDown must be cleared');
        expect(d.onTapUp, isNull);
        expect(d.onTapCancel, isNull);
      }

      // Start (play) and Stop icons must render in inactiveColor.
      final playIcon = tester.widget<Icon>(iconByData(FontAwesomeIcons.play));
      final stopIcon = tester.widget<Icon>(iconByData(FontAwesomeIcons.stop));
      expect(playIcon.color, tint,
          reason: 'Start icon must paint in inactiveColor');
      expect(stopIcon.color, tint,
          reason: 'Stop icon must paint in inactiveColor');

      // Lock badge must be present so the operator immediately sees WHY the
      // button is non-interactive.
      expect(lockOverlay(), findsOneWidget,
          reason: 'inactive pill must render the lock badge');
    });
  });

  group('manualModeKey set + stream false', () {
    testWidgets(
        'polarity=manualWhenTrue + stream=false → inactive + tinted icons',
        (tester) async {
      final fake = _FakeStateMan();
      fake.push('mode/manual', false);

      const tint = Color(0xFF112233);
      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )
        ..manualModeKey = 'mode/manual'
        ..manualModePolarity = ManualModePolarity.manualWhenTrue
        ..inactiveColor = tint;

      await tester.pumpWidget(wrap(
        overrides: [stateManProvider.overrideWith((_) async => fake)],
        child: SizedBox(
          width: 240,
          height: 80,
          child: StartStopPillButton(config),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final detectors = tester
          .widgetList<GestureDetector>(segmentGestureDetectors())
          .toList();
      expect(detectors, isNotEmpty);
      for (final d in detectors) {
        expect(d.onTapDown, isNull,
            reason: 'manualWhenTrue + stream=false → inactive');
        expect(d.onTapUp, isNull);
        expect(d.onTapCancel, isNull);
      }

      final playIcon = tester.widget<Icon>(iconByData(FontAwesomeIcons.play));
      final stopIcon = tester.widget<Icon>(iconByData(FontAwesomeIcons.stop));
      expect(playIcon.color, tint);
      expect(stopIcon.color, tint);

      expect(lockOverlay(), findsOneWidget,
          reason: 'inactive pill must render the lock badge');
    });

    testWidgets('polarity=manualWhenFalse + stream=false → interactive',
        (tester) async {
      final fake = _FakeStateMan();
      fake.push('mode/manual', false);

      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )
        ..manualModeKey = 'mode/manual'
        ..manualModePolarity = ManualModePolarity.manualWhenFalse;

      await tester.pumpWidget(wrap(
        overrides: [stateManProvider.overrideWith((_) async => fake)],
        child: SizedBox(
          width: 240,
          height: 80,
          child: StartStopPillButton(config),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final detectors = tester
          .widgetList<GestureDetector>(segmentGestureDetectors())
          .toList();
      expect(detectors, isNotEmpty);
      for (final d in detectors) {
        expect(d.onTapDown, isNotNull);
        expect(d.onTapUp, isNotNull);
      }
      expect(lockOverlay(), findsNothing,
          reason: 'interactive pill must NOT render the lock badge');
    });
  });
}

/// Minimal stand-in for [StateMan] that lets tests push synchronous values
/// for a given key. Only `subscribe` is implemented.
class _FakeStateMan implements StateMan {
  final Map<String, BehaviorSubject<DynamicValue>> _streams = {};

  void push(String key, bool value) {
    final s = _streams.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    s.add(DynamicValue(value: value, typeId: NodeId.boolean));
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    final s = _streams.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    return s.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeStateMan: ${invocation.memberName} not implemented in test scope',
    );
  }
}

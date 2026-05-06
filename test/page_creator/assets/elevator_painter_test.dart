import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/elevator_painter.dart';

void main() {
  group('ElevatorPainter shouldRepaint contract', () {
    test('same inputs → shouldRepaint=false', () {
      final notifier = ValueNotifier<double>(0.5);
      final a = ElevatorPainter(progress: notifier, isStale: false);
      final b = ElevatorPainter(progress: notifier, isStale: false);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('different progress notifier → shouldRepaint=true', () {
      final n1 = ValueNotifier<double>(0.5);
      final n2 = ValueNotifier<double>(0.5); // distinct instance, same value
      final a = ElevatorPainter(progress: n1, isStale: false);
      final b = ElevatorPainter(progress: n2, isStale: false);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('different isStale → shouldRepaint=true', () {
      final n = ValueNotifier<double>(0.5);
      final a = ElevatorPainter(progress: n, isStale: false);
      final b = ElevatorPainter(progress: n, isStale: true);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('different isOutOfRange → shouldRepaint=true (ELEV-15)', () {
      final n = ValueNotifier<double>(0.5);
      final a = ElevatorPainter(progress: n, isStale: false, isOutOfRange: false);
      final b = ElevatorPainter(progress: n, isStale: false, isOutOfRange: true);
      expect(a.shouldRepaint(b), isTrue,
          reason:
              'Toggling isOutOfRange must trigger a repaint so the amber '
              'outline appears/disappears (ELEV-15).');
    });

    test('cross-runtimeType → shouldRepaint=true (Pitfall 3 guard)', () {
      final n = ValueNotifier<double>(0.5);
      final elevator = ElevatorPainter(progress: n, isStale: false);
      final other = _DummyPainter();
      // shouldRepaint accepts a covariant CustomPainter; the cross-runtimeType
      // guard inside ElevatorPainter.shouldRepaint must short-circuit to true.
      expect(elevator.shouldRepaint(other), isTrue);
    });
  });

  group('CONTEXT compliance — default active colour (ELEV-02)', () {
    test('default activeColor is neutral grey (Color(0xFF757575))', () {
      final notifier = ValueNotifier<double>(0.5);
      final painter = ElevatorPainter(progress: notifier);
      expect(painter.activeColor, const Color(0xFF757575),
          reason:
              '02-CONTEXT §Visual & Position Pipeline locks rails+platform '
              'as neutral grey. Default active colour MUST match '
              'Colors.grey.shade600 (#757575), not Material blue.');
    });
  });

  group('ElevatorPainter goldens', () {
    const elevatorKey = Key('elevator_painter_golden');

    Future<void> pumpElevator(
      WidgetTester tester, {
      required double progress,
      required bool isStale,
    }) async {
      final notifier = ValueNotifier<double>(progress);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: elevatorKey,
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: CustomPaint(
                    size: const Size(200, 300),
                    painter: ElevatorPainter(
                      progress: notifier,
                      isStale: isStale,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Pin to a deterministic frame — no pumpAndSettle (Pitfall 6).
      await tester.pump(Duration.zero);
    }

    testWidgets('stale.png', (tester) async {
      await pumpElevator(tester, progress: 0.5, isStale: true);
      await expectLater(
        find.byKey(elevatorKey),
        matchesGoldenFile('goldens/elevator/stale.png'),
      );
    });

    testWidgets('position_0.png', (tester) async {
      await pumpElevator(tester, progress: 0.0, isStale: false);
      await expectLater(
        find.byKey(elevatorKey),
        matchesGoldenFile('goldens/elevator/position_0.png'),
      );
    });

    testWidgets('position_50.png', (tester) async {
      await pumpElevator(tester, progress: 0.5, isStale: false);
      await expectLater(
        find.byKey(elevatorKey),
        matchesGoldenFile('goldens/elevator/position_50.png'),
      );
    });

    testWidgets('position_100.png', (tester) async {
      await pumpElevator(tester, progress: 1.0, isStale: false);
      await expectLater(
        find.byKey(elevatorKey),
        matchesGoldenFile('goldens/elevator/position_100.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 4 — Out-of-range golden (ELEV-15)
  //
  // CONTEXT §Out-of-Range Outline lock: a 2px amber outline (Color(0xFFFFA500))
  // hugs the bbox when isOutOfRange=true. The golden captures the rails+deck
  // at progress=0.5 with the outline overlaid — visually validates the locked
  // amber colour and stroke width without depending on Theme.colorScheme.
  // ---------------------------------------------------------------------------
  group('Out-of-range golden (ELEV-15)', () {
    const elevatorKey = Key('elevator_painter_oor_golden');

    testWidgets('position_50_out_of_range.png', (tester) async {
      final notifier = ValueNotifier<double>(0.5);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: elevatorKey,
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: CustomPaint(
                    size: const Size(200, 300),
                    painter: ElevatorPainter(
                      progress: notifier,
                      isStale: false,
                      isOutOfRange: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      await expectLater(
        find.byKey(elevatorKey),
        matchesGoldenFile('goldens/elevator/position_50_out_of_range.png'),
      );
    });
  });
}

class _DummyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

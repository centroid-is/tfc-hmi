import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/auger_conveyor_painter.dart';

const _augerKey = Key('auger_test_widget');

/// Wraps the auger painter in a minimal widget tree for testing.
Widget buildAugerTestWidget({
  Color stateColor = Colors.grey,
  double phaseOffset = 0.0,
  bool showAuger = true,
  int pitchCount = 6,
  AugerEndCaps endCaps = AugerEndCaps.both,
  double width = 600,
  double height = 120,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: RepaintBoundary(
          key: _augerKey,
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: AugerConveyorPainter(
                stateColor: stateColor,
                phaseOffset: phaseOffset,
                showAuger: showAuger,
                pitchCount: pitchCount,
                endCaps: endCaps,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AugerConveyorPainter', () {
    // ── Unit tests for painter properties ──

    test('shouldRepaint returns true when stateColor changes', () {
      final a = AugerConveyorPainter(stateColor: Colors.green);
      final b = AugerConveyorPainter(stateColor: Colors.red);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when phaseOffset changes', () {
      final a =
          AugerConveyorPainter(stateColor: Colors.grey, phaseOffset: 0.0);
      final b =
          AugerConveyorPainter(stateColor: Colors.grey, phaseOffset: 1.0);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns false when nothing changes', () {
      final a =
          AugerConveyorPainter(stateColor: Colors.grey, phaseOffset: 0.5);
      final b =
          AugerConveyorPainter(stateColor: Colors.grey, phaseOffset: 0.5);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('shouldRepaint returns true when showAuger changes', () {
      final a =
          AugerConveyorPainter(stateColor: Colors.grey, showAuger: true);
      final b =
          AugerConveyorPainter(stateColor: Colors.grey, showAuger: false);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when endCaps changes', () {
      final a = AugerConveyorPainter(
          stateColor: Colors.grey, endCaps: AugerEndCaps.both);
      final b = AugerConveyorPainter(
          stateColor: Colors.grey, endCaps: AugerEndCaps.none);
      expect(a.shouldRepaint(b), isTrue);
    });

    // ── Widget rendering tests ──

    testWidgets('renders without errors at default size', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget());
      expect(find.byKey(_augerKey), findsOneWidget);
    });

    testWidgets('renders in flat mode when showAuger is false',
        (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(showAuger: false));
      expect(find.byKey(_augerKey), findsOneWidget);
    });

    testWidgets('renders with different state colors', (tester) async {
      for (final color in [
        Colors.green,
        Colors.blue,
        Colors.yellow,
        Colors.grey,
        Colors.red
      ]) {
        await tester.pumpWidget(buildAugerTestWidget(stateColor: color));
        expect(find.byKey(_augerKey), findsOneWidget);
      }
    });

    testWidgets('renders at small sizes without errors', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(width: 60, height: 15));
      expect(find.byKey(_augerKey), findsOneWidget);
    });

    testWidgets('renders with various phase offsets', (tester) async {
      for (final phase in [0.0, 0.5, 1.0, 3.14, 6.28]) {
        await tester.pumpWidget(buildAugerTestWidget(phaseOffset: phase));
        expect(find.byKey(_augerKey), findsOneWidget);
      }
    });

    testWidgets('renders with different pitch counts', (tester) async {
      for (final count in [2, 4, 6, 10]) {
        await tester.pumpWidget(buildAugerTestWidget(pitchCount: count));
        expect(find.byKey(_augerKey), findsOneWidget);
      }
    });

    testWidgets('renders with all end cap variants', (tester) async {
      for (final caps in AugerEndCaps.values) {
        await tester.pumpWidget(buildAugerTestWidget(endCaps: caps));
        expect(find.byKey(_augerKey), findsOneWidget);
      }
    });

    // ── Golden file tests (produce PNGs at test/painter/goldens/) ──

    testWidgets('golden: default grey stopped auger', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget());
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_grey_stopped.png'),
      );
    });

    testWidgets('golden: green running auger', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 0.8,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_green_running.png'),
      );
    });

    testWidgets('golden: red fault auger', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.red,
        phaseOffset: 2.0,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_red_fault.png'),
      );
    });

    testWidgets('golden: blue clean auger', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.blue,
        phaseOffset: 1.5,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_blue_clean.png'),
      );
    });

    testWidgets('golden: yellow manual auger', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.yellow,
        phaseOffset: 1.0,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_yellow_manual.png'),
      );
    });

    testWidgets('golden: flat conveyor (no auger)', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(showAuger: false));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_flat_mode.png'),
      );
    });

    testWidgets('golden: rotation phase 0', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 0.0,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_phase_0.png'),
      );
    });

    testWidgets('golden: rotation phase quarter', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 1.57,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_phase_quarter.png'),
      );
    });

    testWidgets('golden: rotation phase half', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 3.14,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_phase_half.png'),
      );
    });

    testWidgets('golden: rotation phase three quarter', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 4.71,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_phase_three_quarter.png'),
      );
    });

    // ── End cap golden tests ──

    testWidgets('golden: end caps both', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 0.8,
        endCaps: AugerEndCaps.both,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_endcaps_both.png'),
      );
    });

    testWidgets('golden: end cap left only', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 0.8,
        endCaps: AugerEndCaps.left,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_endcaps_left.png'),
      );
    });

    testWidgets('golden: end cap right only', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 0.8,
        endCaps: AugerEndCaps.right,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_endcaps_right.png'),
      );
    });

    testWidgets('golden: end caps none', (tester) async {
      await tester.pumpWidget(buildAugerTestWidget(
        stateColor: Colors.green,
        phaseOffset: 0.8,
        endCaps: AugerEndCaps.none,
      ));
      await expectLater(
        find.byKey(_augerKey),
        matchesGoldenFile('goldens/auger_endcaps_none.png'),
      );
    });
  });
}

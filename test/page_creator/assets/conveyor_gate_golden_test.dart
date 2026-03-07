import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/page_creator/assets/conveyor_gate_painter.dart';

const _gateKey = Key('gate_test');

/// Wraps a gate painter in a minimal widget tree for golden testing.
///
/// Dispatches to the correct painter based on [variant]:
/// - [GateVariant.pneumatic]: PneumaticDiverterPainter (uses [openAngle])
/// - [GateVariant.slider]: SliderGatePainter
/// - [GateVariant.pusher]: PusherGatePainter
Widget buildGateWidget({
  GateVariant variant = GateVariant.pneumatic,
  double progress = 0.0,
  Color color = Colors.green,
  double openAngle = 45.0,
  GateSide side = GateSide.left,
}) {
  final progressNotifier = ValueNotifier(progress);
  final CustomPainter painter;
  switch (variant) {
    case GateVariant.pneumatic:
      painter = PneumaticDiverterPainter(
        progress: progressNotifier,
        stateColor: color,
        openAngleDegrees: openAngle,
        side: side,
      );
    case GateVariant.slider:
      painter = SliderGatePainter(
        progress: progressNotifier,
        stateColor: color,
        side: side,
      );
    case GateVariant.pusher:
      painter = PusherGatePainter(
        progress: progressNotifier,
        stateColor: color,
        side: side,
      );
  }

  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: RepaintBoundary(
          key: _gateKey,
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(painter: painter),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ConveyorGate golden tests',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    // ── Pneumatic diverter (existing) ──

    testWidgets('gate closed', (tester) async {
      await tester.pumpWidget(
          buildGateWidget(progress: 0.0, color: Colors.white));
      await expectLater(
        find.byKey(_gateKey),
        matchesGoldenFile('goldens/conveyor_gate_closed.png'),
      );
    });

    testWidgets('gate open', (tester) async {
      await tester.pumpWidget(
          buildGateWidget(progress: 1.0, color: Colors.green));
      await expectLater(
        find.byKey(_gateKey),
        matchesGoldenFile('goldens/conveyor_gate_open.png'),
      );
    });

    testWidgets('gate right side', (tester) async {
      await tester.pumpWidget(buildGateWidget(
        progress: 1.0,
        color: Colors.green,
        side: GateSide.right,
      ));
      await expectLater(
        find.byKey(_gateKey),
        matchesGoldenFile('goldens/conveyor_gate_right_open.png'),
      );
    });

    // ── Slider gate ──

    testWidgets('slider closed', (tester) async {
      await tester.pumpWidget(buildGateWidget(
        variant: GateVariant.slider,
        progress: 0.0,
        color: Colors.white,
      ));
      await expectLater(
        find.byKey(_gateKey),
        matchesGoldenFile('goldens/conveyor_gate_slider_closed.png'),
      );
    });

    testWidgets('slider open', (tester) async {
      await tester.pumpWidget(buildGateWidget(
        variant: GateVariant.slider,
        progress: 1.0,
        color: Colors.green,
      ));
      await expectLater(
        find.byKey(_gateKey),
        matchesGoldenFile('goldens/conveyor_gate_slider_open.png'),
      );
    });

    // ── Pusher gate ──

    testWidgets('pusher closed', (tester) async {
      await tester.pumpWidget(buildGateWidget(
        variant: GateVariant.pusher,
        progress: 0.0,
        color: Colors.white,
      ));
      await expectLater(
        find.byKey(_gateKey),
        matchesGoldenFile('goldens/conveyor_gate_pusher_closed.png'),
      );
    });

    testWidgets('pusher open', (tester) async {
      await tester.pumpWidget(buildGateWidget(
        variant: GateVariant.pusher,
        progress: 1.0,
        color: Colors.green,
      ));
      await expectLater(
        find.byKey(_gateKey),
        matchesGoldenFile('goldens/conveyor_gate_pusher_open.png'),
      );
    });
  });
}

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/page_creator/assets/conveyor_gate_painter.dart';

const _gateKey = Key('gate_test');

/// Wraps the PneumaticDiverterPainter in a minimal widget tree for golden testing.
Widget buildGateWidget({
  double progress = 0.0,
  Color color = Colors.green,
  double openAngle = 45.0,
  GateSide side = GateSide.left,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: RepaintBoundary(
          key: _gateKey,
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: PneumaticDiverterPainter(
                progress: ValueNotifier(progress),
                stateColor: color,
                openAngleDegrees: openAngle,
                side: side,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ConveyorGate golden tests',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
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
  });
}

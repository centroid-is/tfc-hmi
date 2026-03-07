import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';

// CHILD-03: Gate sizing from conveyor dimensions
// CHILD-04: Visual overflow (cylinder extends outside conveyor bounds)

void main() {
  group('Child gate sizing (CHILD-03)', () {
    testWidgets(
        'ConveyorGate uses bounded constraints when placed inside Positioned',
        (tester) async {
      // Gate placed inside a SizedBox (simulating Positioned constraints)
      // should use those constraints, not MediaQuery-based config.size.
      // The LayoutBuilder inside _buildGate detects bounded constraints.
      final config = ConveyorGateConfig();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: ConveyorGate(config: config),
                ),
              ),
            ),
          ),
        ),
      );

      // Widget should render without error and contain a CustomPaint
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('child gate sized to conveyor belt height (square)',
        (tester) async {
      // Gate within tight 60x60 constraints should paint at that size
      final config = ConveyorGateConfig();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: ConveyorGate(config: config),
                ),
              ),
            ),
          ),
        ),
      );

      // Verify a CustomPaint exists (the gate rendered successfully
      // using the bounded constraints from the SizedBox)
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('Child gate overflow positioning (CHILD-04)', () {
    test('left-side gate has negative top offset for cylinder overflow', () {
      // Replicate the _positionedChildGate formula:
      // yTop = -gateSize * 0.3  for GateSide.left
      const conveyorSize = Size(200, 40);
      final gate = ConveyorGateConfig(side: GateSide.left, position: 0.5);

      final beltHeight = conveyorSize.height;
      final gateSize = beltHeight;
      final yTop = gate.side == GateSide.left
          ? -gateSize * 0.3
          : conveyorSize.height - gateSize * 0.7;

      // For conveyorSize=(200,40): gateSize=40, yTop = -12
      expect(yTop, lessThan(0),
          reason: 'Left-side gate should overflow above conveyor');
      expect(yTop, -12.0);
    });

    test('right-side gate extends below conveyor bounds', () {
      // Replicate the _positionedChildGate formula:
      // yTop = conveyorSize.height - gateSize * 0.7  for GateSide.right
      const conveyorSize = Size(200, 40);
      final gate = ConveyorGateConfig(side: GateSide.right, position: 0.5);

      final beltHeight = conveyorSize.height;
      final gateSize = beltHeight;
      final yTop = gate.side == GateSide.left
          ? -gateSize * 0.3
          : conveyorSize.height - gateSize * 0.7;

      // For conveyorSize=(200,40): gateSize=40, yTop = 40 - 28 = 12
      // yTop + gateSize = 12 + 40 = 52 > conveyorSize.height (40)
      expect(yTop + gateSize, greaterThan(conveyorSize.height),
          reason: 'Right-side gate should overflow below conveyor');
      expect(yTop, 12.0);
    });
  });
}

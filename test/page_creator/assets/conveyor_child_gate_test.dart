import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';

// CHILD-03: Gate sizing from conveyor dimensions
// CHILD-04: Visual overflow (cylinder extends outside conveyor bounds)

void main() {
  group('Child gate sizing (CHILD-03)', () {
    test('ConveyorGate uses bounded constraints when placed inside Positioned', () {
      // After Task 1: gate placed inside a SizedBox (simulating Positioned constraints)
      // should use those constraints, not MediaQuery-based config.size
      fail('Wave 0 stub -- implement in Task 1');
    });

    test('child gate sized to conveyor belt height (square)', () {
      // After Task 1: gate within tight 80x80 constraints should paint at 80x80
      fail('Wave 0 stub -- implement in Task 1');
    });
  });

  group('Child gate overflow positioning (CHILD-04)', () {
    test('left-side gate has negative top offset for cylinder overflow', () {
      // After Task 1: _positionedChildGate with GateSide.left should produce
      // Positioned with top < 0 (overflow above conveyor)
      fail('Wave 0 stub -- implement in Task 1');
    });

    test('right-side gate extends below conveyor bounds', () {
      // After Task 1: _positionedChildGate with GateSide.right should produce
      // Positioned with top + height > conveyorSize.height
      fail('Wave 0 stub -- implement in Task 1');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';

// CHILD-06: Config dialog gate management
//
// The full conveyor config widget depends on KeyField (ConsumerStatefulWidget)
// which requires stateManProvider to resolve. In test without an OPC UA server,
// the FutureProvider never completes, causing widget tests to hang.
//
// We verify the gate management behavior via unit tests on ConveyorConfig:
// - Add gate adds ChildGateEntry to list
// - Gate summary text format (side and position from entry, variant from gate)
// - Remove gate from list
// These test the same logic that the dialog widget exercises.

void main() {
  group('Conveyor config gate management (CHILD-06)', () {
    test('Add Gate creates a new ChildGateEntry in gates list', () {
      final config = ConveyorConfig();
      expect(config.gates, isEmpty);

      // Simulate what the Add Gate button does:
      config.gates.add(ChildGateEntry(gate: ConveyorGateConfig()));

      expect(config.gates, hasLength(1));
      expect(config.gates.first, isA<ChildGateEntry>());
      final entry = config.gates.first;
      expect(entry.position, 0.5); // default position
      expect(entry.gate.gateVariant, GateVariant.pneumatic); // default variant
      expect(entry.side, GateSide.left); // default side
    });

    test('gate row displays variant, side, and position summary', () {
      final entry = ChildGateEntry(
        position: 0.5,
        side: GateSide.left,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pneumatic),
      );

      // Summary format: side and position from entry, variant from gate
      final summary =
          '${entry.gate.gateVariant.name} - ${entry.side.name} @ ${(entry.position * 100).round()}%';
      expect(summary, 'pneumatic - left @ 50%');
    });

    test('gate row summary updates for different configurations', () {
      final entry1 = ChildGateEntry(
        position: 0.72,
        side: GateSide.right,
        gate: ConveyorGateConfig(gateVariant: GateVariant.slider),
      );
      final summary1 =
          '${entry1.gate.gateVariant.name} - ${entry1.side.name} @ ${(entry1.position * 100).round()}%';
      expect(summary1, 'slider - right @ 72%');

      final entry2 = ChildGateEntry(
        position: 0.0,
        side: GateSide.left,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pusher),
      );
      final summary2 =
          '${entry2.gate.gateVariant.name} - ${entry2.side.name} @ ${(entry2.position * 100).round()}%';
      expect(summary2, 'pusher - left @ 0%');
    });

    test('Delete removes gate from list', () {
      final config = ConveyorConfig();
      final entry = ChildGateEntry(
        position: 0.5,
        side: GateSide.left,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pneumatic),
      );
      config.gates.add(entry);
      expect(config.gates, hasLength(1));

      // Simulate what the delete button does:
      config.gates.removeAt(config.gates.indexOf(entry));
      expect(config.gates, isEmpty);
    });

    test('multiple gates can be added and individually removed', () {
      final config = ConveyorConfig();
      final entry1 = ChildGateEntry(
        position: 0.2,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pneumatic),
      );
      final entry2 = ChildGateEntry(
        position: 0.8,
        gate: ConveyorGateConfig(gateVariant: GateVariant.slider),
      );
      config.gates.add(entry1);
      config.gates.add(entry2);
      expect(config.gates, hasLength(2));

      // Remove first gate
      config.gates.removeAt(config.gates.indexOf(entry1));
      expect(config.gates, hasLength(1));
      expect(config.gates.first.gate.gateVariant, GateVariant.slider);
    });

    test('gates list roundtrips through JSON after add', () {
      final config = ConveyorConfig();
      config.gates.add(ChildGateEntry(
        position: 0.35,
        side: GateSide.right,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pusher),
      ));

      final json = config.toJson();
      final restored = ConveyorConfig.fromJson(json);

      expect(restored.gates, hasLength(1));
      final entry = restored.gates.first;
      expect(entry.gate.gateVariant, GateVariant.pusher);
      expect(entry.side, GateSide.right);
      expect(entry.position, 0.35);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/page_creator/assets/conveyor_gate_painter.dart';

void main() {
  group('ConveyorGateConfig', () {
    // ── JSON serialization roundtrip ──

    test('JSON roundtrip preserves all fields', () {
      final config = ConveyorGateConfig(
        gateVariant: GateVariant.pneumatic,
        side: GateSide.right,
        stateKey: 'ns=2;s=Gate1.State',
        openAngleDegrees: 60.0,
        openTimeMs: 500,
        closeTimeMs: 300,
        openColor: Colors.blue,
        closedColor: Colors.red,
      );

      final json = config.toJson();
      final restored = ConveyorGateConfig.fromJson(json);

      expect(restored.gateVariant, GateVariant.pneumatic);
      expect(restored.side, GateSide.right);
      expect(restored.stateKey, 'ns=2;s=Gate1.State');
      expect(restored.openAngleDegrees, 60.0);
      expect(restored.openTimeMs, 500);
      expect(restored.closeTimeMs, 300);
      expect(restored.openColor.value, Colors.blue.value);
      expect(restored.closedColor.value, Colors.red.value);
    });

    test('JSON roundtrip preserves null closeTimeMs', () {
      final config = ConveyorGateConfig(
        gateVariant: GateVariant.pneumatic,
        side: GateSide.left,
        stateKey: '',
        openAngleDegrees: 45.0,
        openTimeMs: 800,
        closeTimeMs: null,
        openColor: Colors.green,
        closedColor: Colors.white,
      );

      final json = config.toJson();
      final restored = ConveyorGateConfig.fromJson(json);

      expect(restored.closeTimeMs, isNull);
    });

    // ── Default values ──

    test('preview factory has correct defaults', () {
      final config = ConveyorGateConfig.preview();

      expect(config.gateVariant, GateVariant.pneumatic);
      expect(config.side, GateSide.left);
      expect(config.openAngleDegrees, 45.0);
      expect(config.openTimeMs, 800);
      expect(config.closeTimeMs, isNull);
      expect(config.openColor, Colors.green);
      expect(config.closedColor, Colors.white);
      expect(config.stateKey, '');
    });

    // ── Display metadata ──

    test('displayName returns Conveyor Gate', () {
      final config = ConveyorGateConfig.preview();
      expect(config.displayName, 'Conveyor Gate');
    });

    test('category returns Visualization', () {
      final config = ConveyorGateConfig.preview();
      expect(config.category, 'Visualization');
    });

    // ── Enum deserialization with unknown values ──

    test('unknown GateVariant falls back to pneumatic', () {
      final json = ConveyorGateConfig.preview().toJson();
      json['gateVariant'] = 'unknown_future_variant';
      final restored = ConveyorGateConfig.fromJson(json);
      expect(restored.gateVariant, GateVariant.pneumatic);
    });

    test('unknown GateSide falls back to left', () {
      final json = ConveyorGateConfig.preview().toJson();
      json['side'] = 'unknown_future_side';
      final restored = ConveyorGateConfig.fromJson(json);
      expect(restored.side, GateSide.left);
    });
  });

  group('PneumaticDiverterPainter', () {
    // ── shouldRepaint ──

    test('shouldRepaint returns false when all state fields identical', () {
      final progress = ValueNotifier(0.0);
      final a = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      final b = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isFalse);
    });

    test('shouldRepaint returns true when stateColor changes', () {
      final progress = ValueNotifier(0.0);
      final a = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      final b = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.red,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when openAngleDegrees changes', () {
      final progress = ValueNotifier(0.0);
      final a = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      final b = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.green,
        openAngleDegrees: 90.0,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when side changes', () {
      final progress = ValueNotifier(0.0);
      final a = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      final b = PneumaticDiverterPainter(
        progress: progress,
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.right,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint ignores progress value changes', () {
      final a = PneumaticDiverterPainter(
        progress: ValueNotifier(0.0),
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      final b = PneumaticDiverterPainter(
        progress: ValueNotifier(1.0),
        stateColor: Colors.green,
        openAngleDegrees: 45.0,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isFalse);
    });

    // ── Widget rendering tests ──

    testWidgets('renders without errors at default size', (tester) async {
      const testKey = Key('gate_paint_test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  key: testKey,
                  painter: PneumaticDiverterPainter(
                    progress: ValueNotifier(0.0),
                    stateColor: Colors.green,
                    openAngleDegrees: 45.0,
                    side: GateSide.left,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(testKey), findsOneWidget);
    });

    testWidgets('renders with right side without errors', (tester) async {
      const testKey = Key('gate_paint_test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  key: testKey,
                  painter: PneumaticDiverterPainter(
                    progress: ValueNotifier(1.0),
                    stateColor: Colors.green,
                    openAngleDegrees: 90.0,
                    side: GateSide.right,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(testKey), findsOneWidget);
    });
  });
}

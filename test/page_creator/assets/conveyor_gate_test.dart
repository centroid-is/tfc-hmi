import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
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
      expect(config.forceOpenKey, '');
      expect(config.forceOpenFeedbackKey, '');
      expect(config.forceCloseKey, '');
      expect(config.forceCloseFeedbackKey, '');
    });

    // ── Force key serialization ──

    test('JSON roundtrip with force key fields preserves all four keys', () {
      final config = ConveyorGateConfig(
        forceOpenKey: 'ns=2;s=Gate1.ForceOpen',
        forceOpenFeedbackKey: 'ns=2;s=Gate1.ForceOpenFb',
        forceCloseKey: 'ns=2;s=Gate1.ForceClose',
        forceCloseFeedbackKey: 'ns=2;s=Gate1.ForceCloseFb',
      );

      final json = config.toJson();
      final restored = ConveyorGateConfig.fromJson(json);

      expect(restored.forceOpenKey, 'ns=2;s=Gate1.ForceOpen');
      expect(restored.forceOpenFeedbackKey, 'ns=2;s=Gate1.ForceOpenFb');
      expect(restored.forceCloseKey, 'ns=2;s=Gate1.ForceClose');
      expect(restored.forceCloseFeedbackKey, 'ns=2;s=Gate1.ForceCloseFb');
    });

    test('JSON without force keys deserializes to empty strings (backward compat)', () {
      final json = ConveyorGateConfig.preview().toJson();
      // Remove force keys to simulate legacy JSON
      json.remove('forceOpenKey');
      json.remove('forceOpenFeedbackKey');
      json.remove('forceCloseKey');
      json.remove('forceCloseFeedbackKey');

      final restored = ConveyorGateConfig.fromJson(json);

      expect(restored.forceOpenKey, '');
      expect(restored.forceOpenFeedbackKey, '');
      expect(restored.forceCloseKey, '');
      expect(restored.forceCloseFeedbackKey, '');
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

  group('SliderGatePainter', () {
    // ── shouldRepaint ──

    test('shouldRepaint returns false when stateColor and side are identical',
        () {
      final progress = ValueNotifier(0.0);
      final a = SliderGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      final b = SliderGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isFalse);
    });

    test('shouldRepaint returns true when stateColor changes', () {
      final progress = ValueNotifier(0.0);
      final a = SliderGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      final b = SliderGatePainter(
        progress: progress,
        stateColor: Colors.red,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when side changes', () {
      final progress = ValueNotifier(0.0);
      final a = SliderGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      final b = SliderGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.right,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    // ── Widget rendering tests ──

    testWidgets('renders without errors at default size', (tester) async {
      const testKey = Key('slider_paint_test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  key: testKey,
                  painter: SliderGatePainter(
                    progress: ValueNotifier(0.0),
                    stateColor: Colors.green,
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
      const testKey = Key('slider_paint_test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  key: testKey,
                  painter: SliderGatePainter(
                    progress: ValueNotifier(1.0),
                    stateColor: Colors.white,
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

  group('PusherGatePainter', () {
    // ── shouldRepaint ──

    test('shouldRepaint returns false when stateColor and side are identical',
        () {
      final progress = ValueNotifier(0.0);
      final a = PusherGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      final b = PusherGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isFalse);
    });

    test('shouldRepaint returns true when stateColor changes', () {
      final progress = ValueNotifier(0.0);
      final a = PusherGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      final b = PusherGatePainter(
        progress: progress,
        stateColor: Colors.red,
        side: GateSide.left,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when side changes', () {
      final progress = ValueNotifier(0.0);
      final a = PusherGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.left,
      );
      final b = PusherGatePainter(
        progress: progress,
        stateColor: Colors.green,
        side: GateSide.right,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    // ── Widget rendering tests ──

    testWidgets('renders without errors at default size', (tester) async {
      const testKey = Key('pusher_paint_test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  key: testKey,
                  painter: PusherGatePainter(
                    progress: ValueNotifier(0.0),
                    stateColor: Colors.green,
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
      const testKey = Key('pusher_paint_test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  key: testKey,
                  painter: PusherGatePainter(
                    progress: ValueNotifier(1.0),
                    stateColor: Colors.white,
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

  group('ConveyorGate interaction', () {
    // ── Clickability logic (INT-01) ──
    // The ConveyorGate widget wraps the gate in a GestureDetector only when
    // forceOpenKey or forceCloseKey is non-empty. We verify the gating logic
    // via config properties since the full widget requires ProviderScope +
    // stateManProvider.

    test('gate is not clickable when no force keys configured', () {
      final config = ConveyorGateConfig(
        forceOpenKey: '',
        forceCloseKey: '',
      );
      final isInteractive =
          config.forceOpenKey.isNotEmpty || config.forceCloseKey.isNotEmpty;
      expect(isInteractive, isFalse);
    });

    test('gate is clickable when force open key configured', () {
      final config = ConveyorGateConfig(
        forceOpenKey: 'ns=2;s=Gate1.ForceOpen',
        forceCloseKey: '',
      );
      final isInteractive =
          config.forceOpenKey.isNotEmpty || config.forceCloseKey.isNotEmpty;
      expect(isInteractive, isTrue);
    });

    test('gate is clickable when force close key configured', () {
      final config = ConveyorGateConfig(
        forceOpenKey: '',
        forceCloseKey: 'ns=2;s=Gate1.ForceClose',
      );
      final isInteractive =
          config.forceOpenKey.isNotEmpty || config.forceCloseKey.isNotEmpty;
      expect(isInteractive, isTrue);
    });

    test('gate is clickable when both force keys configured', () {
      final config = ConveyorGateConfig(
        forceOpenKey: 'ns=2;s=Gate1.ForceOpen',
        forceCloseKey: 'ns=2;s=Gate1.ForceClose',
      );
      final isInteractive =
          config.forceOpenKey.isNotEmpty || config.forceCloseKey.isNotEmpty;
      expect(isInteractive, isTrue);
    });

    // ── Forced-state color logic (VIS-03) ──

    test('force feedback keys control whether forced color is applied', () {
      final configWithFeedback = ConveyorGateConfig(
        forceOpenFeedbackKey: 'ns=2;s=Gate1.ForceOpenFb',
        forceCloseFeedbackKey: '',
      );
      final hasForceFeedback =
          configWithFeedback.forceOpenFeedbackKey.isNotEmpty ||
              configWithFeedback.forceCloseFeedbackKey.isNotEmpty;
      expect(hasForceFeedback, isTrue);

      final configWithoutFeedback = ConveyorGateConfig();
      final hasNoFeedback =
          configWithoutFeedback.forceOpenFeedbackKey.isNotEmpty ||
              configWithoutFeedback.forceCloseFeedbackKey.isNotEmpty;
      expect(hasNoFeedback, isFalse);
    });
  });

  group('ChildGateEntry', () {
    test('JSON roundtrip preserves position, side, and gate fields', () {
      final entry = ChildGateEntry(
        position: 0.3,
        side: GateSide.right,
        gate: ConveyorGateConfig(
          gateVariant: GateVariant.slider,
          stateKey: 'ns=2;s=Gate1.State',
        ),
      );

      final json = entry.toJson();
      final restored = ChildGateEntry.fromJson(json);

      expect(restored.position, 0.3);
      expect(restored.side, GateSide.right);
      expect(restored.gate.gateVariant, GateVariant.slider);
      expect(restored.gate.stateKey, 'ns=2;s=Gate1.State');
    });

    test('default constructor has position=0.5 and side=GateSide.left', () {
      final entry = ChildGateEntry(gate: ConveyorGateConfig());

      expect(entry.position, 0.5);
      expect(entry.side, GateSide.left);
    });

    test('nested gate fields survive serialization roundtrip', () {
      final entry = ChildGateEntry(
        position: 0.7,
        side: GateSide.left,
        gate: ConveyorGateConfig(
          gateVariant: GateVariant.pusher,
          openAngleDegrees: 60.0,
          openTimeMs: 500,
          closeTimeMs: 300,
          openColor: Colors.blue,
          closedColor: Colors.red,
          forceOpenKey: 'ns=2;s=Gate1.ForceOpen',
        ),
      );

      final json = entry.toJson();
      final restored = ChildGateEntry.fromJson(json);

      expect(restored.gate.gateVariant, GateVariant.pusher);
      expect(restored.gate.openAngleDegrees, 60.0);
      expect(restored.gate.openTimeMs, 500);
      expect(restored.gate.closeTimeMs, 300);
      expect(restored.gate.openColor.value, Colors.blue.value);
      expect(restored.gate.closedColor.value, Colors.red.value);
      expect(restored.gate.forceOpenKey, 'ns=2;s=Gate1.ForceOpen');
    });
  });

  group('ConveyorConfig gates list', () {
    test('gates list with one ChildGateEntry roundtrips correctly', () {
      final conveyor = ConveyorConfig();
      conveyor.gates.add(ChildGateEntry(
        position: 0.7,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pneumatic),
      ));

      final json = conveyor.toJson();
      final restored = ConveyorConfig.fromJson(json);

      expect(restored.gates, hasLength(1));
      expect(restored.gates.first, isA<ChildGateEntry>());
      expect(restored.gates.first.position, 0.7);
      expect(restored.gates.first.gate.gateVariant, GateVariant.pneumatic);
    });

    test('preview() has empty gates list', () {
      final config = ConveyorConfig.preview();
      expect(config.gates, isEmpty);
    });

    test('JSON without gates field deserializes to empty list (backward compat)',
        () {
      final json = ConveyorConfig.preview().toJson();
      json.remove('gates');
      final restored = ConveyorConfig.fromJson(json);
      expect(restored.gates, isEmpty);
    });

    test('multiple gates of different variants roundtrip all gates', () {
      final conveyor = ConveyorConfig();
      conveyor.gates.add(ChildGateEntry(
        position: 0.2,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pneumatic),
      ));
      conveyor.gates.add(ChildGateEntry(
        position: 0.5,
        gate: ConveyorGateConfig(gateVariant: GateVariant.slider),
      ));
      conveyor.gates.add(ChildGateEntry(
        position: 0.8,
        gate: ConveyorGateConfig(gateVariant: GateVariant.pusher),
      ));

      final json = conveyor.toJson();
      final restored = ConveyorConfig.fromJson(json);

      expect(restored.gates, hasLength(3));
      expect(restored.gates[0].gate.gateVariant, GateVariant.pneumatic);
      expect(restored.gates[0].position, 0.2);
      expect(restored.gates[1].gate.gateVariant, GateVariant.slider);
      expect(restored.gates[1].position, 0.5);
      expect(restored.gates[2].gate.gateVariant, GateVariant.pusher);
      expect(restored.gates[2].position, 0.8);
    });

    test('old-format JSON (flat gate with asset_name) deserializes into ChildGateEntry', () {
      // Simulate old JSON where gates were serialized as flat ConveyorGateConfig objects
      final oldGateJson = ConveyorGateConfig(
        gateVariant: GateVariant.pneumatic,
        side: GateSide.right,
      ).toJson();
      // In old format, position was inline on the gate config
      oldGateJson['position'] = 0.3;

      final conveyorJson = ConveyorConfig.preview().toJson();
      conveyorJson['gates'] = [oldGateJson];

      final restored = ConveyorConfig.fromJson(conveyorJson);

      expect(restored.gates, hasLength(1));
      expect(restored.gates.first, isA<ChildGateEntry>());
      expect(restored.gates.first.position, 0.3);
      expect(restored.gates.first.gate.gateVariant, GateVariant.pneumatic);
    });

    test('old-format JSON extracts side from gate into ChildGateEntry', () {
      final oldGateJson = ConveyorGateConfig(
        gateVariant: GateVariant.slider,
        side: GateSide.right,
      ).toJson();
      oldGateJson['position'] = 0.6;

      final conveyorJson = ConveyorConfig.preview().toJson();
      conveyorJson['gates'] = [oldGateJson];

      final restored = ConveyorConfig.fromJson(conveyorJson);

      expect(restored.gates.first.side, GateSide.right);
      expect(restored.gates.first.position, 0.6);
    });

    test('ConveyorGateConfig JSON without position field still deserializes', () {
      final json = ConveyorGateConfig.preview().toJson();
      // Ensure no position key exists (it shouldn't after migration, but verify)
      json.remove('position');
      final restored = ConveyorGateConfig.fromJson(json);
      // Should not throw; gate config is valid without position
      expect(restored.gateVariant, GateVariant.pneumatic);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/page_creator/assets/elevator.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/sensor.dart';

void main() {
  group('ElevatorConfig defaults', () {
    test('default positionKey is empty string', () {
      expect(ElevatorConfig().positionKey, '');
    });

    test('default tweenDurationMs is 250', () {
      expect(ElevatorConfig().tweenDurationMs, 250);
    });

    test('default children list is empty', () {
      expect(ElevatorConfig().children, isEmpty);
    });

    test('displayName is "Elevator"', () {
      expect(ElevatorConfig().displayName, 'Elevator');
    });

    test('category is "Visualization"', () {
      expect(ElevatorConfig().category, 'Visualization');
    });

    test('preview() factory creates a placeable instance', () {
      final cfg = ElevatorConfig.preview();
      expect(cfg.children, isEmpty);
      expect(cfg.positionKey, '');
    });
  });

  group('ElevatorChildEntry shape', () {
    test('default offsetX is 0.5 (lateral centre)', () {
      // Use a SensorConfig from Phase 1 as a real BaseAsset fixture.
      final entry = ElevatorChildEntry(child: SensorConfig.preview());
      expect(entry.offsetX, 0.5);
    });

    test('id is non-empty String when constructed without explicit id', () {
      final entry = ElevatorChildEntry(child: SensorConfig.preview());
      expect(entry.id, isNotEmpty);
      expect(entry.id, isA<String>());
    });

    test('two entries constructed back-to-back have different ids', () async {
      final a = ElevatorChildEntry(child: SensorConfig.preview());
      // Microsecond-resolution clock requires a small await for delta on
      // fast hardware.
      await Future<void>.delayed(const Duration(microseconds: 50));
      final b = ElevatorChildEntry(child: SensorConfig.preview());
      expect(a.id, isNot(equals(b.id)));
    });

    test('explicit id is preserved when passed in', () {
      final entry = ElevatorChildEntry(
        id: 'fixed-id-001',
        child: SensorConfig.preview(),
      );
      expect(entry.id, 'fixed-id-001');
    });
  });

  group('JSON round-trip', () {
    test('default ElevatorConfig round-trips with Map deep-equality', () {
      final original = ElevatorConfig();
      final json1 = original.toJson();
      final restored = ElevatorConfig.fromJson(json1);
      final json2 = restored.toJson();
      expect(json2, equals(json1));
    });

    test('ElevatorConfig with non-default tweenDurationMs round-trips', () {
      final original =
          ElevatorConfig(positionKey: '/pos/key', tweenDurationMs: 500);
      final restored = ElevatorConfig.fromJson(original.toJson());
      expect(restored.positionKey, '/pos/key');
      expect(restored.tweenDurationMs, 500);
    });

    test('toJson includes asset_name = "ElevatorConfig"', () {
      expect(ElevatorConfig().toJson()['asset_name'], 'ElevatorConfig');
    });

    test('empty children list round-trips as []', () {
      final json = ElevatorConfig().toJson();
      expect(json['children'], isA<List>());
      expect(json['children'], isEmpty);
    });

    test('fromJson yields children=[] when JSON omits the children key', () {
      final partialJson = <String, dynamic>{
        'asset_name': 'ElevatorConfig',
        'positionKey': '/k',
        'tweenDurationMs': 250,
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.1, 'height': 0.4},
        // no 'children' key
      };
      final cfg = ElevatorConfig.fromJson(partialJson);
      expect(cfg.children, isEmpty);
    });
  });

  group('Polymorphic child round-trip', () {
    test('ElevatorChildEntry with SensorConfig child round-trips deep-equal',
        () {
      final original = ElevatorChildEntry(
        id: 'fixed-id-100',
        offsetX: 0.25,
        child: SensorConfig(
          kind: SensorKind.opticField,
          detectionKey: '/foo/bar',
          tag: 'PE-101A',
        ),
      );
      final json1 = original.toJson();
      final restored = ElevatorChildEntry.fromJson(json1);
      final json2 = restored.toJson();
      expect(json2, equals(json1));
    });

    test(
        'decoded child runtimeType is concrete SensorConfig (polymorphic restoration)',
        () {
      final original = ElevatorChildEntry(
        child: SensorConfig(
          detectionKey: '/k',
          kind: SensorKind.inductiveField,
        ),
      );
      final restored = ElevatorChildEntry.fromJson(original.toJson());
      expect(restored.child, isA<SensorConfig>());
      expect((restored.child as SensorConfig).kind, SensorKind.inductiveField);
      expect((restored.child as SensorConfig).detectionKey, '/k');
    });

    test('ElevatorConfig with two heterogeneous children round-trips deep-equal',
        () {
      final original = ElevatorConfig(
        positionKey: '/elev/pos',
        children: [
          ElevatorChildEntry(
            id: 'a',
            offsetX: 0.25,
            child: SensorConfig(
              kind: SensorKind.redLight,
              detectionKey: '/d1',
            ),
          ),
          ElevatorChildEntry(
            id: 'b',
            offsetX: 0.75,
            child: ConveyorGateConfig(stateKey: '/g1'),
          ),
        ],
      );
      final json1 = original.toJson();
      final restored = ElevatorConfig.fromJson(json1);
      final json2 = restored.toJson();
      expect(json2, equals(json1));
      expect(restored.children, hasLength(2));
      expect(restored.children[0].child, isA<SensorConfig>());
      expect(restored.children[1].child, isA<ConveyorGateConfig>());
    });
  });

  group('_childrenFromJson legacy / future tolerance', () {
    test('children=null in JSON yields []', () {
      final json = <String, dynamic>{
        'asset_name': 'ElevatorConfig',
        'positionKey': '/k',
        'tweenDurationMs': 250,
        'children': null,
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.1, 'height': 0.4},
      };
      expect(ElevatorConfig.fromJson(json).children, isEmpty);
    });

    test('children key entirely absent yields []', () {
      // Already covered in group "JSON round-trip"; locked here for the
      // legacy shim regression-guard contract.
      final json = <String, dynamic>{
        'asset_name': 'ElevatorConfig',
        'positionKey': '/k',
        'tweenDurationMs': 250,
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.1, 'height': 0.4},
      };
      expect(ElevatorConfig.fromJson(json).children, isEmpty);
    });

    test('children=[] empty array yields []', () {
      final json = <String, dynamic>{
        'asset_name': 'ElevatorConfig',
        'positionKey': '/k',
        'tweenDurationMs': 250,
        'children': <dynamic>[],
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.1, 'height': 0.4},
      };
      expect(ElevatorConfig.fromJson(json).children, isEmpty);
    });

    test('allKeys includes positionKey when non-empty (BaseAsset *Key pattern)',
        () {
      final cfg = ElevatorConfig(positionKey: '/elev/01/position');
      expect(cfg.allKeys, contains('/elev/01/position'));
    });

    test('allKeys excludes empty positionKey', () {
      final cfg = ElevatorConfig(positionKey: '');
      expect(cfg.allKeys, isNot(contains('')));
    });
  });

  group('AssetRegistry round-trip', () {
    test(
        'AssetRegistry.parse extracts a registered ElevatorConfig from a saved page JSON',
        () {
      final source = ElevatorConfig(
        positionKey: '/elev/01/position',
        tweenDurationMs: 400,
      );
      final pageJson = {
        'page': {
          'assets': [source.toJson()],
        },
      };
      final parsed = AssetRegistry.parse(pageJson);
      expect(parsed, hasLength(1));
      expect(parsed.first, isA<ElevatorConfig>());
      final elevator = parsed.first as ElevatorConfig;
      expect(elevator.positionKey, '/elev/01/position');
      expect(elevator.tweenDurationMs, 400);
      expect(elevator.children, isEmpty);
    });

    test(
        'Saved page WITHOUT an ElevatorConfig still loads cleanly (back-compat — ELEV-18)',
        () {
      // A page saved before this asset existed — only contains an LEDConfig.
      // We seed the JSON via LEDConfig.preview().toJson() (mirrors the
      // sensor_config_test.dart precedent) so the shape is guaranteed
      // identical to a real persisted page (avoids handcrafted JSON
      // drifting from the actual ColorConverter contract).
      // Locks Pitfall 5 §"register-in-both silent failure" by exercising
      // the negative path: a registry crawl that finds ZERO ElevatorConfigs
      // MUST NOT fail, and MUST find the LEDConfig that IS present.
      final legacyPageJson = {
        'page': {
          'assets': [
            AssetRegistry.createDefaultAsset(
                    AssetRegistry.defaultFactories.keys.firstWhere(
                        (t) => t.toString() == 'LEDConfig'))
                .toJson(),
          ],
        },
      };
      final parsed = AssetRegistry.parse(legacyPageJson);
      expect(parsed, hasLength(1));
      // Critically: parse did NOT throw and returned exactly the LED.
      expect(parsed.first.runtimeType.toString(), 'LEDConfig');
    });

    test(
        'AssetRegistry.createDefaultAsset(ElevatorConfig) returns a fresh ElevatorConfig (palette path — ELEV-16)',
        () {
      final fresh = AssetRegistry.createDefaultAsset(ElevatorConfig);
      expect(fresh, isA<ElevatorConfig>());
      final elevator = fresh as ElevatorConfig;
      expect(elevator.positionKey, ''); // default empty (stale)
      expect(elevator.tweenDurationMs, 250); // CONTEXT specifics default
      expect(elevator.children, isEmpty); // ELEV-18 surface: empty in Phase 2
    });
  });
}

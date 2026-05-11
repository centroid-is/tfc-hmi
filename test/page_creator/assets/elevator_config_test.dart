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

    // Plan 260511-ehy: vertical anchor offset (offsetY). Default 0.0 keeps the
    // child's bottom on the platform (Plan 260511-dxa invariant). Positive
    // raises the child above the platform; negative lowers it below.
    test('default offsetY is 0.0 (bottom-on-platform anchor) [260511-ehy]', () {
      final entry = ElevatorChildEntry(child: SensorConfig.preview());
      expect(entry.offsetY, 0.0);
    });

    test('constructed offsetY value is preserved on the instance [260511-ehy]',
        () {
      final entry = ElevatorChildEntry(
        child: SensorConfig.preview(),
        offsetY: 0.7,
      );
      expect(entry.offsetY, 0.7);
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
        'ElevatorChildEntry with non-default offsetY round-trips deep-equal '
        '[260511-ehy]', () {
      // offsetY is part of the schema as of Plan 260511-ehy. Round-trip must
      // be bit-perfect: deep-equal JSON before/after AND the field value must
      // survive verbatim.
      final original = ElevatorChildEntry(
        id: 'fixed-y',
        offsetX: 0.25,
        offsetY: 0.7,
        child: SensorConfig(detectionKey: '/k'),
      );
      final json1 = original.toJson();
      final restored = ElevatorChildEntry.fromJson(json1);
      final json2 = restored.toJson();
      expect(json2, equals(json1),
          reason: 'toJson(fromJson(toJson)) must be a fixed point.');
      expect(restored.offsetY, 0.7,
          reason: 'fromJson must restore offsetY=0.7 verbatim.');
    });

    test(
        'legacy JSON without offsetY restores to offsetY=0.0 (back-compat) '
        '[260511-ehy]', () {
      // Saved pages predating Plan 260511-ehy do NOT carry an `offsetY` key.
      // The `@JsonKey(defaultValue: 0.0)` annotation must fill the gap so
      // those pages keep loading bit-identically to the pre-change behaviour.
      final legacyJson = <String, dynamic>{
        'id': 'legacy',
        'offsetX': 0.5,
        'child': SensorConfig.preview().toJson(),
        // no 'offsetY' key — this is the back-compat surface.
      };
      final entry = ElevatorChildEntry.fromJson(legacyJson);
      expect(entry.offsetY, 0.0,
          reason: 'Legacy JSON without offsetY must default to 0.0.');
      // And a subsequent toJson emits the offsetY key (now part of the
      // canonical shape), with the default value preserved.
      final reJson = entry.toJson();
      expect(reJson['offsetY'], 0.0,
          reason:
              'toJson must emit offsetY:0.0 after a legacy fromJson — the '
              'canonical schema now always carries the field.');
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

    test('ElevatorConfig with simulate=true round-trips and preserves field (QUAL-08)',
        () {
      // Plan 04-04 — simulate motion toggle. The field is `bool?` with
      // `@JsonKey(includeIfNull: false)` so the JSON round-trip must:
      //   - emit `simulate: true` when set
      //   - restore `simulate == true` after fromJson
      //   - omit the key entirely when null (default)
      final original = ElevatorConfig(
        positionKey: '/elev/pos',
        simulate: true,
      );
      final json1 = original.toJson();
      expect(json1['simulate'], true,
          reason: 'simulate=true must serialise as the boolean literal true.');
      final restored = ElevatorConfig.fromJson(json1);
      expect(restored.simulate, true,
          reason: 'fromJson must restore simulate=true after round-trip.');
      // Round-trip stability — second toJson must deep-equal the first.
      expect(restored.toJson(), equals(json1));
    });

    test('ElevatorConfig with simulate=null omits the key from toJson (QUAL-08)',
        () {
      // Default null state: includeIfNull:false means the JSON map MUST NOT
      // carry a `simulate` key at all. Locks the back-compat contract — old
      // saved pages that pre-date Plan 04-04 keep round-tripping bit-perfectly.
      final cfg = ElevatorConfig(positionKey: '/elev/pos');
      expect(cfg.simulate, isNull);
      final json = cfg.toJson();
      expect(json.containsKey('simulate'), isFalse,
          reason:
              'simulate=null must be omitted from toJson (back-compat with '
              'pre-Plan-04-04 saved pages).');
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

  // ---------------------------------------------------------------------------
  // allKeys flat-map (ELEV-13)
  //
  // Locks the contract: ElevatorConfig.allKeys returns positionKey (if
  // non-empty) concatenated with every child's allKeys flat-mapped, with
  // duplicates removed. This is required because the default
  // BaseAsset.allKeys (common.dart) only introspects top-level JSON field
  // names and does NOT recurse into the children wrapper list — so without
  // an override, alarms/collectors silently miss every key configured on
  // a child asset (ARCHITECTURE Anti-Pattern 6).
  //
  // Sensor field names hardcoded from sensor.dart (Phase 1):
  //   - detectionKey, risingEdgeDelayKey, fallingEdgeDelayKey
  // ---------------------------------------------------------------------------
  group('allKeys flat-map (ELEV-13)', () {
    test('empty config returns empty list (back-compat)', () {
      // Default ElevatorConfig: positionKey='', children=[]. The allKeys
      // result must be empty — locking back-compat for Phase-2 saved pages
      // that have no children and no positionKey configured yet.
      final cfg = ElevatorConfig();
      expect(cfg.allKeys, isEmpty);
    });

    test('positionKey only — no children', () {
      // Trivial case: only positionKey set. The override must include it.
      final cfg = ElevatorConfig(positionKey: 'lift.position');
      expect(cfg.allKeys, equals(['lift.position']));
    });

    test('one Sensor child surfaces all sensor keys', () {
      // The critical RED case: default BaseAsset.allKeys does NOT recurse
      // into the children list, so without the override the sensor's
      // detection/risingEdgeDelay/fallingEdgeDelay keys are dropped.
      final cfg = ElevatorConfig(
        positionKey: 'lift.pos',
        children: [
          ElevatorChildEntry(
            child: SensorConfig(
              detectionKey: 'sensor.detect',
              risingEdgeDelayKey: 'sensor.rising',
              fallingEdgeDelayKey: 'sensor.falling',
            ),
          ),
        ],
      );
      expect(
        cfg.allKeys,
        unorderedEquals(<String>[
          'lift.pos',
          'sensor.detect',
          'sensor.rising',
          'sensor.falling',
        ]),
      );
    });

    test('multiple children flat-map all keys, parent first', () {
      // Ordering rule per CONTEXT §Editor & allKeys:
      //   [positionKey?, ...children[0].allKeys, ...children[1].allKeys, ...]
      final childA = SensorConfig(
        detectionKey: 'a.detect',
        risingEdgeDelayKey: 'a.rising',
        fallingEdgeDelayKey: 'a.falling',
      );
      final childB = SensorConfig(
        detectionKey: 'b.detect',
        risingEdgeDelayKey: 'b.rising',
        fallingEdgeDelayKey: 'b.falling',
      );
      final cfg = ElevatorConfig(
        positionKey: 'lift.pos',
        children: [
          ElevatorChildEntry(child: childA),
          ElevatorChildEntry(child: childB),
        ],
      );
      // Parent positionKey appears first.
      expect(cfg.allKeys.first, 'lift.pos');
      // Length: positionKey + every key from both children, no truncation.
      expect(
        cfg.allKeys.length,
        1 + childA.allKeys.length + childB.allKeys.length,
      );
      // All expected keys present (set semantics — order beyond first is
      // implementation-incidental within insertion order).
      expect(
        cfg.allKeys,
        unorderedEquals(<String>[
          'lift.pos',
          ...childA.allKeys,
          ...childB.allKeys,
        ]),
      );
    });

    test('duplicate keys are deduplicated', () {
      // Same key configured on parent positionKey AND a child detectionKey
      // must appear exactly once in the result — locks the dedup invariant
      // (T-03-06 mitigation).
      final cfg = ElevatorConfig(
        positionKey: 'shared',
        children: [
          ElevatorChildEntry(
            child: SensorConfig(detectionKey: 'shared'),
          ),
        ],
      );
      expect(cfg.allKeys.where((k) => k == 'shared').length, 1);
    });

    test('empty positionKey is filtered out', () {
      // A blank positionKey must NOT appear in the result — alarms/collectors
      // would otherwise try to subscribe to '' (T-03-06 mitigation).
      final cfg = ElevatorConfig(
        positionKey: '',
        children: [
          ElevatorChildEntry(
            child: SensorConfig(detectionKey: 'd'),
          ),
        ],
      );
      expect(cfg.allKeys, isNot(contains('')));
      expect(cfg.allKeys, contains('d'));
    });
  });
}

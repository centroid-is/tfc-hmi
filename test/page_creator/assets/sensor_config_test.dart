import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/sensor.dart';

void main() {
  group('SensorConfig defaults', () {
    test('default kind is SensorKind.redLight', () {
      final config = SensorConfig();
      expect(config.kind, SensorKind.redLight);
    });

    test('default activeColor is Colors.green', () {
      final config = SensorConfig();
      expect(config.activeColor, Colors.green);
    });

    test('default inactiveColor is Colors.grey.shade400', () {
      final config = SensorConfig();
      expect(config.inactiveColor.value, Colors.grey.shade400.value);
    });

    test('default invertActivePolarity is false', () {
      final config = SensorConfig();
      expect(config.invertActivePolarity, isFalse);
    });

    test('default detectionKey is empty string', () {
      final config = SensorConfig();
      expect(config.detectionKey, '');
    });

    test('default risingEdgeDelayKey is empty string', () {
      final config = SensorConfig();
      expect(config.risingEdgeDelayKey, '');
    });

    test('default fallingEdgeDelayKey is empty string', () {
      final config = SensorConfig();
      expect(config.fallingEdgeDelayKey, '');
    });

    test('default tag is null', () {
      final config = SensorConfig();
      expect(config.tag, isNull);
    });

    test('displayName is "Sensor"', () {
      final config = SensorConfig();
      expect(config.displayName, 'Sensor');
    });

    test('category is "Visualization"', () {
      final config = SensorConfig();
      expect(config.category, 'Visualization');
    });
  });

  group('SensorKind enum', () {
    test('SensorKind has exactly three values', () {
      expect(SensorKind.values.length, 3);
    });

    test('SensorKind values are redLight, opticField, inductiveField', () {
      final names = SensorKind.values.map((v) => v.name).toSet();
      expect(names, {'redLight', 'opticField', 'inductiveField'});
    });
  });

  group('JSON round-trip', () {
    test('round-trips every field', () {
      final config = SensorConfig(
        kind: SensorKind.opticField,
        detectionKey: '/foo/bar',
        invertActivePolarity: true,
        risingEdgeDelayKey: '/r',
        fallingEdgeDelayKey: '/f',
        activeColor: Colors.cyan,
        inactiveColor: Colors.orange,
        tag: 'PE-101A',
      );

      final json = config.toJson();
      final restored = SensorConfig.fromJson(json);
      final reEncoded = restored.toJson();

      expect(reEncoded, equals(json));
    });

    test('toJson includes asset_name = "SensorConfig"', () {
      final config = SensorConfig();
      expect(config.toJson()['asset_name'], 'SensorConfig');
    });
  });

  group('Legacy JSON tolerance', () {
    test('loads with sensible defaults when invertActivePolarity is missing',
        () {
      final legacyJson = <String, dynamic>{
        'asset_name': 'SensorConfig',
        'kind': 'redLight',
        'detectionKey': '/legacy/key',
        // no invertActivePolarity
        // no risingEdgeDelayKey / fallingEdgeDelayKey
        // no tag
        // no activeColor / inactiveColor
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final config = SensorConfig.fromJson(legacyJson);
      expect(config.invertActivePolarity, isFalse);
      expect(config.risingEdgeDelayKey, '');
      expect(config.fallingEdgeDelayKey, '');
      expect(config.tag, isNull);
      expect(config.activeColor, Colors.green);
      expect(config.inactiveColor.value, Colors.grey.shade400.value);
    });

    test('unknown SensorKind value falls back to redLight (forward-compat)',
        () {
      final futureKindJson = <String, dynamic>{
        'asset_name': 'SensorConfig',
        'kind': 'thermalSensor', // hypothetical future kind
        'detectionKey': '/k',
        'invertActivePolarity': false,
        'risingEdgeDelayKey': '',
        'fallingEdgeDelayKey': '',
        'activeColor': {
          'red': 0.298,
          'green': 0.686,
          'blue': 0.314,
          'alpha': 1.0,
        },
        'inactiveColor': {
          'red': 0.741,
          'green': 0.741,
          'blue': 0.741,
          'alpha': 1.0,
        },
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final config = SensorConfig.fromJson(futureKindJson);
      expect(config.kind, SensorKind.redLight); // unknownEnumValue fallback
    });

    test('allKeys returns detection + edge-delay keys', () {
      final config = SensorConfig(
        detectionKey: '/d',
        risingEdgeDelayKey: '/r',
        fallingEdgeDelayKey: '/f',
        tag: 'PE-101A',
      );
      final keys = config.allKeys.toSet();
      expect(keys, containsAll({'/d', '/r', '/f'}));
      // T-01-03 (Information Disclosure): tag must NOT be classified as a key.
      expect(keys, isNot(contains('PE-101A')));
    });
  });

  group('AssetRegistry round-trip', () {
    test(
        'AssetRegistry.parse extracts a registered SensorConfig from a saved page JSON',
        () {
      final source = SensorConfig(
        kind: SensorKind.opticField,
        detectionKey: '/foo',
        tag: 'PE-202B',
      );
      final pageJson = {
        'page': {
          'assets': [source.toJson()],
        },
      };
      final parsed = AssetRegistry.parse(pageJson);
      expect(parsed, hasLength(1));
      expect(parsed.first, isA<SensorConfig>());
      final sensor = parsed.first as SensorConfig;
      expect(sensor.kind, SensorKind.opticField);
      expect(sensor.detectionKey, '/foo');
      expect(sensor.tag, 'PE-202B');
    });

    test(
        'Saved page WITHOUT a SensorConfig still loads cleanly (back-compat — SENS-16)',
        () {
      // A page saved before this asset existed — only contains an LEDConfig.
      // We seed the JSON via LEDConfig.preview().toJson() so the shape is
      // guaranteed identical to a real persisted page (avoids handcrafted
      // JSON drifting from the actual ColorConverter contract).
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
      // Critically: parse did NOT throw and returned exactly the LED — the
      // registry's SensorConfig entry did not interfere with non-Sensor JSON.
      expect(parsed.first.runtimeType.toString(), 'LEDConfig');
    });

    test(
        'AssetRegistry.createDefaultAsset(SensorConfig) returns a fresh SensorConfig (palette path — SENS-01)',
        () {
      final fresh = AssetRegistry.createDefaultAsset(SensorConfig);
      expect(fresh, isA<SensorConfig>());
      expect((fresh as SensorConfig).kind, SensorKind.redLight); // default kind
    });
  });

  group('sensorIsActive polarity inversion', () {
    test(
      'rawBool=true,  invert=false -> true',
      () => expect(
        sensorIsActive(rawBool: true, invertActivePolarity: false),
        isTrue,
      ),
    );
    test(
      'rawBool=false, invert=false -> false',
      () => expect(
        sensorIsActive(rawBool: false, invertActivePolarity: false),
        isFalse,
      ),
    );
    test(
      'rawBool=true,  invert=true  -> false',
      () => expect(
        sensorIsActive(rawBool: true, invertActivePolarity: true),
        isFalse,
      ),
    );
    test(
      'rawBool=false, invert=true  -> true',
      () => expect(
        sensorIsActive(rawBool: false, invertActivePolarity: true),
        isTrue,
      ),
    );
  });
}

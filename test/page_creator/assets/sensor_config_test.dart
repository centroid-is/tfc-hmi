import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

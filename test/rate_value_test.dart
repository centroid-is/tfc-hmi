import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/rate_value.dart';

void main() {
  group('RateValueConfig serialization', () {
    test('round-trip JSON preserves all fields', () {
      final config = RateValueConfig(
        key: 'weigher.weight',
        textColor: const Color(0xFF0000FF),
        pollInterval: const Duration(seconds: 30),
        defaultInterval: 10,
        intervalPresets: [1, 5, 10, 30],
        graphHeader: 'Throughput',
        howMany: 30,
        unit: 'kg',
        showPerHour: true,
        decimalPlaces: 2,
      );
      config.text = 'Weight Rate';
      config.intervalVariable = 'rateInterval';

      final json = config.toJson();
      final jsonStr = jsonEncode(json);
      final restored =
          RateValueConfig.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

      expect(restored.key, 'weigher.weight');
      expect(restored.pollInterval.inSeconds, 30);
      expect(restored.defaultInterval, 10);
      expect(restored.intervalPresets, [1, 5, 10, 30]);
      expect(restored.graphHeader, 'Throughput');
      expect(restored.howMany, 30);
      expect(restored.unit, 'kg');
      expect(restored.showPerHour, true);
      expect(restored.decimalPlaces, 2);
      expect(restored.text, 'Weight Rate');
      expect(restored.intervalVariable, 'rateInterval');
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {
        'asset_name': 'RateValueConfig',
        'key': 'test.key',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final config = RateValueConfig.fromJson(json);
      expect(config.key, 'test.key');
      expect(config.decimalPlaces, 1);
      expect(config.pollInterval.inSeconds, 15);
      expect(config.defaultInterval, 1);
      expect(config.intervalPresets, [1, 5, 10, 30, 60]);
      expect(config.howMany, 20);
      expect(config.unit, 'kg');
      expect(config.showPerHour, false);
    });
  });

  group('RateValueConfig', () {
    test('preview has sensible defaults', () {
      final config = RateValueConfig.preview();
      expect(config.key, 'key');
      expect(config.decimalPlaces, 1);
      expect(config.defaultInterval, 1);
      expect(config.displayName, 'Rate Value');
      expect(config.category, 'Text & Numbers');
      expect(config.unit, 'kg');
    });

    test('displayName and category are correct', () {
      final config = RateValueConfig(key: 'test');
      expect(config.displayName, 'Rate Value');
      expect(config.category, 'Text & Numbers');
    });
  });
}

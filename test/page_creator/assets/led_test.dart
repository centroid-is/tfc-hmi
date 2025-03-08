import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/common.dart';

void main() {
  group('LEDConfig', () {
    test('toJson serializes all fields correctly', () {
      final config = LEDConfig(
        key: 'test_led',
        onColor: const Color.fromARGB(255, 0, 255, 0),
        offColor: const Color.fromARGB(255, 255, 0, 0),
        textPos: TextPos.above,
        size: const Size(20, 20),
      );

      final json = config.toJson();

      expect(json, {
        'asset_name': 'LEDConfig',
        'coordinates': {
          'x': 0.0,
          'y': 0.0,
          'angle': null,
        },
        'key': 'test_led',
        'on_color': {
          'red': 0.0,
          'green': 1.0,
          'blue': 0.0,
        },
        'off_color': {
          'red': 1.0,
          'green': 0.0,
          'blue': 0.0,
        },
        'text_pos': 'above',
        'size': {
          'width': 20.0,
          'height': 20.0,
        },
      });
    });
  });
}

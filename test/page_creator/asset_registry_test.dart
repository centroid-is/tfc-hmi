import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/button.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/text.dart';
import 'package:tfc/page_creator/assets/common.dart';

void main() {
  group('AssetRegistry.createDefaultAssetByName', () {
    test('returns ButtonConfig for "ButtonConfig"', () {
      final asset = AssetRegistry.createDefaultAssetByName('ButtonConfig');
      expect(asset, isNotNull);
      expect(asset, isA<ButtonConfig>());
    });

    test('returns LEDConfig for "LEDConfig"', () {
      final asset = AssetRegistry.createDefaultAssetByName('LEDConfig');
      expect(asset, isNotNull);
      expect(asset, isA<LEDConfig>());
    });

    test('returns NumberConfig for "NumberConfig"', () {
      final asset = AssetRegistry.createDefaultAssetByName('NumberConfig');
      expect(asset, isNotNull);
      expect(asset, isA<NumberConfig>());
    });

    test('returns TextAssetConfig for "TextAssetConfig"', () {
      final asset = AssetRegistry.createDefaultAssetByName('TextAssetConfig');
      expect(asset, isNotNull);
      expect(asset, isA<TextAssetConfig>());
    });

    test('returns null for unknown type', () {
      final asset = AssetRegistry.createDefaultAssetByName('NonExistentConfig');
      expect(asset, isNull);
    });

    test('returns null for empty string', () {
      final asset = AssetRegistry.createDefaultAssetByName('');
      expect(asset, isNull);
    });

    test('key can be set via dynamic dispatch', () {
      final asset = AssetRegistry.createDefaultAssetByName('ButtonConfig');
      expect(asset, isNotNull);
      (asset as dynamic).key = 'ceiling.lights.1';
      expect((asset as ButtonConfig).key, 'ceiling.lights.1');
    });

    test('text and textPos can be set on default asset', () {
      final asset = AssetRegistry.createDefaultAssetByName('ButtonConfig');
      expect(asset, isNotNull);
      asset!.text = 'Bathroom Ceiling';
      asset.textPos = TextPos.below;
      expect(asset.text, 'Bathroom Ceiling');
      expect(asset.textPos, TextPos.below);
    });

    test('coordinates can be set on default asset', () {
      final asset = AssetRegistry.createDefaultAssetByName('ButtonConfig');
      expect(asset, isNotNull);
      asset!.coordinates = Coordinates(x: 0.565, y: 0.175);
      expect(asset.coordinates.x, 0.565);
      expect(asset.coordinates.y, 0.175);
    });
  });

  group('AssetRegistry.parse with minimal MCP JSON', () {
    test('fails to parse ButtonConfig without required fields', () {
      // This is the root cause of the bug: AssetRegistry.parse calls
      // ButtonConfig.fromJson which requires outward_color, inward_color,
      // button_type, coordinates, size -- none of which are in the MCP
      // proposal's minimal JSON.
      expect(
        () => AssetRegistry.parse({
          'assets': [
            {
              'asset_name': 'ButtonConfig',
              'key': 'ceiling.lights.1',
              'title': 'Bathroom Ceiling',
            },
          ],
        }),
        throwsA(anything),
      );
    });

    test('succeeds with fully populated ButtonConfig JSON', () {
      final assets = AssetRegistry.parse({
        'assets': [
          {
            'asset_name': 'ButtonConfig',
            'key': 'ceiling.lights.1',
            'text': 'Bathroom Ceiling',
            'outward_color': {
              'red': 0.3,
              'green': 0.7,
              'blue': 0.3,
              'alpha': 1.0
            },
            'inward_color': {
              'red': 0.6,
              'green': 0.6,
              'blue': 0.6,
              'alpha': 1.0
            },
            'button_type': 'circle',
            'coordinates': {'x': 0.565, 'y': 0.175},
            'size': {'width': 0.03, 'height': 0.03},
          },
        ],
      });
      expect(assets, hasLength(1));
      expect(assets.first, isA<ButtonConfig>());
      expect((assets.first as ButtonConfig).key, 'ceiling.lights.1');
    });
  });
}

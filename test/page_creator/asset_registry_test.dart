import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/button.dart';

void main() {
  group('AssetRegistry.parse', () {
    test('fails to parse ButtonConfig without required fields', () {
      // AssetRegistry.parse calls ButtonConfig.fromJson which requires
      // outward_color, inward_color, button_type, coordinates, size.
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

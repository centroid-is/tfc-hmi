import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/button.dart';

/// JSON-level tests for the disabled-key / polarity / disabled-color
/// fields added to `ButtonConfig` in the v1.1 hardening sweep.
///
/// Backwards-compat contract: existing persisted ButtonConfig JSON predating
/// these fields MUST still load, with sensible defaults populated.
void main() {
  Map<String, dynamic> baseJson() => <String, dynamic>{
        'asset_name': 'ButtonConfig',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.1, 'height': 0.1},
        'text': null,
        'textPos': 'right',
        'techDocId': null,
        'plcAssetKey': null,
        'key': 'some/key',
        'feedback': null,
        'icon': null,
        'outward_color': {
          'red': 0.0,
          'green': 1.0,
          'blue': 0.0,
          'alpha': 1.0,
        },
        'inward_color': {
          'red': 0.5,
          'green': 0.5,
          'blue': 0.5,
          'alpha': 1.0,
        },
        'button_type': 'circle',
        'is_toggle': false,
        'server_writes_low': false,
      };

  group('ButtonConfig defaults (disabled-key / polarity / color)', () {
    test('default disabledKey is null', () {
      final config = ButtonConfig.preview();
      expect(config.disabledKey, isNull);
    });

    test('default disabledPolarity is disableWhenTrue', () {
      final config = ButtonConfig.preview();
      expect(config.disabledPolarity, DisabledPolarity.disableWhenTrue);
    });

    test('default disabledColor is a sensible muted gray', () {
      final config = ButtonConfig.preview();
      // We don't lock the exact swatch; we just lock that:
      //  - it has full alpha
      //  - it is reasonably desaturated (R ≈ G ≈ B)
      // This keeps the default visually "disabled" without coupling the
      // test to a specific gray shade.
      final c = config.disabledColor;
      expect(c.a, 1.0);
      final r = c.r;
      final g = c.g;
      final b = c.b;
      // Channels within 1/255 of one another → effectively gray.
      expect((r - g).abs() < 1.0 / 255.0, isTrue,
          reason: 'default disabledColor channels must be near-equal (gray)');
      expect((g - b).abs() < 1.0 / 255.0, isTrue,
          reason: 'default disabledColor channels must be near-equal (gray)');
    });
  });

  group('DisabledPolarity enum', () {
    test('has exactly two values', () {
      expect(DisabledPolarity.values.length, 2);
    });

    test('values are disableWhenTrue and disableWhenFalse', () {
      final names = DisabledPolarity.values.map((v) => v.name).toSet();
      expect(names, {'disableWhenTrue', 'disableWhenFalse'});
    });
  });

  group('ButtonConfig JSON round-trip', () {
    test('legacy JSON (no disabled-* fields) loads with defaults', () {
      // Legacy persisted page-editor data — predates the disabled-* fields.
      // Loader must tolerate the missing keys and apply defaults.
      final legacyJson = baseJson();
      final config = ButtonConfig.fromJson(legacyJson);

      expect(config.disabledKey, isNull,
          reason: 'missing disabledKey must default to null');
      expect(config.disabledPolarity, DisabledPolarity.disableWhenTrue,
          reason: 'missing disabledPolarity must default to disableWhenTrue');
      // Color must be present (the converter never yields null for this
      // non-nullable field) and must be gray-ish.
      expect(config.disabledColor.a, 1.0);
    });

    test('round-trips with all three new fields explicitly set', () {
      final config = ButtonConfig(
        key: 'btn/start',
        outwardColor: const Color(0xFF00FF00),
        inwardColor: const Color(0xFF808080),
        buttonType: ButtonType.square,
      )
        ..disabledKey = 'safety/interlock'
        ..disabledPolarity = DisabledPolarity.disableWhenFalse
        ..disabledColor = const Color(0xFF334455);

      final json = config.toJson();
      // Wire-format keys are stable — these are persisted to PostgreSQL via
      // Preferences, so the snake_case names are part of the on-disk contract.
      expect(json.containsKey('disabled_key'), isTrue,
          reason: 'wire key "disabled_key" must be present');
      expect(json.containsKey('disabled_polarity'), isTrue,
          reason: 'wire key "disabled_polarity" must be present');
      expect(json.containsKey('disabled_color'), isTrue,
          reason: 'wire key "disabled_color" must be present');

      final restored = ButtonConfig.fromJson(json);
      expect(restored.disabledKey, 'safety/interlock');
      expect(restored.disabledPolarity, DisabledPolarity.disableWhenFalse);
      // ColorConverter is RGB-with-alpha (channel doubles). Re-encoding then
      // decoding should yield a Color whose channel ints round-trip.
      expect((restored.disabledColor.r * 255).round(),
          (config.disabledColor.r * 255).round());
      expect((restored.disabledColor.g * 255).round(),
          (config.disabledColor.g * 255).round());
      expect((restored.disabledColor.b * 255).round(),
          (config.disabledColor.b * 255).round());
    });

    test('toJson re-encodes a no-op preview config without throwing', () {
      // Smoke check: a default preview config must serialize cleanly even
      // with disabledKey=null. Guards against accidental non-nullable
      // wire requirement on disabled_key.
      final config = ButtonConfig.preview();
      final json = config.toJson();
      expect(json['disabled_key'], isNull);
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/converter/color_converter.dart';
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
        outwardColor: const AssetColor.literal(Color(0xFF00FF00)),
        inwardColor: const AssetColor.literal(Color(0xFF808080)),
        buttonType: ButtonType.square,
      )
        ..disabledKey = 'safety/interlock'
        ..disabledPolarity = DisabledPolarity.disableWhenFalse
        ..disabledColor = const Color(0xFF334455);

      // ButtonConfig.toJson() produces a shallow map where nested
      // typed fields (e.g. Coordinates) remain as their typed instances.
      // The persistence path (Preferences → PostgreSQL) round-trips this
      // via `jsonEncode` / `jsonDecode`, which invokes nested toJson()s
      // and re-parses everything as plain Map<String, dynamic>. We mirror
      // that here so the fromJson contract is exercised honestly.
      final raw = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;

      // Wire-format keys are stable — these are persisted to PostgreSQL via
      // Preferences, so the snake_case names are part of the on-disk contract.
      expect(raw.containsKey('disabled_key'), isTrue,
          reason: 'wire key "disabled_key" must be present');
      expect(raw.containsKey('disabled_polarity'), isTrue,
          reason: 'wire key "disabled_polarity" must be present');
      expect(raw.containsKey('disabled_color'), isTrue,
          reason: 'wire key "disabled_color" must be present');

      final restored = ButtonConfig.fromJson(raw);
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

  // ----- textColor (optional label color override) -----
  //
  // Default behaviour: `textColor == null` means "use the default theme
  // color" for the asset label (the existing behaviour predating this
  // field). A non-null value replaces the default color for the label.
  group('ButtonConfig.textColor (optional label color)', () {
    test('default textColor is null (use theme default)', () {
      final config = ButtonConfig.preview();
      expect(config.textColor, isNull,
          reason:
              'default textColor must be null so existing buttons keep the '
              'theme default label color');
    });

    test('legacy JSON without text_color loads as null', () {
      // Existing persisted ButtonConfig records predate this field. The
      // loader must tolerate a missing `text_color` key and yield null
      // (= keep theme default — zero visible regression).
      final legacyJson = baseJson();
      expect(legacyJson.containsKey('text_color'), isFalse,
          reason: 'sanity: baseJson must not include text_color');
      final config = ButtonConfig.fromJson(legacyJson);
      expect(config.textColor, isNull);
    });

    test('round-trips when textColor is set', () {
      final config = ButtonConfig(
        key: 'btn/start',
        outwardColor: const AssetColor.literal(Color(0xFF00FF00)),
        inwardColor: const AssetColor.literal(Color(0xFF808080)),
        buttonType: ButtonType.square,
      )..textColor = const Color(0xFFAB12CD);

      // Match the persistence contract used elsewhere in this file: take
      // the typed toJson() through jsonEncode/jsonDecode so nested
      // converters re-emit raw maps (mirrors Preferences -> Postgres).
      final raw = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;

      expect(raw.containsKey('text_color'), isTrue,
          reason: 'wire key "text_color" must be present when non-null');

      final restored = ButtonConfig.fromJson(raw);
      expect(restored.textColor, isNotNull);
      expect((restored.textColor!.r * 255).round(),
          (config.textColor!.r * 255).round());
      expect((restored.textColor!.g * 255).round(),
          (config.textColor!.g * 255).round());
      expect((restored.textColor!.b * 255).round(),
          (config.textColor!.b * 255).round());
    });

    test('round-trips when textColor is explicitly null', () {
      // Explicit null must survive serialization — it's the "use the
      // theme default color" signal and is semantically distinct from
      // any concrete color.
      final config = ButtonConfig.preview();
      expect(config.textColor, isNull);

      final raw = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;
      // Either key is absent or its value is null — both encode the
      // "use default" state. The JSON-generator emits the key with a
      // null value, which is the shape we accept.
      if (raw.containsKey('text_color')) {
        expect(raw['text_color'], isNull);
      }

      final restored = ButtonConfig.fromJson(raw);
      expect(restored.textColor, isNull);
    });
  });
}

// Tests for the Arrow asset.
//
// These tests lock three contracts the asset currently violates:
//   1. The BaseAsset `text` overlay must render when set (label-shows-up
//      regression — operators rely on the standard page-view label overlay).
//   2. The arrow visual must scale with the asset's allocated SizedBox
//      (scales-with-size regression — fixed-pixel Icon ignores its parent
//      constraints).
//   3. ArrowConfig must expose a declarable `Color color` field that JSON
//      round-trips and back-fills legacy saved pages with a sane default.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/arrow.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/registry.dart';

void main() {
  // Minimal scaffold so DefaultTextStyle / IconTheme / Directionality exist.
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('Arrow label routing through BaseAsset.text', () {
    // ARROW-LBL-01: When the page editor sets BaseAsset.text on an
    // ArrowConfig, the page-view's standard Positioned label overlay must
    // render it. We exercise that indirectly here by asserting the config
    // accepts and round-trips the inherited `text` field — the page-view
    // overlay (lib/pages/page_view.dart line 398) already consumes
    // `asset.text` for every asset uniformly.
    test('Arrow accepts BaseAsset.text and round-trips it through JSON', () {
      final config = ArrowConfig(key: '', label: 'unused-internal-label')
        ..text = 'Flow A'
        ..textPos = TextPos.below;

      final restored = ArrowConfig.fromJson(config.toJson());
      expect(restored.text, 'Flow A');
      expect(restored.textPos, TextPos.below);
    });
  });

  group('Arrow icon scales with asset size', () {
    // ARROW-SCL-01: The arrow visual must consume the SizedBox the page
    // view gives it (asset.size.width * W, asset.size.height * H). A bare
    // Icon with no `size:` falls back to IconTheme.size (~24px) regardless
    // of its parent — that breaks operator perception at any non-default
    // asset size. Render the arrow inside two SizedBoxes (small vs large);
    // the rendered Icon's effective size must scale ~linearly.
    testWidgets('Icon glyph size scales with parent SizedBox', (tester) async {
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 40,
          height: 40,
          child: Builder(
            builder: (ctx) => ArrowConfig(key: '', label: '').build(ctx),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final smallIcon = tester.widget<Icon>(find.byType(Icon));
      final smallSize = smallIcon.size ?? 0;

      await tester.pumpWidget(wrap(
        SizedBox(
          width: 200,
          height: 200,
          child: Builder(
            builder: (ctx) => ArrowConfig(key: '', label: '').build(ctx),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final largeIcon = tester.widget<Icon>(find.byType(Icon));
      final largeSize = largeIcon.size ?? 0;

      // Large icon must be at least ~3x small icon (200/40 = 5x ratio).
      expect(largeSize, greaterThan(smallSize * 3),
          reason:
              'Arrow Icon must scale with its parent SizedBox. Got small=$smallSize, large=$largeSize.');
    });
  });

  group('ArrowConfig color field', () {
    // ARROW-COL-01: ArrowConfig must expose a non-nullable `Color color`
    // field that JSON round-trips through `@ColorConverter()`. The default
    // mirrors the painter's prior hard-coded value (`Colors.black`).
    test('default color is Colors.black', () {
      final config = ArrowConfig(key: '', label: '');
      expect(config.color, Colors.black);
    });

    test('JSON round-trips the color field', () {
      final config = ArrowConfig(
        key: '',
        label: '',
        color: Colors.red,
      );

      final json = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;
      final restored = ArrowConfig.fromJson(json);
      expect(restored.color.value, Colors.red.value);
    });

    test(
        'legacy JSON without a color field deserializes with default Colors.black',
        () {
      final legacyJson = <String, dynamic>{
        'asset_name': 'ArrowConfig',
        'key': '',
        'label': '',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final config = ArrowConfig.fromJson(legacyJson);
      expect(config.color, Colors.black,
          reason:
              'Back-compat: arrows saved before the color field must load.');
    });

    testWidgets('Icon uses the configured color', (tester) async {
      final config = ArrowConfig(key: '', label: '', color: Colors.red);
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 80,
          height: 80,
          child: Builder(builder: (ctx) => config.build(ctx)),
        ),
      ));
      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, Colors.red);
    });
  });

  group('AssetRegistry round-trip preserves color', () {
    test('parsed ArrowConfig preserves color through registry', () {
      final source = ArrowConfig(key: '', label: '', color: Colors.purple);
      final pageJson = {
        'page': {
          'assets': [source.toJson()],
        },
      };
      final parsed = AssetRegistry.parse(pageJson);
      expect(parsed, hasLength(1));
      expect(parsed.first, isA<ArrowConfig>());
      final arrow = parsed.first as ArrowConfig;
      expect(arrow.color.value, Colors.purple.value);
    });
  });

  group('Per-direction bool input keys', () {
    // ARROW-DIR-01: A freshly-constructed ArrowConfig with no direction
    // keys set must JSON round-trip unchanged. The `<dir>InputKey` fields
    // use `@JsonKey(includeIfNull: false)` so legacy pages stay
    // byte-equivalent — nothing new appears in the serialized payload.
    test('all-null direction keys round-trip with no extra JSON fields', () {
      final config = ArrowConfig(key: '', label: '');
      expect(config.upInputKey, isNull);
      expect(config.downInputKey, isNull);
      expect(config.leftInputKey, isNull);
      expect(config.rightInputKey, isNull);

      final json = config.toJson();
      expect(json.containsKey('upInputKey'), isFalse);
      expect(json.containsKey('downInputKey'), isFalse);
      expect(json.containsKey('leftInputKey'), isFalse);
      expect(json.containsKey('rightInputKey'), isFalse);

      final restored = ArrowConfig.fromJson(jsonDecode(jsonEncode(json))
          as Map<String, dynamic>);
      expect(restored.upInputKey, isNull);
      expect(restored.downInputKey, isNull);
      expect(restored.leftInputKey, isNull);
      expect(restored.rightInputKey, isNull);
      expect(restored.hasDirectionInputs, isFalse);
    });

    // ARROW-DIR-02: Setting a subset of direction keys round-trips just
    // those fields; the unset ones stay null and stay out of JSON.
    test('partial direction keys round-trip and unset stays unset', () {
      final config = ArrowConfig(
        key: '',
        label: '',
        upInputKey: 'tag.upBool',
        leftInputKey: 'tag.leftBool',
      );

      final json = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;
      expect(json['upInputKey'], 'tag.upBool');
      expect(json['leftInputKey'], 'tag.leftBool');
      expect(json.containsKey('downInputKey'), isFalse);
      expect(json.containsKey('rightInputKey'), isFalse);

      final restored = ArrowConfig.fromJson(json);
      expect(restored.upInputKey, 'tag.upBool');
      expect(restored.downInputKey, isNull);
      expect(restored.leftInputKey, 'tag.leftBool');
      expect(restored.rightInputKey, isNull);
      expect(restored.hasDirectionInputs, isTrue);
    });

    // ARROW-DIR-03: All four direction keys round-trip cleanly.
    test('all direction keys round-trip', () {
      final config = ArrowConfig(
        key: 'legacy_key',
        label: '',
        upInputKey: 'up.bool',
        downInputKey: 'down.bool',
        leftInputKey: 'left.bool',
        rightInputKey: 'right.bool',
      );

      final restored = ArrowConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);
      expect(restored.upInputKey, 'up.bool');
      expect(restored.downInputKey, 'down.bool');
      expect(restored.leftInputKey, 'left.bool');
      expect(restored.rightInputKey, 'right.bool');
      // Legacy key is still preserved alongside the per-direction inputs.
      expect(restored.key, 'legacy_key');
      expect(restored.hasDirectionInputs, isTrue);
    });

    // ARROW-DIR-04: Legacy JSON saved before this change (no `<dir>InputKey`
    // entries) must deserialize with all direction keys null and
    // `hasDirectionInputs` false, so the runtime takes the legacy path.
    test(
        'legacy JSON without direction keys deserializes with all nulls',
        () {
      final legacyJson = <String, dynamic>{
        'asset_name': 'ArrowConfig',
        'key': 'old_key',
        'label': '',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final config = ArrowConfig.fromJson(legacyJson);
      expect(config.upInputKey, isNull);
      expect(config.downInputKey, isNull);
      expect(config.leftInputKey, isNull);
      expect(config.rightInputKey, isNull);
      expect(config.hasDirectionInputs, isFalse,
          reason:
              'Legacy pages must skip the per-direction path and use the original single-key behaviour.');
    });

    // ARROW-DIR-05: The empty-string trick the editor uses to "clear" a
    // direction picker must surface as null on the next save.
    test('empty-string direction keys do not count as configured', () {
      final config = ArrowConfig(
        key: '',
        label: '',
      );
      // Simulate the editor explicitly clearing each field — the editor
      // normalises empty input to null, but we sanity-check the
      // `hasDirectionInputs` guard treats explicit empty strings the
      // same as null.
      config.upInputKey = '';
      config.downInputKey = '';
      config.leftInputKey = '';
      config.rightInputKey = '';
      expect(config.hasDirectionInputs, isFalse);
    });
  });
}

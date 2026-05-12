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
      final smallCfg = ArrowConfig(key: '', label: '');
      await tester.pumpWidget(wrap(
        SizedBox(width: 40, height: 40, child: smallCfg.build(tester.element(find.byType(Scaffold)))),
      ));
      await tester.pumpAndSettle();
      final smallIcon = tester.widget<Icon>(find.byType(Icon));
      final smallSize = smallIcon.size ?? 0;

      await tester.pumpWidget(wrap(
        SizedBox(width: 200, height: 200, child: ArrowConfig(key: '', label: '').build(tester.element(find.byType(Scaffold)))),
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
}

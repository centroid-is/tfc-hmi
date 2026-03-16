import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/chat/palette_context_menu.dart';
import 'package:tfc/chat/ai_context_action.dart';
import 'package:tfc/chat/chat_overlay.dart' show ChatContextType;
import 'package:tfc/page_creator/assets/common.dart';

/// Minimal test asset that implements [Asset] with configurable fields.
class _TestAsset extends BaseAsset {
  final String _displayNameOverride;
  final String _categoryOverride;

  _TestAsset({
    String displayName = 'LED',
    String category = 'General',
  })  : _displayNameOverride = displayName,
        _categoryOverride = category;

  @override
  String get displayName => _displayNameOverride;

  @override
  String get category => _categoryOverride;

  @override
  String? get text => null;

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  Widget configure(BuildContext context) => const SizedBox();

  @override
  Map<String, dynamic> toJson() => {
        'asset_name': assetName,
      };
}

void main() {
  group('buildPaletteTypeContextBlock', () {
    test('includes asset type name and category', () {
      final asset = _TestAsset(displayName: 'LED', category: 'Indicators');
      final block = buildPaletteTypeContextBlock(
        asset: asset,
      );
      expect(block, contains('[ASSET TYPE CONTEXT'));
      expect(block, contains('Type: LED'));
      expect(block, contains('Category: Indicators'));
      expect(block, contains('[END ASSET TYPE CONTEXT]'));
    });

    test('includes page name when provided', () {
      final asset = _TestAsset(displayName: 'Number');
      final block = buildPaletteTypeContextBlock(
        asset: asset,
        pageName: 'motor-overview',
      );
      expect(block, contains('Current page: motor-overview'));
    });

    test('includes existing asset summary when provided', () {
      final asset = _TestAsset(displayName: 'Button');
      final block = buildPaletteTypeContextBlock(
        asset: asset,
        pageName: 'pump-page',
        existingAssetSummary: '3 LEDs, 2 Numbers, 1 Graph',
      );
      expect(block, contains('3 LEDs, 2 Numbers, 1 Graph'));
    });

    test('omits page name when null', () {
      final asset = _TestAsset(displayName: 'LED');
      final block = buildPaletteTypeContextBlock(
        asset: asset,
      );
      expect(block, isNot(contains('Current page:')));
    });

    test('omits existing assets when null', () {
      final asset = _TestAsset(displayName: 'LED');
      final block = buildPaletteTypeContextBlock(
        asset: asset,
      );
      expect(block, isNot(contains('Existing assets:')));
    });
  });

  group('buildExplainTypePrompt', () {
    test('contains the asset type display name', () {
      final prompt = buildExplainTypePrompt('LED');
      expect(prompt, contains('LED'));
    });

    test('is a short user-friendly prompt', () {
      final prompt = buildExplainTypePrompt('Schneider ATV320');
      expect(prompt.length, lessThan(200));
      expect(prompt, isNot(contains('[ASSET TYPE CONTEXT')));
    });
  });

  group('buildCreateWithAiPrompt', () {
    test('contains the asset type display name', () {
      final prompt = buildCreateWithAiPrompt('Graph Asset');
      expect(prompt, contains('Graph Asset'));
    });

    test('includes page name when provided', () {
      final prompt =
          buildCreateWithAiPrompt('Number', pageName: 'motor-overview');
      expect(prompt, contains('motor-overview'));
    });

    test('is a short user-friendly prompt', () {
      final prompt = buildCreateWithAiPrompt('LED');
      expect(prompt.length, lessThan(200));
      expect(prompt, isNot(contains('[ASSET TYPE CONTEXT')));
    });
  });

  group('buildPaletteItemMenuItems', () {
    test('returns two menu items', () {
      final asset = _TestAsset(displayName: 'LED', category: 'Indicators');
      final items = buildPaletteItemMenuItems(
        asset: asset,
      );
      expect(items.length, 2);
    });

    test('first item is "Explain this type"', () {
      final asset = _TestAsset(displayName: 'LED', category: 'Indicators');
      final items = buildPaletteItemMenuItems(
        asset: asset,
      );
      expect(items[0].label, 'Explain this type');
      expect(items[0].icon, Icons.help_outline);
      expect(items[0].sendImmediately, isFalse);
      expect(items[0].prefillText, contains('LED'));
    });

    test('second item is "Create this with AI"', () {
      final asset = _TestAsset(displayName: 'LED', category: 'Indicators');
      final items = buildPaletteItemMenuItems(
        asset: asset,
        pageName: 'test-page',
      );
      expect(items[1].label, 'Create this with AI');
      expect(items[1].icon, Icons.auto_awesome);
      expect(items[1].sendImmediately, isFalse);
      expect(items[1].prefillText, contains('LED'));
    });

    test('items have context blocks (not in prefillText)', () {
      final asset = _TestAsset(displayName: 'LED', category: 'Indicators');
      final items = buildPaletteItemMenuItems(
        asset: asset,
      );
      // Context block should be in the contextBlock field, NOT in prefillText
      expect(items[0].prefillText, isNot(contains('[ASSET TYPE CONTEXT')));
      expect(items[1].prefillText, isNot(contains('[ASSET TYPE CONTEXT')));
      expect(items[0].contextBlock, contains('[ASSET TYPE CONTEXT'));
      expect(items[1].contextBlock, contains('[ASSET TYPE CONTEXT'));
    });

    test('items have contextLabel and contextType set', () {
      final asset = _TestAsset(displayName: 'LED', category: 'Indicators');
      final items = buildPaletteItemMenuItems(
        asset: asset,
      );
      expect(items[0].contextLabel, 'LED');
      expect(items[0].contextType, ChatContextType.asset);
      expect(items[1].contextLabel, 'LED');
      expect(items[1].contextType, ChatContextType.asset);
    });

    test('second item includes page context when pageName provided', () {
      final asset = _TestAsset(displayName: 'Number', category: 'Data');
      final items = buildPaletteItemMenuItems(
        asset: asset,
        pageName: 'pump-overview',
        existingAssetSummary: '2 LEDs, 1 Button',
      );
      expect(items[1].contextBlock, contains('pump-overview'));
      expect(items[1].contextBlock, contains('2 LEDs, 1 Button'));
      expect(items[1].prefillText, contains('pump-overview'));
    });

    test('explain item includes instructions in context block', () {
      final asset = _TestAsset(displayName: 'LED');
      final items = buildPaletteItemMenuItems(asset: asset);
      // Should include instructions for the LLM
      expect(items[0].contextBlock, contains('what it displays'));
      expect(items[0].contextBlock, contains('configuration'));
    });

    test('create item includes instructions in context block', () {
      final asset = _TestAsset(displayName: 'LED');
      final items = buildPaletteItemMenuItems(asset: asset);
      // Should include instructions for the LLM
      expect(items[1].contextBlock, contains('configure'));
    });
  });

  group('summarizeExistingAssets', () {
    test('returns empty string for empty list', () {
      expect(summarizeExistingAssets([]), isEmpty);
    });

    test('counts assets by display name', () {
      final assets = [
        _TestAsset(displayName: 'LED'),
        _TestAsset(displayName: 'LED'),
        _TestAsset(displayName: 'Number'),
      ];
      final summary = summarizeExistingAssets(assets);
      expect(summary, contains('2 LEDs'));
      expect(summary, contains('1 Number'));
    });

    test('pluralizes correctly with "s" suffix', () {
      final assets = [
        _TestAsset(displayName: 'Button'),
        _TestAsset(displayName: 'Button'),
        _TestAsset(displayName: 'Button'),
      ];
      final summary = summarizeExistingAssets(assets);
      expect(summary, contains('3 Buttons'));
    });

    test('does not pluralize singular counts', () {
      final assets = [
        _TestAsset(displayName: 'Graph Asset'),
      ];
      final summary = summarizeExistingAssets(assets);
      expect(summary, contains('1 Graph Asset'));
      expect(summary, isNot(contains('Graph Assets')));
    });
  });
}

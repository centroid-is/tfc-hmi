import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/chat/hamburger_context_menu.dart';
import 'package:tfc/chat/chat_overlay.dart' show ChatContextType;
import 'package:tfc/page_creator/assets/common.dart';

/// Minimal test asset that implements [Asset] with configurable fields.
class _TestAsset extends BaseAsset {
  final String _key;
  final String? _textOverride;
  final String _displayNameOverride;

  _TestAsset({
    String key = '',
    String? text,
    String displayName = 'TestAsset',
  })  : _key = key,
        _textOverride = text,
        _displayNameOverride = displayName;

  @override
  String get displayName => _displayNameOverride;

  @override
  String? get text => _textOverride;

  @override
  String get category => 'Test';

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  Widget configure(BuildContext context) => const SizedBox();

  @override
  Map<String, dynamic> toJson() => {
        'key': _key.isEmpty ? null : _key,
        'asset_name': 'TestAsset',
      };
}

void main() {
  group('buildPageContextBlock', () {
    test('includes page name in context block', () {
      final block = buildPageContextBlock(
        pageName: 'Pump Station',
        assets: [],
      );
      expect(block, contains('[PAGE CONTEXT'));
      expect(block, contains('Page: Pump Station'));
      expect(block, contains('[END PAGE CONTEXT]'));
    });

    test('includes existing asset summaries', () {
      final assets = [
        _TestAsset(key: 'pump3.speed', displayName: 'Number'),
        _TestAsset(text: 'Motor Status', displayName: 'LED'),
      ];
      final block = buildPageContextBlock(
        pageName: 'Test Page',
        assets: assets,
      );
      expect(block, contains('Existing assets (2):'));
      expect(block, contains('Number'));
      expect(block, contains('pump3.speed'));
      expect(block, contains('LED'));
      expect(block, contains('Motor Status'));
    });

    test('shows "none" when no assets exist', () {
      final block = buildPageContextBlock(
        pageName: 'Empty Page',
        assets: [],
      );
      expect(block, contains('Existing assets: none'));
    });

    test('includes available asset types from registry', () {
      final block = buildPageContextBlock(
        pageName: 'Test Page',
        assets: [],
      );
      expect(block, contains('Available asset types:'));
      // Should include well-known types from AssetRegistry.defaultFactories
      // Just verify it has some types listed (the registry has 30+ types)
      expect(block, contains('LED'));
      expect(block, contains('Number'));
    });

    test('tells LLM this is pre-fetched context', () {
      final block = buildPageContextBlock(
        pageName: 'Test',
        assets: [],
      );
      expect(block, contains('already fetched'));
    });
  });

  group('buildHamburgerMenuItems', () {
    test('returns three menu items', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Pump Station',
        assets: [],
      );
      expect(items.length, 3);
    });

    test('first item is "Create asset with AI"', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Test Page',
        assets: [],
      );
      final item = items[0];
      expect(item.label, 'Create asset with AI');
      expect(item.icon, Icons.add_circle_outline);
      expect(item.sendImmediately, isFalse);
      expect(item.prefillText, contains('Create'));
      expect(item.prefillText, contains('Test Page'));
    });

    test('second item is "Design page layout"', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Test Page',
        assets: [],
      );
      final item = items[1];
      expect(item.label, 'Design page layout');
      expect(item.icon, Icons.dashboard_customize);
      expect(item.sendImmediately, isFalse);
      expect(item.prefillText, contains('layout'));
    });

    test('third item is "Add multiple assets"', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Test Page',
        assets: [],
      );
      final item = items[2];
      expect(item.label, 'Add multiple assets');
      expect(item.icon, Icons.library_add);
      expect(item.sendImmediately, isFalse);
      expect(item.prefillText, contains('multiple'));
    });

    test('all items have context blocks with PAGE CONTEXT', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Test Page',
        assets: [
          _TestAsset(key: 'pump3.speed', displayName: 'Number'),
        ],
      );
      for (final item in items) {
        expect(item.contextBlock, isNotNull);
        expect(item.contextBlock, contains('[PAGE CONTEXT'));
        expect(item.contextBlock, contains('[END PAGE CONTEXT]'));
      }
    });

    test('items have contextLabel set to page name', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Pump Station',
        assets: [],
      );
      for (final item in items) {
        expect(item.contextLabel, 'Pump Station');
      }
    });

    test('items have contextType set to page', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Test',
        assets: [],
      );
      for (final item in items) {
        expect(item.contextType, ChatContextType.page);
      }
    });

    test('prefill texts do not contain context blocks', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Test Page',
        assets: [],
      );
      for (final item in items) {
        expect(item.prefillText, isNot(contains('[PAGE CONTEXT')));
      }
    });

    test('context blocks include existing asset info when assets present', () {
      final items = buildHamburgerMenuItems(
        pageName: 'Motor Page',
        assets: [
          _TestAsset(key: 'motor1.speed', displayName: 'Number'),
          _TestAsset(text: 'VFD Status', displayName: 'LED'),
        ],
      );
      // All items share the same page context
      for (final item in items) {
        expect(item.contextBlock, contains('motor1.speed'));
        expect(item.contextBlock, contains('VFD Status'));
        expect(item.contextBlock, contains('Existing assets (2)'));
      }
    });
  });
}

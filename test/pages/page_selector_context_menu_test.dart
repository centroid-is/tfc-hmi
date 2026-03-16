import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/chat/ai_context_action.dart';
import 'package:tfc/chat/chat_overlay.dart' show ChatContextType;
import 'package:tfc/chat/page_context_menu.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:flutter/material.dart';

void main() {
  group('buildPageContextBlock', () {
    test('includes page name and path in context block', () {
      final page = AssetPage(
        menuItem: const MenuItem(
          label: 'Overview',
          path: '/overview',
          icon: Icons.home,
        ),
        assets: [],
        mirroringDisabled: false,
      );

      final block = buildPageContextBlock('/overview', page);
      expect(block, contains('[PAGE CONTEXT'));
      expect(block, contains('Name: Overview'));
      expect(block, contains('Path: /overview'));
      expect(block, contains('[END PAGE CONTEXT]'));
    });

    test('tells LLM not to re-fetch', () {
      final page = AssetPage(
        menuItem: const MenuItem(
          label: 'Test',
          path: '/test',
          icon: Icons.home,
        ),
        assets: [],
        mirroringDisabled: false,
      );

      final block = buildPageContextBlock('/test', page);
      expect(block, contains('do NOT re-fetch'));
    });

    test('includes asset count', () {
      final page = AssetPage(
        menuItem: const MenuItem(
          label: 'Motors',
          path: '/motors',
          icon: Icons.engineering,
        ),
        assets: [
          _TestAsset(key: 'pump1.speed', displayName: 'Number'),
          _TestAsset(key: 'pump2.speed', displayName: 'Number'),
          _TestAsset(text: 'Status', displayName: 'LED'),
        ],
        mirroringDisabled: false,
      );

      final block = buildPageContextBlock('/motors', page);
      expect(block, contains('Assets (3):'));
    });

    test('lists each asset with type, key, position and size', () {
      final asset = _TestAsset(
        key: 'pump1.speed',
        displayName: 'Number',
        x: 0.25,
        y: 0.50,
        width: 0.1,
        height: 0.05,
      );
      final page = AssetPage(
        menuItem: const MenuItem(
          label: 'Motors',
          path: '/motors',
          icon: Icons.engineering,
        ),
        assets: [asset],
        mirroringDisabled: false,
      );

      final block = buildPageContextBlock('/motors', page);
      expect(block, contains('Number'));
      expect(block, contains('pump1.speed'));
      expect(block, contains('0.25'));
      expect(block, contains('0.50'));
    });

    test('uses text label when asset has no key', () {
      final asset = _TestAsset(
        text: 'Motor Status',
        displayName: 'LED',
        x: 0.1,
        y: 0.1,
        width: 0.03,
        height: 0.03,
      );
      final page = AssetPage(
        menuItem: const MenuItem(
          label: 'Status',
          path: '/status',
          icon: Icons.info,
        ),
        assets: [asset],
        mirroringDisabled: false,
      );

      final block = buildPageContextBlock('/status', page);
      expect(block, contains('Motor Status'));
    });

    test('includes mirroring info', () {
      final page = AssetPage(
        menuItem: const MenuItem(
          label: 'Mirrored',
          path: '/mirrored',
          icon: Icons.home,
        ),
        assets: [],
        mirroringDisabled: true,
      );

      final block = buildPageContextBlock('/mirrored', page);
      expect(block, contains('Mirroring disabled: true'));
    });

    test('handles empty page gracefully', () {
      final page = AssetPage(
        menuItem: const MenuItem(
          label: 'Empty',
          path: '/',
          icon: Icons.home,
        ),
        assets: [],
        mirroringDisabled: false,
      );

      final block = buildPageContextBlock('/', page);
      expect(block, contains('[PAGE CONTEXT'));
      expect(block, contains('Assets (0)'));
      expect(block, contains('[END PAGE CONTEXT]'));
    });
  });

  group('buildPageSelectorMenuItems', () {
    late AssetPage testPage;

    setUp(() {
      testPage = AssetPage(
        menuItem: const MenuItem(
          label: 'Overview',
          path: '/overview',
          icon: Icons.home,
        ),
        assets: [
          _TestAsset(key: 'pump1.speed', displayName: 'Number'),
          _TestAsset(text: 'Status LED', displayName: 'LED'),
        ],
        mirroringDisabled: false,
      );
    });

    test('returns four menu items', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      expect(items.length, 4);
    });

    test('first item is "Create Page with AI"', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      final item = items[0];
      expect(item.label, 'Create Page with AI');
      expect(item.icon, Icons.add_circle_outline);
      // This is a direct action item -- no context block or prefill needed
      expect(item.contextBlock, isNull);
    });

    test('second item is "Describe this page"', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      final item = items[1];
      expect(item.label, 'Describe this page');
      expect(item.sendImmediately, isFalse);
      expect(item.prefillText, contains('Overview'));
    });

    test('third item is "Improve layout"', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      final item = items[2];
      expect(item.label, 'Improve layout');
      expect(item.sendImmediately, isFalse);
      expect(item.prefillText, contains('layout'));
    });

    test('fourth item is "Create similar page"', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      final item = items[3];
      expect(item.label, 'Create similar page');
      expect(item.sendImmediately, isFalse);
      expect(item.prefillText, contains('similar'));
    });

    test('AI items have context blocks with PAGE CONTEXT', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      // Skip first item (Create New Page) -- it has no context block
      for (final item in items.skip(1)) {
        expect(item.contextBlock, isNotNull);
        expect(item.contextBlock, contains('[PAGE CONTEXT'));
        expect(item.contextBlock, contains('[END PAGE CONTEXT]'));
      }
    });

    test('AI items have contextLabel set to page name', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      for (final item in items.skip(1)) {
        expect(item.contextLabel, 'Page: Overview');
      }
    });

    test('AI items have contextType set to page', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      for (final item in items.skip(1)) {
        expect(item.contextType, ChatContextType.page);
      }
    });

    test('AI item prefillText does NOT contain context block', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      for (final item in items.skip(1)) {
        expect(item.prefillText, isNot(contains('[PAGE CONTEXT')));
      }
    });

    test('context block includes asset details from the page', () {
      final items = buildPageSelectorMenuItems('/overview', testPage);
      // AI items share the same context block containing asset info
      final block = items[1].contextBlock!;
      expect(block, contains('pump1.speed'));
      expect(block, contains('Number'));
      expect(block, contains('Status LED'));
      expect(block, contains('LED'));
    });
  });
}

/// Minimal test asset with configurable fields for testing page context.
class _TestAsset extends BaseAsset {
  final String _key;
  final String? _textOverride;
  final String _displayNameOverride;
  final double _x;
  final double _y;
  final double _width;
  final double _height;

  _TestAsset({
    String key = '',
    String? text,
    String displayName = 'TestAsset',
    double x = 0.0,
    double y = 0.0,
    double width = 0.03,
    double height = 0.03,
  })  : _key = key,
        _textOverride = text,
        _displayNameOverride = displayName,
        _x = x,
        _y = y,
        _width = width,
        _height = height;

  @override
  String get displayName => _displayNameOverride;

  @override
  String? get text => _textOverride;

  @override
  String get category => 'Test';

  @override
  Coordinates get coordinates => Coordinates(x: _x, y: _y);

  @override
  set coordinates(Coordinates coordinates) {}

  @override
  RelativeSize get size => RelativeSize(width: _width, height: _height);

  @override
  set size(RelativeSize size) {}

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

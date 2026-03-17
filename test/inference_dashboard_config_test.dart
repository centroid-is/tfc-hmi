import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc_dart/core/preferences.dart';

/// Minimal in-memory PreferencesApi for PageManager construction.
class _FakePreferences implements PreferencesApi {
  final Map<String, Object> _store = {};

  @override
  Future<String?> getString(String key) async => _store[key] as String?;
  @override
  Future<void> setString(String key, String value) async =>
      _store[key] = value;
  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      _store.keys.toSet();
  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map.from(_store);
  @override
  Future<bool?> getBool(String key) async => _store[key] as bool?;
  @override
  Future<int?> getInt(String key) async => _store[key] as int?;
  @override
  Future<double?> getDouble(String key) async => _store[key] as double?;
  @override
  Future<List<String>?> getStringList(String key) async =>
      _store[key] as List<String>?;
  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);
  @override
  Future<void> setBool(String key, bool value) async => _store[key] = value;
  @override
  Future<void> setInt(String key, int value) async => _store[key] = value;
  @override
  Future<void> setDouble(String key, double value) async =>
      _store[key] = value;
  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _store[key] = value;
  @override
  Future<void> remove(String key) async => _store.remove(key);
  @override
  Future<void> clear({Set<String>? allowList}) async {
    if (allowList == null) {
      _store.clear();
    } else {
      _store.removeWhere((k, _) => allowList.contains(k));
    }
  }
}

void main() {
  group('Inference dashboard config validation', () {
    late String pageEditorJson;
    late String keyMappingsJson;
    late Map<String, dynamic> keyMappingsData;

    setUpAll(() {
      final pageEditorFile =
          File('centroid-hmi/web/config/page-editor.json');
      expect(pageEditorFile.existsSync(), isTrue,
          reason: 'page-editor.json must exist in centroid-hmi/web/config/');
      pageEditorJson = pageEditorFile.readAsStringSync();

      final keyMappingsFile =
          File('centroid-hmi/web/config/keymappings.json');
      expect(keyMappingsFile.existsSync(), isTrue,
          reason: 'keymappings.json must exist in centroid-hmi/web/config/');
      keyMappingsJson = keyMappingsFile.readAsStringSync();
      keyMappingsData =
          jsonDecode(keyMappingsJson) as Map<String, dynamic>;
    });

    test('page-editor.json is valid JSON parseable by PageManager', () {
      final manager = PageManager(pages: {}, prefs: _FakePreferences());
      // fromJson populates manager.pages from the JSON string
      manager.fromJson(pageEditorJson);
      expect(manager.pages, isNotEmpty,
          reason: 'PageManager should parse at least one page');
    });

    test('all asset types are recognized by the registry', () {
      final json = jsonDecode(pageEditorJson) as Map<String, dynamic>;

      // Collect all asset_name values from the JSON
      final assetNames = <String>[];
      void findAssets(dynamic part) {
        if (part is Map<String, dynamic>) {
          if (part.containsKey('asset_name')) {
            assetNames.add(part['asset_name'] as String);
          }
          part.values.forEach(findAssets);
        } else if (part is List) {
          part.forEach(findAssets);
        }
      }

      findAssets(json);
      expect(assetNames, isNotEmpty,
          reason: 'Should find asset_name entries in the JSON');

      // Verify each asset_name can be parsed by the registry
      for (final name in assetNames) {
        final asset = AssetRegistry.createDefaultAssetByName(name);
        expect(asset, isNotNull,
            reason: 'Asset type "$name" must be registered in AssetRegistry');
      }
    });

    test(
        'asset count matches expected '
        '(4 NumberConfig + 1 ImageFeedConfig + 1 InferenceLogConfig + 1 ButtonConfig = 7)',
        () {
      final manager = PageManager(pages: {}, prefs: _FakePreferences());
      manager.fromJson(pageEditorJson);

      // Count all assets across all pages
      var totalAssets = 0;
      final typeCounts = <String, int>{};
      for (final page in manager.pages.values) {
        for (final asset in page.assets) {
          totalAssets++;
          final name = asset.assetName;
          typeCounts[name] = (typeCounts[name] ?? 0) + 1;
        }
      }

      expect(totalAssets, equals(7),
          reason: 'Expected 7 total assets, got $totalAssets. '
              'Breakdown: $typeCounts');

      expect(typeCounts['NumberConfig'], equals(4),
          reason: 'Expected 4 NumberConfig assets');
      expect(typeCounts['ImageFeedConfig'], equals(1),
          reason: 'Expected 1 ImageFeedConfig asset');
      expect(typeCounts['InferenceLogConfig'], equals(1),
          reason: 'Expected 1 InferenceLogConfig asset');
      expect(typeCounts['ButtonConfig'], equals(1),
          reason: 'Expected 1 ButtonConfig asset');
    });

    test('all asset keys reference valid keymappings entries', () {
      final manager = PageManager(pages: {}, prefs: _FakePreferences());
      manager.fromJson(pageEditorJson);

      final nodes =
          (keyMappingsData['nodes'] as Map<String, dynamic>).keys.toSet();

      for (final page in manager.pages.values) {
        for (final asset in page.assets) {
          // allKeys is on BaseAsset, cast to access it
          final baseAsset = asset as BaseAsset;
          for (final key in baseAsset.allKeys) {
            expect(nodes.contains(key), isTrue,
                reason:
                    'Asset key "$key" from ${asset.assetName} must exist '
                    'in keymappings.json nodes. Available: $nodes');
          }
        }
      }
    });

    test('keymappings.json contains all required inference keys', () {
      final nodes =
          (keyMappingsData['nodes'] as Map<String, dynamic>).keys.toSet();

      const requiredKeys = [
        'inference.result',
        'inference.stats.processed',
        'inference.stats.avg_confidence',
        'inference.stats.latency_ms',
        'inference.stats.errors',
        'inference.control.pause',
      ];

      for (final key in requiredKeys) {
        expect(nodes.contains(key), isTrue,
            reason: 'keymappings.json must contain "$key"');
      }
    });

    test('page has correct menu item', () {
      final manager = PageManager(pages: {}, prefs: _FakePreferences());
      manager.fromJson(pageEditorJson);

      // Should have a home/root page
      expect(manager.pages.containsKey('/'), isTrue,
          reason: 'Should have a page at path "/"');

      final homePage = manager.pages['/']!;
      expect(homePage.menuItem.label, equals('Inference Monitor'));
    });
  });
}

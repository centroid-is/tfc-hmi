import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc_dart/core/preferences.dart';

/// Minimal in-memory [PreferencesApi] so a [PageManager] can round-trip.
class _FakePreferences implements PreferencesApi {
  final Map<String, Object> _store = {};

  @override
  Future<String?> getString(String key) async => _store[key] as String?;
  @override
  Future<void> setString(String key, String value) async => _store[key] = value;
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
  Future<void> setDouble(String key, double value) async => _store[key] = value;
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
  group('MenuItem.isNavigationSection', () {
    test('an explicitly flagged item is a section even when empty', () {
      const item = MenuItem(
        label: 'Diagnostics',
        path: '/diagnostics',
        icon: Icons.folder,
        isSection: true,
      );
      expect(item.isNavigationSection, isTrue);
    });

    test('a plain page is not a section', () {
      const item = MenuItem(label: 'Home', path: '/', icon: Icons.home);
      expect(item.isNavigationSection, isFalse);
    });

    test('legacy data without the flag is inferred from children', () {
      const item = MenuItem(
        label: 'Diagnostics',
        path: '/diagnostics',
        icon: Icons.folder,
        children: [
          MenuItem(label: 'IOs', path: '/diagnostics/ios', icon: Icons.list),
        ],
      );
      expect(item.isSection, isFalse, reason: 'flag was never written');
      expect(item.isNavigationSection, isTrue);
    });
  });

  group('MenuItem serialization', () {
    test('round-trips the section flag', () {
      const item = MenuItem(
        label: 'Diagnostics',
        path: '/diagnostics',
        icon: Icons.folder,
        isSection: true,
      );
      final restored = MenuItem.fromJson(item.toJson());
      expect(restored.isSection, isTrue);
      expect(restored.children, isEmpty);
    });

    test('defaults to false when the key is absent', () {
      final restored = MenuItem.fromJson({
        'label': 'Home',
        'path': '/',
        'icon': 'home',
        'children': <dynamic>[],
      });
      expect(restored.isSection, isFalse);
    });
  });

  group('MenuItem.copyWith', () {
    test('preserves the section flag', () {
      const section = MenuItem(
        label: 'Diagnostics',
        path: '/diagnostics',
        icon: Icons.folder,
        isSection: true,
      );
      final withChild = section.copyWith(children: [
        const MenuItem(label: 'IOs', path: '/diagnostics/ios', icon: Icons.list),
      ]);
      expect(withChild.isSection, isTrue);
      expect(withChild.label, 'Diagnostics');
      expect(withChild.children.single.label, 'IOs');
    });
  });

  group('PageManager persistence', () {
    test('an empty section survives save/load', () {
      final manager = PageManager(prefs: _FakePreferences(), pages: {
        '/diagnostics': AssetPage(
          menuItem: const MenuItem(
            label: 'Diagnostics',
            path: '/diagnostics',
            icon: Icons.folder,
            isSection: true,
          ),
          assets: [],
          mirroringDisabled: false,
        ),
      });

      manager.fromJson(manager.toJson());

      final restored = manager.pages['/diagnostics']!.menuItem;
      expect(restored.isSection, isTrue);
      expect(restored.isNavigationSection, isTrue,
          reason: 'reopening the editor must still show it as a section');
    });

    test('getRootMenuItems keeps the flag on resolved items', () {
      final manager = PageManager(prefs: _FakePreferences(), pages: {
        '/diagnostics': AssetPage(
          menuItem: const MenuItem(
            label: 'Diagnostics',
            path: '/diagnostics',
            icon: Icons.folder,
            isSection: true,
          ),
          assets: [],
          mirroringDisabled: false,
        ),
      });

      final roots = manager.getRootMenuItems();
      expect(roots.single.isSection, isTrue);
    });
  });
}

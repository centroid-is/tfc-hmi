import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc_dart/core/preferences.dart';

/// Minimal in-memory implementation of PreferencesApi for tests.
class FakePreferences implements PreferencesApi {
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

// ── Helpers ──────────────────────────────────────────────────────────────────

AssetPage _page(String label, String path,
    {List<MenuItem> children = const [], int? priority}) {
  return AssetPage(
    menuItem: MenuItem(
      label: label,
      path: path,
      icon: Icons.pageview,
      children: children,
    ),
    assets: [],
    mirroringDisabled: false,
    navigationPriority: priority,
  );
}

MenuItem _menuRef(String label, String path) {
  return MenuItem(label: label, path: path, icon: Icons.pageview);
}

PageManager _manager({Map<String, AssetPage>? pages}) {
  return PageManager(
    pages: pages ?? {},
    prefs: FakePreferences(),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('PageManager keying by path', () {
    test('pages are keyed by path, not label', () {
      final mgr = _manager(pages: {
        '/': _page('Home', '/'),
        '/settings': _page('Settings', '/settings'),
      });

      expect(mgr.pages.containsKey('/'), isTrue);
      expect(mgr.pages.containsKey('/settings'), isTrue);
      expect(mgr.pages['/']!.menuItem.label, 'Home');
    });

    test('same label under different sections produces distinct keys', () {
      // This is the exact bug scenario: two pages named "roe" in different sections
      final mgr = _manager(pages: {
        '/section-a': _page('Section A', '/section-a', children: [
          _menuRef('roe', '/section-a/roe'),
        ]),
        '/section-a/roe': _page('roe', '/section-a/roe'),
        '/section-b': _page('Section B', '/section-b', children: [
          _menuRef('roe', '/section-b/roe'),
        ]),
        '/section-b/roe': _page('roe', '/section-b/roe'),
      });

      expect(mgr.pages.length, 4);
      expect(mgr.pages.containsKey('/section-a/roe'), isTrue);
      expect(mgr.pages.containsKey('/section-b/roe'), isTrue);
      // Both pages exist independently
      expect(mgr.pages['/section-a/roe']!.menuItem.label, 'roe');
      expect(mgr.pages['/section-b/roe']!.menuItem.label, 'roe');
    });
  });

  group('toJson / fromJson round-trip', () {
    test('single page survives round-trip', () {
      final mgr = _manager(pages: {
        '/': _page('Home', '/'),
      });
      final json = mgr.toJson();
      mgr.fromJson(json);

      expect(mgr.pages.length, 1);
      expect(mgr.pages.containsKey('/'), isTrue);
      expect(mgr.pages['/']!.menuItem.label, 'Home');
      expect(mgr.pages['/']!.menuItem.path, '/');
    });

    test('multiple pages with same label survive round-trip', () {
      final mgr = _manager(pages: {
        '/section-a/roe': _page('roe', '/section-a/roe'),
        '/section-b/roe': _page('roe', '/section-b/roe'),
      });
      final json = mgr.toJson();
      mgr.fromJson(json);

      expect(mgr.pages.length, 2);
      expect(mgr.pages.containsKey('/section-a/roe'), isTrue);
      expect(mgr.pages.containsKey('/section-b/roe'), isTrue);
    });

    test('section with children survives round-trip', () {
      final mgr = _manager(pages: {
        '/diagnostics': _page('Diagnostics', '/diagnostics', children: [
          _menuRef('IOs', '/diagnostics/ios'),
          _menuRef('Motors', '/diagnostics/motors'),
        ]),
        '/diagnostics/ios': _page('IOs', '/diagnostics/ios'),
        '/diagnostics/motors': _page('Motors', '/diagnostics/motors'),
      });
      final json = mgr.toJson();
      mgr.fromJson(json);

      expect(mgr.pages.length, 3);
      final section = mgr.pages['/diagnostics']!;
      expect(section.menuItem.children.length, 2);
      expect(section.menuItem.children[0].path, '/diagnostics/ios');
      expect(section.menuItem.children[1].path, '/diagnostics/motors');
    });

    test('toJson uses path as JSON key', () {
      final mgr = _manager(pages: {
        '/my-page': _page('My Page', '/my-page'),
      });
      final decoded = jsonDecode(mgr.toJson()) as Map<String, dynamic>;
      expect(decoded.containsKey('/my-page'), isTrue);
    });
  });

  group('backward compatibility (_fromJson)', () {
    test('old format with label keys and path in menu_item', () {
      // Old format: JSON key is the label, but menu_item.path exists
      final oldJson = jsonEncode({
        'Home': {
          'menu_item': {
            'label': 'Home',
            'path': '/',
            'icon': 'home',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
          'navigation_priority': 0,
        },
        'Settings': {
          'menu_item': {
            'label': 'Settings',
            'path': '/settings',
            'icon': 'settings',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
        },
      });

      final mgr = _manager();
      mgr.fromJson(oldJson);

      // Should be keyed by path from menu_item, not the JSON key
      expect(mgr.pages.containsKey('/'), isTrue);
      expect(mgr.pages.containsKey('/settings'), isTrue);
      expect(mgr.pages.containsKey('Home'), isFalse);
      expect(mgr.pages.containsKey('Settings'), isFalse);
    });

    test('old section with empty path gets a generated path', () {
      final oldJson = jsonEncode({
        'Diagnostics': {
          'menu_item': {
            'label': 'Diagnostics',
            'path': '',
            'icon': 'folder',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
        },
      });

      final mgr = _manager();
      mgr.fromJson(oldJson);

      // Should generate /diagnostics from the JSON key "Diagnostics"
      expect(mgr.pages.containsKey('/diagnostics'), isTrue);
      expect(mgr.pages['/diagnostics']!.menuItem.label, 'Diagnostics');
      // The menu_item path should be updated too
      expect(mgr.pages['/diagnostics']!.menuItem.path, '/diagnostics');
    });

    test('old section with null path gets a generated path', () {
      final oldJson = jsonEncode({
        'My Section': {
          'menu_item': {
            'label': 'My Section',
            'icon': 'folder',
            'children': [],
          },
          'assets': [],
          'mirroring_disabled': false,
        },
      });

      final mgr = _manager();
      mgr.fromJson(oldJson);

      expect(mgr.pages.containsKey('/my-section'), isTrue);
      expect(mgr.pages['/my-section']!.menuItem.path, '/my-section');
    });
  });

  group('getRootMenuItems', () {
    test('returns only root pages (not referenced as children)', () {
      final mgr = _manager(pages: {
        '/': _page('Home', '/', priority: 0),
        '/diagnostics': _page('Diagnostics', '/diagnostics',
            children: [_menuRef('IOs', '/diagnostics/ios')], priority: 1),
        '/diagnostics/ios': _page('IOs', '/diagnostics/ios', priority: 0),
      });

      final roots = mgr.getRootMenuItems();
      expect(roots.length, 2);
      expect(roots[0].label, 'Home');
      expect(roots[1].label, 'Diagnostics');
    });

    test('root items are sorted by navigation priority', () {
      final mgr = _manager(pages: {
        '/b': _page('B', '/b', priority: 2),
        '/a': _page('A', '/a', priority: 0),
        '/c': _page('C', '/c', priority: 1),
      });

      final roots = mgr.getRootMenuItems();
      expect(roots.map((r) => r.label).toList(), ['A', 'C', 'B']);
    });

    test('children are resolved from the flat map', () {
      final mgr = _manager(pages: {
        '/section': _page('Section', '/section', children: [
          _menuRef('Page A', '/section/a'),
          _menuRef('Page B', '/section/b'),
        ]),
        '/section/a': _page('Page A', '/section/a', children: [
          _menuRef('Sub', '/section/a/sub'),
        ]),
        '/section/b': _page('Page B', '/section/b'),
        '/section/a/sub': _page('Sub', '/section/a/sub'),
      });

      final roots = mgr.getRootMenuItems();
      expect(roots.length, 1);
      final section = roots[0];
      expect(section.children.length, 2);
      // Page A should have its sub-child resolved
      final pageA = section.children[0];
      expect(pageA.children.length, 1);
      expect(pageA.children[0].label, 'Sub');
    });
  });

  group('copyPages', () {
    test('produces a deep copy', () {
      final original = {
        '/': _page('Home', '/'),
        '/foo': _page('Foo', '/foo'),
      };
      final copy = PageManager.copyPages(original);

      expect(copy.length, 2);
      expect(copy.containsKey('/'), isTrue);
      expect(copy.containsKey('/foo'), isTrue);
      // Verify it's a different map instance
      expect(identical(copy, original), isFalse);
    });

    test('copy preserves children references', () {
      final original = {
        '/section': _page('Section', '/section', children: [
          _menuRef('Child', '/section/child'),
        ]),
        '/section/child': _page('Child', '/section/child'),
      };
      final copy = PageManager.copyPages(original);

      expect(copy['/section']!.menuItem.children.length, 1);
      expect(copy['/section']!.menuItem.children[0].path, '/section/child');
    });
  });

  group('collectChildPaths', () {
    test('collects paths from flat children list', () {
      final children = [
        _menuRef('A', '/a'),
        _menuRef('B', '/b'),
      ];
      final paths = <String>{};
      PageManager.collectChildPaths(children, paths, '/parent');
      expect(paths, {'/a', '/b'});
    });

    test('excludes self-references', () {
      final children = [
        _menuRef('Self', '/parent'),
        _menuRef('Other', '/other'),
      ];
      final paths = <String>{};
      PageManager.collectChildPaths(children, paths, '/parent');
      expect(paths, {'/other'});
    });

    test('collects nested children recursively', () {
      final children = [
        MenuItem(
          label: 'Parent',
          path: '/a',
          icon: Icons.pageview,
          children: [_menuRef('Nested', '/a/nested')],
        ),
      ];
      final paths = <String>{};
      PageManager.collectChildPaths(children, paths, '/root');
      expect(paths, {'/a', '/a/nested'});
    });
  });

  group('save and load', () {
    test('save then load preserves pages keyed by path', () async {
      final prefs = FakePreferences();
      final mgr = PageManager(
        pages: {
          '/': _page('Home', '/'),
          '/settings': _page('Settings', '/settings'),
        },
        prefs: prefs,
      );
      await mgr.save();

      final mgr2 = PageManager(pages: {}, prefs: prefs);
      await mgr2.load();

      expect(mgr2.pages.length, 2);
      expect(mgr2.pages.containsKey('/'), isTrue);
      expect(mgr2.pages.containsKey('/settings'), isTrue);
      expect(mgr2.pages['/']!.menuItem.label, 'Home');
    });

    test('load with no data creates default Home page at /', () async {
      final prefs = FakePreferences();
      final mgr = PageManager(pages: {}, prefs: prefs);
      await mgr.load();

      expect(mgr.pages.containsKey('/'), isTrue);
      expect(mgr.pages['/']!.menuItem.label, 'Home');
    });

    test('duplicate labels in different sections survive save/load cycle',
        () async {
      final prefs = FakePreferences();
      final mgr = PageManager(
        pages: {
          '/section-a': _page('Section A', '/section-a', children: [
            _menuRef('roe', '/section-a/roe'),
          ]),
          '/section-a/roe': _page('roe', '/section-a/roe'),
          '/section-b': _page('Section B', '/section-b', children: [
            _menuRef('roe', '/section-b/roe'),
          ]),
          '/section-b/roe': _page('roe', '/section-b/roe'),
        },
        prefs: prefs,
      );
      await mgr.save();

      final mgr2 = PageManager(pages: {}, prefs: prefs);
      await mgr2.load();

      expect(mgr2.pages.length, 4);
      expect(mgr2.pages.containsKey('/section-a/roe'), isTrue);
      expect(mgr2.pages.containsKey('/section-b/roe'), isTrue);
      expect(mgr2.pages['/section-a/roe']!.menuItem.label, 'roe');
      expect(mgr2.pages['/section-b/roe']!.menuItem.label, 'roe');
    });
  });

  group('editing scenarios', () {
    test('renaming a page changes its path key', () {
      // Simulate what happens when a user renames a page:
      // 1. Remove old key
      // 2. Insert with new path key
      final mgr = _manager(pages: {
        '/diagnostics': _page('Diagnostics', '/diagnostics', children: [
          _menuRef('IOs', '/diagnostics/ios'),
        ]),
        '/diagnostics/ios': _page('IOs', '/diagnostics/ios'),
      });

      // Simulate rename: IOs -> Inputs/Outputs (path: /diagnostics/inputs-outputs)
      final oldPage = mgr.pages.remove('/diagnostics/ios')!;
      final renamedPage = AssetPage(
        menuItem: MenuItem(
          label: 'Inputs/Outputs',
          path: '/diagnostics/inputs-outputs',
          icon: oldPage.menuItem.icon,
        ),
        assets: oldPage.assets,
        mirroringDisabled: oldPage.mirroringDisabled,
        navigationPriority: oldPage.navigationPriority,
      );
      mgr.pages['/diagnostics/inputs-outputs'] = renamedPage;

      expect(mgr.pages.containsKey('/diagnostics/ios'), isFalse);
      expect(mgr.pages.containsKey('/diagnostics/inputs-outputs'), isTrue);
      expect(mgr.pages['/diagnostics/inputs-outputs']!.menuItem.label,
          'Inputs/Outputs');
    });

    test('renaming does not affect other pages', () {
      final mgr = _manager(pages: {
        '/': _page('Home', '/'),
        '/settings': _page('Settings', '/settings'),
        '/about': _page('About', '/about'),
      });

      // Rename settings -> preferences
      mgr.pages.remove('/settings');
      mgr.pages['/preferences'] = _page('Preferences', '/preferences');

      expect(mgr.pages.length, 3);
      expect(mgr.pages.containsKey('/'), isTrue);
      expect(mgr.pages['/']!.menuItem.label, 'Home');
      expect(mgr.pages.containsKey('/about'), isTrue);
      expect(mgr.pages['/about']!.menuItem.label, 'About');
      expect(mgr.pages.containsKey('/preferences'), isTrue);
    });

    test('renaming page in section A does not affect page in section B', () {
      final mgr = _manager(pages: {
        '/section-a/roe': _page('roe', '/section-a/roe'),
        '/section-b/roe': _page('roe', '/section-b/roe'),
      });

      // Rename section-a's roe to "fish-roe"
      mgr.pages.remove('/section-a/roe');
      mgr.pages['/section-a/fish-roe'] = _page('fish roe', '/section-a/fish-roe');

      expect(mgr.pages.length, 2);
      // Section B's roe is untouched
      expect(mgr.pages.containsKey('/section-b/roe'), isTrue);
      expect(mgr.pages['/section-b/roe']!.menuItem.label, 'roe');
      // Section A's renamed page exists
      expect(mgr.pages.containsKey('/section-a/fish-roe'), isTrue);
    });
  });
}

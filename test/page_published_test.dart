/// Unpublished pages — drafts an engineer is still building.
///
/// `getRootMenuItems` is the only gate: the app feeds its result to both the
/// navigation menu and the route table, so whatever this drops is genuinely
/// unreachable rather than merely hidden. Everything here is about what comes
/// out of that call, plus the two ways a draft could quietly re-publish itself
/// — a round trip through storage, or being moved to another section.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc_dart/core/preferences.dart';

/// Minimal in-memory [PreferencesApi], so a manager can save and reload.
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
  Future<void> clear({Set<String>? allowList}) async => _store.clear();
}

AssetPage _page(
  String label,
  String path, {
  List<MenuItem> children = const [],
  int? priority,
  bool published = true,
}) {
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
    published: published,
  );
}

MenuItem _ref(String label, String path) =>
    MenuItem(label: label, path: path, icon: Icons.pageview);

PageManager _manager(Map<String, AssetPage> pages, [PreferencesApi? prefs]) =>
    PageManager(pages: pages, prefs: prefs ?? _FakePreferences());

/// Every path reachable from [items], the way the router walks them.
Set<String> _reachable(List<MenuItem> items) {
  final paths = <String>{};
  void walk(List<MenuItem> list) {
    for (final item in list) {
      if (item.path != null) paths.add(item.path!);
      walk(item.children);
    }
  }

  walk(items);
  return paths;
}

void main() {
  group('publishing gates navigation', () {
    test('a published page is offered to the menu and the router', () {
      final mgr = _manager({'/': _page('Home', '/')});
      expect(_reachable(mgr.getRootMenuItems()), {'/'});
    });

    test('an unpublished top-level page is not offered at all', () {
      final mgr = _manager({
        '/': _page('Home', '/', priority: 0),
        '/wip': _page('Chiller', '/wip', priority: 1, published: false),
      });

      expect(_reachable(mgr.getRootMenuItems()), {'/'});
      expect(mgr.pages.containsKey('/wip'), isTrue,
          reason: 'the draft stays in the editor, it is only hidden');
    });

    test('an unpublished page inside a section drops out of that section', () {
      final mgr = _manager({
        '/lines': _page('Lines', '/lines', children: [
          _ref('Line 1', '/lines/one'),
          _ref('Line 2', '/lines/two'),
        ]),
        '/lines/one': _page('Line 1', '/lines/one'),
        '/lines/two': _page('Line 2', '/lines/two', published: false),
      });

      final roots = mgr.getRootMenuItems();
      expect(_reachable(roots), {'/lines', '/lines/one'});
      expect(roots.single.children.map((c) => c.label), ['Line 1']);
    });

    test('an unpublished section takes its whole subtree with it', () {
      // Publishing a child of a draft section cannot make it reachable: the
      // section is the only way into it.
      final mgr = _manager({
        '/': _page('Home', '/', priority: 0),
        '/lines': _page('Lines', '/lines', priority: 1, published: false,
            children: [_ref('Line 1', '/lines/one')]),
        '/lines/one': _page('Line 1', '/lines/one'),
      });

      expect(_reachable(mgr.getRootMenuItems()), {'/'});
    });

    test("a section's self-referencing landing entry is left alone", () {
      // A section lists itself as a child to give itself a landing page; that
      // entry is the section, not a separate page to filter.
      final mgr = _manager({
        '/diag': _page('Diagnostics', '/diag', children: [
          _ref('Diagnostics', '/diag'),
          _ref('IOs', '/diag/ios'),
        ]),
        '/diag/ios': _page('IOs', '/diag/ios', published: false),
      });

      final roots = mgr.getRootMenuItems();
      expect(roots.single.children.map((c) => c.path), ['/diag']);
    });

    test('a child that is not one of our pages is not filtered', () {
      // Menu entries registered by the app itself have no AssetPage, so
      // publishing has nothing to say about them.
      final mgr = _manager({
        '/section': _page('Section', '/section', children: [
          _ref('External', '/advanced/history-view'),
        ]),
      });

      expect(_reachable(mgr.getRootMenuItems()),
          {'/section', '/advanced/history-view'});
    });
  });

  group('the flag survives', () {
    test('a save and reload', () async {
      final prefs = _FakePreferences();
      final mgr = _manager({
        '/': _page('Home', '/'),
        '/wip': _page('Chiller', '/wip', published: false),
      }, prefs);
      await mgr.save();

      final reloaded = PageManager(pages: {}, prefs: prefs);
      await reloaded.load();

      expect(reloaded.pages['/wip']!.published, isFalse);
      expect(reloaded.pages['/']!.published, isTrue);
      expect(_reachable(reloaded.getRootMenuItems()), {'/'});
    });

    test('being moved into a section', () {
      final moved = PageManager.movePage(
        {
          '/lines': _page('Lines', '/lines'),
          '/wip': _page('Chiller', '/wip', published: false),
        },
        pagePath: '/wip',
        newParentPath: '/lines',
      );

      expect(moved['/wip']!.published, isFalse,
          reason: 'moving a draft must not publish it');
    });

    test('a copy of the page map', () {
      final copied = PageManager.copyPages({
        '/wip': _page('Chiller', '/wip', published: false),
      });
      expect(copied['/wip']!.published, isFalse);
    });
  });

  group('page data written before publishing existed', () {
    test('loads as published', () async {
      final prefs = _FakePreferences();
      await prefs.setString(
        PageManager.storageKey,
        jsonEncode({
          '/': {
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
        }),
      );

      final mgr = PageManager(pages: {}, prefs: prefs);
      await mgr.load();

      expect(mgr.pages['/']!.published, isTrue,
          reason: 'an upgrade must not hide every existing page');
      expect(_reachable(mgr.getRootMenuItems()), {'/'});
    });
  });
}

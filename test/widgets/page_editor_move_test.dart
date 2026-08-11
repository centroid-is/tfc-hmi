/// Tests for moving a page or section between sections in the page editor.
///
/// The Pages dialog orders items within a level by drag-and-drop, but the
/// nested [ReorderableListView]s swallow drags, so cross-section moves get
/// their own "move" button and destination picker. These tests drive that
/// picker end to end and assert on what the editor saves.
library;

import 'dart:io' show Platform;

import 'package:beamer/beamer.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc_dart/core/preferences.dart';

import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/pages/page_editor.dart';
import 'package:tfc/providers/alarm.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/page_manager.dart';
import 'package:tfc/route_registry.dart';

/// Minimal in-memory [PreferencesApi] so the editor can load and save.
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

AssetPage _page(String label, String path,
    {List<MenuItem> children = const [],
    bool isSection = false,
    int? priority}) {
  return AssetPage(
    menuItem: MenuItem(
      label: label,
      path: path,
      icon: isSection ? Icons.folder : Icons.pageview,
      children: children,
      isSection: isSection,
    ),
    assets: [],
    mirroringDisabled: false,
    navigationPriority: priority,
  );
}

MenuItem _ref(String label, String path) =>
    MenuItem(label: label, path: path, icon: Icons.pageview);

/// Home, a "Packing" section holding "Weigher" and a nested "Lines" section,
/// and an empty "Freezer" section to move things into.
PageManager _manager() {
  return PageManager(
    prefs: _FakePreferences(),
    pages: {
      '/': _page('Home', '/', priority: 0),
      '/packing': _page('Packing', '/packing', isSection: true, priority: 1,
          children: [
            _ref('Weigher', '/packing/weigher'),
            _ref('Lines', '/packing/lines'),
          ]),
      '/packing/weigher': _page('Weigher', '/packing/weigher', priority: 0),
      '/packing/lines':
          _page('Lines', '/packing/lines', isSection: true, priority: 1),
      '/freezer': _page('Freezer', '/freezer', isSection: true, priority: 2),
    },
  );
}

/// The editor lives inside [BaseScaffold], which reads the current Beamer
/// location during build, so it needs a router above it.
class _EditorLocation extends BeamLocation<BeamState> {
  _EditorLocation()
      : super(RouteInformation(uri: Uri.parse('/advanced/page-editor')));

  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) => const [
        BeamPage(key: ValueKey('page-editor'), child: PageEditor()),
      ];

  @override
  List<Pattern> get pathPatterns => ['/advanced/page-editor'];
}

Widget _buildEditor(PageManager manager) {
  final routerDelegate = BeamerDelegate(
    locationBuilder: (routeInformation, _) => _EditorLocation(),
  );
  return ProviderScope(
    overrides: [
      pageManagerProvider.overrideWith((ref) async => manager),
      databaseProvider.overrideWith((ref) async => null),
      alarmManProvider
          .overrideWith((ref) => throw StateError('No AlarmMan in tests')),
    ],
    child: BeamerProvider(
      routerDelegate: routerDelegate,
      child: MaterialApp.router(
        routerDelegate: routerDelegate,
        routeInformationParser: BeamerParser(),
      ),
    ),
  );
}

Future<void> _openPagesDialog(WidgetTester tester) async {
  await tester.tap(find.text('Home').first);
  await tester.pumpAndSettle();
  expect(find.text('Pages'), findsOneWidget);
}

/// The tree row for [label] inside the Pages dialog.
Finder _treeNode(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(ListTile),
    );

/// Opens the destination picker for [label] and returns the picker's dialog.
Future<Finder> _openMoveDialog(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: _treeNode(label),
    matching: find.byIcon(Icons.drive_file_move_outline),
  ));
  await tester.pumpAndSettle();
  final dialog = find.ancestor(
    of: find.text('Move "$label"'),
    matching: find.byType(AlertDialog),
  );
  expect(dialog, findsOneWidget);
  return dialog;
}

/// The picker row for section [label].
Finder _destination(Finder dialog, String label) => find.descendant(
      of: dialog,
      matching: find.widgetWithText(ListTile, label),
    );

/// Holds the row for [label] until the drag starts, drops it on [target], and
/// lets the resulting move settle.
Future<void> _dragRowOnto(
  WidgetTester tester,
  String label,
  Finder target,
) async {
  final gesture = await tester.startGesture(tester.getCenter(_treeNode(label)));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The always-present "Top level" drop zone at the foot of the Pages dialog.
Finder _topLevelDropZone() => find.byIcon(Icons.north);

/// Closes the Pages dialog and presses Save, so the manager holds the result.
Future<void> _closeAndSave(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.save));
  await tester.pumpAndSettle();
}

List<String> _childrenOf(PageManager manager, String path) =>
    manager.pages[path]!.menuItem.children.map((c) => c.path!).toList();

void main() {
  setUp(() {
    // The asset canvas constructs SharedPreferencesAsync directly.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    // BaseScaffold renders a NavigationBar from the registry, which asserts on
    // fewer than two destinations.
    final registry = RouteRegistry();
    registry.menuItems.clear();
    registry.addMenuItem(
        const MenuItem(label: 'Home', path: '/', icon: Icons.home));
    registry.addMenuItem(const MenuItem(
        label: 'Advanced', path: '/advanced', icon: Icons.settings));
  });

  group('moving pages between sections', () {
    testWidgets('a page moves into another section', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      final dialog = await _openMoveDialog(tester, 'Weigher');
      await tester.tap(_destination(dialog, 'Freezer'));
      await tester.pumpAndSettle();

      await _closeAndSave(tester);

      expect(_childrenOf(manager, '/packing'), ['/packing/lines']);
      expect(_childrenOf(manager, '/freezer'), ['/packing/weigher']);
      // The page keeps its address, so links to it stay valid.
      expect(manager.pages['/packing/weigher']!.menuItem.path,
          '/packing/weigher');
    });

    testWidgets('a page moves out to the top level', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      final dialog = await _openMoveDialog(tester, 'Weigher');
      await tester.tap(_destination(dialog, 'Top level'));
      await tester.pumpAndSettle();

      await _closeAndSave(tester);

      expect(_childrenOf(manager, '/packing'), ['/packing/lines']);
      expect(manager.getRootMenuItems().map((r) => r.label).toList(),
          ['Home', 'Packing', 'Freezer', 'Weigher']);
    });

    testWidgets('a section moves with its children', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      final dialog = await _openMoveDialog(tester, 'Packing');
      await tester.tap(_destination(dialog, 'Freezer'));
      await tester.pumpAndSettle();

      await _closeAndSave(tester);

      expect(_childrenOf(manager, '/freezer'), ['/packing']);
      expect(_childrenOf(manager, '/packing'),
          ['/packing/weigher', '/packing/lines']);
      expect(manager.getRootMenuItems().map((r) => r.label).toList(),
          ['Home', 'Freezer']);
    });

    testWidgets('destinations inside the moved item are refused',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildEditor(_manager()));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      final dialog = await _openMoveDialog(tester, 'Packing');

      // Its own nested section would detach the whole subtree.
      expect(
        find.descendant(
          of: _destination(dialog, 'Lines'),
          matching: find.text('Inside the item being moved'),
        ),
        findsOneWidget,
      );
      // Packing is already a root, and cannot be moved into itself.
      expect(
        find.descendant(
          of: _destination(dialog, 'Top level'),
          matching: find.text('Already here'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _destination(dialog, 'Packing'),
          matching: find.text('This is the item being moved'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the current section is not offered as a destination',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildEditor(_manager()));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      final dialog = await _openMoveDialog(tester, 'Weigher');
      expect(
        find.descendant(
          of: _destination(dialog, 'Packing'),
          matching: find.text('Already here'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('dragging a page onto a section moves it', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      await _dragRowOnto(tester, 'Weigher', _treeNode('Freezer'));
      await _closeAndSave(tester);

      expect(_childrenOf(manager, '/packing'), ['/packing/lines']);
      expect(_childrenOf(manager, '/freezer'), ['/packing/weigher']);
    });

    testWidgets('dragging a page onto the top level drop zone un-nests it',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      await _dragRowOnto(tester, 'Weigher', _topLevelDropZone());
      await _closeAndSave(tester);

      expect(_childrenOf(manager, '/packing'), ['/packing/lines']);
      expect(manager.getRootMenuItems().map((r) => r.label).toList(),
          ['Home', 'Packing', 'Freezer', 'Weigher']);
    });

    testWidgets('dragging a section into its own child is refused',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      await _dragRowOnto(tester, 'Packing', _treeNode('Lines'));
      await _closeAndSave(tester);

      expect(_childrenOf(manager, '/packing'),
          ['/packing/weigher', '/packing/lines']);
      expect(_childrenOf(manager, '/packing/lines'), isEmpty);
      expect(manager.getRootMenuItems().map((r) => r.label).toList(),
          ['Home', 'Packing', 'Freezer']);
    });

    testWidgets('dropping a page back on its own section changes nothing',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      await _dragRowOnto(tester, 'Weigher', _treeNode('Packing'));
      await _closeAndSave(tester);

      expect(_childrenOf(manager, '/packing'),
          ['/packing/weigher', '/packing/lines']);
    });

    testWidgets('a move can be undone', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = _manager();
      await tester.pumpWidget(_buildEditor(manager));
      await tester.pumpAndSettle();
      await _openPagesDialog(tester);

      final dialog = await _openMoveDialog(tester, 'Weigher');
      await tester.tap(_destination(dialog, 'Freezer'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      // The editor picks its undo modifier from the host platform.
      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(_childrenOf(manager, '/packing'),
          ['/packing/weigher', '/packing/lines']);
      expect(_childrenOf(manager, '/freezer'), isEmpty);
    });
  });
}

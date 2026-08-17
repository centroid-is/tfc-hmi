/// Reordering the top level of the navigation from the Pages dialog.
///
/// `test/page_manager_test.dart` pins what `sortTopLevel` does with a stored
/// order. This drives the real editor instead: the dialog must list the app's
/// own destinations (registered in the route registry, not pages) next to the
/// root pages, let them be dragged into a new order, and persist that order
/// where the app's next start picks it up.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';

import '../helpers/page_editor_harness.dart';

/// Two pages, so page rows and built-in rows interleave.
PageManager _twoPageManager(FakeEditorPreferences prefs) {
  return PageManager(
    prefs: prefs,
    pages: {
      '/': AssetPage(
        menuItem: const MenuItem(label: 'Home', path: '/', icon: Icons.home),
        assets: [],
        mirroringDisabled: true,
        navigationPriority: 0,
      ),
      '/chiller': AssetPage(
        menuItem: const MenuItem(
            label: 'Chiller', path: '/chiller', icon: Icons.ac_unit),
        assets: [],
        mirroringDisabled: true,
        navigationPriority: 1,
      ),
    },
  );
}

Future<FakeEditorPreferences> _pumpTwoPages(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final prefs = FakeEditorPreferences();
  await tester.pumpWidget(buildEditorUnderTest(_twoPageManager(prefs)));
  await tester.pumpAndSettle();
  return prefs;
}

Future<void> _openPages(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_drop_down));
  await tester.pumpAndSettle();
  expect(find.text('Pages'), findsOneWidget);
}

/// The dialog row labelled [label]. Labels also show up in the editor toolbar
/// and the navigation bar, so everything is scoped to the dialog's tree.
Finder _rowText(String label) => find.descendant(
      of: find.byType(ReorderableListView),
      matching: find.text(label),
    );

Finder _row(String label) => find.ancestor(
      of: _rowText(label),
      matching: find.byType(ListTile),
    );

/// The reorder handle on the row labelled [label].
Finder _dragHandle(String label) =>
    find.descendant(of: _row(label), matching: find.byIcon(Icons.drag_handle));

/// Centre-y of the row labelled [label], for asserting on-screen order.
double _rowY(WidgetTester tester, String label) =>
    tester.getCenter(_rowText(label)).dy;

/// Drags [label]'s handle vertically by [dy], slowly enough for the
/// [ReorderableListView] to track the pointer and settle on a drop index —
/// a single-jump [WidgetTester.drag] outruns it.
Future<void> _reorderBy(WidgetTester tester, String label, double dy) async {
  final gesture =
      await tester.startGesture(tester.getCenter(_dragHandle(label)));
  await tester.pump(const Duration(milliseconds: 100));
  for (var i = 0; i < 4; i++) {
    await gesture.moveBy(Offset(0, dy / 4));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<List<String>?> _savedOrder(FakeEditorPreferences prefs) async {
  final raw = await prefs.getString(PageManager.orderStorageKey);
  if (raw == null) return null;
  return (jsonDecode(raw) as List).cast<String>();
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('the dialog lists app destinations as drag-only rows',
      (tester) async {
    await _pumpTwoPages(tester);
    await _openPages(tester);

    // The harness registers "Advanced" in the registry without a page for it.
    expect(find.text('Built-in — drag to reorder'), findsOneWidget);
    expect(
        find.descendant(
            of: _row('Advanced'), matching: find.byIcon(Icons.delete)),
        findsNothing,
        reason: 'a built-in cannot be deleted, edited or unpublished here');
    expect(_dragHandle('Advanced'), findsOneWidget);

    // Registry order puts it after Home; Chiller, unknown to the registry
    // until a restart, goes last.
    expect(_rowY(tester, 'Home'), lessThan(_rowY(tester, 'Advanced')));
    expect(_rowY(tester, 'Advanced'), lessThan(_rowY(tester, 'Chiller')));
  });

  testWidgets('dragging a built-in above the pages persists the full order',
      (tester) async {
    final prefs = await _pumpTwoPages(tester);
    await _openPages(tester);

    final homeY = _rowY(tester, 'Home');
    final advancedY = _rowY(tester, 'Advanced');
    await _reorderBy(tester, 'Advanced', homeY - advancedY - 20);

    expect(_rowY(tester, 'Advanced'), lessThan(_rowY(tester, 'Home')));

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(await _savedOrder(prefs), ['/advanced', '/', '/chiller']);

    // What the app does on its next start with that order.
    final reloaded = PageManager(pages: {}, prefs: prefs);
    await reloaded.load();
    final items = [
      const MenuItem(label: 'Home', path: '/', icon: Icons.home),
      const MenuItem(
          label: 'Advanced', path: '/advanced', icon: Icons.settings),
    ];
    reloaded.sortTopLevel(items);
    expect(items.first.path, '/advanced');
  });

  testWidgets('reordering only pages still persists and renumbers priorities',
      (tester) async {
    final prefs = await _pumpTwoPages(tester);
    await _openPages(tester);

    final homeY = _rowY(tester, 'Home');
    final chillerY = _rowY(tester, 'Chiller');
    await _reorderBy(tester, 'Chiller', homeY - chillerY - 20);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(await _savedOrder(prefs), ['/chiller', '/', '/advanced']);

    final saved = jsonDecode((await prefs.getString(PageManager.storageKey))!)
        as Map<String, dynamic>;
    expect(saved['/chiller']['navigation_priority'], 0);
    expect(saved['/']['navigation_priority'], 1);
  });

  testWidgets('an untouched editor saves no order', (tester) async {
    final prefs = await _pumpTwoPages(tester);
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(await _savedOrder(prefs), isNull,
        reason: 'no stored order means the registration order still rules');
  });
}

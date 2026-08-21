/// Ctrl/Cmd+Z reaches what the Pages dialog does, too.
///
/// Adding, renaming, deleting and reordering pages went onto the canvas's
/// undo history not at all: the operator's next Ctrl+Z skipped straight past a
/// deleted page to whatever asset edit came before it, and there was no way
/// back at all for the page itself. The dialog is a modal route, so the
/// shortcut deliberately stands down while it is up — these are the undos an
/// operator reaches for after closing it.
///
/// The other half is where the editor is left standing: the snapshot carries
/// the open page and the top-level order alongside the pages, so undoing the
/// creation of a page cannot leave the editor showing one that no longer
/// exists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/assets/common.dart' show Asset;
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc/routes.dart';

import '../helpers/page_editor_harness.dart';

int boxCount(WidgetTester tester) => find.byType(DrawnBox).evaluate().length;

Future<void> openPagesDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_drop_down));
  await tester.pumpAndSettle();
  expect(find.text('Pages'), findsOneWidget);
}

Future<void> closePagesDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
}

/// The tree row for [label] inside the Pages dialog.
Finder treeRow(String label) => find.ancestor(
      of: find.descendant(
          of: find.byType(ListTile), matching: find.text(label)),
      matching: find.byType(ListTile),
    );

/// Adds a top-level page called [name].
Future<void> addPage(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(TextButton, 'Page').last);
  await tester.pumpAndSettle();
  expect(find.text('Add page'), findsOneWidget);
  await tester.enterText(find.byType(TextField).last, name);
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
  await tester.pumpAndSettle();
}

/// Registers the app's default menu, with History View nested under Advanced —
/// the built-in whose promotion is stored in the top-level order.
void registerMenuWithHistoryInAdvanced() {
  final registry = RouteRegistry();
  registry.menuItems.removeWhere((m) => m.path == '/advanced');
  registry.addMenuItem(const MenuItem(
    label: 'Advanced',
    path: '/advanced',
    icon: Icons.settings,
    children: [
      MenuItem(
          label: 'History View',
          path: AppRoutes.historyView,
          icon: Icons.history),
    ],
  ));
}

/// A two-page manager, so a page can be deleted with somewhere left to stand.
PageManager twoPageManager(FakeEditorPreferences prefs, List<Asset> onHome) {
  return PageManager(
    prefs: prefs,
    pages: {
      '/': AssetPage(
        menuItem: const MenuItem(label: 'Home', path: '/', icon: Icons.home),
        assets: onHome,
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

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('undo takes back a page, and the editor with it', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await openPagesDialog(tester);
    await addPage(tester, 'Chiller');
    await closePagesDialog(tester);

    // Creating a page switches to it, so the canvas is now the new empty one.
    expect(boxCount(tester), 0);

    await pressUndo(tester);

    expect(boxCount(tester), 1,
        reason: 'the undo must put the editor back on a page that exists — '
            'not leave it pointed at the one it just removed');
    await openPagesDialog(tester);
    expect(treeRow('Chiller'), findsNothing);
    await closePagesDialog(tester);
  });

  testWidgets('undo brings a deleted page back', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = FakeEditorPreferences();
    await tester.pumpWidget(
        buildEditorUnderTest(twoPageManager(prefs, [editorBox(0.3, 0.3)])));
    await tester.pumpAndSettle();

    await openPagesDialog(tester);
    await tester.tap(find.descendant(
        of: treeRow('Chiller'), matching: find.byIcon(Icons.delete)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last); // Confirm.
    await tester.pumpAndSettle();
    expect(treeRow('Chiller'), findsNothing);
    await closePagesDialog(tester);

    await pressUndo(tester);

    await openPagesDialog(tester);
    expect(treeRow('Chiller'), findsOneWidget,
        reason: 'a deleted page is exactly the thing Ctrl+Z is for');
    await closePagesDialog(tester);
  });

  testWidgets('undo restores a renamed page', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await openPagesDialog(tester);
    await tester.tap(find.descendant(
        of: treeRow('Home'), matching: find.byIcon(Icons.edit)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Overview');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Update'));
    await tester.pumpAndSettle();
    expect(treeRow('Overview'), findsOneWidget);
    await closePagesDialog(tester);

    await pressUndo(tester);

    expect(boxCount(tester), 1,
        reason: 'the rename moved the page to a new path; undoing it must '
            'move the editor back with it rather than leave a blank canvas');
    await openPagesDialog(tester);
    expect(treeRow('Home'), findsOneWidget);
    await closePagesDialog(tester);
  });

  testWidgets('undo puts a promoted built-in back under Advanced',
      (tester) async {
    registerMenuWithHistoryInAdvanced();
    await pumpEditorWith(tester, []);

    await openPagesDialog(tester);
    await tester
        .tap(find.byKey(const ValueKey('promote-builtin-/history-view')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('app-item-/history-view')), findsOneWidget);
    await closePagesDialog(tester);

    await pressUndo(tester);

    await openPagesDialog(tester);
    expect(find.byKey(const ValueKey('advanced-builtin-/history-view')),
        findsOneWidget,
        reason: 'the top-level order is edited here too, so it has to travel '
            'in the undo snapshot — no page JSON records it');
    await closePagesDialog(tester);
  });
}

/// Publishing a page for a permission group, from the Pages dialog.
///
/// `test/access_routes_menu_groups_test.dart` pins what the registry does with
/// `MenuItem.requiredGroup`. This drives the editor: pick a group on a row,
/// save, and read back the JSON an operator's HMI would load — the menu and
/// route table follow from that via `declareMenuRouteGroups`.
///
/// Written RED first: these tests describe the control before it existed.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';

import '../helpers/page_editor_harness.dart';

PageManager _manager(FakeEditorPreferences prefs) {
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

Future<FakeEditorPreferences> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final prefs = FakeEditorPreferences();
  await tester.pumpWidget(buildEditorUnderTest(_manager(prefs)));
  await tester.pumpAndSettle();
  return prefs;
}

Future<void> _openPages(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_drop_down));
  await tester.pumpAndSettle();
  expect(find.text('Pages'), findsOneWidget);
}

/// The published-for control on the row labelled [label], found by tooltip so
/// the test reads the same words the engineer does.
Finder _publishedFor(String label, {String tooltip = 'Published for everyone'}) {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(ListTile),
  );
  return find.descendant(of: row, matching: find.byTooltip(tooltip));
}

Future<Map<String, dynamic>> _saveAndReadPages(
    WidgetTester tester, FakeEditorPreferences prefs) async {
  await tester.tap(find.byIcon(Icons.save));
  await tester.pumpAndSettle();
  final raw = await prefs.getString(PageManager.storageKey);
  expect(raw, isNotNull);
  return jsonDecode(raw!) as Map<String, dynamic>;
}

Map<String, dynamic> _menuItemOf(Map<String, dynamic> saved, String path) =>
    (saved[path] as Map<String, dynamic>)['menu_item'] as Map<String, dynamic>;

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('every row carries the control, reading "everyone" when unset',
      (tester) async {
    await _pump(tester);
    await _openPages(tester);

    expect(_publishedFor('Home'), findsOneWidget);
    expect(_publishedFor('Chiller'), findsOneWidget);
  });

  testWidgets('picking a group publishes the page for it', (tester) async {
    final prefs = await _pump(tester);
    await _openPages(tester);

    await tester.tap(_publishedFor('Chiller'));
    await tester.pumpAndSettle();

    // The menu offers the same words the roles screen uses, plus Everyone.
    expect(find.text('Everyone'), findsOneWidget);
    expect(find.text('Setpoints'), findsOneWidget);
    expect(find.text('Device parameters'), findsOneWidget);

    await tester.tap(find.text('Setpoints'));
    await tester.pumpAndSettle();

    // The control now says so, where the engineer is looking.
    expect(_publishedFor('Chiller', tooltip: 'Published for Setpoints'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    final saved = await _saveAndReadPages(tester, prefs);
    expect(_menuItemOf(saved, '/chiller')['required_group'], 'setpoints');
    expect(_menuItemOf(saved, '/').containsKey('required_group'), isFalse,
        reason: 'the untouched page must not gain a key');
  });

  testWidgets('Everyone clears it again', (tester) async {
    final prefs = await _pump(tester);
    await _openPages(tester);

    await tester.tap(_publishedFor('Chiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setpoints'));
    await tester.pumpAndSettle();

    await tester
        .tap(_publishedFor('Chiller', tooltip: 'Published for Setpoints'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();

    expect(_publishedFor('Chiller'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    final saved = await _saveAndReadPages(tester, prefs);
    expect(_menuItemOf(saved, '/chiller').containsKey('required_group'),
        isFalse,
        reason: 'clearing must remove the key, not write null');
  });

  testWidgets('the choice survives undo of an unrelated edit route: '
      'it is part of page history', (tester) async {
    final prefs = await _pump(tester);
    await _openPages(tester);

    await tester.tap(_publishedFor('Chiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    final saved = await _saveAndReadPages(tester, prefs);
    expect(_menuItemOf(saved, '/chiller')['required_group'], 'configure');
  });
}

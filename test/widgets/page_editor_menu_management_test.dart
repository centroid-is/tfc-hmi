/// The Pages dialog as menu manager: Home is an ordinary page — deletable
/// like any other, with nothing pinning `/` (main.dart no longer registers a
/// hard-coded Home menu item; the `/` route falls back via RouteRedirect when
/// Home is gone).
///
/// Built-in rows and top-level reordering are covered by
/// page_editor_nav_order_test.dart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';

import '../helpers/page_editor_harness.dart';

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

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('Home can be deleted like any other page', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = FakeEditorPreferences();
    await tester.pumpWidget(buildEditorUnderTest(_twoPageManager(prefs)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(find.text('Pages'), findsOneWidget);

    final homeRow = find.ancestor(
        of: find.descendant(
            of: find.byType(ListTile), matching: find.text('Home')),
        matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: homeRow.first, matching: find.byIcon(Icons.delete)));
    await tester.pumpAndSettle();

    // Confirm the dialog.
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    final raw = await prefs.getString(PageManager.storageKey);
    final saved = jsonDecode(raw!) as Map<String, dynamic>;
    expect(saved.containsKey('/'), isFalse,
        reason: 'nothing protects / — deleting Home really removes it');
    expect(saved.containsKey('/chiller'), isTrue);
  });
}

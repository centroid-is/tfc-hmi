/// History View placement in the Pages dialog: it defaults to living under
/// Advanced (its pre-#154 spot) and the operator can promote it to the top
/// level — recorded as membership in the shared top-level order, which is
/// what main.dart reads back at startup (`historyViewIsTopLevel`).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc/routes.dart';

import '../helpers/page_editor_harness.dart';

/// Registers the menu shape the app has by default: History View nested
/// under Advanced.
void _registerMenuWithHistoryInAdvanced() {
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

Future<void> _openPages(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_drop_down));
  await tester.pumpAndSettle();
  expect(find.text('Pages'), findsOneWidget);
}

Future<void> _saveEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.save));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setUpEditorEnvironment();
    _registerMenuWithHistoryInAdvanced();
  });

  testWidgets(
      'History View starts under Advanced: no top-level row, and the dialog '
      'offers "Move to top level"', (tester) async {
    await pumpEditorWith(tester, []);
    await _openPages(tester);

    expect(find.byKey(const ValueKey('app-item-/history-view')), findsNothing);
    expect(find.byKey(const ValueKey('advanced-builtin-/history-view')),
        findsOneWidget);
    expect(find.text('Built-in — in Advanced'), findsOneWidget);
  });

  testWidgets('promoting History View persists it into the top-level order',
      (tester) async {
    final prefs = await pumpEditorWith(tester, []);
    await _openPages(tester);

    await tester
        .tap(find.byKey(const ValueKey('promote-builtin-/history-view')));
    await tester.pumpAndSettle();

    // The dialog now shows it as an ordinary draggable built-in row.
    expect(
        find.byKey(const ValueKey('app-item-/history-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('advanced-builtin-/history-view')),
        findsNothing);

    await _saveEditor(tester);

    final stored = await prefs.getString(PageManager.orderStorageKey);
    expect(stored, isNotNull,
        reason: 'promotion must survive a restart via the stored order');
    final order = (jsonDecode(stored!) as List).cast<String>();
    expect(order, contains(AppRoutes.historyView));
  });

  testWidgets('demoting History View removes it from the stored order',
      (tester) async {
    final prefs = await pumpEditorWith(tester, []);
    await _openPages(tester);

    // Promote first, then demote — the round trip an operator would take.
    await tester
        .tap(find.byKey(const ValueKey('promote-builtin-/history-view')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('demote-builtin-/history-view')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-item-/history-view')), findsNothing);
    expect(find.byKey(const ValueKey('advanced-builtin-/history-view')),
        findsOneWidget);

    await _saveEditor(tester);

    final stored = await prefs.getString(PageManager.orderStorageKey);
    if (stored != null) {
      final order = (jsonDecode(stored) as List).cast<String>();
      expect(order, isNot(contains(AppRoutes.historyView)));
    }
  });
}

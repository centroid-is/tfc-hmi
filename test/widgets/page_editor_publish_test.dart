/// Unpublishing a page from the editor, end to end.
///
/// `test/page_published_test.dart` pins what `getRootMenuItems` does with the
/// flag. This drives the real editor instead: toggle a page in the Pages
/// dialog, save, and read back what an operator's HMI would load on its next
/// start — which is the only thing that decides whether they can reach it.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/page.dart';

import '../helpers/page_editor_harness.dart';

/// Two pages, so one can be hidden while the other stays visible.
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

/// Opens the Pages dialog from the page selector.
Future<void> _openPages(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_drop_down));
  await tester.pumpAndSettle();
  expect(find.text('Pages'), findsOneWidget);
}

/// The publish toggle on the row labelled [label].
Finder _publishToggle(WidgetTester tester, String label) {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(ListTile),
  );
  return find.descendant(
    of: row,
    matching: find.byWidgetPredicate((w) =>
        w is Icon &&
        (w.icon == Icons.visibility || w.icon == Icons.visibility_off)),
  );
}

/// Saves and returns the page map an operator's HMI would load.
Future<Map<String, dynamic>> _saveAndReadPages(
    WidgetTester tester, FakeEditorPreferences prefs) async {
  await tester.tap(find.byIcon(Icons.save));
  await tester.pumpAndSettle();
  final raw = await prefs.getString(PageManager.storageKey);
  expect(raw, isNotNull, reason: 'the editor should have saved the page map');
  return jsonDecode(raw!) as Map<String, dynamic>;
}

/// What the navigation and route table would be built from, after a restart.
Set<String> _navigablePaths(Map<String, dynamic> saved) {
  final manager = PageManager(pages: {}, prefs: FakeEditorPreferences());
  manager.fromJson(jsonEncode(saved));
  final paths = <String>{};
  void walk(List<MenuItem> items) {
    for (final item in items) {
      if (item.path != null) paths.add(item.path!);
      walk(item.children);
    }
  }

  walk(manager.getRootMenuItems());
  return paths;
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('a page starts published', (tester) async {
    final prefs = await _pumpTwoPages(tester);
    final saved = await _saveAndReadPages(tester, prefs);

    expect(_navigablePaths(saved), {'/', '/chiller'});
  });

  testWidgets('unpublishing a page hides it from operators but keeps it',
      (tester) async {
    final prefs = await _pumpTwoPages(tester);

    await _openPages(tester);
    await tester.tap(_publishToggle(tester, 'Chiller'));
    await tester.pumpAndSettle();

    // The row says so, in the dialog the engineer is looking at.
    expect(find.text('Draft — not published'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final saved = await _saveAndReadPages(tester, prefs);
    expect(_navigablePaths(saved), {'/'},
        reason: 'the draft should not reach the menu or the router');
    expect(saved.containsKey('/chiller'), isTrue,
        reason: 'the page and its assets must still be there to finish later');
  });

  testWidgets('the canvas marks the page you are editing as a draft',
      (tester) async {
    await _pumpTwoPages(tester);

    await _openPages(tester);
    await tester.tap(_publishToggle(tester, 'Chiller'));
    await tester.pumpAndSettle();
    // Selecting the page closes the dialog and puts it on the canvas.
    await tester.tap(find.text('Chiller'));
    await tester.pumpAndSettle();

    expect(find.text('Draft'), findsOneWidget,
        reason: 'the page selector should say the page is not published');
  });

  testWidgets('publishing it again puts it back', (tester) async {
    final prefs = await _pumpTwoPages(tester);

    await _openPages(tester);
    await tester.tap(_publishToggle(tester, 'Chiller'));
    await tester.pumpAndSettle();
    await tester.tap(_publishToggle(tester, 'Chiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(_navigablePaths(await _saveAndReadPages(tester, prefs)),
        {'/', '/chiller'});
  });

  testWidgets('unpublishing is undoable', (tester) async {
    final prefs = await _pumpTwoPages(tester);

    await _openPages(tester);
    await tester.tap(_publishToggle(tester, 'Chiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await pressUndo(tester);

    expect(_navigablePaths(await _saveAndReadPages(tester, prefs)),
        {'/', '/chiller'});
  });
}

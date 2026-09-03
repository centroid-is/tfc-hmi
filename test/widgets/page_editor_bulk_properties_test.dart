/// The properties pane inside the page editor: how it is reached, how it
/// keeps up with a selection changing underneath it, and that a bulk edit is
/// one entry on the undo stack.
///
/// The pane itself is covered in `bulk_property_editor_test.dart`. What is
/// tested here is only what the editor owns — the pane is an overlay entry
/// built once, so it does not rebuild simply because the editor did, and
/// every way the selection can move has to be pushed into it by hand.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, TextInputAction;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/widgets/bulk_property_editor.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

/// The width field of the open properties pane.
Finder _widthField() => find.descendant(
      of: find.byKey(bulkControlKey('width')),
      matching: find.byType(TextField),
    );

Future<void> _setWidth(WidgetTester tester, String percent) async {
  await tester.enterText(_widthField(), percent);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// Opens the properties pane on everything the marquee covers.
Future<void> _openOnSelection(
  WidgetTester tester, {
  required double atX,
  required double atY,
  required int count,
}) async {
  await marquee(tester, 0.05, 0.05, 0.95, 0.95);
  expect(selectedCount(tester), count);
  await chooseFromAssetMenu(tester, atX, atY, 'Edit $count assets');
  expect(find.byType(BulkPropertyEditor), findsOneWidget);
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('one typed width resizes the whole selection', (tester) async {
    final prefs = await pumpEditorWith(tester, [
      editorBox(0.25, 0.3),
      editorBox(0.5, 0.3),
      editorBox(0.75, 0.3),
    ]);
    await _openOnSelection(tester, atX: 0.5, atY: 0.3, count: 3);

    await _setWidth(tester, '20');

    final saved = await saveAndReadBack(tester, prefs);
    expect(saved, hasLength(3));
    for (final asset in saved) {
      expect((asset['size'] as Map)['width'], closeTo(0.2, 1e-6));
    }
  });

  testWidgets('a bulk edit is one undo entry, not one per asset',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [
      editorBox(0.25, 0.3),
      editorBox(0.5, 0.3),
      editorBox(0.75, 0.3),
    ]);
    await _openOnSelection(tester, atX: 0.5, atY: 0.3, count: 3);

    await _setWidth(tester, '20');
    await pressUndo(tester);

    // A single Ctrl+Z puts all three back, rather than unwinding them one at
    // a time and leaving the page in a state that was never on screen.
    final saved = await saveAndReadBack(tester, prefs);
    for (final asset in saved) {
      expect((asset['size'] as Map)['width'], isNot(closeTo(0.2, 1e-6)));
    }
  });

  testWidgets('the pane follows the selection growing under it',
      (tester) async {
    await pumpEditorWith(tester, [
      editorBox(0.25, 0.3),
      editorBox(0.5, 0.3),
      editorBox(0.75, 0.3),
    ]);

    // Open on two of the three.
    await marquee(tester, 0.05, 0.05, 0.62, 0.95);
    expect(selectedCount(tester), 2);
    await chooseFromAssetMenu(tester, 0.5, 0.3, 'Edit 2 assets');
    expect(find.text('2 assets'), findsOneWidget);

    // Marquee the third in as well. The pane is an overlay entry and does
    // not rebuild on its own, so this is the editor pushing the change in.
    await marquee(tester, 0.05, 0.05, 0.95, 0.95);
    await tester.pumpAndSettle();

    expect(selectedCount(tester), 3);
    expect(find.text('3 assets'), findsOneWidget);
  });

  testWidgets('a width typed after the selection grew reaches every asset',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [
      editorBox(0.25, 0.3),
      editorBox(0.5, 0.3),
      editorBox(0.75, 0.3),
    ]);

    await marquee(tester, 0.05, 0.05, 0.62, 0.95);
    await chooseFromAssetMenu(tester, 0.5, 0.3, 'Edit 2 assets');
    await marquee(tester, 0.05, 0.05, 0.95, 0.95);
    await tester.pumpAndSettle();

    await _setWidth(tester, '20');

    // Including the asset that joined after the pane opened — the rows are
    // rebound, not left pointing at the original pair.
    final saved = await saveAndReadBack(tester, prefs);
    expect(saved, hasLength(3));
    for (final asset in saved) {
      expect((asset['size'] as Map)['width'], closeTo(0.2, 1e-6));
    }
  });

  testWidgets('deleting the selection closes the pane', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3), editorBox(0.6, 0.6)]);
    await _openOnSelection(tester, atX: 0.3, atY: 0.3, count: 2);

    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    // Nothing left to edit: an empty pane is a dead strip over the canvas.
    expect(find.byType(DrawnBox), findsNothing);
    expect(find.byType(BulkPropertyEditor), findsNothing);
    expect(find.byType(SidePane), findsNothing);
  });

  testWidgets('a canvas edit made outside the pane shows up in its rows',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.25, 0.3), editorBox(0.5, 0.3)]);
    await _openOnSelection(tester, atX: 0.5, atY: 0.3, count: 2);

    final angle = find.descendant(
      of: find.byKey(bulkControlKey('angle')),
      matching: find.byType(TextField),
    );
    // Unrotated assets carry a null angle, which the row shows as empty.
    expect(tester.widget<TextField>(angle).controller?.text, isEmpty);

    // A group rotation is a canvas edit the pane had no hand in; its rows
    // must re-read the assets rather than keep their opening values.
    await pressRotate(tester);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(angle).controller?.text, '90');
  });

  testWidgets('the properties pane and the config pane do not both open',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.25, 0.3), editorBox(0.5, 0.3)]);

    // Open the single-asset form first...
    await tapAsset(tester, 0.25, 0.3);
    await chooseFromAssetMenu(tester, 0.25, 0.3, 'Edit');
    expect(find.byType(SidePane), findsOneWidget);
    expect(find.byType(BulkPropertyEditor), findsNothing);

    // ...then the properties grid. Only one pane fits the strip.
    await _openOnSelection(tester, atX: 0.5, atY: 0.3, count: 2);
    expect(find.byType(SidePane), findsOneWidget);
  });
}

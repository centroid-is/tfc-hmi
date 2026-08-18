/// Undo must survive everything an operator does around a delete.
///
/// Ctrl/Cmd+Z is the whole safety net for the canvas — there is no redo and no
/// confirmation on delete — so it cannot depend on where keyboard focus
/// happens to sit or on which build entry the last no-op burned. The failures
/// pinned here were all reported as "undo is not reliable":
///
///  * Focus parked somewhere neutral (a dismissed dialog, a clicked button)
///    left the editor's Focus subtree out of the key-dispatch chain, so the
///    shortcut never reached the editor at all.
///  * Undo replaces every asset with a fresh copy, but the selection kept the
///    dead instances: the next Delete removed nothing yet still pushed a
///    snapshot, so the following Ctrl+Z popped that no-op and appeared dead.
///  * On macOS only Cmd was accepted, though the same operator uses Ctrl on
///    the plant's Linux panels all day.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/page_creator/assets/text.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

int boxCount(WidgetTester tester) => find.byType(DrawnBox).evaluate().length;

/// A text asset at ([x], [y]) — the asset type whose config pane has text
/// fields, which is what makes the pane hold keyboard focus.
TextAssetConfig textAssetAt(double x, double y) => TextAssetConfig.preview()
  ..coordinates = Coordinates(x: x, y: y)
  ..size = const RelativeSize(width: 0.12, height: 0.06);

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('delete via keyboard, Ctrl/Cmd+Z restores', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    expect(boxCount(tester), 0);

    await pressUndo(tester);
    expect(boxCount(tester), 1, reason: 'undo must bring the asset back');
  });

  testWidgets('undo works with keyboard focus parked nowhere', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    expect(boxCount(tester), 0);

    // What a dismissed dialog or a clicked toolbar button leaves behind:
    // focus on some scope with the editor's Focus node nowhere in the
    // dispatch chain. The shortcut must not depend on it.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await pressUndo(tester);
    expect(boxCount(tester), 1,
        reason: 'undo must not depend on where keyboard focus sits');
  });

  testWidgets('delete from the config pane, Ctrl/Cmd+Z restores',
      (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await tester.tap(find.descendant(
        of: find.byType(SidePane), matching: find.text('Delete')));
    await tester.pumpAndSettle();
    expect(find.byType(TextAssetWidget), findsNothing);

    await pressUndo(tester);
    expect(find.byType(TextAssetWidget), findsOneWidget,
        reason: 'the pane Delete button must be undoable without an '
            'arming click on the canvas first');
  });

  testWidgets('a no-op delete after undo does not burn the history',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    // Two history entries: the rotation, then the delete.
    await tapAsset(tester, 0.3, 0.3);
    await pressRotate(tester);
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    expect(boxCount(tester), 0);

    // Undo the delete; the selection from before it is now dead instances.
    await pressUndo(tester);
    expect(boxCount(tester), 1);

    // A Delete on that dead selection removes nothing — and must not push a
    // snapshot either, or the next undo pops the no-op instead of the
    // rotation.
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    expect(boxCount(tester), 1);

    await pressUndo(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['angle'] ?? 0.0, closeTo(0.0, 0.01),
        reason: 'the second undo must reach the rotation, not a no-op '
            'snapshot');
  });

  testWidgets('Ctrl+Z undoes on every platform, macOS included',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    expect(boxCount(tester), 0);

    // Literal Ctrl, not [editorModifier]: the same operator uses Ctrl on the
    // plant's Linux panels, so the macOS build accepts it alongside Cmd.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(boxCount(tester), 1);
  });

  testWidgets('Delete while typing in the config pane edits text, not assets',
      (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    final paneField = find.descendant(
        of: find.byType(SidePane), matching: find.byType(TextField));
    await tester.tap(paneField.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    await pressEditorKey(tester, LogicalKeyboardKey.backspace);
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    expect(find.byType(TextAssetWidget), findsOneWidget,
        reason: 'keys aimed at a text field must never edit the canvas');

    // Close the pane so its watch timer does not outlive the test.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('Delete with the context menu open does not touch the canvas',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await tester.tapAt(onCanvas(tester, 0.3, 0.3),
        buttons: 0x02 /* kSecondaryButton */);
    await tester.pumpAndSettle();

    await pressEditorKey(tester, LogicalKeyboardKey.delete);

    // Dismiss the menu.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(boxCount(tester), 1,
        reason: 'shortcuts stand down while a menu route is on top');
  });
}

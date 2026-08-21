/// Ctrl/Cmd+Z with an asset's config pane open.
///
/// The pane is non-modal and the canvas keeps working underneath it, so an
/// operator undoes things while configuring — and used to be punished for it
/// twice over:
///
///  * the undo re-parses the page, so the pane's asset became a dead instance
///    and the next watch tick shut the pane. Configuring a device meant
///    reopening the form after every Ctrl+Z.
///  * nothing the pane itself did was on the undo history at all. Ctrl+Z after
///    an hour in the form undid whatever came *before* it and silently kept
///    the pane's edit.
///
/// Both are pinned here. The pane is only shut when the undo genuinely takes
/// its asset away.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/editor_clipboard.dart';
import 'package:tfc/page_creator/assets/text.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

/// A clipboard whose contents the test scripts, as in the paste tests.
class FakeClipboard extends EditorClipboard {
  Uint8List? image;
  String? text;
  @override
  Future<Uint8List?> readImage() async => image;
  @override
  Future<String?> readText() async => text;
  @override
  Future<void> writeText(String value) async => text = value;
}

/// A text asset at ([x], [y]) — the asset type whose pane is a form worth
/// keeping open, and whose one text field is easy to drive.
TextAssetConfig textAssetAt(double x, double y, {String? content}) =>
    TextAssetConfig.preview()
      ..coordinates = Coordinates(x: x, y: y)
      ..size = const RelativeSize(width: 0.12, height: 0.06)
      ..textContent = content ?? 'original';

Finder get paneTextField => find
    .descendant(of: find.byType(SidePane), matching: find.byType(TextField))
    .first;

/// Types [content] into the pane's text field and lets the editor's watch tick
/// notice — the pane edits its asset in place, so a tick is how the change
/// reaches the canvas and the undo history.
Future<void> typeInPane(WidgetTester tester, String content) async {
  await tester.enterText(paneTextField, content);
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pumpAndSettle();
}

Future<void> closePane(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
}

Future<void> pressCopy(WidgetTester tester) async {
  await tester.sendKeyDownEvent(editorModifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(editorModifier);
  await tester.pumpAndSettle();
}

Future<void> pressPaste(WidgetTester tester) async {
  await tester.sendKeyDownEvent(editorModifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(editorModifier);
  await tester.pumpAndSettle();
}

/// Taps the open pane's Delete action, which removes exactly the asset the
/// pane is pointed at.
Future<void> deleteFromPane(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Delete'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setUpEditorEnvironment();
    EditorClipboard.instance = FakeClipboard();
  });

  tearDown(() => EditorClipboard.instance = EditorClipboard());

  testWidgets('undo leaves the open pane open', (tester) async {
    final prefs = await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    // The pane may hold focus; a canvas click re-arms the shortcuts and
    // selects the asset the arrow key is about to move.
    await tapAsset(tester, 0.4, 0.4);
    await pressEditorKey(tester, LogicalKeyboardKey.arrowRight);

    await pressUndo(tester);

    expect(find.byType(SidePane), findsOneWidget,
        reason: 'an undo on the canvas is no reason to take the form away');

    await closePane(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'], closeTo(0.4, 0.0001),
        reason: 'the nudge itself must still have been undone');
  });

  testWidgets('the reopened pane points at the asset that came back',
      (tester) async {
    final prefs = await pumpEditorWith(
        tester, [textAssetAt(0.4, 0.4), textAssetAt(0.7, 0.7)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await tapAsset(tester, 0.4, 0.4);
    await pressEditorKey(tester, LogicalKeyboardKey.arrowRight);
    await pressUndo(tester);

    // The pane's Delete is the sharpest test of what it is pointed at: after
    // the undo it must take the restored 0.4 asset, not its neighbour and not
    // a dead instance.
    await deleteFromPane(tester);

    final saved = await saveAndReadBack(tester, prefs);
    expect(saved, hasLength(1));
    expect(coordsOf(saved.single)['x'], closeTo(0.7, 0.0001));
  });

  testWidgets('the selection survives an undo', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await pressEditorKey(tester, LogicalKeyboardKey.arrowRight);
    await pressUndo(tester);

    expect(selectedCount(tester), 1,
        reason: 'undoing a nudge must not cost the operator their selection');
  });

  testWidgets('the pane closes when the undo takes its asset away',
      (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    // Paste re-points the pane at the copy, so the undo of that paste is an
    // undo of the very asset the pane is showing.
    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await tapAsset(tester, 0.4, 0.4);
    await pressCopy(tester);
    await pressPaste(tester);
    expect(find.byType(TextAssetWidget), findsNWidgets(2));
    expect(find.byType(SidePane), findsOneWidget);

    await pressUndo(tester);

    expect(find.byType(TextAssetWidget), findsOneWidget);
    expect(find.byType(SidePane), findsNothing,
        reason: 'the pasted asset is gone, so its form has nothing to edit');
  });

  testWidgets('an edit made in the pane is undoable', (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await typeInPane(tester, 'changed');
    expect(find.text('changed'), findsWidgets,
        reason: 'the pane mirrors onto the canvas as it is typed');

    await closePane(tester);
    await pressUndo(tester);

    expect(find.text('changed'), findsNothing,
        reason: 'Ctrl+Z must undo the pane edit, not whatever came before it');
    expect(find.text('original'), findsWidgets);
  });

  testWidgets('a run of edits to one property undoes as one', (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await typeInPane(tester, 'half');
    await typeInPane(tester, 'halfway there');
    await closePane(tester);

    await pressUndo(tester);

    expect(find.text('original'), findsWidgets,
        reason: 'typing a label is one edit, not one per keystroke — '
            'otherwise a long key name flushes the whole history');
  });

  testWidgets('a pane edit made just before Ctrl+Z is the thing undone',
      (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    // A rotation first, so there is an older entry for the undo to reach
    // past if the pane's own edit never made it onto the history.
    await tapAsset(tester, 0.4, 0.4);
    await pressRotate(tester);
    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await typeInPane(tester, 'changed');

    // No pane close and no canvas click: straight to the shortcut, the way an
    // operator who has just clicked a colour swatch would.
    await tester.tap(find.byType(TextAssetWidget).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await pressUndo(tester);

    expect(find.text('changed'), findsNothing);
    expect(find.text('original'), findsWidgets);
    expect(find.byType(SidePane), findsOneWidget,
        reason: 'undoing the pane edit leaves the form up to carry on in');

    await closePane(tester);
  });
}

/// Arrow keys nudge the canvas selection.
///
/// The mouse is fine for coarse placement but hopeless for the last few
/// pixels; the arrows are the precision tool. The contract pinned here:
///
///  * one press moves the whole selection exactly one canvas pixel, Shift
///    makes it ten — both in screen direction, regardless of asset rotation;
///  * holding the key keeps moving (repeats count), yet the whole
///    press-and-hold walks back in a single Ctrl/Cmd+Z;
///  * an empty selection and the canvas edge are both quietly inert;
///  * a focused text field owns its own arrows — the caret must move, not
///    the selection behind the pane.
library;

import 'package:flutter/material.dart' show Size, TextField;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/pages/page_view.dart' show AssetStack;

import '../helpers/page_editor_harness.dart';

/// The canvas's rendered size, for converting the pixel nudge back into the
/// normalized coordinates the page persists.
Size canvasSize(WidgetTester tester) =>
    tester.getRect(find.byType(AssetStack)).size;

/// Taps [key] with optional repeats before release, the shape of a real
/// press-and-hold.
Future<void> pressArrow(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  int repeats = 0,
  bool shift = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  for (var i = 0; i < repeats; i++) {
    await tester.sendKeyRepeatEvent(key);
  }
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('one press moves the selection one canvas pixel',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight);
    await pressArrow(tester, LogicalKeyboardKey.arrowDown);

    final canvas = canvasSize(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'],
        closeTo(0.3 + 1 / canvas.width, 1e-9));
    expect(coordsOf(saved.single)['y'],
        closeTo(0.3 + 1 / canvas.height, 1e-9));
  });

  testWidgets('all four directions move where they say', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.5, 0.5)]);
    await tapAsset(tester, 0.5, 0.5);

    // Two rights, one left, two downs, one up: net one right and one down.
    await pressArrow(tester, LogicalKeyboardKey.arrowRight);
    await pressArrow(tester, LogicalKeyboardKey.arrowRight);
    await pressArrow(tester, LogicalKeyboardKey.arrowLeft);
    await pressArrow(tester, LogicalKeyboardKey.arrowDown);
    await pressArrow(tester, LogicalKeyboardKey.arrowDown);
    await pressArrow(tester, LogicalKeyboardKey.arrowUp);

    final canvas = canvasSize(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'],
        closeTo(0.5 + 1 / canvas.width, 1e-9));
    expect(coordsOf(saved.single)['y'],
        closeTo(0.5 + 1 / canvas.height, 1e-9));
  });

  testWidgets('Shift makes the step ten pixels', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight, shift: true);

    final canvas = canvasSize(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'],
        closeTo(0.3 + 10 / canvas.width, 1e-9));
    expect(coordsOf(saved.single)['y'], closeTo(0.3, 1e-9));
  });

  testWidgets('the arrows move in screen direction on a rotated asset',
      (tester) async {
    // A drag on a rotated asset arrives in the rotated local frame and has
    // to be projected back; the arrows never enter that frame, so rotation
    // must not bend them.
    final prefs =
        await pumpEditorWith(tester, [editorBox(0.4, 0.4, angle: 90)]);
    await tapAsset(tester, 0.4, 0.4);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight);

    final canvas = canvasSize(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'],
        closeTo(0.4 + 1 / canvas.width, 1e-9));
    expect(coordsOf(saved.single)['y'], closeTo(0.4, 1e-9));
  });

  testWidgets('a multi-selection moves as one', (tester) async {
    final prefs = await pumpEditorWith(
        tester, [editorBox(0.2, 0.2), editorBox(0.6, 0.6)]);
    await marquee(tester, 0.05, 0.05, 0.75, 0.75);
    expect(selectedCount(tester), 2);

    await pressArrow(tester, LogicalKeyboardKey.arrowDown);

    final canvas = canvasSize(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(savedYs(saved), [
      closeTo(0.2 + 1 / canvas.height, 1e-9),
      closeTo(0.6 + 1 / canvas.height, 1e-9),
    ]);
    expect(savedXs(saved), [closeTo(0.2, 1e-9), closeTo(0.6, 1e-9)]);
  });

  testWidgets('nothing selected, nothing moves', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight);

    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'], closeTo(0.3, 1e-9));
  });

  testWidgets('the canvas edge clamps, exactly like a drag', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.001, 0.3)]);
    await tapAsset(tester, 0.001, 0.3);

    await pressArrow(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    await pressArrow(tester, LogicalKeyboardKey.arrowLeft, shift: true);

    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'], 0.0);
  });

  testWidgets('holding the key keeps moving', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight, repeats: 4);

    final canvas = canvasSize(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'],
        closeTo(0.3 + 5 / canvas.width, 1e-9));
  });

  testWidgets('a whole press-and-hold is one undo entry', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight, repeats: 4);
    await pressUndo(tester);

    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'], closeTo(0.3, 1e-9),
        reason: 'one Ctrl/Cmd+Z must take back the whole hold, not one '
            'pixel of it');
  });

  testWidgets('separate presses undo one press at a time', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight);
    await pressArrow(tester, LogicalKeyboardKey.arrowRight);
    await pressUndo(tester);

    final canvas = canvasSize(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'],
        closeTo(0.3 + 1 / canvas.width, 1e-9));
  });

  testWidgets('a focused text field keeps its arrows', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);

    // The config pane's text fields take keyboard focus; the caret owns the
    // arrows for as long as they do.
    await chooseFromAssetMenu(tester, 0.3, 0.3, 'Edit');
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    await pressArrow(tester, LogicalKeyboardKey.arrowLeft);

    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'], closeTo(0.3, 1e-9),
        reason: 'arrows in a text field must move the caret, not the '
            'selection behind it');
  });
}

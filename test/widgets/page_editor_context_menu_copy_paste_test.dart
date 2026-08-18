/// Copy and Paste from the right-click menus, end to end.
///
/// The asset menu gains Copy (the selection when the clicked asset is in it,
/// otherwise just that asset — the same targets rule as every other entry)
/// and "Paste here". Empty canvas gains its own right-click menu whose
/// "Paste here" drops the copied group centred on the click point, pulled
/// back on-canvas near an edge. Right-clicking empty canvas must no longer
/// start a marquee or clear the selection.
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/page_creator/assets/editor_clipboard.dart';

import '../helpers/page_editor_harness.dart';

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

int boxCount(WidgetTester tester) => find.byType(DrawnBox).evaluate().length;

/// Right-clicks empty canvas at relative ([fx], [fy]) and taps the canvas
/// menu's "Paste here".
Future<void> pasteHereAt(WidgetTester tester, double fx, double fy) async {
  await tester.tapAt(onCanvas(tester, fx, fy), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  expect(find.text('Paste here'), findsOneWidget,
      reason: 'right-clicking empty canvas should offer "Paste here"');
  await tester.tap(find.text('Paste here'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setUpEditorEnvironment();
    EditorClipboard.instance = FakeClipboard();
  });

  tearDown(() => EditorClipboard.instance = EditorClipboard());

  testWidgets('menu Copy, then canvas-menu Paste lands centred on the click',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await chooseFromAssetMenu(tester, 0.3, 0.3, 'Copy');
    await pasteHereAt(tester, 0.7, 0.6);

    expect(boxCount(tester), 2);
    expect(selectedCount(tester), 1,
        reason: 'the pasted copy becomes the selection');

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved)[1], closeTo(0.7, 0.005));
    expect(savedYs(saved)[1], closeTo(0.6, 0.005));
  });

  testWidgets('Copy acts on the whole selection, and paste keeps its layout',
      (tester) async {
    final prefs = await pumpEditorWith(
        tester, [editorBox(0.3, 0.3), editorBox(0.5, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await tapAsset(tester, 0.5, 0.3, addToSelection: true);
    // The entry counts its targets, like every other selection-aware entry.
    await chooseFromAssetMenu(tester, 0.3, 0.3, 'Copy 2 assets');
    await pasteHereAt(tester, 0.5, 0.7);

    expect(boxCount(tester), 4);

    final saved = await saveAndReadBack(tester, prefs);
    final xs = savedXs(saved);
    final ys = savedYs(saved);
    // Rigid drop, centred on the click.
    expect(xs[3] - xs[2], closeTo(0.2, 1e-9));
    expect((xs[2] + xs[3]) / 2, closeTo(0.5, 0.005));
    expect(ys[2], closeTo(0.7, 0.005));
    expect(ys[3], closeTo(0.7, 0.005));
  });

  testWidgets('the asset menu itself offers Paste here', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Copy');
    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Paste here');

    expect(boxCount(tester), 2);
  });

  testWidgets('a paste at the edge lands flush, not half off-canvas',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await chooseFromAssetMenu(tester, 0.3, 0.3, 'Copy');
    await pasteHereAt(tester, 0.99, 0.5);

    final saved = await saveAndReadBack(tester, prefs);
    // The box is 0.12 wide: flush right is x = 1 - 0.06.
    expect(savedXs(saved)[1], closeTo(0.94, 0.005));
  });

  testWidgets('right-clicking empty canvas does not clear the selection',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    expect(selectedCount(tester), 1);

    await tester.tapAt(onCanvas(tester, 0.7, 0.7), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(selectedCount(tester), 1,
        reason: 'a right-click asks for a menu, it is not a deselect');

    // Dismiss the menu.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });
}

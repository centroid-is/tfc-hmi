/// Copy/paste in the page editor must survive the operator touching anything
/// else that takes keyboard focus.
///
/// The shortcuts are handled globally, so focus cannot starve them of key
/// events — but they deliberately stand down while a text field has focus,
/// or typing would edit the canvas. The persistent danger is a field that
/// *keeps* focus while the operator returns to the canvas — above all the
/// config side pane, which lives in the root overlay: configure an asset,
/// click that same asset (the pane stays open), press Ctrl/Cmd+C — if the
/// pane's field still held focus, the shortcut would still be muted.
///
/// The behaviour pinned here: any click on the canvas takes keyboard focus
/// back from whatever text field held it, un-muting the shortcuts.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/page_creator/assets/editor_clipboard.dart';
import 'package:tfc/page_creator/assets/text.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

/// A clipboard whose contents the test scripts, as in the image-paste tests.
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

int boxCount(WidgetTester tester) => find.byType(DrawnBox).evaluate().length;

/// A text asset at ([x], [y]) — the asset type whose config pane has text
/// fields, which is what makes the pane hold keyboard focus.
TextAssetConfig textAssetAt(double x, double y) => TextAssetConfig.preview()
  ..coordinates = Coordinates(x: x, y: y)
  ..size = const RelativeSize(width: 0.12, height: 0.06);

/// Puts focus into the first text field of the open config pane.
Future<void> focusPaneField(WidgetTester tester) async {
  final paneField = find.descendant(
      of: find.byType(SidePane), matching: find.byType(TextField));
  expect(paneField, findsWidgets,
      reason: 'the text asset config pane offers text fields');
  await tester.tap(paneField.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Closes the pane so its periodic watch timer does not outlive the test.
Future<void> closePane(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setUpEditorEnvironment();
    EditorClipboard.instance = FakeClipboard();
  });

  tearDown(() => EditorClipboard.instance = EditorClipboard());

  testWidgets('select, copy, paste duplicates the asset', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await pressCopy(tester);
    await pressPaste(tester);

    expect(boxCount(tester), 2);
    expect(selectedCount(tester), 1,
        reason: 'the pasted copy becomes the selection');
  });

  testWidgets(
      'configure an asset, reselect it, copy/paste — the everyday '
      'configure-then-duplicate flow', (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    // Open the asset's config pane and put focus in one of its fields.
    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await focusPaneField(tester);

    // Click the same asset: the pane stays open (it already shows this
    // asset), so nothing disposes the focused field — the click itself has
    // to bring keyboard focus back to the canvas.
    await tapAsset(tester, 0.4, 0.4);
    expect(selectedCount(tester), 1);

    await pressCopy(tester);
    await pressPaste(tester);

    expect(find.byType(TextAssetWidget), findsNWidgets(2),
        reason: 'a canvas click while the config pane holds focus '
            'must re-arm the copy/paste shortcuts');

    await closePane(tester);
  });

  testWidgets('marquee-select with the config pane focused, then copy/paste',
      (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await focusPaneField(tester);

    // Rubber-band over the asset, starting on empty canvas — the other way
    // an operator reselects after configuring.
    await marquee(tester, 0.2, 0.2, 0.55, 0.6);
    expect(selectedCount(tester), 1);

    await pressCopy(tester);
    await pressPaste(tester);

    expect(find.byType(TextAssetWidget), findsNWidgets(2),
        reason: 'starting a marquee while the config pane holds focus '
            'must re-arm the copy/paste shortcuts');

    await closePane(tester);
  });

  testWidgets('copy/paste still works after typing in the palette search',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.35, 0.35)]);

    // Open the palette and put focus in its search field, the way an
    // operator does when hunting for an asset type.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'box');
    await tester.pump();

    // First click dismisses the palette (its tap-out barrier wins the
    // gesture arena), the second selects the asset.
    await tapAsset(tester, 0.35, 0.35);
    await tapAsset(tester, 0.35, 0.35);
    expect(selectedCount(tester), 1);

    await pressCopy(tester);
    await pressPaste(tester);

    expect(boxCount(tester), 2,
        reason: 'canvas clicks after using the palette search '
            'must re-arm the copy/paste shortcuts');
  });
}

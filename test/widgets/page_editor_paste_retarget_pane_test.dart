/// Pasting while an asset's config pane is open re-points the pane at what
/// the paste produced.
///
/// The everyday flow: an operator configures an asset, duplicates it, and
/// goes on to configure the copy. Before this behaviour the pane kept showing
/// the source, so edits meant for the copy — and above all the pane's Delete
/// button — landed on the original. A paste of a single asset (copied or an
/// image from the clipboard) now swaps the pane over to it; a group paste has
/// no single asset for the pane to show, so it stays on the source. A paste
/// with no pane open opens none.
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

import '../helpers/image_fixtures.dart';
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

/// A text asset at ([x], [y]) — an asset type with a config pane worth
/// keeping open through a duplicate-and-edit flow.
TextAssetConfig textAssetAt(double x, double y) => TextAssetConfig.preview()
  ..coordinates = Coordinates(x: x, y: y)
  ..size = const RelativeSize(width: 0.12, height: 0.06);

/// Taps the open pane's Delete action, which removes exactly the asset the
/// pane is pointed at — the discriminator these tests read the retarget from.
Future<void> deleteFromPane(WidgetTester tester) async {
  final button = find.widgetWithText(TextButton, 'Delete');
  expect(button, findsOneWidget,
      reason: 'the config pane offers a Delete action');
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> closePane(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeClipboard clipboard;

  setUp(() {
    setUpEditorEnvironment();
    clipboard = FakeClipboard();
    EditorClipboard.instance = clipboard;
  });

  tearDown(() => EditorClipboard.instance = EditorClipboard());

  testWidgets('pasting one asset re-points the open pane at the copy',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    // The pane may hold focus; a canvas click re-arms the shortcuts.
    await tapAsset(tester, 0.4, 0.4);
    await pressCopy(tester);
    await pressPaste(tester);

    expect(find.byType(TextAssetWidget), findsNWidgets(2));
    expect(find.byType(SidePane), findsOneWidget,
        reason: 'the pane survives the paste, now showing the copy');

    // Deleting from the pane must take the pasted copy (offset from the
    // source by the paste nudge), leaving the source where it was.
    await deleteFromPane(tester);
    expect(find.byType(TextAssetWidget), findsOneWidget);

    final saved = await saveAndReadBack(tester, prefs);
    expect(saved, hasLength(1));
    expect(coordsOf(saved.single)['x'], closeTo(0.4, 0.001),
        reason: 'the survivor is the source — the pane pointed at the copy');
  });

  testWidgets('pasting with no pane open opens none', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

    await tapAsset(tester, 0.3, 0.3);
    await pressCopy(tester);
    await pressPaste(tester);

    expect(find.byType(DrawnBox), findsNWidgets(2));
    expect(find.byType(SidePane), findsNothing,
        reason: 'a paste alone is not a request to start configuring');
  });

  testWidgets('a group paste leaves the pane on the source asset',
      (tester) async {
    final prefs = await pumpEditorWith(
        tester, [editorBox(0.3, 0.3), editorBox(0.6, 0.6)]);

    // Copy both, then open the pane on the first. Selecting it alone first
    // is what makes Edit mean the single-asset config pane: with the pair
    // still selected the entry opens the properties grid instead.
    await marquee(tester, 0.15, 0.15, 0.75, 0.75);
    expect(selectedCount(tester), 2);
    await pressCopy(tester);
    await tapAsset(tester, 0.3, 0.3);
    await chooseFromAssetMenu(tester, 0.3, 0.3, 'Edit');

    // Reselect the pair — the marquee also brings keyboard focus back to
    // the canvas — and paste the group.
    await marquee(tester, 0.15, 0.15, 0.75, 0.75);
    await pressPaste(tester);

    expect(find.byType(DrawnBox), findsNWidgets(4));
    expect(find.byType(SidePane), findsOneWidget);

    // The pane still points at the source: its Delete removes the box at
    // 0.3, not either of the pasted pair (nudged to 0.32 / 0.62).
    await deleteFromPane(tester);
    final saved = await saveAndReadBack(tester, prefs);
    final xs = savedXs(saved)..sort();
    expect(xs, hasLength(3));
    expect(xs[0], closeTo(0.32, 0.001));
    expect(xs[1], closeTo(0.6, 0.001));
    expect(xs[2], closeTo(0.62, 0.001));
  });

  testWidgets('pasting a clipboard image re-points the pane at the new image',
      (tester) async {
    await pumpEditorWith(tester, [textAssetAt(0.4, 0.4)]);

    await chooseFromAssetMenu(tester, 0.4, 0.4, 'Edit');
    await tapAsset(tester, 0.4, 0.4);
    expect(find.widgetWithText(SidePane, 'Text'), findsOneWidget);

    clipboard.image = fixturePngBytes;
    await pressPaste(tester);
    // Ingest decodes the image through the engine's codec; that future only
    // completes while real async is allowed to run.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SidePane, 'Image'), findsOneWidget,
        reason: 'the pane now shows the pasted image asset');

    await closePane(tester);
  });
}

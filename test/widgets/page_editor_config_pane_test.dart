/// End-to-end cover for the page editor's asset configuration pane.
///
/// Configuring an asset used to open a modal dialog: a barrier over the
/// canvas, nothing visible behind it, and a close-reopen cycle for every
/// change you wanted to see. It is now a docked, non-modal `SidePane`, which
/// changes three things a test can pin down:
///
///   * the canvas is still there and still live while the pane is open,
///   * edits made in the pane land on the canvas without closing it, and
///   * the pane follows the operator — tapping another asset re-points it,
///     and an asset that leaves the canvas takes its pane with it.
///
/// The live-update path is the one worth guarding. Config editors write
/// straight into the asset they were handed, so the editor watches the asset's
/// serialization rather than any callback; if that watch stops running these
/// tests fail while nothing else does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

/// Taps the asset at canvas-relative ([fx], [fy]) in pan mode, which is what
/// opens its config pane.
Future<void> tapAsset(WidgetTester tester, double fx, double fy) async {
  await tester.tapAt(onCanvas(tester, fx, fy));
  await tester.pumpAndSettle();
}

/// Where the single drawn box sits, as a fraction of the canvas.
Offset boxOnCanvas(WidgetTester tester, [int index = 0]) {
  final canvas = tester.getRect(find.byType(AssetStack));
  final box = tester.getCenter(find.byType(DrawnBox).at(index));
  return Offset(
    (box.dx - canvas.left) / canvas.width,
    (box.dy - canvas.top) / canvas.height,
  );
}

/// Types [value] into the coordinate field labelled [label] in the open pane,
/// then waits out one poll of the editor's config watch.
Future<void> enterCoordinate(
    WidgetTester tester, String label, String value) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );
  expect(field, findsOneWidget, reason: 'the pane should offer "$label"');
  await tester.enterText(field, value);
  // Typing produces no pointer event, so the canvas only catches up on the
  // next tick of the watch.
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pumpAndSettle();
}

/// Drags the asset at canvas-relative ([fx], [fy]) [dx] pixels to the right.
///
/// Deliberately many small moves rather than one big one: the asset's pan
/// recognizer shares an arena with the canvas's `InteractiveViewer`, and a
/// single jump lets the viewer take the gesture.
Future<void> dragAssetRight(
    WidgetTester tester, double fx, double fy, double dx) async {
  final gesture = await tester.startGesture(onCanvas(tester, fx, fy));
  await tester.pump(const Duration(milliseconds: 20));
  for (var moved = 0.0; moved < dx; moved += 20) {
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Closes the pane the way an operator would, so no watch timer outlives the
/// test.
Future<void> closePane(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('tapping an asset docks a pane instead of a modal dialog',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await tapAsset(tester, 0.3, 0.4);

    expect(find.byType(SidePane), findsOneWidget);
    expect(find.byType(Dialog), findsNothing,
        reason: 'the config editor should no longer be a dialog');

    // Non-modal: nothing is covering the canvas, and the canvas is still
    // rendering the asset behind the pane.
    expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
    expect(find.byType(AssetStack), findsOneWidget);
    expect(find.byType(DrawnBox), findsOneWidget);

    await closePane(tester);
    expect(find.byType(SidePane), findsNothing);
  });

  testWidgets('edits in the pane reach the canvas while it stays open',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await tapAsset(tester, 0.3, 0.4);

    await enterCoordinate(tester, 'X 0-100%', '70');

    expect(find.byType(SidePane), findsOneWidget,
        reason: 'the pane should not have to close for the change to show');
    expect(boxOnCanvas(tester).dx, closeTo(0.7, 0.005),
        reason: 'the canvas should already show the new x');

    await closePane(tester);
  });

  testWidgets('a pane edit is part of what gets saved', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await tapAsset(tester, 0.3, 0.4);
    await enterCoordinate(tester, 'Y 0-100%', '80');
    await closePane(tester);

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedYs(saved), [closeTo(0.8, 1e-9)]);
  });

  testWidgets('tapping another asset re-points the open pane', (tester) async {
    // Both boxes sit left of where the pane docks, so the second tap reaches
    // the canvas rather than the pane sitting over it.
    await pumpEditorWith(tester, [editorBox(0.2, 0.3), editorBox(0.45, 0.6)]);

    await tapAsset(tester, 0.2, 0.3);
    expect(find.byType(SidePane), findsOneWidget);

    await tapAsset(tester, 0.45, 0.6);
    expect(find.byType(SidePane), findsOneWidget,
        reason: 'one pane, swapped over — not a second one on top');

    // The pane is now editing the second box: move it and check which one
    // shifted.
    await enterCoordinate(tester, 'X 0-100%', '90');
    expect(boxOnCanvas(tester, 0).dx, closeTo(0.2, 0.005));
    expect(boxOnCanvas(tester, 1).dx, closeTo(0.9, 0.005));

    await closePane(tester);
  });

  testWidgets('the canvas still takes drags while the pane is open',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await tapAsset(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget);

    // The whole point of the pane: drag the asset around without dismissing
    // the editor first.
    await dragAssetRight(tester, 0.3, 0.4, 140);

    expect(find.byType(SidePane), findsOneWidget,
        reason: 'dragging on the canvas must not dismiss the pane');
    expect(boxOnCanvas(tester).dx, greaterThan(0.35),
        reason: 'the drag should have moved the asset');

    await closePane(tester);
    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved).single, greaterThan(0.35));
  });

  testWidgets('the pane can be dragged wider, and stays that wide',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.2, 0.3), editorBox(0.45, 0.6)]);
    await tapAsset(tester, 0.2, 0.3);

    final before = tester.getRect(find.byType(SidePane)).width;

    // The handle is the strip down the pane's left edge.
    final pane = tester.getRect(find.byType(SidePane));
    await tester.dragFrom(
      Offset(pane.left + 4, pane.center.dy),
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(SidePane)).width;
    expect(after, closeTo(before + 160, 1),
        reason: 'dragging the handle left should widen the pane');

    // The width an engineer settled on is the one the next asset opens at.
    await tapAsset(tester, 0.45, 0.6);
    expect(tester.getRect(find.byType(SidePane)).width, closeTo(after, 1));

    await closePane(tester);
  });

  testWidgets('tapping the same asset again closes its pane', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    await tapAsset(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget);

    await tapAsset(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsNothing);
  });

  testWidgets('deleting from the pane removes the asset and closes the pane',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await tapAsset(tester, 0.3, 0.4);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(SidePane), findsNothing);
    expect(find.byType(DrawnBox), findsNothing);

    final saved = await saveAndReadBack(tester, prefs);
    expect(saved, isEmpty);
  });

  testWidgets('the pane follows the asset off the canvas', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await tapAsset(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget);

    // Select the box and delete it with the keyboard — a path that knows
    // nothing about the pane.
    await enterSelectMode(tester);
    await marquee(tester, 0.1, 0.2, 0.6, 0.7);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.byType(DrawnBox), findsNothing);
    expect(find.byType(SidePane), findsNothing,
        reason: 'a pane must not outlive the asset it is configuring');
  });
}

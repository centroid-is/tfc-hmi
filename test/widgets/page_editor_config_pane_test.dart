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
///
/// The pane is opened from the right-click menu's "Edit" entry. It used to
/// open on a plain tap, back when the editor had a separate mode in which
/// tapping selected instead; with one mode a tap always selects, so
/// configuring moved to the menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

/// Opens the config pane for the asset at canvas-relative ([fx], [fy]) the way
/// an operator does: right-click, then "Edit".
Future<void> openConfigPane(WidgetTester tester, double fx, double fy) =>
    chooseFromAssetMenu(tester, fx, fy, 'Edit');

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
  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('"Edit" docks a pane instead of a modal dialog', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await openConfigPane(tester, 0.3, 0.4);

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
    await openConfigPane(tester, 0.3, 0.4);

    await enterCoordinate(tester, 'X 0-100%', '70');

    expect(find.byType(SidePane), findsOneWidget,
        reason: 'the pane should not have to close for the change to show');
    expect(boxOnCanvas(tester).dx, closeTo(0.7, 0.005),
        reason: 'the canvas should already show the new x');

    await closePane(tester);
  });

  testWidgets('a pane edit is part of what gets saved', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await openConfigPane(tester, 0.3, 0.4);
    await enterCoordinate(tester, 'Y 0-100%', '80');
    await closePane(tester);

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedYs(saved), [closeTo(0.8, 1e-9)]);
  });

  testWidgets('a plain tap on another asset re-points the open pane',
      (tester) async {
    // Both boxes sit left of where the pane docks, so the second tap reaches
    // the canvas rather than the pane sitting over it.
    await pumpEditorWith(tester, [editorBox(0.2, 0.3), editorBox(0.45, 0.6)]);

    await openConfigPane(tester, 0.2, 0.3);
    expect(find.byType(SidePane), findsOneWidget);

    // Only the first one needs the menu. With a pane already up it behaves as
    // an inspector for the selection, so selecting the next asset is enough —
    // which is what makes configuring several assets in a row bearable now
    // that a tap no longer opens the editor by itself.
    await tapAsset(tester, 0.45, 0.6);
    expect(find.byType(SidePane), findsOneWidget,
        reason: 'one pane, swapped over — not a second one on top');
    expect(selectedCount(tester), 1,
        reason: 'the tap should have selected the asset it re-pointed to');

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
    await openConfigPane(tester, 0.3, 0.4);
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

  testWidgets('tapping the asset the pane is already on leaves it open',
      (tester) async {
    // The pane's open/close is a toggle underneath, which would make the
    // asset it is already showing the one asset you cannot click without
    // losing the editor. Both routes back onto it have to be no-ops.
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    await openConfigPane(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget);

    await tapAsset(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget,
        reason: 'selecting the configured asset should not close its pane');

    await openConfigPane(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget,
        reason: '"Edit" on the configured asset should not close its pane');

    await closePane(tester);
    expect(find.byType(SidePane), findsNothing,
        reason: 'Close is what closes it');
  });

  testWidgets('deleting from the pane removes the asset and closes the pane',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await openConfigPane(tester, 0.3, 0.4);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(SidePane), findsNothing);
    expect(find.byType(DrawnBox), findsNothing);

    final saved = await saveAndReadBack(tester, prefs);
    expect(saved, isEmpty);
  });

  testWidgets('the pane follows the asset off the canvas', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await openConfigPane(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget);

    // Select the box and delete it with the keyboard — a path that knows
    // nothing about the pane.
    await marquee(tester, 0.1, 0.2, 0.6, 0.7);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.byType(DrawnBox), findsNothing);
    expect(find.byType(SidePane), findsNothing,
        reason: 'a pane must not outlive the asset it is configuring');
  });
}

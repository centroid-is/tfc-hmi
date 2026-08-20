/// The canvas steps aside from the config pane — not the other way round.
///
/// The pane docks over the right-hand strip of the screen, which is exactly
/// where the asset being configured may live — and an editor you cannot see
/// under the form that edits it defeats the point of a non-modal pane. So the
/// editor gives the pane its strip outright: the canvas re-fits itself beside
/// the open pane (it is an aspect-fitted box, so the whole page stays in
/// view, just smaller), follows the pane's resize handle, and takes the strip
/// back when the pane closes. The pane itself keeps the width the operator
/// chose — no asset position can squeeze it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc/widgets/zoomable_canvas.dart';

import '../helpers/page_editor_harness.dart';

/// Opens the config pane for the asset at canvas-relative ([fx], [fy]) the way
/// an operator does: right-click, then "Edit".
Future<void> openConfigPane(WidgetTester tester, double fx, double fy) =>
    chooseFromAssetMenu(tester, fx, fy, 'Edit');

Future<void> closePane(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pumpAndSettle();
}

Rect paneRect(WidgetTester tester) => tester.getRect(find.byType(SidePane));
Rect boxRect(WidgetTester tester) => tester.getRect(find.byType(DrawnBox));

/// The canvas viewport: the clipped, aspect-fitted box the page renders in.
/// (Not [AssetStack] — its global rect inflates with the zoom transform,
/// while the box the operator actually sees is this clip.)
Rect canvasRect(WidgetTester tester) => tester.getRect(find
    .descendant(
        of: find.byType(ZoomableCanvas), matching: find.byType(ClipRect))
    // `.first` = the canvas's own aspect-fitted clip; the second is
    // InteractiveViewer's internal one.
    .first);

void main() {
  setUp(setUpEditorEnvironment);

  // Geometry the cases below lean on, at the harness's 1400x1000 window: the
  // canvas spans the full 1400px width, and the pane's preferred width is 520
  // — so its left edge sits at 868 and a box centred at x=0.65 would be
  // covered if the canvas stayed put.

  testWidgets('the canvas insets beside the pane, asset in plain view',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.65, 0.4)]);
    final fullWidth = canvasRect(tester).width;

    await openConfigPane(tester, 0.65, 0.4);

    final pane = paneRect(tester);
    expect(pane.width, 520,
        reason: 'the pane keeps its width — the canvas is what moves');
    expect(canvasRect(tester).right, lessThan(pane.left),
        reason: 'the canvas ends with daylight before the pane begins');
    expect(canvasRect(tester).width, lessThan(fullWidth));
    expect(boxRect(tester).right, lessThan(pane.left),
        reason: 'the asset being edited must be in plain view beside the '
            'pane — wherever on the page it sits');

    await closePane(tester);
    expect(canvasRect(tester).width, fullWidth,
        reason: 'the strip is a loan — the canvas gets it back on close');
  });

  testWidgets('an asset in the pane\'s own corner stays visible too',
      (tester) async {
    // Under #204's narrow-the-pane approach this was the unfixable case: not
    // even a minimum-width pane cleared x=0.9. Re-fitting the canvas clears
    // any position.
    await pumpEditorWith(tester, [editorBox(0.9, 0.4)]);
    await openConfigPane(tester, 0.9, 0.4);

    expect(paneRect(tester).width, 520);
    expect(boxRect(tester).right, lessThan(paneRect(tester).left));

    await closePane(tester);
  });

  testWidgets('the canvas follows the pane\'s resize handle', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.65, 0.4)]);
    await openConfigPane(tester, 0.65, 0.4);
    final before = canvasRect(tester);

    // Drag the handle left: a wider pane leaves the canvas less room.
    final pane = paneRect(tester);
    final gesture =
        await tester.startGesture(Offset(pane.left + 5, pane.center.dy));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(paneRect(tester).width, greaterThan(pane.width));
    expect(canvasRect(tester).width, lessThan(before.width));
    expect(canvasRect(tester).right, lessThan(paneRect(tester).left));
    expect(boxRect(tester).right, lessThan(paneRect(tester).left));

    await closePane(tester);
  });

  testWidgets('a zoomed canvas is inset whole — nothing slides under the pane',
      (tester) async {
    // Zooming happens inside the canvas's own box; the inset moves that box.
    // Pinch to 2x with the pane open, and the viewport — whatever part of
    // the page it shows — must still end before the pane begins.
    await pumpEditorWith(tester, [editorBox(0.45, 0.4)]);
    await openConfigPane(tester, 0.45, 0.4);

    final canvas = canvasRect(tester);
    final cy = canvas.center.dy;
    final focal = canvas.left + 400;
    final a = await tester.startGesture(Offset(focal - 40, cy));
    final b = await tester.startGesture(Offset(focal + 40, cy));
    await tester.pump(const Duration(milliseconds: 20));
    // Spread to double the pointer distance in small steps: scale 2 about
    // the (fixed) midpoint.
    for (var i = 0; i < 8; i++) {
      await a.moveBy(const Offset(-5, 0));
      await b.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    expect(canvasRect(tester).right, lessThan(paneRect(tester).left),
        reason: 'zoom lives inside the canvas box; the box itself stays '
            'clear of the pane');

    await closePane(tester);
  });
}

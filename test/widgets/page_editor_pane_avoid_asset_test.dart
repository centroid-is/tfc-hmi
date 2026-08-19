/// The config pane steps aside from the asset it is editing.
///
/// The pane docks over the right-hand strip of the canvas, which is exactly
/// where the asset being configured may live — and an editor you cannot see
/// under the form that edits it defeats the point of a non-modal pane. So the
/// editor narrows the pane just enough to leave the asset visible, follows the
/// asset as it moves (drags, typed coordinates), widens back out once it is
/// clear, and hands the width back to the operator the moment they touch the
/// resize handle themselves.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

/// Opens the config pane for the asset at canvas-relative ([fx], [fy]) the way
/// an operator does: right-click, then "Edit".
Future<void> openConfigPane(WidgetTester tester, double fx, double fy) =>
    chooseFromAssetMenu(tester, fx, fy, 'Edit');

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
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pumpAndSettle();
}

Future<void> closePane(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pumpAndSettle();
}

Rect paneRect(WidgetTester tester) => tester.getRect(find.byType(SidePane));
Rect boxRect(WidgetTester tester) => tester.getRect(find.byType(DrawnBox));

void main() {
  setUp(setUpEditorEnvironment);

  // Geometry the cases below lean on, at the harness's 1400x1000 window: the
  // canvas spans the full 1400px width, an `editorBox` is 168px wide, and the
  // pane's preferred width is 520 — so its left edge sits at 868 and a box
  // centred at x=0.65 (right edge 994) is covered, while at x=0.3 it is clear.

  testWidgets('the pane opens narrowed when it would cover the asset',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.65, 0.4)]);
    await openConfigPane(tester, 0.65, 0.4);

    final pane = paneRect(tester);
    expect(pane.width, lessThan(520),
        reason: 'the pane should give up width rather than cover the asset');
    expect(pane.left, greaterThanOrEqualTo(boxRect(tester).right),
        reason: 'the asset being edited must stay visible beside the pane');

    await closePane(tester);
  });

  testWidgets('an asset in the clear gets the full preferred width',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await openConfigPane(tester, 0.3, 0.4);

    expect(paneRect(tester).width, 520,
        reason: 'nothing to step aside from — no width to give up');

    await closePane(tester);
  });

  testWidgets('the pane widens back out when the asset moves away',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.65, 0.4)]);
    await openConfigPane(tester, 0.65, 0.4);
    expect(paneRect(tester).width, lessThan(520));

    await enterCoordinate(tester, 'X 0-100%', '30');

    expect(paneRect(tester).width, 520,
        reason: 'the step-aside is a loan, not a new width — the pane '
            'returns to the operator\'s width once the asset is clear');

    await closePane(tester);
  });

  testWidgets('the pane narrows as a drag brings the asset under it',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await openConfigPane(tester, 0.3, 0.4);
    expect(paneRect(tester).width, 520);

    // Drag the box under the pane. Many small moves, as the asset's pan
    // recognizer shares an arena with the canvas's InteractiveViewer.
    final gesture = await tester.startGesture(onCanvas(tester, 0.3, 0.4));
    await tester.pump(const Duration(milliseconds: 20));
    for (var moved = 0.0; moved < 500; moved += 20) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final pane = paneRect(tester);
    expect(pane.width, lessThan(520),
        reason: 'the watch should have stepped the pane off the moving asset');
    expect(pane.left, greaterThanOrEqualTo(boxRect(tester).right));

    await closePane(tester);
  });

  testWidgets('it never narrows below the pane minimum', (tester) async {
    // At x=0.9 not even a minimum-width pane clears the asset; width alone
    // cannot help, and a pane below minimum would be unusable anyway.
    await pumpEditorWith(tester, [editorBox(0.9, 0.4)]);
    await openConfigPane(tester, 0.9, 0.4);

    expect(paneRect(tester).width, SidePaneDefaults.minWidth);

    await closePane(tester);
  });

  testWidgets('a hand-resized pane stays where the operator put it',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await openConfigPane(tester, 0.3, 0.4);

    // The operator takes the width in hand: drag the resize handle.
    final before = paneRect(tester);
    final gesture =
        await tester.startGesture(Offset(before.left + 5, before.center.dy));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final chosen = paneRect(tester).width;
    expect(chosen, greaterThan(before.width));

    // Now send the asset under the pane. The automatic step-aside must not
    // fight a width the operator just chose by hand.
    await enterCoordinate(tester, 'X 0-100%', '65');
    expect(paneRect(tester).width, chosen,
        reason: 'a hand-set width wins over the step-aside until the pane '
            'is next opened');

    await closePane(tester);
  });
}

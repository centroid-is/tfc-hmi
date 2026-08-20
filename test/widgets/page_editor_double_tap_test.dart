/// End-to-end cover for double-click opening the config pane.
///
/// A single tap selects and nothing else; the config pane was reachable only
/// through the right-click menu's "Edit". Double-click is the pointer-first
/// shortcut for the same thing: it selects the asset and docks its pane in
/// one gesture. The single-tap meaning is untouched — it just lands after the
/// double-tap window, which is the standard Flutter disambiguation cost.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/pages/page_view.dart' show AssetStack;
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

/// Closes the pane the way an operator would, so no watch timer outlives the
/// test.
Future<void> closePane(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('double-click opens the config pane and selects the asset',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    await doubleTapAsset(tester, 0.3, 0.4);

    expect(find.byType(SidePane), findsOneWidget,
        reason: 'double-click should dock the config editor');
    expect(find.byType(Dialog), findsNothing);
    expect(selectedCount(tester), 1,
        reason: 'the double-click swallows both single taps, so it has to '
            'select the asset itself');

    await closePane(tester);
    expect(find.byType(SidePane), findsNothing);
  });

  testWidgets('a single tap still only selects', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    await tapAsset(tester, 0.3, 0.4);

    expect(selectedCount(tester), 1);
    expect(find.byType(SidePane), findsNothing,
        reason: 'one click selects; it takes the second to open the pane');
  });

  testWidgets('double-click on the asset whose pane is open leaves it open',
      (tester) async {
    // The pane's open/close is a toggle underneath; a repeated double-click
    // must not read as "close".
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    await doubleTapAsset(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget);

    await doubleTapAsset(tester, 0.3, 0.4);
    expect(find.byType(SidePane), findsOneWidget,
        reason: 'double-clicking the configured asset again is a no-op');

    await closePane(tester);
  });

  testWidgets('double-click on another asset re-points the open pane',
      (tester) async {
    // Both boxes sit left of where the pane docks, so the second double-click
    // reaches the canvas rather than the pane sitting over it.
    await pumpEditorWith(tester, [editorBox(0.2, 0.3), editorBox(0.45, 0.6)]);

    await doubleTapAsset(tester, 0.2, 0.3);
    expect(find.byType(SidePane), findsOneWidget);

    await doubleTapAsset(tester, 0.45, 0.6);
    expect(find.byType(SidePane), findsOneWidget,
        reason: 'one pane, swapped over — not a second one on top');
    expect(selectedCount(tester), 1,
        reason: 'the selection follows the double-click');

    await closePane(tester);
  });

  testWidgets('a double-click replaces a multi-selection with just its asset',
      (tester) async {
    await pumpEditorWith(tester,
        [editorBox(0.2, 0.3), editorBox(0.45, 0.6), editorBox(0.6, 0.2)]);

    await marquee(tester, 0.1, 0.1, 0.7, 0.7);
    expect(selectedCount(tester), 3);

    // Reaching for a double-click says "just this one": the pane configures a
    // single asset, and the selection border should agree with what it shows.
    await doubleTapAsset(tester, 0.45, 0.6);
    expect(find.byType(SidePane), findsOneWidget);
    expect(selectedCount(tester), 1);

    await closePane(tester);
  });

  testWidgets('edits in a double-click-opened pane reach the canvas',
      (tester) async {
    // Guards that this entry point wires up the same live-sync watch as the
    // menu's "Edit" — an asset pane that silently stopped mirroring edits
    // would look open but be broken.
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await doubleTapAsset(tester, 0.3, 0.4);

    final field = find.ancestor(
      of: find.text('X 0-100%'),
      matching: find.byType(TextFormField),
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, '70');
    // Typing produces no pointer event, so the canvas only catches up on the
    // next tick of the editor's config watch.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    final canvasBox = tester.getCenter(find.byType(DrawnBox));
    final canvas = tester.getRect(find.byType(AssetStack));
    expect((canvasBox.dx - canvas.left) / canvas.width, closeTo(0.7, 0.005),
        reason: 'the canvas should already show the new x');

    await closePane(tester);
  });
}

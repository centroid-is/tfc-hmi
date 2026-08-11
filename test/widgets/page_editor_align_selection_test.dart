/// End-to-end cover for aligning a multi-selection in the page editor.
///
/// The maths lives in `alignGroup` and is unit-tested in
/// test/pages/page_editor_align_group_test.dart. This drives the real editor
/// instead: marquee-select scattered boxes, right-click, pick the entry, then
/// read the saved JSON back.
///
/// The two things only an end-to-end test can catch are the axis wiring —
/// "horizontally" must produce a row, i.e. a shared y — and the enabled state
/// of the entries, which is what keeps a no-op off the undo history.
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/page_editor_harness.dart';

/// Whether the context menu entry labelled [label] is tappable.
bool _menuEntryEnabled(WidgetTester tester, String label) {
  final tile = tester.widget<ListTile>(find.ancestor(
    of: find.text(label),
    matching: find.byType(ListTile),
  ));
  return tile.enabled;
}

void main() {
  setUp(setUpEditorEnvironment);

  /// Three boxes at scattered positions: no two share an x or a y.
  Future<FakeEditorPreferences> pumpScattered(WidgetTester tester) =>
      pumpEditorWith(tester,
          [editorBox(0.2, 0.3), editorBox(0.5, 0.7), editorBox(0.8, 0.5)]);

  /// Marquee-selects all three.
  Future<void> selectAll(WidgetTester tester) async {
    await marquee(tester, 0.1, 0.15, 0.9, 0.85);
  }

  /// Opens the menu over the asset at ([fx], [fy]) without choosing anything.
  Future<void> openMenu(WidgetTester tester, double fx, double fy) async {
    await tester.tapAt(onCanvas(tester, fx, fy), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('aligns a selection horizontally into a row', (tester) async {
    final prefs = await pumpScattered(tester);
    await selectAll(tester);

    // The label proves all three are selected.
    await chooseFromAssetMenu(tester, 0.5, 0.7, 'Align 3 assets horizontally');

    final saved = await saveAndReadBack(tester, prefs);

    // A row: one shared y, at the midpoint of the outermost centres
    // (0.3 and 0.7).
    for (final y in savedYs(saved)) {
      expect(y, closeTo(0.5, 1e-9));
    }
    // x untouched — this is the axis assertion that catches a swap.
    expect(savedXs(saved),
        [closeTo(0.2, 1e-9), closeTo(0.5, 1e-9), closeTo(0.8, 1e-9)]);
  });

  testWidgets('aligns a selection vertically into a column', (tester) async {
    final prefs = await pumpScattered(tester);
    await selectAll(tester);

    await chooseFromAssetMenu(tester, 0.5, 0.7, 'Align 3 assets vertically');

    final saved = await saveAndReadBack(tester, prefs);

    // A column: one shared x, midway between 0.2 and 0.8.
    for (final x in savedXs(saved)) {
      expect(x, closeTo(0.5, 1e-9));
    }
    expect(savedYs(saved),
        [closeTo(0.3, 1e-9), closeTo(0.7, 1e-9), closeTo(0.5, 1e-9)]);
  });

  testWidgets('angles survive an align', (tester) async {
    // Aligning moves assets; it must not quietly straighten them.
    final prefs = await pumpEditorWith(tester, [
      editorBox(0.3, 0.3, angle: 45),
      editorBox(0.7, 0.7),
    ]);
    await marquee(tester, 0.15, 0.15, 0.85, 0.85);

    await chooseFromAssetMenu(tester, 0.7, 0.7, 'Align 2 assets horizontally');

    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved[0])['angle'], 45);
    expect(coordsOf(saved[1])['angle'], isNull);
  });

  testWidgets('both aligns together stack the selection on one point',
      (tester) async {
    final prefs = await pumpScattered(tester);
    await selectAll(tester);

    await chooseFromAssetMenu(tester, 0.5, 0.7, 'Align 3 assets horizontally');
    // After the first align the selection still holds, but every asset now
    // shares a y — so the boxes overlap and the click point has to be one
    // that is still on an asset.
    await chooseFromAssetMenu(tester, 0.5, 0.5, 'Align 3 assets vertically');

    final saved = await saveAndReadBack(tester, prefs);
    for (final asset in saved) {
      expect(coordsOf(asset)['x'] as double, closeTo(0.5, 1e-9));
      expect(coordsOf(asset)['y'] as double, closeTo(0.5, 1e-9));
    }
  });

  testWidgets('undo reverts an align in one step', (tester) async {
    final prefs = await pumpScattered(tester);
    await selectAll(tester);

    await chooseFromAssetMenu(tester, 0.5, 0.7, 'Align 3 assets horizontally');
    await pressUndo(tester);

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedYs(saved),
        [closeTo(0.3, 1e-9), closeTo(0.7, 1e-9), closeTo(0.5, 1e-9)]);
  });

  testWidgets('an already-aligned selection disables the entry',
      (tester) async {
    // A row already shares a y, so aligning horizontally would do nothing and
    // must not be offered — otherwise it burns an undo step. Aligning
    // vertically is still real work, which proves the check is per axis.
    await pumpEditorWith(tester,
        [editorBox(0.3, 0.5), editorBox(0.5, 0.5), editorBox(0.7, 0.5)]);
    await marquee(tester, 0.15, 0.3, 0.85, 0.7);

    await openMenu(tester, 0.5, 0.5);

    expect(_menuEntryEnabled(tester, 'Align 3 assets horizontally'), isFalse,
        reason: 'the row already shares a y');
    expect(_menuEntryEnabled(tester, 'Align 3 assets vertically'), isTrue,
        reason: 'the row does not share an x');
  });

  testWidgets('a single asset cannot be aligned', (tester) async {
    // Outside select mode the menu acts on one asset, which is already its own
    // group centre — there is nothing to line up.
    await pumpScattered(tester);

    await openMenu(tester, 0.2, 0.3);

    expect(_menuEntryEnabled(tester, 'Align horizontally'), isFalse);
    expect(_menuEntryEnabled(tester, 'Align vertically'), isFalse);
  });
}

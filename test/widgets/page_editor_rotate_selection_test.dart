/// End-to-end cover for rotating a multi-selection in the page editor.
///
/// The maths lives in `rotateGroup` and is unit-tested in
/// test/pages/page_editor_rotate_group_test.dart. What those tests cannot see
/// is the wiring: that the context menu offers the entries, that they act on
/// the whole marquee selection rather than the asset under the cursor, that
/// the canvas aspect ratio actually reaches the maths, and that the result is
/// what gets persisted.
///
/// So this drives the real editor: marquee-select a row of boxes, right-click,
/// pick "Rotate 3 assets 90° clockwise", then read the saved JSON back.
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/page_editor_harness.dart';

void main() {
  setUp(setUpEditorEnvironment);

  /// A row of three boxes across the middle of the canvas.
  Future<FakeEditorPreferences> pumpRow(WidgetTester tester) => pumpEditorWith(
      tester, [editorBox(0.3, 0.5), editorBox(0.5, 0.5), editorBox(0.7, 0.5)]);

  /// Marquee-selects the whole row.
  Future<void> selectRow(WidgetTester tester) async {
    await enterSelectMode(tester);
    await marquee(tester, 0.15, 0.3, 0.85, 0.7);
  }

  testWidgets('rotates a marquee selection as a group', (tester) async {
    final prefs = await pumpRow(tester);
    final aspect = canvasAspect(tester);
    // The spacing assertion below is only meaningful on a non-square canvas —
    // on a square one it would pass with the aspect handling ripped out.
    expect(aspect, greaterThan(1.5),
        reason: 'the editor canvas should be wide (it renders 16:9)');

    await selectRow(tester);

    // The label proves all three are selected — if the marquee had missed,
    // it would read "Rotate 90° clockwise".
    await chooseFromAssetMenu(
        tester, 0.5, 0.5, 'Rotate 3 assets 90° clockwise');

    final saved = await saveAndReadBack(tester, prefs);
    expect(saved, hasLength(3));

    // The row is now a column through the group's centre.
    for (final x in savedXs(saved)) {
      expect(x, closeTo(0.5, 1e-9));
    }

    // Clockwise: the leftmost box is now the topmost.
    final ys = savedYs(saved);
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));

    // The spacing is preserved *in pixels*, which is the whole point of the
    // aspect correction: 0.2 of the canvas width has to become 0.2 * aspect
    // of its height. Without the correction this would come out as 0.2.
    expect(ys[1] - ys[0], closeTo(0.2 * aspect, 1e-9));
    expect(ys[2] - ys[1], closeTo(0.2 * aspect, 1e-9));

    // ...and every box spun, not just orbited.
    for (final asset in saved) {
      expect(coordsOf(asset)['angle'], 90);
    }
  });

  testWidgets('rotating back restores the original layout', (tester) async {
    final prefs = await pumpRow(tester);
    await selectRow(tester);

    await chooseFromAssetMenu(
        tester, 0.5, 0.5, 'Rotate 3 assets 90° clockwise');
    // The selection survives the rotation, so the second turn hits the same
    // three assets — worth asserting, since losing it would silently make the
    // menu act on one box.
    await chooseFromAssetMenu(
        tester, 0.5, 0.5, 'Rotate 3 assets 90° counter-clockwise');

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved),
        [closeTo(0.3, 1e-9), closeTo(0.5, 1e-9), closeTo(0.7, 1e-9)]);
    for (final y in savedYs(saved)) {
      expect(y, closeTo(0.5, 1e-9));
    }
    // Back to "never rotated", so mirrored pages behave as they did before.
    for (final asset in saved) {
      expect(coordsOf(asset)['angle'], isNull);
    }
  });

  testWidgets('undo reverts a group rotation in one step', (tester) async {
    final prefs = await pumpRow(tester);
    await selectRow(tester);

    await chooseFromAssetMenu(
        tester, 0.5, 0.5, 'Rotate 3 assets 90° clockwise');
    await pressUndo(tester);

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved),
        [closeTo(0.3, 1e-9), closeTo(0.5, 1e-9), closeTo(0.7, 1e-9)]);
    for (final asset in saved) {
      expect(coordsOf(asset)['angle'], isNull);
    }
  });

  testWidgets('an unselected asset rotates on its own', (tester) async {
    // Outside select mode there is no selection, so the menu acts on just the
    // asset under the cursor — and a single asset spins in place.
    final prefs = await pumpRow(tester);

    await chooseFromAssetMenu(tester, 0.3, 0.5, 'Rotate 90° clockwise');

    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved[0])['angle'], 90);
    expect(savedXs(saved)[0], closeTo(0.3, 1e-9));
    expect(savedYs(saved)[0], closeTo(0.5, 1e-9));

    // The other two are untouched.
    expect(coordsOf(saved[1])['angle'], isNull);
    expect(coordsOf(saved[2])['angle'], isNull);
  });
}

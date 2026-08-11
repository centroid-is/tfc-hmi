/// End-to-end cover for mirroring a selection in the page editor.
///
/// The maths lives in `mirrorGroup` and is unit-tested in
/// test/pages/page_editor_mirror_group_test.dart. This drives the real editor
/// instead, for the parts only the wiring can get wrong: that the menu offers
/// the entries, that they act on the whole selection rather than the asset
/// under the cursor, that the axes are not crossed, and that the result is
/// what gets persisted.
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/page_editor_harness.dart';

void main() {
  setUp(setUpEditorEnvironment);

  /// A row of three boxes across the middle, marquee-selected.
  Future<FakeEditorPreferences> pumpSelectedRow(WidgetTester tester) async {
    final prefs = await pumpEditorWith(tester,
        [editorBox(0.25, 0.5), editorBox(0.4, 0.5), editorBox(0.75, 0.5)]);
    await marquee(tester, 0.1, 0.3, 0.9, 0.7);
    expect(selectedCount(tester), 3);
    return prefs;
  }

  testWidgets('mirrors a selection horizontally about its own centre',
      (tester) async {
    final prefs = await pumpSelectedRow(tester);

    // The label proves all three are selected — if the marquee had missed it
    // would read "Mirror horizontally".
    await chooseFromAssetMenu(tester, 0.4, 0.5, 'Mirror 3 assets horizontally');

    final saved = await saveAndReadBack(tester, prefs);
    // Centre of the row is 0.5, so each x reflects to 1 - x. The order along
    // the row is reversed while the group stays where it was.
    expect(savedXs(saved), [
      closeTo(0.75, 1e-9),
      closeTo(0.6, 1e-9),
      closeTo(0.25, 1e-9),
    ]);
    // The other axis is untouched.
    for (final y in savedYs(saved)) {
      expect(y, closeTo(0.5, 1e-9));
    }
  });

  testWidgets('mirrors a selection vertically about its own centre',
      (tester) async {
    final prefs = await pumpEditorWith(tester,
        [editorBox(0.5, 0.25), editorBox(0.5, 0.4), editorBox(0.5, 0.75)]);
    await marquee(tester, 0.3, 0.1, 0.7, 0.9);
    expect(selectedCount(tester), 3);

    await chooseFromAssetMenu(tester, 0.5, 0.4, 'Mirror 3 assets vertically');

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedYs(saved), [
      closeTo(0.75, 1e-9),
      closeTo(0.6, 1e-9),
      closeTo(0.25, 1e-9),
    ]);
    for (final x in savedXs(saved)) {
      expect(x, closeTo(0.5, 1e-9));
    }
  });

  testWidgets('mirroring the same way twice restores the layout',
      (tester) async {
    final prefs = await pumpSelectedRow(tester);

    await chooseFromAssetMenu(tester, 0.4, 0.5, 'Mirror 3 assets horizontally');
    // The selection survives the flip, so the second one hits the same three
    // assets — worth asserting, since losing it would silently reduce the
    // entry to acting on one box.
    await chooseFromAssetMenu(tester, 0.6, 0.5, 'Mirror 3 assets horizontally');

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved), [
      closeTo(0.25, 1e-9),
      closeTo(0.4, 1e-9),
      closeTo(0.75, 1e-9),
    ]);
    // Back to "never rotated" rather than to an explicit 0, so mirrored pages
    // render as they did before the round trip.
    for (final asset in saved) {
      expect(coordsOf(asset)['angle'], isNull);
    }
  });

  testWidgets('a flip is undoable in one step', (tester) async {
    final prefs = await pumpSelectedRow(tester);

    await chooseFromAssetMenu(tester, 0.4, 0.5, 'Mirror 3 assets horizontally');
    await pressUndo(tester);

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved), [
      closeTo(0.25, 1e-9),
      closeTo(0.4, 1e-9),
      closeTo(0.75, 1e-9),
    ]);
  });

  testWidgets('with nothing selected it flips only the asset clicked',
      (tester) async {
    // A single unselected asset is the degenerate case: its own centre is the
    // group centre, so it stays put and only its angle reflects.
    final prefs = await pumpEditorWith(
        tester, [editorBox(0.3, 0.5), editorBox(0.7, 0.5)]);

    await chooseFromAssetMenu(tester, 0.3, 0.5, 'Mirror horizontally');

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved), [closeTo(0.3, 1e-9), closeTo(0.7, 1e-9)],
        reason: 'neither asset should have moved');
    expect(coordsOf(saved[0])['angle'], 180);
    expect(coordsOf(saved[1])['angle'], isNull,
        reason: 'the asset that was not clicked must be left alone');
  });
}

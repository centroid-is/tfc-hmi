/// End-to-end cover for the modifier-held marquee: a Ctrl/Cmd rubber band
/// toggles the boxed assets against the existing selection — unselected
/// assets join, already-selected ones leave — instead of replacing it, the
/// drag-shaped twin of modifier-clicking a single asset.
///
/// Where a test needs to know *which* assets survived (not just how many),
/// it deletes the selection and reads the persisted page back: positions
/// identify the boxes.
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/page_editor_harness.dart';

void main() {
  setUp(setUpEditorEnvironment);

  /// Three boxes in a row across the middle: A at 0.25, B at 0.5, C at 0.75.
  /// Each is 0.12 wide and 0.06 tall, so a marquee has empty canvas to start
  /// on above and between them.
  Future<FakeEditorPreferences> pumpRow(WidgetTester tester) => pumpEditorWith(
      tester, [editorBox(0.25, 0.5), editorBox(0.5, 0.5), editorBox(0.75, 0.5)]);

  testWidgets('a plain marquee still replaces the selection', (tester) async {
    final prefs = await pumpRow(tester);
    await marquee(tester, 0.1, 0.35, 0.35, 0.65); // A
    expect(selectedCount(tester), 1);

    await marquee(tester, 0.65, 0.35, 0.9, 0.65); // C, no modifier
    expect(selectedCount(tester), 1);

    // Deleting the selection removes C alone: A and B stay.
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved), [0.25, 0.5]);
  });

  testWidgets('a modifier marquee adds unselected assets to the selection',
      (tester) async {
    await pumpRow(tester);
    await marquee(tester, 0.1, 0.35, 0.35, 0.65); // A
    expect(selectedCount(tester), 1);

    await marquee(tester, 0.65, 0.35, 0.9, 0.65, addToSelection: true); // C
    expect(selectedCount(tester), 2);
  });

  testWidgets('a modifier marquee deselects assets it re-covers',
      (tester) async {
    await pumpRow(tester);
    await marquee(tester, 0.05, 0.35, 0.95, 0.65); // all three
    expect(selectedCount(tester), 3);

    await marquee(tester, 0.4, 0.35, 0.6, 0.65, addToSelection: true); // B
    expect(selectedCount(tester), 2);
  });

  testWidgets('a modifier marquee over a mixed group toggles each side',
      (tester) async {
    final prefs = await pumpRow(tester);
    await marquee(tester, 0.1, 0.35, 0.35, 0.65); // A
    expect(selectedCount(tester), 1);

    // Box A and B together: A was selected so it leaves, B joins.
    await marquee(tester, 0.1, 0.35, 0.6, 0.65, addToSelection: true);
    expect(selectedCount(tester), 1);

    // Deleting proves the survivor is B: A and C remain on the page.
    await pressEditorKey(tester, LogicalKeyboardKey.delete);
    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved), [0.25, 0.75]);
  });

  testWidgets(
      'toggling is computed against the selection at drag start, so an asset '
      'the box passes over and retreats from is restored, not lost',
      (tester) async {
    await pumpRow(tester);
    await marquee(tester, 0.1, 0.35, 0.35, 0.65); // A
    expect(selectedCount(tester), 1);

    // Grow a modifier marquee over A, then shrink back off it before
    // releasing. Mid-drag A toggles off; retreating must bring it back.
    await tester.sendKeyDownEvent(editorModifier);
    final gesture = await tester.startGesture(onCanvas(tester, 0.1, 0.35));
    await tester.pump();
    await gesture.moveTo(onCanvas(tester, 0.3, 0.55)); // box covers A
    await tester.pump();
    expect(selectedCount(tester), 0, reason: 'A toggled off while boxed');
    await gesture.moveTo(onCanvas(tester, 0.12, 0.37)); // box retreats
    await tester.pump();
    await gesture.up();
    await tester.sendKeyUpEvent(editorModifier);
    await tester.pumpAndSettle();

    expect(selectedCount(tester), 1, reason: 'A back once the box left it');
  });
}

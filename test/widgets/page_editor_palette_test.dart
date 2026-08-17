/// End-to-end tests for the asset palette and the canvas delete paths.
///
/// Two regressions anchor this file:
///
///   * Typing in the palette's search box used to fight the canvas shortcuts.
///     The editor's key handler guarded against text fields with
///     `primaryFocus.context?.widget is EditableText` — but a text field's
///     focus node attaches to a `Focus` widget *inside* `EditableText`, so the
///     guard never matched and backspace/delete/R fell through to the canvas:
///     backspace deleted the selected asset instead of a character.
///
///   * Searching "multivac" found nothing, because the search matched only
///     `displayName` and the machine lives inside the umbrella "3rd Party
///     Equipment" tile. `Asset.searchKeywords` now carries the per-kind names.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/page_editor_harness.dart';

/// The palette's search box. The palette is the only TextField the editor
/// shows outside of dialogs and panes, so the type finder is unambiguous —
/// and asserted so, to fail loudly the day that changes.
Finder _searchField() {
  final field = find.byType(TextField);
  expect(field, findsOneWidget,
      reason: 'the palette search box should be the only TextField on screen');
  return field;
}

Future<void> _openPalette(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

Future<void> _closePalette(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(_searchField(), query);
  await tester.pumpAndSettle();
}

Future<void> _pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_searchField()).controller!.text;

void main() {
  setUp(setUpEditorEnvironment);

  group('palette search vs canvas shortcuts', () {
    testWidgets('backspace edits the query, not the canvas', (tester) async {
      final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

      // The dangerous state: an asset is selected, so a key falling through
      // to the canvas has something to destroy.
      await tapAsset(tester, 0.3, 0.3);
      expect(selectedCount(tester), 1);

      await _openPalette(tester);
      await _search(tester, 'multivac');

      await _pressKey(tester, LogicalKeyboardKey.backspace);
      expect(_fieldText(tester), 'multiva',
          reason: 'backspace should delete a character, not be swallowed');

      // Forward delete with the cursor at the end edits nothing — the point
      // is that it must not fall through and delete the selected asset.
      await _pressKey(tester, LogicalKeyboardKey.delete);
      expect(_fieldText(tester), 'multiva');

      // R is the canvas rotate shortcut; typing it must not rotate.
      await _pressKey(tester, LogicalKeyboardKey.keyR);

      await _closePalette(tester);
      final saved = await saveAndReadBack(tester, prefs);
      expect(saved, hasLength(1),
          reason: 'no key typed into the search box may delete an asset');
      expect(coordsOf(saved.single)['angle'], isNull,
          reason: 'typing R in the search box must not rotate the selection');
    });

    testWidgets('canvas shortcuts still work once the palette is closed',
        (tester) async {
      final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);

      await _openPalette(tester);
      await _search(tester, 'conveyor');
      await _closePalette(tester);

      await tapAsset(tester, 0.3, 0.3);
      await _pressKey(tester, LogicalKeyboardKey.backspace);

      final saved = await saveAndReadBack(tester, prefs);
      expect(saved, isEmpty,
          reason: 'with no text field focused, backspace deletes the '
              'selection as before');
    });
  });

  group('palette search coverage', () {
    testWidgets('finds the machines inside the 3rd-party tile',
        (tester) async {
      await pumpEditorWith(tester, []);
      await _openPalette(tester);

      // The umbrella tile answers to each machine an operator would look
      // for, including the ASCII spelling of the vöðlari.
      for (final query in ['multivac', 'Afak', 'speedbatcher', 'vodlari']) {
        await _search(tester, query);
        expect(find.text('3rd Party Equipment'), findsOneWidget,
            reason: 'searching "$query" should surface the 3rd-party tile');
      }

      await _search(tester, 'no-such-machine');
      expect(find.text('3rd Party Equipment'), findsNothing);
    });

    testWidgets('the query survives closing and reopening the palette',
        (tester) async {
      await pumpEditorWith(tester, []);

      await _openPalette(tester);
      await _search(tester, 'multivac');
      await _closePalette(tester);
      await _openPalette(tester);

      // Field and grid must agree: before the query lived in a controller,
      // reopening showed an empty box over a still-filtered grid.
      expect(_fieldText(tester), 'multivac');
      expect(find.text('3rd Party Equipment'), findsOneWidget);
      expect(find.text('Conveyor'), findsNothing);
    });
  });

  group('context-menu delete', () {
    testWidgets('deletes the asset under the cursor', (tester) async {
      final prefs = await pumpEditorWith(
          tester, [editorBox(0.3, 0.3), editorBox(0.7, 0.7)]);

      await chooseFromAssetMenu(tester, 0.3, 0.3, 'Delete');

      final saved = await saveAndReadBack(tester, prefs);
      expect(savedXs(saved), [0.7],
          reason: 'only the right-clicked asset goes; the other stays');
    });

    testWidgets('deletes the whole selection when the asset is part of one',
        (tester) async {
      final prefs = await pumpEditorWith(
          tester, [editorBox(0.3, 0.3), editorBox(0.7, 0.7)]);

      await marquee(tester, 0.1, 0.1, 0.9, 0.9);
      expect(selectedCount(tester), 2);

      await chooseFromAssetMenu(tester, 0.3, 0.3, 'Delete 2 assets');
      expect(selectedCount(tester), 0);

      // One undo step brings the group back — the delete was one action.
      await pressUndo(tester);
      final saved = await saveAndReadBack(tester, prefs);
      expect(saved, hasLength(2));
    });
  });
}

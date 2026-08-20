/// End-to-end cover for the page editor having one editing mode.
///
/// It used to have two, behind a floating toggle: a "pan" mode where a tap
/// opened an asset's configuration and a drag panned the canvas, and a
/// "select" mode where a tap selected and a drag rubber-banded. Everything
/// that operates on a selection — delete, copy, align, rotate, resize — was
/// therefore unreachable from the mode the editor started in, and the mode you
/// were in was a floating button's colour.
///
/// The two turned out to overlap almost completely. Dragging an asset already
/// moved it in both. Panning is only possible when zoomed in at all —
/// `ZoomableCanvas` pins `minScale` to 1.0 with no boundary margin, so at 1:1
/// the child exactly fills the viewport and a pan has nowhere to go — so pan
/// mode's exclusive gesture did nothing for most of the time it was on. What
/// genuinely conflicted was only the meaning of a tap on an asset, and the
/// meaning of a drag on empty canvas.
///
/// Both are resolved here rather than by a mode:
///
///   * a tap always selects; configuring moved to the right-click menu, and
///   * a drag on empty canvas always rubber-bands, unless the pan key is held.
///
/// These tests pin the resulting behaviour down from the operator's side.
library;

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/pages/page_view.dart' show AssetStack;
import 'package:tfc/widgets/panes/side_pane.dart';

import '../helpers/page_editor_harness.dart';

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('there is no mode toggle left to press', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    expect(find.byIcon(Icons.pan_tool), findsNothing);
    expect(find.byIcon(Icons.select_all), findsNothing);
  });

  testWidgets('a tap selects, with no mode to enter first', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    expect(selectedCount(tester), 0);

    await tapAsset(tester, 0.3, 0.4);
    expect(selectedCount(tester), 1);

    // ...and does not open the configuration editor on the way.
    expect(find.byType(SidePane), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the modifier extends a selection built by tapping',
      (tester) async {
    await pumpEditorWith(tester,
        [editorBox(0.2, 0.3), editorBox(0.5, 0.3), editorBox(0.8, 0.3)]);

    await tapAsset(tester, 0.2, 0.3);
    await tapAsset(tester, 0.5, 0.3, addToSelection: true);
    expect(selectedCount(tester), 2);

    // Without the modifier the next tap replaces rather than extends.
    await tapAsset(tester, 0.8, 0.3);
    expect(selectedCount(tester), 1);
  });

  testWidgets('a tap on empty canvas clears the selection', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    await tapAsset(tester, 0.3, 0.4);
    expect(selectedCount(tester), 1);

    await tester.tapAt(onCanvas(tester, 0.8, 0.8));
    await tester.pumpAndSettle();
    expect(selectedCount(tester), 0);
  });

  testWidgets('a drag on empty canvas rubber-bands with no mode to enter',
      (tester) async {
    await pumpEditorWith(tester,
        [editorBox(0.3, 0.5), editorBox(0.5, 0.5), editorBox(0.8, 0.5)]);

    // A band across the left two only.
    await marquee(tester, 0.15, 0.3, 0.62, 0.7);
    expect(selectedCount(tester), 2);
  });

  testWidgets('a drag that starts on an asset moves it, not a marquee',
      (tester) async {
    // The gesture the two modes used to disambiguate by mode: it has to reach
    // the asset even though the marquee listener is now always live.
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.5)]);

    final gesture = await tester.startGesture(onCanvas(tester, 0.3, 0.5));
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 7; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved).single, greaterThan(0.35),
        reason: 'the asset should have moved with the drag');
  });

  group('keyboard', () {
    /// Two boxes 0.2 apart, marquee-selected, so the group cases are the ones
    /// under test. Kept close together so a quarter turn — which trades width
    /// for height and so multiplies the separation by the canvas aspect —
    /// still lands the pair inside the canvas untranslated.
    Future<FakeEditorPreferences> pumpSelectedPair(WidgetTester tester) async {
      final prefs = await pumpEditorWith(
          tester, [editorBox(0.4, 0.5), editorBox(0.6, 0.5)]);
      await marquee(tester, 0.25, 0.3, 0.75, 0.7);
      expect(selectedCount(tester), 2);
      return prefs;
    }

    testWidgets('Delete removes the selection', (tester) async {
      final prefs = await pumpSelectedPair(tester);

      await pressEditorKey(tester, LogicalKeyboardKey.delete);

      expect(find.byType(DrawnBox), findsNothing);
      expect(await saveAndReadBack(tester, prefs), isEmpty);
    });

    testWidgets('Backspace removes the selection too', (tester) async {
      // Bound alongside Delete because a Mac keyboard's delete key reports as
      // backspace; both work everywhere rather than being switched on the
      // host platform, so a shared page reads the same on either.
      final prefs = await pumpSelectedPair(tester);

      await pressEditorKey(tester, LogicalKeyboardKey.backspace);

      expect(find.byType(DrawnBox), findsNothing);
      expect(await saveAndReadBack(tester, prefs), isEmpty);
    });

    testWidgets('Delete with nothing selected is a no-op', (tester) async {
      final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.5)]);

      await pressEditorKey(tester, LogicalKeyboardKey.delete);

      expect(find.byType(DrawnBox), findsOneWidget);
      expect(await saveAndReadBack(tester, prefs), hasLength(1));
    });

    testWidgets('R rotates the selection as a group', (tester) async {
      final prefs = await pumpSelectedPair(tester);
      final aspect = canvasAspect(tester);
      // The spacing assertion below only means anything on a wide canvas.
      expect(aspect, greaterThan(1.5));

      await pressRotate(tester);

      final saved = await saveAndReadBack(tester, prefs);
      // The row became a column through the group's centre, clockwise: the
      // box that was on the left is now on top.
      for (final x in savedXs(saved)) {
        expect(x, closeTo(0.5, 1e-9));
      }
      final ys = savedYs(saved);
      expect(ys[0], lessThan(ys[1]));

      // Spacing is preserved in pixels, not in normalized units: 0.2 of the
      // canvas width becomes 0.2 * aspect of its height. This is the aspect
      // correction inside `rotateGroup`, and it only runs if the shortcut
      // found the canvas constraints to hand it — which is the part of this
      // that is specific to driving the rotation from the keyboard.
      expect(ys[1] - ys[0], closeTo(0.2 * aspect, 1e-9));

      // ...and each box spun on its own centre as well as orbiting.
      for (final asset in saved) {
        expect(coordsOf(asset)['angle'], 90);
      }
    });

    testWidgets('Shift+R rotates the other way', (tester) async {
      final prefs = await pumpSelectedPair(tester);

      await pressRotate(tester, counterClockwise: true);

      final saved = await saveAndReadBack(tester, prefs);
      // Counter-clockwise: the box that was on the left is now at the bottom.
      final ys = savedYs(saved);
      expect(ys[0], greaterThan(ys[1]));
    });

    testWidgets('R then Shift+R is a round trip', (tester) async {
      final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.5)]);
      await tapAsset(tester, 0.3, 0.5);

      await pressRotate(tester);
      await pressRotate(tester, counterClockwise: true);

      final saved = await saveAndReadBack(tester, prefs);
      // Back to "never rotated", not to an explicit 0, so mirrored pages
      // behave as they did before the round trip.
      expect(coordsOf(saved.single)['angle'], isNull);
      expect(savedXs(saved).single, closeTo(0.3, 1e-9));
      expect(savedYs(saved).single, closeTo(0.5, 1e-9));
    });

    testWidgets('R with nothing selected is a no-op', (tester) async {
      final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.5)]);

      await pressRotate(tester);

      final saved = await saveAndReadBack(tester, prefs);
      final angle = coordsOf(saved.single)['angle'];
      expect(angle == null || angle == 0, isTrue,
          reason: 'an unselected asset should not have turned');
    });

    testWidgets('a rotate is undoable', (tester) async {
      final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.5)]);
      await tapAsset(tester, 0.3, 0.5);

      await pressRotate(tester);
      await pressUndo(tester);

      final saved = await saveAndReadBack(tester, prefs);
      final angle = coordsOf(saved.single)['angle'];
      expect(angle == null || angle == 0, isTrue);
    });

    testWidgets('holding the pan key stands the marquee down', (tester) async {
      // Space is what turns a drag on empty canvas back into a canvas pan.
      // Nothing here can observe the pan itself — at 1:1 there is nothing to
      // pan — but the marquee must get out of its way, which is observable.
      await pumpEditorWith(tester, [editorBox(0.3, 0.5), editorBox(0.7, 0.5)]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await marquee(tester, 0.15, 0.3, 0.85, 0.7);
      expect(selectedCount(tester), 0,
          reason: 'with the pan key held the drag should not select');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await marquee(tester, 0.15, 0.3, 0.85, 0.7);
      expect(selectedCount(tester), 2,
          reason: 'releasing it should hand the drag back to the marquee');
    });
  });

  group('right-click menu', () {
    testWidgets('offers Edit above the geometry actions', (tester) async {
      await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

      await tester.tapAt(onCanvas(tester, 0.3, 0.4), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Edit')).dy,
        lessThan(tester.getCenter(find.text('Rotate 90° clockwise')).dy),
        reason: 'Edit is the entry that replaced tap-to-configure; it leads',
      );
    });

    testWidgets('Edit opens the config pane for the asset under the cursor',
        (tester) async {
      // Two selected, but Edit configures the one that was right-clicked —
      // the pane edits a single asset, unlike the entries below it.
      await pumpEditorWith(
          tester, [editorBox(0.25, 0.5), editorBox(0.45, 0.5)]);
      await marquee(tester, 0.1, 0.3, 0.6, 0.7);
      expect(selectedCount(tester), 2);

      await chooseFromAssetMenu(tester, 0.45, 0.5, 'Edit');
      expect(find.byType(SidePane), findsOneWidget);

      // Prove which asset the pane holds by moving it.
      final field = find.ancestor(
        of: find.text('X 0-100%'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field, '90');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.byType(DrawnBox), findsNWidgets(2));
      final canvas = tester.getRect(find.byType(AssetStack));
      final moved = tester.getCenter(find.byType(DrawnBox).at(1));
      expect((moved.dx - canvas.left) / canvas.width, closeTo(0.9, 0.005));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });
  });
}

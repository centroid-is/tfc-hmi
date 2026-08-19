/// Moving assets must stay cheap per tick.
///
/// The editor's dirty check compares a JSON encode of every page against the
/// last save, and the canvas config used to be re-read from preferences on
/// every rebuild. Neither belongs inside a continuous gesture: a drag delivers
/// an update per pointer event and a held arrow key repeats per frame, so
/// per-tick encodes and reads are what made moving assets lag on big projects.
///
/// The contract pinned here:
///
///  * a whole drag or press-and-hold re-encodes the pages exactly once, when
///    the gesture settles (pointer up / key up) — never per tick;
///  * deferring the encode loses nothing: the save button shows unsaved
///    mid-gesture, and the settle recompute restores the exact compare so
///    nudging back onto the saved spot reads as saved again;
///  * the canvas config is read from preferences once per mount, not once per
///    drag tick.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:tfc/pages/page_editor.dart';

import '../helpers/page_editor_harness.dart';

/// The save button, whose colour is the editor's unsaved-changes indicator.
FloatingActionButton _saveFab(WidgetTester tester) =>
    tester.widget<FloatingActionButton>(
        find.widgetWithIcon(FloatingActionButton, Icons.save));

bool _showsUnsaved(WidgetTester tester) =>
    _saveFab(tester).backgroundColor == Colors.orange;

/// In-memory preferences that count reads of the canvas config, so a test
/// can pin that rebuilds do not re-read it.
base class _CountingPrefs extends InMemorySharedPreferencesAsync {
  _CountingPrefs() : super.empty();

  int assetStackConfigReads = 0;

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) {
    if (key == 'asset_stack_config') assetStackConfigReads++;
    return super.getString(key, options);
  }
}

/// Drags from the asset at relative ([fx], [fy]) through [moves], leaving the
/// gesture down so the caller can look at mid-drag state. The first move must
/// exceed the pan slop on its own or nothing starts.
Future<TestGesture> _startAssetDrag(
  WidgetTester tester,
  double fx,
  double fy,
  List<Offset> moves,
) async {
  final gesture = await tester.startGesture(onCanvas(tester, fx, fy));
  await tester.pump();
  for (final move in moves) {
    await gesture.moveBy(move);
    await tester.pump();
  }
  return gesture;
}

/// Presses [key] with [repeats] repeat events before the release, the shape
/// of a real press-and-hold.
Future<void> _holdArrow(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  int repeats = 0,
}) async {
  await tester.sendKeyDownEvent(key);
  for (var i = 0; i < repeats; i++) {
    await tester.sendKeyRepeatEvent(key);
  }
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setUpEditorEnvironment();
    PageEditor.debugJsonEncodes = 0;
  });

  testWidgets('a whole drag encodes the pages once, at pointer up',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);
    PageEditor.debugJsonEncodes = 0;

    final gesture = await _startAssetDrag(tester, 0.3, 0.3, const [
      Offset(30, 0), // crosses the pan slop
      Offset(8, 0),
      Offset(8, 4),
      Offset(8, 4),
      Offset(8, 4),
      Offset(8, 4),
    ]);

    expect(PageEditor.debugJsonEncodes, 0,
        reason: 'no tick of a drag may re-encode every page');
    expect(_showsUnsaved(tester), isTrue,
        reason: 'deferring the encode must not defer the unsaved indicator');

    await gesture.up();
    await tester.pumpAndSettle();

    expect(PageEditor.debugJsonEncodes, 1,
        reason: 'the release settles the gesture with a single encode');
    expect(_showsUnsaved(tester), isTrue);
  });

  testWidgets('a whole press-and-hold encodes the pages once, at key up',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);
    PageEditor.debugJsonEncodes = 0;

    await _holdArrow(tester, LogicalKeyboardKey.arrowRight, repeats: 8);

    expect(PageEditor.debugJsonEncodes, 1,
        reason: 'nine nudges in one hold must settle in a single encode');
    expect(_showsUnsaved(tester), isTrue);
  });

  testWidgets('nudging back onto the saved spot reads as saved again',
      (tester) async {
    // The settle recompute is what keeps the deferred dirty flag honest: a
    // stale "unsaved" that never healed would outlive the gesture.
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);
    expect(_showsUnsaved(tester), isFalse);

    await _holdArrow(tester, LogicalKeyboardKey.arrowRight);
    expect(_showsUnsaved(tester), isTrue);

    await _holdArrow(tester, LogicalKeyboardKey.arrowLeft);
    expect(_showsUnsaved(tester), isFalse,
        reason: 'one pixel right then one pixel left is exactly the saved '
            'page, and the key-up recompute must notice');
  });

  testWidgets('a drag still persists where the asset ended up',
      (tester) async {
    // How far the recognizers swallow before the pan wins is not this
    // test's business — what matters is that deferring the JSON sync did
    // not defer the movement itself out of the save.
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);

    final gesture = await _startAssetDrag(tester, 0.3, 0.3, const [
      Offset(30, 0), // crosses the pan slop
      Offset(20, 15),
      Offset(20, 15),
      Offset(20, 15),
    ]);
    await gesture.up();
    await tester.pumpAndSettle();

    final saved = await saveAndReadBack(tester, prefs);
    expect(coordsOf(saved.single)['x'], greaterThan(0.3));
    expect(coordsOf(saved.single)['y'], greaterThan(0.3));
  });

  testWidgets('the canvas config is read once per mount, not per drag tick',
      (tester) async {
    final counting = _CountingPrefs();
    SharedPreferencesAsyncPlatform.instance = counting;

    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);
    final readsAfterMount = counting.assetStackConfigReads;
    expect(readsAfterMount, greaterThan(0));

    final gesture = await _startAssetDrag(tester, 0.3, 0.3, const [
      Offset(30, 0),
      Offset(8, 0),
      Offset(8, 0),
      Offset(8, 0),
    ]);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(counting.assetStackConfigReads, readsAfterMount,
        reason: 'rebuilds during a drag must reuse the config read at mount');
  });
}

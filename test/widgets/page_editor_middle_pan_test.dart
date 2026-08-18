/// Middle-mouse-button panning in the page editor.
///
/// The editor reserves plain drags for the marquee and only lets
/// `InteractiveViewer` pan while Space is held, which left the middle button —
/// the gesture that already panned the page viewer — doing nothing here. A
/// middle-button drag has no other meaning on the canvas, so `ZoomableCanvas`
/// now treats it as a pan unconditionally, and the marquee listener has to
/// stand down for it: a middle drag must neither rubber-band nor clear the
/// selection underneath the pan.
library;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/page_editor_harness.dart';

/// The canvas's transformation, reached through the editor's one
/// `InteractiveViewer` so the test reads the same matrix the operator's pan
/// manipulates.
TransformationController _canvasController(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

/// Zooms the canvas to 2x, centred, so a pan has somewhere to go — at 1:1 the
/// child exactly fills the viewport and the translation is pinned.
Future<Rect> _zoomToTwice(WidgetTester tester) async {
  final viewport = tester.getRect(find.byType(InteractiveViewer));
  _canvasController(tester).value = Matrix4.identity()
    ..translateByDouble(-viewport.width / 2, -viewport.height / 2, 0, 1)
    ..scaleByDouble(2, 2, 2, 1);
  await tester.pump();
  return viewport;
}

/// Drags with only the middle mouse button held, [by] in two steps from
/// [from], the way a real mouse crosses the touch slop mid-gesture.
Future<void> _middleDrag(WidgetTester tester, Offset from, Offset by) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
    buttons: kMiddleMouseButton,
  );
  await tester.pump();
  await gesture.moveBy(by / 2);
  await tester.pump();
  await gesture.moveBy(by / 2);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('a middle-button drag pans the canvas, no Space required',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    final viewport = await _zoomToTwice(tester);

    final before = _canvasController(tester).value.getTranslation();
    await _middleDrag(tester, viewport.center, const Offset(60, 40));
    final after = _canvasController(tester).value.getTranslation();

    // Dragging right and down carries the content along, so the translation
    // grows. The exact figure depends on when the pan engages within the
    // drag; the direction and that it moved at all are the contract.
    expect(after.x, greaterThan(before.x),
        reason: 'a middle drag right must pan the canvas right');
    expect(after.y, greaterThan(before.y),
        reason: 'a middle drag down must pan the canvas down');
  });

  testWidgets('a middle-button drag is not a marquee', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    // Sweep empty canvas right across the asset; a marquee this size would
    // select it.
    await _middleDrag(
      tester,
      onCanvas(tester, 0.1, 0.1),
      onCanvas(tester, 0.6, 0.7) - onCanvas(tester, 0.1, 0.1),
    );

    expect(selectedCount(tester), 0,
        reason: 'a middle drag must not rubber-band a selection');
  });

  testWidgets('a middle-button drag leaves the selection alone',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);
    await tapAsset(tester, 0.3, 0.4);
    expect(selectedCount(tester), 1);

    // A primary-button drag on empty canvas would clear this selection on
    // pointer-down; the pan must not.
    await _middleDrag(
      tester,
      onCanvas(tester, 0.7, 0.7),
      const Offset(60, 40),
    );

    expect(selectedCount(tester), 1,
        reason: 'panning must not deselect what the operator picked');
  });

  testWidgets('a middle-button drag starting on an asset does not move it',
      (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.4)]);

    await _middleDrag(
      tester,
      onCanvas(tester, 0.3, 0.4),
      const Offset(80, 60),
    );

    final saved = await saveAndReadBack(tester, prefs);
    expect(savedXs(saved), [0.3],
        reason: 'the middle button pans; only a primary drag moves an asset');
    expect(savedYs(saved), [0.4]);
  });
}

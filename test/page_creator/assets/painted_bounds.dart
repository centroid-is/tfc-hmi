// Bounds of the pixels a conveyor actually paints.
//
// Shared because geometry is a poor proxy for ink and both callers were
// reaching for the same wrong one. `Path.getBounds` is a control-point
// estimate, not a measurement: on a skeleton the fit has stretched it reports
// a rect tens of pixels larger than anything drawn inside it. Nor is the ink
// the band outline — the outline is stroked, so half the border's width lies
// beyond it — and when a band is too wide for its own bend the painter drops
// the outline entirely and strokes the centerline instead, which reaches
// further still.
//
// Rasterising sidesteps all of that: whatever the painter chose to do, these
// are the pixels it left.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// Room left around the box, so ink painted outside it is still caught rather
/// than clipped away by the edge of the image.
const paintPadding = 60.0;

/// Bounds of what [geometry] paints into a [box]-sized area, in box
/// coordinates: (0,0) is the box's top left, so a negative left means the
/// belt painted outside it.
///
/// Null if nothing was painted at all.
///
/// Call inside `tester.runAsync` — `toImage` needs a real event loop.
Future<Rect?> paintedBounds(Size box, ConveyorPathGeometry? geometry,
    {double? straightBeltWidth}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(paintPadding, paintPadding);
  ConveyorPainter(
    color: Colors.green,
    batches: const {},
    angle: 0,
    showFrequency: false,
    frequency: null,
    geometry: geometry,
    straightBeltWidth: straightBeltWidth,
  ).paint(canvas, box);

  final w = (box.width + 2 * paintPadding).ceil();
  final h = (box.height + 2 * paintPadding).ceil();
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  // Every canvas in the fill sweeps rasterises one of these; left undisposed
  // they pile up for the length of the run.
  image.dispose();
  if (data == null) return null;
  final bytes = data.buffer.asUint8List();

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // Anything but near-transparent counts, so the antialiased fringe of
      // the outline is included rather than quietly trimmed off.
      if (bytes[(y * w + x) * 4 + 3] > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  return Rect.fromLTRB(minX - paintPadding, minY - paintPadding,
      maxX + 1 - paintPadding, maxY + 1 - paintPadding);
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// The page editor draws an asset's blue selection box from its layout box:
/// `asset.size` fractions times the *canvas* constraints (see `AssetStack`),
/// and lays the asset out with those exact tight constraints. The canvas is
/// never the whole window — the editor has panes and headers around it — so
/// `MediaQuery.of(context).size` is a different (larger) rectangle.
///
/// A turned conveyor must therefore derive its path geometry from the box it
/// is actually laid out in, not from the window. These tests reproduce the
/// AssetStack situation: a tight box that disagrees with MediaQuery, then
/// check the painted belt against the box.
const _background = Color(0xFF1A1A2E);
const _boundaryKey = Key('box-fit-boundary');

/// Hosts a turned conveyor in a tight [box] placed at [boxOrigin] inside a
/// larger canvas, under a MediaQuery of [mediaSize] — the same constraint
/// shape `AssetStack` produces when the editor canvas is smaller than the
/// window.
Widget _host({
  required Size mediaSize,
  required Offset boxOrigin,
  required Size box,
  required ConveyorConfig config,
  required Size canvas,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: mediaSize),
        child: Scaffold(
          backgroundColor: _background,
          body: RepaintBoundary(
            key: _boundaryKey,
            child: Container(
              width: canvas.width,
              height: canvas.height,
              color: _background,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: boxOrigin.dx,
                    top: boxOrigin.dy,
                    width: box.width,
                    height: box.height,
                    child: Conveyor(config),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

ConveyorConfig _turnedPreview() => ConveyorConfig.preview()
  // Deliberately different fractions than the box the widget is given, so a
  // MediaQuery-derived size cannot accidentally coincide with the box.
  ..size = const RelativeSize(width: 0.5, height: 0.5)
  // Thin enough that the bend's true radius fits the test box and the fill
  // solve can genuinely fill it — the spanning assertions rely on that.
  ..beltThickness = 0.15
  ..turns.add(ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5));

Future<ui.Image> _capture(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  final image = await tester.runAsync(() => boundary.toImage());
  return image!;
}

Future<ByteData> _rgba(WidgetTester tester, ui.Image image) async {
  final data = await tester
      .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  return data!;
}

/// Bounding rect of every pixel that is not the background color.
Rect _paintedBounds(ByteData rgba, int width, int height) {
  int minX = width, minY = height, maxX = -1, maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final r = rgba.getUint8(i);
      final g = rgba.getUint8(i + 1);
      final b = rgba.getUint8(i + 2);
      final bg = (r - (_background.r * 255).round()).abs() <= 2 &&
          (g - (_background.g * 255).round()).abs() <= 2 &&
          (b - (_background.b * 255).round()).abs() <= 2;
      if (bg) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  expect(maxX, greaterThanOrEqualTo(0),
      reason: 'nothing was painted at all');
  return Rect.fromLTRB(
      minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
}

void main() {
  testWidgets(
      'turned belt stays inside and centered on its layout box '
      'when MediaQuery disagrees with the box', (tester) async {
    const box = Size(300, 200);
    const origin = Offset(150, 150);
    await tester.pumpWidget(_host(
      mediaSize: const Size(1000, 800),
      canvas: const Size(600, 500),
      boxOrigin: origin,
      box: box,
      config: _turnedPreview(),
    ));

    final image = await _capture(tester);
    final rgba = await _rgba(tester, image);
    final painted = _paintedBounds(rgba, image.width, image.height);
    final boxRect = origin & box;

    // The border stroke may extend ~1px past the fitted path; allow 2px slop.
    final slop = boxRect.inflate(2);
    expect(slop.contains(painted.topLeft), isTrue,
        reason: 'belt paints outside its box: $painted vs box $boxRect');
    expect(slop.contains(painted.bottomRight - const Offset(0.1, 0.1)), isTrue,
        reason: 'belt paints outside its box: $painted vs box $boxRect');

    // Centered on the box — this is what makes the blue selection box and
    // the visual agree.
    expect((painted.center.dx - boxRect.center.dx).abs(), lessThan(3),
        reason: 'belt is horizontally off-center: '
            '${painted.center} vs ${boxRect.center}');
    expect((painted.center.dy - boxRect.center.dy).abs(), lessThan(3),
        reason: 'belt is vertically off-center: '
            '${painted.center} vs ${boxRect.center}');

    // And it should actually use the box — a belt shrunk to a fraction of
    // its box "fits" trivially but is the shortening the operator sees.
    expect(painted.width, greaterThan(boxRect.width * 0.9),
        reason: 'belt does not span its box width: $painted vs $boxRect');
    expect(painted.height, greaterThan(boxRect.height * 0.9),
        reason: 'belt does not span its box height: $painted vs $boxRect');
  });

  testWidgets(
      'same box renders the same belt regardless of window size '
      '(switching screens must not reshape the conveyor)', (tester) async {
    const box = Size(300, 200);
    const origin = Offset(100, 100);
    const canvas = Size(520, 420);

    Future<Uint8List> renderAt(Size mediaSize) async {
      await tester.pumpWidget(_host(
        mediaSize: mediaSize,
        canvas: canvas,
        boxOrigin: origin,
        box: box,
        config: _turnedPreview(),
      ));
      final image = await _capture(tester);
      final rgba = await _rgba(tester, image);
      return rgba.buffer.asUint8List();
    }

    final small = await renderAt(const Size(1000, 800));
    // A different window: other monitor, other aspect ratio.
    final large = await renderAt(const Size(1600, 900));

    expect(small.length, large.length);
    var differing = 0;
    for (var i = 0; i < small.length; i++) {
      if (small[i] != large[i]) differing++;
    }
    expect(differing, 0,
        reason: 'the same conveyor box painted differently under two window '
            'sizes ($differing/${small.length} bytes differ)');
  });

  testWidgets(
      'explicit belt width scales with the box, not the window', (tester) async {
    const box = Size(300, 200);
    const origin = Offset(100, 100);
    const canvas = Size(520, 420);
    final config = _turnedPreview()
      // 10% of the canvas height the asset lives on.
      ..beltWidthRelative = 0.1;

    Future<Rect> paintedAt(Size mediaSize) async {
      await tester.pumpWidget(_host(
        mediaSize: mediaSize,
        canvas: canvas,
        boxOrigin: origin,
        box: box,
        config: config,
      ));
      final image = await _capture(tester);
      final rgba = await _rgba(tester, image);
      return _paintedBounds(rgba, image.width, image.height);
    }

    final first = await paintedAt(const Size(1000, 800));
    final second = await paintedAt(const Size(1600, 900));

    // The belt width is part of the painted footprint; if it tracked the
    // window height it would fatten on the bigger screen.
    expect((first.width - second.width).abs(), lessThan(1),
        reason: 'belt footprint changed with window size: $first vs $second');
    expect((first.height - second.height).abs(), lessThan(1),
        reason: 'belt footprint changed with window size: $first vs $second');
  });
}

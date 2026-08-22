// Text in a page asset must be laid out at the size it is drawn at.
//
// The bug this guards: every asset that wanted its label to follow the asset's
// size wrapped a `Text` in a `FittedBox`. `FittedBox` lays the child out at the
// child's own font size and paints it through a scale transform, so the glyphs
// are rasterised for one size and blitted at another -- soft on screen, and
// sharp again only when something forces a re-raster at the size actually
// shown, which is why zooming the canvas appeared to fix it.
//
// `fittedFontSize` / `AutoSizedText` compute the size first and lay the text
// out at it. These tests pin the arithmetic, the responsiveness to a resize,
// and -- by rasterising both arrangements into the same box -- that the new
// one really is the crisper of the two.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';

const _style = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);

double _widthAt(String text, double fontSize) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _style.copyWith(fontSize: fontSize)),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

double _heightAt(String text, double fontSize) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _style.copyWith(fontSize: fontSize)),
    textDirection: TextDirection.ltr,
  )..layout();
  final h = painter.height;
  painter.dispose();
  return h;
}

/// Of the pixels carrying any ink, the fraction that are mid-grey rather than
/// solid. A glyph rasterised at its final size is mostly solid with a thin
/// antialiased rim; one resampled from another size is mostly rim.
Future<double> _softness(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var mid = 0, ink = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    final v = bytes[i];
    if (v < 250) ink++;
    if (v > 20 && v < 235) mid++;
  }
  expect(ink, greaterThan(0), reason: 'nothing was painted');
  return mid / ink;
}

Future<ui.Image> _rasterise(
    WidgetTester tester, Widget child, Size box) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: const ValueKey('raster'),
          child: SizedBox(
            width: box.width,
            height: box.height,
            child: ColoredBox(color: Colors.white, child: child),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('raster')));
  return boundary.toImage(pixelRatio: 1.0);
}

/// The font size the [AutoSizedText] under [finder] actually rendered at.
double _renderedFontSize(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text));
  return text.style!.fontSize!;
}

void main() {
  group('fittedFontSize', () {
    test('fills the box when nothing caps it', () {
      const box = Size(200, 60);
      final size = fittedFontSize(text: 'Recipes', style: _style, box: box);

      expect(_widthAt('Recipes', size), lessThanOrEqualTo(box.width + 0.5));
      expect(_heightAt('Recipes', size), lessThanOrEqualTo(box.height + 0.5));
      // ...and is genuinely the largest that fits: 10% more overflows.
      final tooBig = size * 1.1;
      expect(
        _widthAt('Recipes', tooBig) > box.width ||
            _heightAt('Recipes', tooBig) > box.height,
        isTrue,
      );
    });

    test('a narrow box is limited by width, not height', () {
      final size = fittedFontSize(
          text: 'Checklists', style: _style, box: const Size(60, 400));
      expect(_widthAt('Checklists', size), lessThanOrEqualTo(60.5));
    });

    test('grows with the box — the asset stays responsive to a resize', () {
      final small =
          fittedFontSize(text: 'Recipes', style: _style, box: const Size(100, 40));
      final large =
          fittedFontSize(text: 'Recipes', style: _style, box: const Size(200, 80));
      expect(large, greaterThan(small));
      // Twice the box is twice the type, give or take rounding.
      expect(large / small, closeTo(2.0, 0.05));
    });

    test('heightFraction caps it at a share of the box height', () {
      const box = Size(2000, 100);
      final capped = fittedFontSize(
          text: 'Recipes', style: _style, box: box, heightFraction: 0.3);
      expect(capped, closeTo(30, 0.01));
    });

    test('the width fit still applies under a heightFraction cap', () {
      // A box tall enough for 0.3 * 100 = 30pt, but far too narrow for it.
      const box = Size(40, 100);
      final size = fittedFontSize(
          text: 'Checklists', style: _style, box: box, heightFraction: 0.3);
      expect(size, lessThan(30));
      expect(_widthAt('Checklists', size), lessThanOrEqualTo(40.5));
    });

    test('maxFontSize and minFontSize bound the result', () {
      expect(
        fittedFontSize(
            text: 'Recipes',
            style: _style,
            box: const Size(2000, 2000),
            maxFontSize: 18),
        18,
      );
      expect(
        fittedFontSize(
            text: 'Recipes',
            style: _style,
            box: const Size(2, 2),
            minFontSize: 6),
        6,
      );
    });

    test('a quarter turn fits the rotated bounding box', () {
      // Upright, a wide short box takes a big font; turned on its side the
      // same string has to fit the box's *height* instead.
      const box = Size(400, 40);
      final upright =
          fittedFontSize(text: 'Recipes', style: _style, box: box);
      final turned = fittedFontSize(
          text: 'Recipes', style: _style, box: box, angleRadians: 1.5707963);
      expect(turned, lessThan(upright));
      // Turned, the text's own width must fit the box height.
      expect(_widthAt('Recipes', turned), lessThanOrEqualTo(box.height + 0.5));
    });

    test('falls back rather than dividing by nothing', () {
      // Empty string: nothing to fit.
      expect(
        fittedFontSize(text: '', style: _style, box: const Size(100, 100)),
        14,
      );
      // Unbounded box: nothing to fit to.
      expect(
        fittedFontSize(
            text: 'Recipes',
            style: _style,
            box: const Size(double.infinity, 100)),
        14,
      );
    });
  });

  group('AutoSizedText', () {
    testWidgets('lays the text out at the computed size, with no FittedBox',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 60,
              child: AutoSizedText('Recipes', style: _style),
            ),
          ),
        ),
      ));

      expect(find.byType(FittedBox), findsNothing);
      expect(
        find.descendant(
            of: find.byType(AutoSizedText), matching: find.byType(Transform)),
        findsNothing,
      );
      final rendered = _renderedFontSize(tester);
      expect(rendered, greaterThan(14));
      expect(_widthAt('Recipes', rendered), lessThanOrEqualTo(200.5));
    });

    testWidgets('re-sizes the type when the box changes', (tester) async {
      Future<double> at(Size box) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: box.width,
                height: box.height,
                child: const AutoSizedText('Recipes', style: _style),
              ),
            ),
          ),
        ));
        return _renderedFontSize(tester);
      }

      final narrow = await at(const Size(120, 200));
      final wide = await at(const Size(240, 200));
      expect(wide, greaterThan(narrow));
    });

    testWidgets('rotates without a separate layout pass', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 60,
              child: AutoSizedText('Recipes',
                  style: _style, angleRadians: 1.5707963),
            ),
          ),
        ),
      ));
      // The turn is a transform (it has to be) but the glyphs are still laid
      // out at their final size: the text's own width fits the box height.
      expect(
        find.descendant(
            of: find.byType(AutoSizedText), matching: find.byType(Transform)),
        findsOneWidget,
      );
      expect(_widthAt('Recipes', _renderedFontSize(tester)),
          lessThanOrEqualTo(60.5));
    });

    testWidgets('rasterises crisper than the FittedBox it replaces',
        (tester) async {
      await tester.runAsync(() async {
        // A box that lands on a non-integer scale factor, which is where
        // resampling shows up worst.
        const box = Size(163.0, 47.0);

        final auto = await _rasterise(
          tester,
          const AutoSizedText('Recipes',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
          box,
        );
        final autoSoftness = await _softness(auto);
        auto.dispose();

        final fitted = await _rasterise(
          tester,
          const Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text('Recipes',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
            ),
          ),
          box,
        );
        final fittedSoftness = await _softness(fitted);
        fitted.dispose();

        // Same string, same box, same final glyph size — the only difference
        // is whether a transform scaled the raster. If this ever stops being
        // true, the FittedBox has crept back in somewhere.
        expect(
          autoSoftness,
          lessThan(fittedSoftness),
          reason: 'AutoSizedText softness $autoSoftness should be below '
              'FittedBox softness $fittedSoftness',
        );
      });
    });
  });
}

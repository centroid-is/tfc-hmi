/// The air cabinet asset takes its chrome from the color scheme.
///
/// It used to be a light-theme widget pasted onto a dark page: a
/// `Colors.grey[200]` box, a `Colors.black26` border and white "off" LEDs,
/// all baked in. On the dark scheme that is a bright grey card with white
/// dots, regardless of what the operator picked in preferences.
///
/// The contract these tests pin is *theme tracking*, not three particular
/// RGBA values: the same widget under [solarized]'s light and dark themes
/// must paint differently, and each must match the scheme it was given. A
/// literal passes an equality check against whichever theme it happened to
/// be written for; it cannot pass both at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/converter/color_converter.dart';
import 'package:tfc/page_creator/assets/aircab.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/theme.dart' show solarized;

/// Keys are empty on purpose: the cabinet draws its idle state without
/// touching OPC UA, so no StateMan fake is needed.
AirCabConfig _config() => AirCabConfig(
      label: 'Air cabinet',
      pressureKey: '',
      softStartKey: '',
      buttonKey: '',
    );

/// Pumps the cabinet under [theme].
///
/// The [MaterialApp] is keyed by brightness so that swapping themes inside one
/// test rebuilds the subtree outright. Reusing it would leave `AnimatedTheme`
/// mid-lerp after a single frame, and the assertion would read the *previous*
/// scheme's color.
Future<void> _pump(WidgetTester tester, ThemeData theme,
    {double side = 220}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        key: ValueKey(theme.brightness),
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: side,
              height: side,
              child: AirCab(config: _config()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The paragraph behind a piece of text the cabinet drew.
RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

/// The cabinet's outer box — the first [Container] the asset builds, the one
/// carrying the rounded [BoxDecoration].
BoxDecoration _cabinetBox(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byType(AirCab), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  final (light, dark) = solarized();

  group('Air cabinet chrome follows the color scheme', () {
    testWidgets('dark scheme: box and border come from the scheme roles',
        (tester) async {
      await _pump(tester, dark);
      final box = _cabinetBox(tester);

      expect(box.color, dark.colorScheme.surfaceContainerHighest,
          reason: 'the cabinet body is a surface role, not a baked grey');
      expect((box.border! as Border).top.color, dark.colorScheme.outlineVariant,
          reason: 'the border is an outline role, not a baked black26');
    });

    testWidgets('light scheme: the same widget takes the light roles',
        (tester) async {
      await _pump(tester, light);
      final box = _cabinetBox(tester);

      expect(box.color, light.colorScheme.surfaceContainerHighest);
      expect((box.border! as Border).top.color, light.colorScheme.outlineVariant);
    });

    testWidgets('the two schemes do not paint the same cabinet',
        (tester) async {
      await _pump(tester, dark);
      final darkBox = _cabinetBox(tester);
      await _pump(tester, light);
      final lightBox = _cabinetBox(tester);

      expect(darkBox.color, isNot(lightBox.color),
          reason: 'a literal fill would be identical under both themes — '
              'that is the bug this asset had');
      expect((darkBox.border! as Border).top.color,
          isNot((lightBox.border! as Border).top.color),
          reason: 'a literal border would be identical under both themes');
    });

    testWidgets('the off state of both LEDs is the grey role, not white',
        (tester) async {
      await _pump(tester, dark);

      final leds = tester
          .widgetList<Led>(
              find.descendant(of: find.byType(AirCab), matching: find.byType(Led)))
          .toList();

      expect(leds, hasLength(2), reason: 'Pressure and Soft start');
      for (final led in leds) {
        expect(led.config.offColor, AssetColor.grey,
            reason: 'an unlit LED on a dark page must not be a white dot');
        expect(led.config.offColor.isRole, isTrue,
            reason: 'role-backed colors re-resolve when the scheme changes');
      }
    });
  });

  /// The lamp captions used to be laid out at half the *row height* and then
  /// clipped to whatever width was left beside a full-height lamp — about 54
  /// logical pixels for ten characters. Every golden showed "Pr…" and "So…",
  /// two letters of a nine- and a ten-character word, on an asset an operator
  /// reads from across a packing hall.
  ///
  /// Both halves of that need pinning. Clipping is the visible failure, but a
  /// caption shrunk to nothing to avoid clipping would be just as unreadable
  /// and would pass a fits-in-its-box check on its own.
  group('the lamp captions are readable', () {
    for (final side in <double>[140, 220, 400]) {
      testWidgets('$side px cabinet: neither caption is clipped',
          (tester) async {
        await _pump(tester, dark, side: side);

        for (final caption in const ['Pressure', 'Soft start']) {
          final paragraph = _paragraph(tester, caption);
          final wanted = TextPainter(
            text: paragraph.text,
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();

          expect(
            wanted.width,
            lessThanOrEqualTo(paragraph.size.width + 0.5),
            reason: '"$caption" wants ${wanted.width.toStringAsFixed(1)}px at '
                'the size it was laid out, and was given '
                '${paragraph.size.width.toStringAsFixed(1)}px — the word is '
                'being cut off',
          );
        }
      });

      testWidgets('$side px cabinet: the captions keep their size',
          (tester) async {
        await _pump(tester, dark, side: side);

        final title = _paragraph(tester, 'Air cabinet').text.style!.fontSize!;
        final sizes = <double>[
          for (final caption in const ['Pressure', 'Soft start'])
            _paragraph(tester, caption).text.style!.fontSize!,
        ];

        expect(sizes.first, closeTo(sizes.last, 0.01),
            reason: 'the two captions are one list and must be set at one '
                'size, not sized independently so the shorter one grows');
        // The lamp is the state and gets 72% of its row (Jon, 2026-08-23:
        // "the LEDs inside the air cabinet are too small"); in a square box
        // the caption takes what is left beside it, which is about a third
        // of the tag. Below that it is fine print; above it the lamp shrinks
        // back to a dot.
        expect(
          sizes.first,
          greaterThan(title * 0.3),
          reason: 'a caption more than three times as small as the cabinet '
              "name is fine print at arm's length, never mind across the hall",
        );
      });
    }
  });
}

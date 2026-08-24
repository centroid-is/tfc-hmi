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
Future<void> _pump(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        key: ValueKey(theme.brightness),
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: AirCab(config: _config()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

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
}

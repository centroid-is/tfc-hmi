// The Recipes and Checklists buttons are utility buttons, not equipment.
//
// They were solid `primary` with bold `onPrimary` text -- two bright blocks on
// a page whose colours are meant to say how the line is doing. They now take
// the scheme's raised surface with the page's own text colour, so they are
// calm in every scheme and still visibly a button (shadow, hairline, pressed
// shrink). These tests pin that to the scheme rather than to one literal grey,
// so the look holds in light and dark alike.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/button.dart';
import 'package:tfc/page_creator/assets/checklists.dart';
import 'package:tfc/page_creator/assets/recipes.dart';
import 'package:tfc/theme.dart';

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget asset) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 200, height: 80, child: asset),
        ),
      ),
    ),
  ));
  await tester.pump();
}

ButtonPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ButtonPainter));
  return paint.painter! as ButtonPainter;
}

void main() {
  final themes = <String, ThemeData>{
    'solarized light': solarized().$1,
    'solarized dark': solarized().$2,
    'muted light': muted().$1,
    'muted dark': muted().$2,
  };

  final assets = <String, Widget Function()>{
    'Recipes': () => Recipes(config: RecipesConfig.preview()),
    'Checklists': () => Checklists(config: ChecklistsConfig.preview()),
  };

  for (final theme in themes.entries) {
    for (final asset in assets.entries) {
      testWidgets('${asset.key} is a calm surface button under ${theme.key}',
          (tester) async {
        await _pump(tester, theme.value, asset.value());
        final scheme = theme.value.colorScheme;

        final painter = _painter(tester);
        // The face is one notch off the page, not the accent colour.
        expect(painter.color, scheme.surfaceContainerHighest);
        expect(painter.color, isNot(scheme.primary));
        expect(painter.color, isNot(scheme.surface));
        // With an edge that shows on a dark fill too.
        expect(painter.borderColor, theme.value.dividerColor);
        expect(painter.buttonType, ButtonType.square);

        // The label is the page's text colour at medium weight -- not bold
        // white on blue.
        final label = tester.widget<Text>(find.text(asset.key));
        expect(label.style!.color, scheme.onSurface);
        expect(label.style!.fontWeight, isNot(FontWeight.bold));
      });
    }
  }

  testWidgets('the face shows it is being pressed, and lets go',
      (tester) async {
    await _pump(
        tester, solarized().$2, Checklists(config: ChecklistsConfig.preview()));
    expect(_painter(tester).isPressed, isFalse);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Checklists)));
    await tester.pump();
    expect(_painter(tester).isPressed, isTrue);

    await gesture.up();
    await tester.pump();
    expect(_painter(tester).isPressed, isFalse);
  });

  testWidgets('the whole face is the button, not only the glyphs',
      (tester) async {
    // A tap in the corner of the face, well clear of the label, still
    // presses it -- the detector is opaque over the painted area.
    await _pump(
        tester, solarized().$1, Recipes(config: RecipesConfig.preview()));
    final corner = tester.getTopLeft(find.byType(Recipes)) + const Offset(6, 6);
    final gesture = await tester.startGesture(corner);
    await tester.pump();
    expect(_painter(tester).isPressed, isTrue);
    await gesture.up();
    await tester.pump();
  });
}

// The button faces the operator actually complained about.
//
// Recipes, Checklists and the drawing-viewer button all drew their label as
// `FittedBox(fit: scaleDown, child: Text(...))` over a `ButtonPainter` face.
// That has two faults at once: `scaleDown` never *grows*, so the label stayed
// at the ambient 14pt however big the button was; and when the button was
// small enough to shrink it, the shrinking was a scale transform over a raster
// made for 14pt. Small type and a resampled raster both read as "blurry until
// I zoom in".
//
// These tests pin the label to the button's size and keep the FittedBox out.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/checklists.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/drawing_viewer.dart';
import 'package:tfc/page_creator/assets/recipes.dart';

Future<double> _labelSize(
    WidgetTester tester, Widget asset, Size box, String label) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: box.width, height: box.height, child: asset),
        ),
      ),
    ),
  ));
  await tester.pump();
  final text = tester.widget<Text>(find.text(label));
  return text.style!.fontSize!;
}

void main() {
  testWidgets('the Recipes label is sized from the button, not scaled into it',
      (tester) async {
    final small = await _labelSize(
        tester, Recipes(config: RecipesConfig.preview()), const Size(90, 40), 'Recipes');
    expect(find.byType(FittedBox), findsNothing);

    final large = await _labelSize(
        tester, Recipes(config: RecipesConfig.preview()), const Size(270, 120),
        'Recipes');

    // It grows with the button — the whole point. `scaleDown` never did.
    expect(large, greaterThan(small));
    // And it is capped at a share of the height rather than filling it.
    expect(large, closeTo(120 * 0.3, 0.51));
  });

  testWidgets('the Checklists label is sized from the button too',
      (tester) async {
    final small = await _labelSize(tester, Checklists(config: ChecklistsConfig.preview()),
        const Size(90, 40), 'Checklists');
    expect(find.byType(FittedBox), findsNothing);

    final large = await _labelSize(tester,
        Checklists(config: ChecklistsConfig.preview()), const Size(270, 120), 'Checklists');

    expect(large, greaterThan(small));
    // The longer word is width-limited before it reaches the 0.3 height cap.
    expect(large, lessThanOrEqualTo(120 * 0.3 + 0.01));
  });

  testWidgets('the drawing button sizes its icon and label from the face',
      (tester) async {
    Future<(double, double)> at(Size box) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: box.width,
                height: box.height,
                child: DrawingViewerButton(config: DrawingViewerConfig.preview()),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final icon = tester.widget<Icon>(find.byIcon(Icons.picture_as_pdf));
      final label = tester.widget<Text>(find.byType(Text).first);
      return (icon.size!, label.style!.fontSize!);
    }

    final (smallIcon, smallLabel) = await at(const Size(90, 60));
    expect(find.byType(FittedBox), findsNothing);
    final (largeIcon, largeLabel) = await at(const Size(270, 180));

    expect(largeIcon, greaterThan(smallIcon));
    expect(largeLabel, greaterThan(smallLabel));
  });

  testWidgets('every button label goes through AutoSizedText', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                  width: 200,
                  height: 80,
                  child: Recipes(config: RecipesConfig.preview())),
              SizedBox(
                  width: 200,
                  height: 80,
                  child: Checklists(config: ChecklistsConfig.preview())),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(AutoSizedText), findsNWidgets(2));
  });
}

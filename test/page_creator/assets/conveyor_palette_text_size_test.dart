import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/theme.dart';

/// The conveyor colour palette is a legend, and its labels must stay
/// legend-sized.
///
/// #275 replaced `FittedBox(fit: BoxFit.scaleDown)` with a plain
/// `AutoSizedText` across the assets. For a button face that was the point --
/// the label should grow with the button. For this asset it was not: each
/// label sits in a box the size of its whole colour swatch, so "Auto" grew
/// until it filled one, and a key to five colours became five giant captions.
///
/// The size only misbehaves on a *large* asset, which is why the goldens that
/// were regenerated alongside that change did not read as obviously wrong --
/// they were compared against nothing.
void main() {
  final (lightTheme, _) = solarized();

  /// What `AutoSizedText` inside the palette resolves as its own default --
  /// captured from the palette's own subtree, because that is the number
  /// `shrinkOnly` caps against. A `DefaultTextStyle` read at the root of a
  /// MaterialApp is the 48pt fallback, which would make the assertion below
  /// pass on a label three times too big.
  late double resolvedDefault;

  /// The palette at [size] logical pixels, under a real theme.
  Future<void> pumpPalette(WidgetTester tester, Size size) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: Center(
            child: Builder(builder: (context) {
              resolvedDefault = DefaultTextStyle.of(context).style.fontSize!;
              return SizedBox(
              width: size.width,
              height: size.height,
              child: ConveyorColorPalette(
                config: ConveyorColorPaletteConfig()
                  ..size = RelativeSize(
                    width: size.width / 800,
                    height: size.height / 600,
                  ),
              ),
            );
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Every rendered font size in the palette, largest first.
  List<double> fontSizes(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (t.style?.fontSize != null) t.style!.fontSize!,
      ]..sort((a, b) => b.compareTo(a));

  testWidgets('labels do not grow past body text, however big the asset is',
      (tester) async {
    // 800x600 makes each of the five swatches ~90px tall. At
    // heightFraction 0.6 an uncapped label reaches ~55pt.
    await pumpPalette(tester, const Size(800, 600));
    final defaultSize = resolvedDefault;

    final sizes = fontSizes(tester);
    expect(sizes, isNotEmpty, reason: 'the palette rendered no text at all');
    expect(sizes.first, lessThanOrEqualTo(defaultSize),
        reason: 'a legend label grew past body text: ${sizes.first}pt against '
            'a ${defaultSize}pt default. This is the #275 regression -- the '
            'label filled its colour swatch.');
  });

  testWidgets('the labels still shrink when the asset is small',
      (tester) async {
    // The other half of scaleDown, and the reason this is not just a fixed
    // font size: a palette dragged small must still fit its own words.
    await pumpPalette(tester, const Size(120, 90));

    final small = fontSizes(tester);
    await pumpPalette(tester, const Size(800, 600));
    final large = fontSizes(tester);

    expect(small.first, lessThan(large.first),
        reason: 'the label did not shrink for a small asset, so it is now a '
            'fixed size rather than shrink-to-fit');
  });

  testWidgets('every swatch label is actually rendered', (tester) async {
    // Guards the two tests above from passing because nothing was drawn.
    await pumpPalette(tester, const Size(800, 600));

    for (final label in ['Auto', 'Clean', 'Manual', 'Stopped', 'Fault']) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }
    expect(find.text('Conveyor colors'), findsOneWidget);
  });
}

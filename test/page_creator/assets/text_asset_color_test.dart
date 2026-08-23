import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/text.dart';

void main() {
  Future<Color?> resolve(WidgetTester tester, Brightness brightness,
      Color? configured) async {
    Color? out;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(builder: (context) {
        out = textAssetColor(context, configured);
        return const SizedBox();
      }),
    ));
    // A theme change animates; read after the lerp has finished.
    await tester.pumpAndSettle();
    return out;
  }

  testWidgets('black follows the theme: light in dark, dark in light',
      (tester) async {
    final dark = await resolve(tester, Brightness.dark, Colors.black);
    final light = await resolve(tester, Brightness.light, Colors.black);
    expect(dark, isNotNull);
    expect(dark!.computeLuminance(), greaterThan(0.5),
        reason: 'the 72 legacy-black labels must be readable on the dark page');
    expect(light!.computeLuminance(), lessThan(0.5));
  });

  testWidgets('null is the theme colour too', (tester) async {
    final dark = await resolve(tester, Brightness.dark, null);
    expect(dark!.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('a chosen colour is honoured as set', (tester) async {
    final c = await resolve(tester, Brightness.dark, Colors.red);
    expect(c, Colors.red);
  });
}

/// The app-bar sign-in affordance, and the semantic elevation colour it is
/// painted with.
///
/// The theme group lives here rather than in a theme test file of its own
/// because this widget is `HmiStateColors.orange`'s only consumer: keeping the
/// token's contract next to the thing that reads it is what stops the two
/// drifting apart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/theme.dart';

void main() {
  group('HmiStateColors.orange', () {
    test('solarizedLight.orange is the Solarized orange', () {
      expect(HmiStateColors.solarizedLight.orange, SolarizedColors.orange);
    });

    test('solarizedDark.orange is the Solarized orange', () {
      expect(HmiStateColors.solarizedDark.orange, SolarizedColors.orange);
    });

    test('mutedLight.orange is the muted forced orange', () {
      expect(HmiStateColors.mutedLight.orange, MutedColors.forcedOrange);
    });

    test('mutedDark.orange is the muted forced orange', () {
      expect(HmiStateColors.mutedDark.orange, MutedColors.forcedOrange);
    });

    test('forcedOrange is not manualOchre — a second ochre would be unreadable',
        () {
      expect(MutedColors.forcedOrange, isNot(MutedColors.manualOchre));
    });

    test('copyWith(orange:) replaces orange and leaves the rest alone', () {
      const base = HmiStateColors.mutedLight;
      final copy = base.copyWith(orange: const Color(0xFF123456));

      expect(copy.orange, const Color(0xFF123456));
      expect(copy.green, base.green);
      expect(copy.yellow, base.yellow);
      expect(copy.blue, base.blue);
      expect(copy.grey, base.grey);
      expect(copy.red, base.red);
      expect(copy.violet, base.violet);
      expect(copy.onState, base.onState);
    });

    test('copyWith() without orange keeps this palette\'s orange', () {
      const base = HmiStateColors.mutedLight;
      expect(base.copyWith().orange, base.orange);
    });

    test('lerp carries orange: t=0 is this palette, t=1 is the other', () {
      const a = HmiStateColors.mutedLight;
      const b = HmiStateColors.solarizedLight;

      expect(a.lerp(b, 0).orange, a.orange);
      expect(a.lerp(b, 1).orange, b.orange);
    });

    testWidgets('of() on a bare MaterialApp still answers with an orange',
        (tester) async {
      late HmiStateColors light;
      late HmiStateColors dark;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          light = HmiStateColors.of(context);
          return const SizedBox.shrink();
        }),
      ));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (context) {
          dark = HmiStateColors.of(context);
          return const SizedBox.shrink();
        }),
      ));

      expect(light.orange, HmiStateColors.solarizedLight.orange);
      expect(dark.orange, HmiStateColors.solarizedDark.orange);
    });
  });
}

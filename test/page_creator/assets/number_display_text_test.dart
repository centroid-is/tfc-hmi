// What a readout puts on screen, and why the empty string is not a unit.
//
// NumberWidget lays the text out with FittedBox(BoxFit.contain): the glyphs
// are scaled until the whole string fits the asset's box. Every character in
// that string therefore costs size, including a separator appended next to no
// units at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/number.dart';

void main() {
  group('numberDisplayText', () {
    test('appends real units, separated by a space', () {
      expect(numberDisplayText('12.34', 'kg'), '12.34 kg');
    });

    test('renders the bare value when units are unset', () {
      expect(numberDisplayText('12.34', null), '12.34');
    });

    test('renders the bare value when units are the empty string', () {
      // The speedbatcher checkweigher readouts are configured this way --
      // units cleared rather than removed. This used to render "12.34 ",
      // whose trailing space FittedBox measures like any other glyph.
      expect(numberDisplayText('12.34', ''), '12.34');
    });

    test('does not leave a trailing separator for any unitless value', () {
      for (final value in <String>['0', '0.00', '-1', '1234.56']) {
        expect(numberDisplayText(value, ''), isNot(endsWith(' ')));
        expect(numberDisplayText(value, null), isNot(endsWith(' ')));
      }
    });

    test('keeps units that are only meaningful as a symbol', () {
      expect(numberDisplayText('50', '%'), '50 %');
    });
  });
}

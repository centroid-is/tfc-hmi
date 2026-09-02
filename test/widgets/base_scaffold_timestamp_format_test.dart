/// The date shown in the app bar and beside every alarm is `dd.MM.yy` --
/// the way the plant writes it. These pin the padding and the two-digit
/// year, which a naive `year % 100` gets wrong for 2000-2009.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/base_scaffold.dart';

void main() {
  group('formatDate', () {
    test('is dd.MM.yy', () {
      expect(formatDate(DateTime(2026, 9, 2, 14, 5, 9)), '02.09.26');
    });

    test('pads single-digit day and month', () {
      expect(formatDate(DateTime(2026, 1, 7)), '07.01.26');
    });

    test('does not pad away a two-digit day or month', () {
      expect(formatDate(DateTime(2026, 12, 31)), '31.12.26');
    });

    test('keeps the leading zero of a noughties year', () {
      expect(formatDate(DateTime(2007, 3, 4)), '04.03.07');
    });
  });

  test('formatTimeOfDay is HH:mm:ss, zero-padded', () {
    expect(formatTimeOfDay(DateTime(2026, 9, 2, 9, 5, 3)), '09:05:03');
  });

  test('formatTimestamp joins the two with a single space', () {
    expect(formatTimestamp(DateTime(2026, 9, 2, 14, 5, 9)), '02.09.26 14:05:09');
  });
}

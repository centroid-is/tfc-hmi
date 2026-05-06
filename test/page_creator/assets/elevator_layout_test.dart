import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/elevator_layout.dart';

void main() {
  group('platformOffsetTop', () {
    test('progress=0.0, h=100, ph=20 -> 80 (platform at bottom)', () {
      expect(platformOffsetTop(0.0, 100.0, 20.0), 80.0);
    });
    test('progress=1.0, h=100, ph=20 -> 0 (platform at top)', () {
      expect(platformOffsetTop(1.0, 100.0, 20.0), 0.0);
    });
    test('progress=0.5, h=100, ph=20 -> 40 (geometric centre)', () {
      expect(platformOffsetTop(0.5, 100.0, 20.0), 40.0);
    });
    test('progress=0.0, h=200, ph=10 -> 190 (verifies (h - ph) factor)', () {
      expect(platformOffsetTop(0.0, 200.0, 10.0), 190.0);
    });
    test('progress=1.0, h=200, ph=10 -> 0 (top is platform-height-independent)', () {
      expect(platformOffsetTop(1.0, 200.0, 10.0), 0.0);
    });
    test('progress=0.5, h=200, ph=40 -> 80 (proves platform thickness subtraction)', () {
      expect(platformOffsetTop(0.5, 200.0, 40.0), 80.0);
    });
    test('platform-fills-bbox at progress=0 -> 0 (degenerate)', () {
      expect(platformOffsetTop(0.0, 100.0, 100.0), 0.0);
    });
    test('platform-fills-bbox at progress=1 -> 0 (degenerate)', () {
      expect(platformOffsetTop(1.0, 100.0, 100.0), 0.0);
    });
  });
}

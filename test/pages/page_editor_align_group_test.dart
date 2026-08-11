import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/pages/page_editor.dart';

/// `alignGroup` backs the editor's "Align horizontally / vertically" entries.
/// It moves every selected asset's centre onto the midpoint between the two
/// outermost centres, along one axis only.
///
/// The axis naming is the easy thing to get backwards: aligning *horizontally*
/// produces a horizontal row, which means a shared **y**.
///
/// `isAlreadyAligned` decides whether the menu entry is enabled, so it has to
/// agree exactly with "alignGroup would change nothing".
void main() {
  List<AssetPlacement> align(List<AssetPlacement> placements, AlignAxis axis) =>
      alignGroup(placements: placements, axis: axis);

  AssetPlacement at(double x, double y, {double? angle, double size = 0.1}) =>
      AssetPlacement(x: x, y: y, width: size, height: size, angle: angle);

  group('alignGroup — horizontal', () {
    test('gives every asset the shared midpoint y', () {
      final result = align(
          [at(0.2, 0.2), at(0.5, 0.6), at(0.8, 0.4)], AlignAxis.horizontal);

      // Extremes are 0.2 and 0.6, so the line is 0.4.
      for (final p in result) {
        expect(p.y, closeTo(0.4, 1e-12));
      }
    });

    test('leaves x alone', () {
      final result = align(
          [at(0.2, 0.2), at(0.5, 0.6), at(0.8, 0.4)], AlignAxis.horizontal);

      expect(result.map((p) => p.x), [0.2, 0.5, 0.8]);
    });
  });

  group('alignGroup — vertical', () {
    test('gives every asset the shared midpoint x', () {
      final result =
          align([at(0.2, 0.2), at(0.6, 0.5), at(0.4, 0.8)], AlignAxis.vertical);

      for (final p in result) {
        expect(p.x, closeTo(0.4, 1e-12));
      }
    });

    test('leaves y alone', () {
      final result =
          align([at(0.2, 0.2), at(0.6, 0.5), at(0.4, 0.8)], AlignAxis.vertical);

      expect(result.map((p) => p.y), [0.2, 0.5, 0.8]);
    });
  });

  group('alignGroup — which line', () {
    test('is the midpoint of the extremes, not the mean', () {
      // Three assets crowded at the bottom and one at the top. The mean would
      // be 0.7; a drawing tool puts the line halfway between the outermost
      // two, so the extremes move symmetrically toward each other.
      final result = align(
        [at(0.1, 0.1), at(0.3, 0.9), at(0.5, 0.9), at(0.7, 0.9)],
        AlignAxis.horizontal,
      );

      for (final p in result) {
        expect(p.y, closeTo(0.5, 1e-12));
      }
    });

    test('ignores asset sizes — centres are what line up', () {
      // A big asset next to a small one: the line sits between their centres,
      // not weighted by how much canvas each covers.
      final result = align([
        AssetPlacement(x: 0.3, y: 0.2, width: 0.5, height: 0.4),
        AssetPlacement(x: 0.7, y: 0.6, width: 0.02, height: 0.02),
      ], AlignAxis.horizontal);

      for (final p in result) {
        expect(p.y, closeTo(0.4, 1e-12));
      }
    });

    test('is idempotent', () {
      final once = align([at(0.2, 0.2), at(0.5, 0.7)], AlignAxis.horizontal);
      final twice = align(once, AlignAxis.horizontal);

      for (var i = 0; i < once.length; i++) {
        expect(twice[i].y, once[i].y);
        expect(twice[i].x, once[i].x);
      }
    });
  });

  group('alignGroup — the two axes compose', () {
    test('aligning both stacks every asset on one point', () {
      final result = align(
        align([at(0.2, 0.2), at(0.8, 0.6)], AlignAxis.horizontal),
        AlignAxis.vertical,
      );

      for (final p in result) {
        expect(p.x, closeTo(0.5, 1e-12));
        expect(p.y, closeTo(0.4, 1e-12));
      }
    });

    test('the second align does not disturb the first', () {
      final horizontal =
          align([at(0.2, 0.2), at(0.8, 0.6)], AlignAxis.horizontal);
      final both = align(horizontal, AlignAxis.vertical);

      for (var i = 0; i < both.length; i++) {
        expect(both[i].y, horizontal[i].y, reason: 'y should survive');
      }
    });
  });

  group('alignGroup — passthrough', () {
    test('sizes and angles are untouched', () {
      final result = align([
        AssetPlacement(x: 0.3, y: 0.2, width: 0.4, height: 0.1, angle: 45),
        AssetPlacement(x: 0.7, y: 0.6, width: 0.05, height: 0.3),
      ], AlignAxis.horizontal);

      expect(result[0].width, 0.4);
      expect(result[0].height, 0.1);
      expect(result[0].angle, 45);
      expect(result[1].angle, isNull);
    });

    test('does not mutate the input', () {
      final before = [at(0.2, 0.2), at(0.8, 0.6)];
      align(before, AlignAxis.horizontal);

      expect(before[0].y, 0.2);
      expect(before[1].y, 0.6);
    });

    test('an empty selection returns empty', () {
      expect(align([], AlignAxis.horizontal), isEmpty);
    });

    test('a single asset is left where it is', () {
      // Its own centre is the midpoint of the extremes.
      final result = align([at(0.3, 0.7)], AlignAxis.horizontal);
      expect(result.single.x, 0.3);
      expect(result.single.y, 0.7);
    });
  });

  group('isAlreadyAligned', () {
    test('true for a row that already shares a y', () {
      expect(
        isAlreadyAligned([at(0.2, 0.5), at(0.8, 0.5)], AlignAxis.horizontal),
        isTrue,
      );
    });

    test('false as soon as one asset is off the line', () {
      expect(
        isAlreadyAligned(
            [at(0.2, 0.5), at(0.5, 0.5), at(0.8, 0.51)], AlignAxis.horizontal),
        isFalse,
      );
    });

    test('checks the axis it was asked about', () {
      // A row shares a y but not an x.
      final row = [at(0.2, 0.5), at(0.8, 0.5)];
      expect(isAlreadyAligned(row, AlignAxis.horizontal), isTrue);
      expect(isAlreadyAligned(row, AlignAxis.vertical), isFalse);
    });

    test('true for fewer than two assets — nothing to line up', () {
      expect(isAlreadyAligned([], AlignAxis.horizontal), isTrue);
      expect(isAlreadyAligned([at(0.3, 0.7)], AlignAxis.horizontal), isTrue);
    });

    test('true for whatever alignGroup just produced', () {
      // alignGroup writes one identical value, so exact equality holds and the
      // menu entry disables itself after a successful align.
      for (final axis in AlignAxis.values) {
        final aligned = align([at(0.2, 0.2), at(0.5, 0.9), at(0.8, 0.4)], axis);
        expect(isAlreadyAligned(aligned, axis), isTrue, reason: '$axis');
      }
    });

    test('agrees with alignGroup being a no-op', () {
      // The predicate exists to disable the menu entry, so it must be exactly
      // the cases where aligning would change nothing.
      final cases = [
        [at(0.2, 0.5), at(0.8, 0.5)],
        [at(0.2, 0.5), at(0.8, 0.6)],
        [at(0.5, 0.2), at(0.5, 0.8)],
        [at(0.3, 0.7)],
        <AssetPlacement>[],
      ];
      for (final placements in cases) {
        for (final axis in AlignAxis.values) {
          final result = align(placements, axis);
          final unchanged = List.generate(
            placements.length,
            (i) =>
                result[i].x == placements[i].x &&
                result[i].y == placements[i].y,
          ).every((same) => same);

          expect(isAlreadyAligned(placements, axis), unchanged,
              reason: 'mismatch for $axis on '
                  '${placements.map((p) => '(${p.x},${p.y})').join(' ')}');
        }
      }
    });
  });
}

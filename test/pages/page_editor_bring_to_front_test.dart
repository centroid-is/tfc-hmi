import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/pages/page_editor.dart';

/// Z-order in the page editor is list order: `AssetStack` renders
/// `AssetPage.assets` in sequence, so the tail of the list is the front of the
/// stack. "Bring to front" therefore moves the selection to the tail — the
/// mirror image of `sendToBackOrder`, covered in
/// page_editor_send_to_back_test.dart.
void main() {
  group('bringToFrontOrder', () {
    test('moves a single asset to the tail', () {
      expect(bringToFrontOrder(['a', 'b', 'c'], {'a'}), ['b', 'c', 'a']);
    });

    test('leaves an asset already at the front alone', () {
      expect(bringToFrontOrder(['a', 'b', 'c'], {'c'}), ['a', 'b', 'c']);
    });

    test('preserves relative order within the selection', () {
      // a before c in the input, so a stays before c in the result.
      expect(
        bringToFrontOrder(['a', 'b', 'c', 'd'], {'c', 'a'}),
        ['b', 'd', 'a', 'c'],
      );
    });

    test('preserves relative order of the assets left behind', () {
      expect(
        bringToFrontOrder(['a', 'b', 'c', 'd', 'e'], {'c'}),
        ['a', 'b', 'd', 'e', 'c'],
      );
    });

    test('handles a non-contiguous selection', () {
      expect(
        bringToFrontOrder(['a', 'b', 'c', 'd', 'e'], {'a', 'c', 'e'}),
        ['b', 'd', 'a', 'c', 'e'],
      );
    });

    test('moving everything is a no-op', () {
      expect(bringToFrontOrder(['a', 'b'], {'a', 'b'}), ['a', 'b']);
    });

    test('ignores targets that are not on the page', () {
      expect(bringToFrontOrder(['a', 'b'], {'zz'}), ['a', 'b']);
    });

    test('does not modify the input list', () {
      final input = ['a', 'b', 'c'];
      bringToFrontOrder(input, {'a'});
      expect(input, ['a', 'b', 'c']);
    });
  });

  group('isAlreadyAtFront', () {
    test('true for the top-most asset', () {
      expect(isAlreadyAtFront(['a', 'b', 'c'], {'c'}), isTrue);
    });

    test('false for anything below it', () {
      expect(isAlreadyAtFront(['a', 'b', 'c'], {'a'}), isFalse);
      expect(isAlreadyAtFront(['a', 'b', 'c'], {'b'}), isFalse);
    });

    test('true for a contiguous run at the front', () {
      expect(isAlreadyAtFront(['a', 'b', 'c'], {'b', 'c'}), isTrue);
    });

    test('false when the run is contiguous but not at the front', () {
      expect(isAlreadyAtFront(['a', 'b', 'c'], {'a', 'b'}), isFalse);
    });

    test('false for a non-contiguous selection touching the front', () {
      expect(isAlreadyAtFront(['a', 'b', 'c'], {'a', 'c'}), isFalse);
    });

    test('true when every asset is selected', () {
      expect(isAlreadyAtFront(['a', 'b'], {'a', 'b'}), isTrue);
    });

    test('true for an empty selection — nothing to move', () {
      expect(isAlreadyAtFront(['a', 'b'], <String>{}), isTrue);
    });

    test('true for an empty page', () {
      expect(isAlreadyAtFront(<String>[], {'a'}), isTrue);
    });

    test('agrees with bringToFrontOrder being a no-op', () {
      // The predicate exists to disable the menu entry, so it must be exactly
      // the cases where reordering would change nothing.
      const page = ['a', 'b', 'c', 'd'];
      for (final targets in [
        {'a'},
        {'b'},
        {'d'},
        {'c', 'd'},
        {'b', 'c'},
        {'b', 'd'},
        {'a', 'b', 'c', 'd'},
        <String>{},
      ]) {
        final unchanged =
            bringToFrontOrder(page, targets).toString() == page.toString();
        expect(isAlreadyAtFront(page, targets), unchanged,
            reason: 'mismatch for targets $targets');
      }
    });
  });
}

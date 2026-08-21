/// The two pieces of bookkeeping that make Ctrl/Cmd+Z survivable in the page
/// editor.
///
/// [matchAssetsAcrossUndo] is what lets the selection and the open config pane
/// live through an undo: the restored page is parsed fresh, so every asset the
/// editor was holding becomes a dead instance unless it can be paired with the
/// one that came back in its place.
///
/// [changedTopLevelKeys] is what keeps a typed label from flushing the
/// 50-entry history: the pane reports changes one serialization at a time, and
/// this says whether the latest one is more of the same property or the start
/// of a new edit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/pages/page_editor.dart';

/// An asset serialization, cut down to what the pairing reads.
Map<String, dynamic> asset(String type, {Object? at, Object? extra}) => {
      constAssetName: type,
      'coordinates': at ?? 0,
      if (extra != null) 'extra': extra,
    };

void main() {
  group('matchAssetsAcrossUndo', () {
    test('pairs untouched assets by their serialization', () {
      final live = [asset('box', at: 1), asset('text', at: 2)];
      final restored = [asset('box', at: 1), asset('text', at: 2)];

      expect(matchAssetsAcrossUndo(live, restored), [0, 1]);
    });

    test('follows a restack, where positions move but contents do not', () {
      final a = asset('box', at: 1);
      final b = asset('box', at: 2);
      final c = asset('text', at: 3);

      // Undoing a send-to-back: the live order is c, a, b; the snapshot's was
      // a, b, c. Nothing changed but the order, so every asset must find its
      // own counterpart rather than whatever sits at its index.
      expect(matchAssetsAcrossUndo([c, a, b], [a, b, c]), [2, 0, 1]);
    });

    test('pairs the one asset the undone edit changed', () {
      final live = [asset('box', at: 1), asset('text', at: 99)];
      final restored = [asset('box', at: 1), asset('text', at: 2)];

      expect(matchAssetsAcrossUndo(live, restored), [0, 1],
          reason: 'the edited asset is the only leftover on either side');
    });

    test('pairs several changed assets in list order', () {
      // What undoing a nudge of a three-asset selection looks like.
      final live = [
        asset('box', at: 11),
        asset('box', at: 22),
        asset('text', at: 33),
      ];
      final restored = [
        asset('box', at: 1),
        asset('box', at: 2),
        asset('text', at: 3),
      ];

      expect(matchAssetsAcrossUndo(live, restored), [0, 1, 2]);
    });

    test('leaves an asset the undo removes unpaired', () {
      // Undoing a paste: the copy has no counterpart to come back as.
      final source = asset('box', at: 1);
      final pasted = asset('box', at: 2);

      expect(matchAssetsAcrossUndo([source, pasted], [source]), [0, null]);
    });

    test('pairs what survives when the undo brings assets back', () {
      // Undoing a delete: the restored page has more than the canvas does.
      final kept = asset('text', at: 9);
      expect(
        matchAssetsAcrossUndo([kept], [asset('box', at: 1), kept]),
        [1],
      );
    });

    test('refuses to pair leftovers of different types', () {
      // Contrived, but the guard is what keeps a positional pairing from
      // handing the config pane an asset of another kind entirely.
      final live = [asset('box', at: 1)];
      final restored = [asset('text', at: 2)];

      expect(matchAssetsAcrossUndo(live, restored), [null]);
    });

    test('handles duplicates without pairing two live assets to one', () {
      final twin = asset('box', at: 1);
      final pairing = matchAssetsAcrossUndo([twin, twin], [twin, twin]);

      expect(pairing.toSet(), {0, 1},
          reason: 'identical assets must still pair one-to-one');
    });

    test('an empty page pairs nothing', () {
      expect(matchAssetsAcrossUndo([], [asset('box')]), isEmpty);
    });
  });

  group('changedTopLevelKeys', () {
    test('names the property that changed', () {
      expect(
        changedTopLevelKeys(
            '{"text":"a","color":1}', '{"text":"ab","color":1}'),
        {'text'},
      );
    });

    test('ignores a change that is not one', () {
      expect(changedTopLevelKeys('{"text":"a"}', '{"text":"a"}'), isEmpty);
    });

    test('sees added and removed properties', () {
      expect(changedTopLevelKeys('{"a":1}', '{"b":1}'), {'a', 'b'});
    });

    test('compares nested values whole', () {
      expect(
        changedTopLevelKeys('{"size":{"w":1,"h":2}}', '{"size":{"w":1,"h":3}}'),
        {'size'},
      );
    });

    test('answers null when it cannot tell', () {
      // The caller reads null as "start a new undo entry", which is the safe
      // way to be wrong: an extra entry costs a second Ctrl+Z, a missing one
      // loses an edit.
      expect(changedTopLevelKeys('not json', '{"a":1}'), isNull);
      expect(changedTopLevelKeys('[1,2]', '{"a":1}'), isNull);
    });
  });
}

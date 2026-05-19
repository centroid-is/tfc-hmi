/// Tests for [UmasBitAliasMap] — pure data, no network.
///
/// Source of truth for the data model used by [UmasBitAliasDecoder]
/// and the `bit-aliases` CLI subcommand.
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_bit_alias_map.dart';

void main() {
  group('BitAliasEntry', () {
    test('equality and hashCode honour all fields', () {
      const a = BitAliasEntry(
        aliasName: '%M5',
        parentBlock: 1,
        parentByteOffset: 0,
        bitOffset: 4,
        parentVariableName: 'mBits',
      );
      const b = BitAliasEntry(
        aliasName: '%M5',
        parentBlock: 1,
        parentByteOffset: 0,
        bitOffset: 4,
        parentVariableName: 'mBits',
      );
      const c = BitAliasEntry(
        aliasName: '%M5',
        parentBlock: 1,
        parentByteOffset: 0,
        bitOffset: 5,
        parentVariableName: 'mBits',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes alias name and bit position', () {
      const e = BitAliasEntry(
        aliasName: '%M5',
        parentBlock: 7,
        parentByteOffset: 0,
        bitOffset: 4,
      );
      final s = e.toString();
      expect(s, contains('%M5'));
      expect(s, contains('bit=4'));
    });
  });

  group('UmasBitAliasMap', () {
    test('empty map: lookup returns null, entries empty', () {
      final map = UmasBitAliasMap(const []);
      expect(map.lookup('%M5'), isNull);
      expect(map.entries, isEmpty);
      expect(map.length, 0);
    });

    test('single-entry lookup hit and miss', () {
      final map = UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: '%M5',
          parentBlock: 1,
          parentByteOffset: 0,
          bitOffset: 4,
        ),
      ]);
      final hit = map.lookup('%M5');
      expect(hit, isNotNull);
      expect(hit!.bitOffset, 4);
      expect(map.lookup('%M999'), isNull);
      expect(map.length, 1);
    });

    test('duplicate alias names — last write wins', () {
      // Defensive: should never happen on a real PLC but the constructor
      // must not throw. Last-write-wins preserves the simplest semantics.
      final map = UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: '%M5',
          parentBlock: 1,
          parentByteOffset: 0,
          bitOffset: 4,
        ),
        BitAliasEntry(
          aliasName: '%M5',
          parentBlock: 2,
          parentByteOffset: 8,
          bitOffset: 0,
        ),
      ]);
      final hit = map.lookup('%M5');
      expect(hit, isNotNull);
      expect(hit!.parentBlock, 2);
      expect(hit.parentByteOffset, 8);
      expect(hit.bitOffset, 0);
    });

    test('entries iteration is stable and complete', () {
      final entries = List<BitAliasEntry>.generate(
        16,
        (i) => BitAliasEntry(
          aliasName: '%M${i + 1}',
          parentBlock: 1,
          parentByteOffset: i ~/ 8,
          bitOffset: i % 8,
        ),
      );
      final map = UmasBitAliasMap(entries);
      final names = map.entries.map((e) => e.aliasName).toList();
      expect(names, hasLength(16));
      expect(names.toSet(), hasLength(16));
      expect(names.first, '%M1');
      expect(names.last, '%M16');
    });

    test('immutability: entries view rejects modification', () {
      final map = UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: '%M1',
          parentBlock: 1,
          parentByteOffset: 0,
          bitOffset: 0,
        ),
      ]);
      // entries is Iterable; if it returns a list it must be unmodifiable.
      final iter = map.entries;
      if (iter is List<BitAliasEntry>) {
        expect(
          () => (iter).add(const BitAliasEntry(
              aliasName: 'x',
              parentBlock: 0,
              parentByteOffset: 0,
              bitOffset: 0)),
          throwsUnsupportedError,
        );
      }
    });
  });
}

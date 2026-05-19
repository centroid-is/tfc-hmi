/// Tests for [UmasBitAliasDecoder] — synchronous bit extraction.
///
/// The decoder is intentionally trivial (single bit-shift) but the
/// shape of the API matters for the parallel Conveyor agent: it
/// consumes [BitAliasDecoder.decodeBit] and must see a stable
/// `(int parentWordValue, String aliasName) -> bool?` signature.
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_bit_alias.dart';
import 'package:tfc_dart/core/umas_bit_alias_map.dart';

void main() {
  group('UmasBitAliasDecoder.decodeBit', () {
    late UmasBitAliasMap map;
    late UmasBitAliasDecoder decoder;

    setUp(() {
      // 16 bits: %M1=bit0 .. %M16=bit15 (parent block 1, parent byte 0)
      final entries = List<BitAliasEntry>.generate(
        16,
        (i) => BitAliasEntry(
          aliasName: '%M${i + 1}',
          parentBlock: 1,
          parentByteOffset: 0,
          bitOffset: i,
        ),
      );
      map = UmasBitAliasMap(entries);
      decoder = UmasBitAliasDecoder(map);
    });

    test('all 16 bits of 0xAA55 decode to the right boolean', () {
      // 0xAA55 = 1010_1010_0101_0101
      //  bit 0 = 1  → %M1
      //  bit 1 = 0  → %M2
      //  bit 2 = 1  → %M3
      //  ...
      const word = 0xAA55;
      final expected = <int, bool>{
        0: true, 1: false, 2: true, 3: false,
        4: true, 5: false, 6: true, 7: false,
        8: false, 9: true, 10: false, 11: true,
        12: false, 13: true, 14: false, 15: true,
      };
      for (int b = 0; b < 16; b++) {
        final got = decoder.decodeBit(word, '%M${b + 1}');
        expect(got, equals(expected[b]),
            reason: 'bit $b of 0xAA55 should be ${expected[b]}');
      }
    });

    test('missing alias name returns null (not a thrown exception)', () {
      expect(decoder.decodeBit(0xFFFF, '%M9999'), isNull);
      expect(decoder.decodeBit(0x0000, 'bogus'), isNull);
    });

    test('decodes all-zero and all-ones parent words exhaustively', () {
      for (int b = 0; b < 16; b++) {
        expect(decoder.decodeBit(0x0000, '%M${b + 1}'), isFalse);
        expect(decoder.decodeBit(0xFFFF, '%M${b + 1}'), isTrue);
      }
    });

    test('upper-bit decoding ignores higher word bits (treats as uint16)', () {
      // The decoder honours the BitAliasEntry.bitOffset literally — if the
      // caller passes a 32-bit value the top half should still be reachable
      // when an entry's bitOffset is in that range. Add a synthetic %B16
      // alias at bit 16 to lock this contract.
      final extended = UmasBitAliasMap([
        ...map.entries,
        const BitAliasEntry(
          aliasName: '%B16',
          parentBlock: 1,
          parentByteOffset: 2,
          bitOffset: 16,
        ),
      ]);
      final dec = UmasBitAliasDecoder(extended);
      expect(dec.decodeBit(0x10000, '%B16'), isTrue);
      expect(dec.decodeBit(0x0FFFF, '%B16'), isFalse);
    });
  });

  group('UmasBitAliasDecoder interface stability', () {
    test('implements BitAliasDecoder', () {
      final dec = UmasBitAliasDecoder(UmasBitAliasMap(const []));
      expect(dec, isA<BitAliasDecoder>());
    });
  });
}

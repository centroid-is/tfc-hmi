// BitAliasDecoder interface contract.
//
// The bit-alias decoder is the seam where the bit-alias enumeration
// code plugs in. This file pins down:
//
//   1. The interface shape (`decodeBit(parentWordValue, aliasName)` -> bool?)
//   2. The contract that unknown aliases return null (never throw)
//   3. The `StubBitAliasDecoder` shipped today returns null for everything
//      so callers can wire the seam now and get sensible "?" fallbacks
//      until the real decoder lands.
//   4. The `MapBitAliasDecoder` masks the right bit from a host-order
//      parent WORD. Bit 0 = LSB.

import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_bit_alias.dart';

void main() {
  group('StubBitAliasDecoder', () {
    test('returns null for any alias name', () {
      const decoder = StubBitAliasDecoder();
      expect(decoder.decodeBit(0, 'red'), isNull);
      expect(decoder.decodeBit(0xFFFF, 'green'), isNull);
      expect(decoder.decodeBit(42, 'unknown-alias'), isNull);
      expect(decoder.decodeBit(-1, 'grey'), isNull);
    });

    test('never throws — even with weird inputs', () {
      const decoder = StubBitAliasDecoder();
      expect(() => decoder.decodeBit(0, ''), returnsNormally);
      expect(() => decoder.decodeBit(0x7FFFFFFF, 'red'), returnsNormally);
    });

    test('is const-constructible (cheap to use as default)', () {
      const a = StubBitAliasDecoder();
      const b = StubBitAliasDecoder();
      expect(identical(a, b), isTrue);
    });
  });

  group('MapBitAliasDecoder', () {
    test('reads bit at known alias position', () {
      const decoder = MapBitAliasDecoder({'red': 0, 'grey': 1, 'green': 2});
      // 0b001 -> red on, grey/green off
      expect(decoder.decodeBit(0x01, 'red'), isTrue);
      expect(decoder.decodeBit(0x01, 'grey'), isFalse);
      expect(decoder.decodeBit(0x01, 'green'), isFalse);
      // 0b010 -> only grey on
      expect(decoder.decodeBit(0x02, 'red'), isFalse);
      expect(decoder.decodeBit(0x02, 'grey'), isTrue);
      expect(decoder.decodeBit(0x02, 'green'), isFalse);
      // 0b100 -> only green on
      expect(decoder.decodeBit(0x04, 'green'), isTrue);
    });

    test('returns null for unknown alias', () {
      const decoder = MapBitAliasDecoder({'red': 0});
      expect(decoder.decodeBit(0xFFFF, 'amber'), isNull);
      expect(decoder.decodeBit(0xFFFF, ''), isNull);
    });

    test('handles all 16 bits of a WORD', () {
      const decoder = MapBitAliasDecoder({
        'b0': 0,
        'b7': 7,
        'b8': 8,
        'b15': 15,
      });
      expect(decoder.decodeBit(0x8001, 'b0'), isTrue); // 0b1...0001
      expect(decoder.decodeBit(0x8001, 'b7'), isFalse);
      expect(decoder.decodeBit(0x8001, 'b15'), isTrue);
      expect(decoder.decodeBit(0x0080, 'b7'), isTrue);
      expect(decoder.decodeBit(0x0100, 'b8'), isTrue);
    });

    test('negative bit indices yield null (defensive)', () {
      const decoder = MapBitAliasDecoder({'bad': -1});
      expect(decoder.decodeBit(0xFFFF, 'bad'), isNull);
    });
  });

  group('BitAliasDecoder interface', () {
    test('custom decoders can be plugged in', () {
      final decoder = _FakeRedOnlyDecoder();
      expect(decoder.decodeBit(0x01, 'red'), isTrue);
      expect(decoder.decodeBit(0x00, 'red'), isFalse);
      expect(decoder.decodeBit(0xFFFF, 'green'), isNull,
          reason: 'unknown alias yields null');
    });

    test('decoders treat unknown aliases as null, not exceptions', () {
      final decoder = _FakeRedOnlyDecoder();
      expect(() => decoder.decodeBit(0, 'green'), returnsNormally);
      expect(decoder.decodeBit(0, 'green'), isNull);
    });
  });
}

/// Toy decoder that understands the alias `red` at bit 0.
class _FakeRedOnlyDecoder implements BitAliasDecoder {
  @override
  bool? decodeBit(int parentWordValue, String aliasName) {
    if (aliasName != 'red') return null;
    return (parentWordValue & 0x01) == 1;
  }
}

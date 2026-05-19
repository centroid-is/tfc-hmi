/// Fixture-based parsing tests for the DD02 12-byte short array records
/// returned for IDX 0x1B..0x23 on the live M580 at 192.168.112.159.
///
/// Source: `/tmp/bitalias-swarm-v2/trailer-probe-raw.json` (Phase 7 of the
/// swarm3-trailer probe). The records below are byte-for-byte copies of
/// what the M580 actually sent — locking them in as a regression fixture
/// guards against silent parser drift.
///
/// The parser under test is the existing
/// [UmasArrayTypeDefinition.tryParse], which already understands the
/// 12-byte wire shape. These tests prove the BOOL-array records this
/// task targets are decoded with the right [classId], [elementTypeId],
/// startIndex, and upperBound — the four fields the
/// [UmasBitAliasMap] builder needs to emit per-bit entries.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_bit_alias_map.dart';
import 'package:tfc_dart/core/umas_types.dart';

Uint8List _hex(String s) {
  final clean = s.replaceAll(RegExp(r'\s+'), '');
  return Uint8List.fromList([
    for (int i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

void main() {
  group('UmasArrayTypeDefinition.tryParse — DD02 short array records', () {
    // Each fixture: (IDX, raw 12-byte response body, expected shape).
    // Class IDs per the PLC4X mspec: 0x0001=BOOL, 0x0015=BYTE, 0x0016=WORD.

    test('IDX 0x1B → ARRAY[1..31] OF BYTE', () {
      final raw = _hex('04 15 00 01 01 00 00 00 1f 00 00 00');
      final def = UmasArrayTypeDefinition.tryParse(raw);
      expect(def, isNotNull);
      expect(def!.classId, 0x04);
      expect(def.elementTypeId, 0x15);
      expect(def.dimensions, hasLength(1));
      expect(def.dimensions.first.startIndex, 1);
      expect(def.dimensions.first.upperBound, 31);
      expect(def.totalElementCount, 31);
    });

    test('IDX 0x1F → ARRAY[1..31] OF BOOL (located-bit allocation #1)', () {
      final raw = _hex('04 01 00 01 01 00 00 00 1f 00 00 00');
      final def = UmasArrayTypeDefinition.tryParse(raw);
      expect(def, isNotNull);
      expect(def!.elementTypeId, 0x0001,
          reason: 'elementTypeId 0x0001 = BOOL');
      expect(def.dimensions.first.startIndex, 1);
      expect(def.dimensions.first.upperBound, 31);
      expect(def.totalElementCount, 31);
    });

    test('IDX 0x20 → ARRAY[257..384] OF BOOL (located-bit allocation #2)',
        () {
      final raw = _hex('04 01 00 01 01 01 00 00 80 01 00 00');
      final def = UmasArrayTypeDefinition.tryParse(raw);
      expect(def, isNotNull);
      expect(def!.elementTypeId, 0x0001);
      expect(def.dimensions.first.startIndex, 257);
      expect(def.dimensions.first.upperBound, 384);
      expect(def.totalElementCount, 128);
    });

    test('IDX 0x21 → ARRAY[1..3] OF BOOL (located-bit allocation #3)', () {
      final raw = _hex('04 01 00 01 01 00 00 00 03 00 00 00');
      final def = UmasArrayTypeDefinition.tryParse(raw);
      expect(def, isNotNull);
      expect(def!.elementTypeId, 0x0001);
      expect(def.dimensions.first.startIndex, 1);
      expect(def.dimensions.first.upperBound, 3);
      expect(def.totalElementCount, 3);
    });

    test('IDX 0x22 → ARRAY[513..640] OF BOOL (located-bit allocation #4)',
        () {
      final raw = _hex('04 01 00 01 01 02 00 00 80 02 00 00');
      final def = UmasArrayTypeDefinition.tryParse(raw);
      expect(def, isNotNull);
      expect(def!.elementTypeId, 0x0001);
      expect(def.dimensions.first.startIndex, 513);
      expect(def.dimensions.first.upperBound, 640);
      expect(def.totalElementCount, 128);
    });

    test('IDX 0x23 → ARRAY[0..7] OF WORD (not a BOOL alias, must be skipped)',
        () {
      final raw = _hex('04 16 00 01 00 00 00 00 07 00 00 00');
      final def = UmasArrayTypeDefinition.tryParse(raw);
      expect(def, isNotNull);
      expect(def!.elementTypeId, 0x16,
          reason: 'elementTypeId 0x16 = WORD — filter out from bit aliases');
      expect(def.dimensions.first.startIndex, 0);
      expect(def.dimensions.first.upperBound, 7);
    });

    test('total BOOL-array bits across the four located-bit allocations = 290',
        () {
      // The headline swarm3-trailer finding: 31 + 128 + 3 + 128 = 290 bits.
      final boolRecords = [
        _hex('04 01 00 01 01 00 00 00 1f 00 00 00'),
        _hex('04 01 00 01 01 01 00 00 80 01 00 00'),
        _hex('04 01 00 01 01 00 00 00 03 00 00 00'),
        _hex('04 01 00 01 01 02 00 00 80 02 00 00'),
      ];
      int total = 0;
      for (final raw in boolRecords) {
        final def = UmasArrayTypeDefinition.tryParse(raw)!;
        expect(def.elementTypeId, 0x0001);
        total += def.totalElementCount;
      }
      expect(total, 290);
    });
  });

  // --------------------------------------------------------------------
  // Bit-alias map construction from a synthetic parent variable + the
  // decoded BOOL-array definitions. This mirrors what UmasClient will do
  // on session prime: locate every UmasVariable whose dataTypeId is a
  // BOOL-array type, then expand the array into N BitAliasEntry rows
  // using parent.blockNo / parent.offset.
  // --------------------------------------------------------------------
  group('UmasBitAliasMap.buildFromArrayDefinition', () {
    test('ARRAY[1..16] OF BOOL → 16 entries, bit 0..15 of parent word', () {
      const def = UmasArrayTypeDefinition(
        classId: 0x04,
        elementTypeId: 0x0001,
        dimensions: [
          UmasArrayDimension(startIndex: 1, upperBound: 16),
        ],
      );
      final entries = UmasBitAliasMap.buildFromArrayDefinition(
        definition: def,
        parentVariableName: 'mBits',
        parentBlock: 1,
        parentByteOffset: 0,
        aliasPrefix: '%M',
      );
      expect(entries, hasLength(16));
      expect(entries.first.aliasName, '%M1');
      expect(entries.first.bitOffset, 0);
      expect(entries.first.parentByteOffset, 0);
      expect(entries.last.aliasName, '%M16');
      expect(entries.last.bitOffset, 15);
      expect(entries.last.parentByteOffset, 0);
      // every entry pinned to the same parent
      for (final e in entries) {
        expect(e.parentBlock, 1);
        expect(e.parentVariableName, 'mBits');
      }
    });

    test('ARRAY[257..384] OF BOOL → 128 entries spanning 8 parent words', () {
      const def = UmasArrayTypeDefinition(
        classId: 0x04,
        elementTypeId: 0x0001,
        dimensions: [
          UmasArrayDimension(startIndex: 257, upperBound: 384),
        ],
      );
      final entries = UmasBitAliasMap.buildFromArrayDefinition(
        definition: def,
        parentVariableName: 'mBits2',
        parentBlock: 2,
        parentByteOffset: 0x40,
        aliasPrefix: '%M',
      );
      expect(entries, hasLength(128));
      expect(entries.first.aliasName, '%M257');
      expect(entries.first.bitOffset, 0);
      expect(entries.first.parentByteOffset, 0x40);
      // %M273 sits at bit 0 of the next word (16 bits later)
      expect(entries[16].aliasName, '%M273');
      expect(entries[16].bitOffset, 0);
      expect(entries[16].parentByteOffset, 0x40 + 2);
      // last alias = %M384, bit 15 of the 8th word
      expect(entries.last.aliasName, '%M384');
      expect(entries.last.bitOffset, 15);
      expect(entries.last.parentByteOffset, 0x40 + 14);
    });

    test('non-BOOL array → empty (filtered out)', () {
      const def = UmasArrayTypeDefinition(
        classId: 0x04,
        elementTypeId: 0x16, // WORD
        dimensions: [
          UmasArrayDimension(startIndex: 0, upperBound: 7),
        ],
      );
      final entries = UmasBitAliasMap.buildFromArrayDefinition(
        definition: def,
        parentVariableName: 'words',
        parentBlock: 1,
        parentByteOffset: 0,
        aliasPrefix: '%M',
      );
      expect(entries, isEmpty);
    });
  });
}

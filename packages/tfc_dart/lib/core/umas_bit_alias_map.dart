/// Immutable data model for the UMAS located-bit / bit-alias registry.
///
/// Each [BitAliasEntry] describes one boolean alias (e.g. `%M5`,
/// `FB_Foo.bRunning`) and how to derive its value from a parent WORD read
/// off the PLC: `(parentBlock, parentByteOffset) → 16-bit read; bit at
/// bitOffset of that word`.
///
/// The map is built on session prime by `UmasClient` after the DD02
/// short-record sweep (IDX 0x1B..0x2A) finds every
/// `ARRAY[..] OF BOOL` type and resolves each occurrence in the
/// top-level variable list back to a concrete (block, offset) pair.
/// See `packages/tfc_dart/lib/core/umas_client.dart` for the live wiring,
/// and `/tmp/bitalias-swarm-v2/trailer-probe.md` for the protocol
/// background (the swarm3-trailer breakthrough that unblocked v1.1).
///
/// The decoder ([UmasBitAliasDecoder] in `umas_bit_alias.dart`) is
/// synchronous: callers fetch the parent WORD once via
/// [UmasClient.readVariable] (or [UmasClient.readBitAlias]) and then ask
/// the decoder to extract individual bits.
library;

import 'dart:typed_data';

import 'package:tfc_dart/core/umas_types.dart';

/// Wire-format layout enum. Public (re-exported via static fields on
/// [UmasBitAliasMap]) but only meaningfully constructed through the
/// `bitArrayLayout*` constants — the type itself is private.
enum _BitArrayLayout {
  /// 16 BOOLs packed per 2-byte WORD; `bitOffset = i % 16`,
  /// `parentByteOffset += (i ~/ 16) * 2`.
  packedBits16,

  /// 1 BOOL per byte (Schneider's default on M580 / B_Elevator for
  /// `ARRAY[..] OF BOOL` fields); `bitOffset = 0`,
  /// `parentByteOffset += i`.
  bytePerBool,
}

/// One located-bit allocation: an alias name pinned to a single bit of
/// a known parent WORD in PLC memory.
class BitAliasEntry {
  /// Canonical alias name. Typically `%M<n>` for located-bit
  /// allocations declared as `ARRAY[..] OF BOOL` at the project level,
  /// or `FB_Instance.member` for boolean members inside DFB/UDT
  /// instances.
  final String aliasName;

  /// UMAS block number containing the parent WORD.
  ///
  /// Mirrors [UmasVariable.blockNo] of the parent variable; used by
  /// [UmasClient.readBitAlias] to issue a 2-byte read against the
  /// correct memory block.
  final int parentBlock;

  /// Byte offset (within [parentBlock]) of the parent WORD this bit
  /// lives in. Computed from the parent variable's `offset` plus the
  /// 2-byte stride of the bit's position within the array.
  final int parentByteOffset;

  /// Bit position within the parent WORD (0..15 for the standard
  /// 16-bit BOOL-array case; higher values are accepted but only
  /// arise for non-WORD parents, which is not the v1.1 contract).
  final int bitOffset;

  /// Name of the parent UMAS variable, if known. Carried for display
  /// only — the decoder does not consult it.
  final String? parentVariableName;

  const BitAliasEntry({
    required this.aliasName,
    required this.parentBlock,
    required this.parentByteOffset,
    required this.bitOffset,
    this.parentVariableName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitAliasEntry &&
          other.aliasName == aliasName &&
          other.parentBlock == parentBlock &&
          other.parentByteOffset == parentByteOffset &&
          other.bitOffset == bitOffset &&
          other.parentVariableName == parentVariableName;

  @override
  int get hashCode => Object.hash(
        aliasName,
        parentBlock,
        parentByteOffset,
        bitOffset,
        parentVariableName,
      );

  @override
  String toString() => 'BitAliasEntry($aliasName '
      'block=0x${parentBlock.toRadixString(16)} '
      'off=0x${parentByteOffset.toRadixString(16)} '
      'bit=$bitOffset'
      '${parentVariableName == null ? '' : ' parent=$parentVariableName'})';
}

/// Read-only index of [BitAliasEntry] keyed by alias name.
///
/// Constructed once on UMAS session prime and re-used until the project
/// CRC changes (at which point [UmasClient] drops the cache and rebuilds).
class UmasBitAliasMap {
  final Map<String, BitAliasEntry> _byName;
  final List<BitAliasEntry> _ordered;

  /// Build a map from a flat list of entries. Last-write-wins on
  /// duplicate alias names (defensive — the live PLC catalog should
  /// not contain duplicates).
  UmasBitAliasMap(Iterable<BitAliasEntry> entries)
      : _ordered = List.unmodifiable(entries),
        _byName = {
          for (final e in entries) e.aliasName: e,
        };

  /// Look up an entry by canonical alias name. Returns `null` for
  /// unknown names so callers can fall back gracefully.
  BitAliasEntry? lookup(String aliasName) => _byName[aliasName];

  /// Unmodifiable view of every entry, in insertion order.
  Iterable<BitAliasEntry> get entries => _ordered;

  /// Number of entries in the map.
  int get length => _ordered.length;

  /// Storage layout of an `ARRAY[..] OF BOOL` on the wire.
  ///
  /// Schneider PLCs declare both layouts depending on context:
  ///   * [packedBits16]: 16 BOOLs per 2-byte WORD; each successive
  ///     element advances the bit position within the same word,
  ///     wrapping to the next word every 16 entries. This is the
  ///     classical "located bit" / `%M`-style packing.
  ///   * [bytePerBool]: 1 BOOL per byte (a non-zero byte is `TRUE`);
  ///     each successive element advances the byte offset by 1 and
  ///     `bitOffset` stays at 0. Observed on M580 / B_Elevator for
  ///     `ARRAY[..] OF BOOL` fields inside DFB instances — see
  ///     `Elevator.BMEP58_ECPU_EXT.DROP_HEALTH` whose array `byteSize`
  ///     equals the element count (31 → 31 bytes).
  static const bitArrayLayoutPackedBits16 = _BitArrayLayout.packedBits16;
  static const bitArrayLayoutBytePerBool = _BitArrayLayout.bytePerBool;

  /// Expand a single `ARRAY[..] OF BOOL` definition (decoded from a DD02
  /// short record via [UmasArrayTypeDefinition.tryParse]) into
  /// per-bit [BitAliasEntry] rows pinned to a concrete parent variable.
  ///
  /// * [definition] — the BOOL-array type definition (`elementTypeId ==
  ///   0x0001`, otherwise an empty list is returned).
  /// * [parentVariableName] — display name carried into every entry.
  /// * [parentBlock] — UMAS block number of the parent variable.
  /// * [parentByteOffset] — byte offset of the parent variable's first
  ///   element within [parentBlock].
  /// * [aliasPrefix] — printed before each array index, e.g. `%M` →
  ///   `%M5`, `%M6`, …. For DFB / UDT BOOL members callers should pass
  ///   `'$parentVariableName.bit'` (or similar) to produce
  ///   `'FB_X.bit5'`-style names.
  /// * [layout] — wire-format layout, defaults to [bitArrayLayoutBytePerBool]
  ///   (one BOOL per byte, `bitOffset==0` always). Pass
  ///   [bitArrayLayoutPackedBits16] for packed `%M`-style addressing
  ///   (16 BOOLs per 2-byte WORD).
  ///
  /// Non-BOOL arrays (element type != 0x0001) return an empty list so
  /// callers can apply this builder unconditionally over every short
  /// record in the catalog.
  static List<BitAliasEntry> buildFromArrayDefinition({
    required UmasArrayTypeDefinition definition,
    required String parentVariableName,
    required int parentBlock,
    required int parentByteOffset,
    required String aliasPrefix,
    _BitArrayLayout layout = _BitArrayLayout.bytePerBool,
  }) {
    if (definition.elementTypeId != 0x0001) return const [];
    if (definition.dimensions.length != 1) return const [];
    final dim = definition.dimensions.first;
    final count = dim.upperBound - dim.startIndex + 1;
    if (count <= 0) return const [];
    final out = <BitAliasEntry>[];
    for (int i = 0; i < count; i++) {
      final arrayIndex = dim.startIndex + i;
      final int byteOff;
      final int bit;
      switch (layout) {
        case _BitArrayLayout.packedBits16:
          byteOff = parentByteOffset + (i ~/ 16) * 2;
          bit = i % 16;
          break;
        case _BitArrayLayout.bytePerBool:
          byteOff = parentByteOffset + i;
          bit = 0;
          break;
      }
      out.add(BitAliasEntry(
        aliasName: '$aliasPrefix$arrayIndex',
        parentBlock: parentBlock,
        parentByteOffset: byteOff,
        bitOffset: bit,
        parentVariableName: parentVariableName,
      ));
    }
    return out;
  }

  /// Decode a single bit from a freshly-read parent WORD. Convenience
  /// wrapper that the decoder uses internally; exposed here so the data
  /// layer is self-contained for tests / tooling that don't want to
  /// import the decoder file.
  static bool? decodeBit({
    required int parentWordValue,
    required BitAliasEntry entry,
  }) {
    if (entry.bitOffset < 0) return null;
    if (entry.bitOffset >= 64) return null;
    return ((parentWordValue >> entry.bitOffset) & 1) == 1;
  }

  /// Decode a single bit from a raw 2-byte WORD buffer (little-endian,
  /// matching the wire convention used by [UmasClient.readVariable]).
  static bool? decodeBitFromBytes({
    required Uint8List wordBytes,
    required BitAliasEntry entry,
  }) {
    if (wordBytes.length < 2) return null;
    final word = wordBytes[0] | (wordBytes[1] << 8);
    return decodeBit(parentWordValue: word, entry: entry);
  }
}

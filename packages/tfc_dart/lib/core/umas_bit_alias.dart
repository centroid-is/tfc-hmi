/// Synchronous bit-extraction decoder for the UMAS located-bit / bit-alias
/// namespace.
///
/// The decoder is intentionally a single bit-shift — the heavy lifting
/// (enumeration, parent-word resolution, caching) happens in
/// [UmasBitAliasMap] (see `umas_bit_alias_map.dart`) and in
/// `UmasClient.bitAliases` / `UmasClient.readBitAlias`.
///
/// The interface contract is `bool? decodeBit(int parentWordValue,
/// String aliasName)` — a plain `int` for the parent word avoids the
/// dynamic-dispatch cost on the hot path and makes the type contract
/// obvious at the call site.
///
/// Invariants:
///   - `decodeBit` MUST return `null` for unknown aliases. It MUST NOT
///     throw — callers treat null as "show a `?` placeholder".
///   - `decodeBit` MUST return `null` when the source word lacks the
///     information needed to evaluate the alias. Callers cannot tell the
///     difference between "unknown alias" and "alias known but data
///     unavailable" — both yield the same UI fallback, which is by design
///     to keep the seam simple.
///   - The host-endianness contract: callers pass the *already-decoded*
///     16-bit UMAS WORD value (e.g. via `readVariableByName`); implementations
///     treat the int as a raw bit-vector with bit 0 = LSB.
library;

import 'package:tfc_dart/core/umas_bit_alias_map.dart';

/// Abstract interface for downstream consumers (Conveyor agent / UI)
/// that want to inject a different implementation under test.
abstract class BitAliasDecoder {
  /// Const-friendly constructor for subclasses (e.g. [StubBitAliasDecoder]).
  const BitAliasDecoder();

  /// Extract the boolean value of [aliasName] from a parent WORD value.
  ///
  /// Returns `null` when [aliasName] is not in the alias registry, so
  /// callers can fall back without catching an exception.
  bool? decodeBit(int parentWordValue, String aliasName);
}

/// Default implementation: looks the alias up in [aliases], then
/// extracts the bit from [parentWordValue].
class UmasBitAliasDecoder implements BitAliasDecoder {
  final UmasBitAliasMap aliases;

  const UmasBitAliasDecoder(this.aliases);

  @override
  bool? decodeBit(int parentWordValue, String aliasName) {
    final entry = aliases.lookup(aliasName);
    if (entry == null) return null;
    return UmasBitAliasMap.decodeBit(
      parentWordValue: parentWordValue,
      entry: entry,
    );
  }
}

/// Default no-op decoder shipped before the real bit-alias enumeration
/// is wired into the running app. Always returns `null` so all aliases
/// render as "?" in the UI.
///
/// Use this as the default value of any `BitAliasDecoder?` parameter
/// (and as the Provider default in `bitAliasDecoderProvider`) to keep
/// call-sites declarative — the real decoder is swapped in via
/// dependency injection without touching consumers.
class StubBitAliasDecoder extends BitAliasDecoder {
  const StubBitAliasDecoder();

  @override
  bool? decodeBit(int parentWordValue, String aliasName) => null;
}

/// Simple decoder backed by a name -> bit-index map. Useful for tests
/// and as a building block for the real decoder, which assembles its
/// alias map from PLC-project metadata.
///
/// Bits are 0-indexed (bit 0 = LSB). Indices outside `[0, 15]` for a
/// 16-bit WORD are allowed (callers may pass a wider int) but the
/// implementation treats the int as a host-order bit-vector and does
/// not enforce a width.
class MapBitAliasDecoder extends BitAliasDecoder {
  final Map<String, int> _bitsByAlias;

  /// Creates a decoder that knows aliases listed in [bitsByAlias].
  /// Aliases not present in the map decode to `null`.
  const MapBitAliasDecoder(this._bitsByAlias);

  @override
  bool? decodeBit(int parentWordValue, String aliasName) {
    final bit = _bitsByAlias[aliasName];
    if (bit == null) return null;
    if (bit < 0) return null;
    return ((parentWordValue >> bit) & 1) == 1;
  }
}

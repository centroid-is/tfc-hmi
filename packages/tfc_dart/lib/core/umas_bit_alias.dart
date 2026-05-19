/// Synchronous bit-extraction decoder for the UMAS located-bit / bit-alias
/// namespace.
///
/// The decoder is intentionally a single bit-shift — the heavy lifting
/// (enumeration, parent-word resolution, caching) happens in
/// [UmasBitAliasMap] (see `umas_bit_alias_map.dart`) and in
/// `UmasClient.bitAliases` / `UmasClient.readBitAlias`.
///
/// Coordination with the parallel Conveyor agent (`conveyor-impl`,
/// worktree `worktree-agent-a632363e`): the interface this file defines
/// is the supersedes the earlier `bool? decodeBit(Object? fbValue, String
/// aliasName)` shape. The new contract is `bool? decodeBit(int
/// parentWordValue, String aliasName)` — a plain `int` for the parent
/// word avoids the dynamic-dispatch cost on the hot path and makes the
/// type contract obvious at the call site.
library;

import 'package:tfc_dart/core/umas_bit_alias_map.dart';

/// Abstract interface for downstream consumers (Conveyor agent / UI)
/// that want to inject a different implementation under test.
abstract class BitAliasDecoder {
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

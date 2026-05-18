// @phase4-stub — Phase 2/3 will replace this with the real model.
//
// This file is the Phase 4 (browser-tree UI affordances) stand-in for the
// `UmasFbMember` model that Phase 2 (FB visibility) and Phase 3 (VAR_INPUT /
// VAR_OUTPUT distinction) will eventually produce in `umas_types.dart` or a
// sibling file. It lets Phase 4 ship the rendering against a stable shape
// before Phases 2/3 have merged.
//
// **Merge unification recipe** (for the orchestrator when Phase 2/3 land):
//   1. Phase 2 (or 3) defines the canonical `UmasFbMember` /
//      `UmasFbMemberDirection` carrying the protocol fields (offset,
//      blockNo, dataTypeId, etc.) on top of the minimum fields below.
//   2. Delete this file.
//   3. Update the single import in
//      `lib/widgets/browse_panel.dart` to the real type's location.
//   4. The four direction enum values MUST be named exactly
//      `input | output | publicVar | inOut | unknown`. If Phase 3 picks
//      different names (e.g. `inout`, `pub`), rename in
//      `BrowseNodeTile._buildIcon` and the widget test.
//   5. The widget reads only `name`, `typeName`, `direction`, `readable`,
//      `unreadableReason`, and the three `kMeta*` metadata-key constants.
//      The real model must keep these fields/keys (or define equivalents).
//
// See `.planning/phases/04-browser-tree-ui-affordances/04-CONTEXT.md` for
// the full coexistence contract.

/// Direction classification for a function-block instance member.
///
/// Phase 4 paints icon + colour + suffix based on this value. Phase 3 (in a
/// parallel worktree) is responsible for assigning the value when the FB
/// member tree is assembled.
enum UmasFbMemberDirection {
  /// `VAR_INPUT` — readable inbound parameter of the FB.
  input,

  /// `VAR_OUTPUT` — readable outbound parameter of the FB.
  output,

  /// Public `VAR` — non-IN_OUT FB local; rendered with the existing
  /// variable affordance (no direction suffix).
  publicVar,

  /// `VAR_IN_OUT` — bidirectional pointer. Plc4j drops these with
  /// reason; pointer resolution is a Phase 5 stretch goal.
  inOut,

  /// Direction could not be determined. Falls back to the existing
  /// variable affordance with no direction suffix.
  unknown,
}

/// A single member of an FB instance as seen by the browser tree.
///
/// Phase 4 uses this only as a fixture carrier for tests and as the
/// data carrier for the `BrowseNode.metadata` round-trip via
/// [toBrowseNodeMetadata]. Phase 2/3 will own the real type and may add
/// additional protocol fields (offset, blockNo, dataTypeId, etc.) — they
/// must keep the five Phase 4 fields available.
class UmasFbMember {
  /// Metadata key under [BrowseNode.metadata] carrying the direction
  /// enum name (one of `input | output | publicVar | inOut | unknown`).
  static const String kMetaDirection = 'fbDirection';

  /// Metadata key carrying `'true'` or `'false'`. Absent → treated as
  /// readable (`true`).
  static const String kMetaReadable = 'fbReadable';

  /// Metadata key carrying a free-form reason string for why a member
  /// is inaccessible (e.g. `'VAR_IN_OUT (PLC returns 0x94)'`).
  static const String kMetaUnreadableReason = 'fbUnreadableReason';

  /// Member identifier, e.g. `'speed'`.
  final String name;

  /// Data-type name, e.g. `'REAL'`. Surfaced in the tile suffix /
  /// detail strip; never null because Phase 2 always populates it.
  final String typeName;

  /// `VAR_INPUT` / `VAR_OUTPUT` / public / `VAR_IN_OUT` classification.
  final UmasFbMemberDirection direction;

  /// `false` for inaccessible members (e.g. unresolved `VAR_IN_OUT`
  /// pointers or types missing from DD03). When `false`, the UI renders
  /// the "not readable" indicator with [unreadableReason] as tooltip.
  final bool readable;

  /// Human-readable reason for why this member is inaccessible.
  /// Required when [readable] is `false`; ignored otherwise.
  final String? unreadableReason;

  const UmasFbMember({
    required this.name,
    required this.typeName,
    required this.direction,
    this.readable = true,
    this.unreadableReason,
  });

  /// Encodes this member's affordance state into the
  /// [BrowseNode.metadata] string map used by the browser-tree UI.
  ///
  /// Phase 2/3 should call this from `UmasBrowseDataSource._toBrowseNode`
  /// when constructing the `BrowseNode` for an FB member, merging the
  /// returned map into the existing metadata.
  Map<String, String> toBrowseNodeMetadata() {
    return <String, String>{
      kMetaDirection: directionToWire(direction),
      kMetaReadable: readable ? 'true' : 'false',
      if (unreadableReason != null) kMetaUnreadableReason: unreadableReason!,
    };
  }

  /// Decodes the direction key from a [BrowseNode.metadata] map.
  /// Returns [UmasFbMemberDirection.unknown] for missing or
  /// unrecognised values — never throws.
  static UmasFbMemberDirection directionFromMetadata(
      Map<String, String> meta) {
    final raw = meta[kMetaDirection];
    if (raw == null) return UmasFbMemberDirection.unknown;
    return directionFromWire(raw);
  }

  /// Decodes the readable key from a [BrowseNode.metadata] map.
  /// Absent key → `true` (readable). Any string other than `'false'`
  /// → `true`.
  static bool readableFromMetadata(Map<String, String> meta) {
    return meta[kMetaReadable] != 'false';
  }

  /// Decodes the unreadable-reason key from a [BrowseNode.metadata] map.
  /// Returns null for missing or empty values.
  static String? unreadableReasonFromMetadata(Map<String, String> meta) {
    final raw = meta[kMetaUnreadableReason];
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  /// Wire-name of a direction enum value. Stable across phases.
  static String directionToWire(UmasFbMemberDirection d) {
    switch (d) {
      case UmasFbMemberDirection.input:
        return 'input';
      case UmasFbMemberDirection.output:
        return 'output';
      case UmasFbMemberDirection.publicVar:
        return 'publicVar';
      case UmasFbMemberDirection.inOut:
        return 'inOut';
      case UmasFbMemberDirection.unknown:
        return 'unknown';
    }
  }

  /// Inverse of [directionToWire]. Unknown / null / empty → `unknown`.
  static UmasFbMemberDirection directionFromWire(String wire) {
    switch (wire) {
      case 'input':
        return UmasFbMemberDirection.input;
      case 'output':
        return UmasFbMemberDirection.output;
      case 'publicVar':
        return UmasFbMemberDirection.publicVar;
      case 'inOut':
        return UmasFbMemberDirection.inOut;
      default:
        return UmasFbMemberDirection.unknown;
    }
  }
}

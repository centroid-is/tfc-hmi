// Browser-tree FB-member metadata bridge.
//
// Phase 3 (VAR_INPUT / VAR_OUTPUT distinction) owns the canonical
// [UmasFbMemberDirection] enum in `umas_fb_direction.dart`. This file
// provides only the metadata-key constants + decoder statics that
// [BrowseNode.metadata] uses to round-trip FB-member affordance state
// for the browser-tree UI (Phase 4).
//
// Post-merge (v1.1) state: the duplicate enum that lived here in Phase 4's
// worktree has been removed in favour of Phase 3's canonical enum. The
// widget call sites in `lib/widgets/browse_panel.dart` remain valid because
// they only depend on `UmasFbMember.{kMetaDirection|kMetaReadable|
// kMetaUnreadableReason}` constants and the three `*FromMetadata` static
// helpers.

import 'package:tfc_dart/core/umas_fb_direction.dart';

export 'package:tfc_dart/core/umas_fb_direction.dart' show UmasFbMemberDirection;

/// Metadata bridge between [UmasVariableTreeNode] (model layer) and
/// [BrowseNode.metadata] (UI layer) for function-block instance members.
///
/// The widget layer (`browse_panel.dart`) reads three keys
/// (`fbDirection`, `fbReadable`, `fbUnreadableReason`) off
/// [BrowseNode.metadata]. The protocol layer (`umas_browse.dart`
/// `_toBrowseNode`) writes them. Both sides go through this class so
/// the key strings and direction-wire encoding stay in one place.
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

  const UmasFbMember._();

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

  /// Encodes member affordance state into a [BrowseNode.metadata] map.
  /// Used by `UmasBrowseDataSource._toBrowseNode` when constructing the
  /// `BrowseNode` for an FB-member node.
  static Map<String, String> toMetadata({
    required UmasFbMemberDirection direction,
    bool readable = true,
    String? unreadableReason,
  }) {
    return <String, String>{
      kMetaDirection: directionToWire(direction),
      kMetaReadable: readable ? 'true' : 'false',
      if (unreadableReason != null && unreadableReason.isNotEmpty)
        kMetaUnreadableReason: unreadableReason,
    };
  }
}

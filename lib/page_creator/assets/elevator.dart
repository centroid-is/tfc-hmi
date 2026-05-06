import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'common.dart';
import 'registry.dart';

part 'elevator.g.dart';

// ---------------------------------------------------------------------------
// Polymorphic child JSON helpers
// ---------------------------------------------------------------------------

/// Deserialise a polymorphic child asset for an [ElevatorChildEntry].
///
/// Walks the existing [AssetRegistry.parse] path so any registered asset
/// type Just Works without elevator-side switching (Anti-Pattern 1 from
/// research/ARCHITECTURE.md).
///
/// The `{'wrapped_child': json}` envelope makes [AssetRegistry.parse]'s
/// JSON-tree crawl find exactly one asset (the child) without bare-Map
/// ambiguity — locked by the polymorphic round-trip tests in
/// `elevator_config_test.dart` ('Polymorphic child round-trip' group).
BaseAsset _childFromJson(Map<String, dynamic> json) {
  final assets = AssetRegistry.parse(<String, dynamic>{'wrapped_child': json});
  if (assets.isEmpty) {
    throw FormatException(
      'ElevatorChildEntry.child JSON did not match any registered '
      'asset_name in AssetRegistry: ${json[constAssetName]}',
    );
  }
  return assets.first as BaseAsset;
}

Map<String, dynamic> _childToJson(BaseAsset child) => child.toJson();

// ---------------------------------------------------------------------------
// Children list legacy / forward-compat shim
// ---------------------------------------------------------------------------

/// Legacy / forward-compat shim for the children list. Locked in
/// Phase 2 from day one (ROADMAP key decision) to avoid the
/// wrapper-promotion migration trap (PITFALLS Pitfall 5).
///
/// Today: returns [] for missing / null and parses each entry as a
/// new-format ElevatorChildEntry. Future schema evolutions add
/// branches here without touching the public type — exact same
/// pattern as conveyor.dart:_gatesFromJson.
List<ElevatorChildEntry> _childrenFromJson(List<dynamic>? json) {
  if (json == null) return <ElevatorChildEntry>[];
  return json
      .map((item) => ElevatorChildEntry.fromJson(item as Map<String, dynamic>))
      .toList();
}

List<Map<String, dynamic>> _childrenToJson(List<ElevatorChildEntry> list) =>
    list.map((e) => e.toJson()).toList();

// ---------------------------------------------------------------------------
// ElevatorChildEntry — locked wrapper schema
// ---------------------------------------------------------------------------

/// Wrapper for a child asset attached to an Elevator's platform.
///
/// Schema locked in Phase 2 (ROADMAP key decision) from day one — even
/// though the children list is empty in this phase, future Phase 3
/// extensions add to the children list without changing the wrapper
/// shape. The `id` is used as a `ValueKey<String>` in Phase 3 to keep
/// child widget identity stable across position changes (Pitfall 1).
@JsonSerializable(explicitToJson: true)
class ElevatorChildEntry {
  /// Stable identity for ValueKey use (Pitfall 1 — Phase 3).
  /// Defaults to microsecond-resolution timestamp; switch to
  /// `package:uuid` only if a real collision risk surfaces.
  String id;

  /// Lateral position on the platform (0.0 = far left, 1.0 = far
  /// right). Default 0.5 = centre.
  double offsetX;

  /// Polymorphic child asset. Round-trips via [AssetRegistry.parse].
  @JsonKey(fromJson: _childFromJson, toJson: _childToJson)
  BaseAsset child;

  ElevatorChildEntry({
    String? id,
    this.offsetX = 0.5,
    required this.child,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  factory ElevatorChildEntry.fromJson(Map<String, dynamic> json) =>
      _$ElevatorChildEntryFromJson(json);

  Map<String, dynamic> toJson() => _$ElevatorChildEntryToJson(this);
}

// ---------------------------------------------------------------------------
// ElevatorConfig — pure data model
// ---------------------------------------------------------------------------

/// Configuration for the Elevator asset.
///
/// Pure data model — JSON-serialisable, no widget/painter wiring.
/// The widget, painter, registry registration, and config dialog
/// are introduced in Plans 02-03..02-05 of this phase.
@JsonSerializable(explicitToJson: true)
class ElevatorConfig extends BaseAsset {
  @override
  String get displayName => 'Elevator';

  @override
  String get category => 'Visualization';

  /// PLC state key emitting the raw 0..100% position float.
  String positionKey;

  /// Tween animation duration in ms. Default 250 (CONTEXT specifics).
  int tweenDurationMs;

  /// Child assets riding the platform. Phase 2 ships with [] —
  /// Phase 3 fills the list via the config-dialog dropdown.
  @JsonKey(fromJson: _childrenFromJson, toJson: _childrenToJson)
  List<ElevatorChildEntry> children;

  ElevatorConfig({
    this.positionKey = '',
    this.tweenDurationMs = 250,
    List<ElevatorChildEntry>? children,
  }) : children =
            children != null ? List<ElevatorChildEntry>.of(children) : [];

  /// Preview factory for the asset palette.
  ElevatorConfig.preview() : this();

  factory ElevatorConfig.fromJson(Map<String, dynamic> json) =>
      _$ElevatorConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ElevatorConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError('Elevator widget — Plan 02-04');
  }

  @override
  Widget configure(BuildContext context) {
    throw UnimplementedError('Elevator config dialog — Plan 02-05');
  }
}

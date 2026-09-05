import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:tfc/converter/icon.dart';
import 'package:tfc_access/tfc_access.dart' show AccessGroup;

part 'menu_item.g.dart';

@JsonSerializable()
class MenuItem {
  final String label;
  final String? path;
  @IconDataConverter()
  final IconData icon;
  final List<MenuItem> children;

  /// Explicitly marks this item as a navigation group rather than a page.
  ///
  /// Sections used to be inferred from [children] being non-empty, which made
  /// a freshly created (still empty) section indistinguishable from a page —
  /// so nothing could be added under it. The flag is persisted; the getter
  /// [isNavigationSection] keeps the old inference alive for data written
  /// before the flag existed.
  @JsonKey(name: 'is_section', defaultValue: false)
  final bool isSection;

  /// The permission group this item is published for, or null for everyone.
  ///
  /// **A group, never a role.** Groups are the primitive the rest of the system
  /// already speaks -- `kRaisedRoutes` declares them, `AccessGate` enforces
  /// them, and an audit row records `groupRequired`. Roles are customer data
  /// that can be renamed or deleted, and a page pointing at a deleted role is
  /// the same failure the anonymous-is-Operator decision exists to avoid. A
  /// page published for `configure` survives somebody renaming "Engineering";
  /// one published for "Engineering" does not.
  ///
  /// **Null means undeclared, which is not the same as `operate`.** A page that
  /// says nothing must not overwrite the group a built-in route already has
  /// from `installRaisedRoutes`, so the loader writes nothing at all rather
  /// than writing a default. See `declareMenuRouteGroups`.
  ///
  /// Set on a section, it covers every page beneath it that does not set its
  /// own -- which is also how a whole section disappears from the menu, since
  /// a section whose children are all hidden is dropped already.
  @JsonKey(name: 'required_group', includeIfNull: false)
  final AccessGroup? requiredGroup;

  const MenuItem({
    required this.label,
    required this.icon,
    this.children = const [],
    this.path,
    this.isSection = false,
    this.requiredGroup,
  });

  /// True when this item groups other pages: either flagged as a section, or
  /// (legacy data) inferred from having children.
  bool get isNavigationSection => isSection || children.isNotEmpty;

  /// [clearRequiredGroup] because `requiredGroup: null` cannot mean "unset it"
  /// and "leave it alone" at once, and unsetting is what the editor does when
  /// somebody publishes a page back to everyone.
  MenuItem copyWith({
    String? label,
    String? path,
    IconData? icon,
    List<MenuItem>? children,
    bool? isSection,
    AccessGroup? requiredGroup,
    bool clearRequiredGroup = false,
  }) {
    return MenuItem(
      label: label ?? this.label,
      path: path ?? this.path,
      icon: icon ?? this.icon,
      children: children ?? this.children,
      isSection: isSection ?? this.isSection,
      requiredGroup:
          clearRequiredGroup ? null : (requiredGroup ?? this.requiredGroup),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is MenuItem &&
        label == other.label &&
        path == other.path &&
        icon == other.icon;
  }

  factory MenuItem.fromJson(Map<String, dynamic> json) =>
      _$MenuItemFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemToJson(this);
}

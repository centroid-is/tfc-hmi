import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:tfc/converter/icon.dart';

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

  const MenuItem({
    required this.label,
    required this.icon,
    this.children = const [],
    this.path,
    this.isSection = false,
  });

  /// True when this item groups other pages: either flagged as a section, or
  /// (legacy data) inferred from having children.
  bool get isNavigationSection => isSection || children.isNotEmpty;

  MenuItem copyWith({
    String? label,
    String? path,
    IconData? icon,
    List<MenuItem>? children,
    bool? isSection,
  }) {
    return MenuItem(
      label: label ?? this.label,
      path: path ?? this.path,
      icon: icon ?? this.icon,
      children: children ?? this.children,
      isSection: isSection ?? this.isSection,
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

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

  const MenuItem({
    required this.label,
    required this.icon,
    this.children = const [],
    this.path,
  });

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

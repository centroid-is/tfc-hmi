import 'package:flutter/material.dart';

class MenuItem {
  final String label;
  final String? path;
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
}

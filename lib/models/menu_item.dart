// lib/models/menu_item.dart
import 'package:flutter/material.dart';

class MenuItem {
  final String label;
  final String path;
  final IconData icon;
  final String hoverText;
  final List<MenuItem>? children;

  const MenuItem({
    required this.label,
    required this.path,
    required this.icon,
    required this.hoverText,
    this.children,
  });
}

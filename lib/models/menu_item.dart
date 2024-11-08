import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';

class MenuItem {
  final String label;
  final Uri path;
  final IconData icon;
  final List<MenuItem>? children;

  const MenuItem({
    required this.label,
    required this.path,
    required this.icon,
    this.children,
  });
}

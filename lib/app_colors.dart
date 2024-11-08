import 'package:flutter/material.dart';

class AppColors {
  static bool _useDarkScheme = true;

  static void setDarkScheme(bool isDark) {
    _useDarkScheme = isDark;
  }

  // Primary and Secondary Colors
  static Color get primaryColor =>
      _useDarkScheme ? const Color.fromARGB(255, 9, 56, 97) : Colors.blueAccent;
  static Color get secondaryColor =>
      _useDarkScheme ? Colors.grey[700]! : Colors.grey;

  // Background Colors
  static Color get backgroundColor =>
      _useDarkScheme ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
  static Color get scaffoldBackgroundColor =>
      _useDarkScheme ? Colors.grey[900]! : Colors.white;

  // Text Colors
  static Color get primaryTextColor =>
      _useDarkScheme ? Colors.white : Colors.black;
  static Color get secondaryTextColor =>
      _useDarkScheme ? Colors.grey[300]! : Colors.grey;
  static Color get errorTextColor => Colors.red;

  // Navigation Colors
  static Color get selectedItemColor =>
      _useDarkScheme ? Colors.greenAccent : Colors.green;
  static Color get unselectedItemColor =>
      _useDarkScheme ? Colors.grey[600]! : Colors.grey;

  // Icon Colors
  static Color get primaryIconColor =>
      _useDarkScheme ? Colors.blue : Colors.blueAccent;
  static Color get secondaryIconColor =>
      _useDarkScheme ? Colors.grey[400]! : Colors.grey;

  // Border Colors
  static Color get borderColor =>
      _useDarkScheme ? Colors.grey[800]! : Colors.grey;

  // Hover and Tooltip Colors
  static Color get hoverColor =>
      _useDarkScheme ? Colors.blue[700]! : Colors.lightBlue;
  static Color get tooltipBackgroundColor =>
      _useDarkScheme ? Colors.grey[800]! : Colors.black87;
  static Color get tooltipTextColor =>
      _useDarkScheme ? Colors.white : Colors.white;

  // Elevated Button Colors
  static Color get elevatedButtonColor =>
      _useDarkScheme ? Colors.blue[700]! : Colors.blueAccent;
  static Color get elevatedButtonTextColor => Colors.white;

  // Add more colors as needed
}

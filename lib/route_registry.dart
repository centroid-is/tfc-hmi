// lib/route_registry.dart
import 'package:flutter/material.dart';
import 'models/menu_item.dart';

class RouteRegistry {
  static final RouteRegistry _instance = RouteRegistry._internal();
  final Map<String, WidgetBuilder> _routes = {};
  final List<MenuItem> dropdownMenuItems = [];
  final List<MenuItem> standardMenuItems = [];

  RouteRegistry._internal();

  factory RouteRegistry() {
    return _instance;
  }

  void registerRoute(String path, WidgetBuilder builder) {
    _routes[path] = builder;
  }

  WidgetBuilder? getBuilder(String path) {
    return _routes[path];
  }

  Map<String, WidgetBuilder> get routes => _routes;

  void addDropdownMenuItem(MenuItem menuItem) {
    dropdownMenuItems.add(menuItem);
  }

  void addStandardMenuItem(MenuItem menuItem) {
    standardMenuItems.add(menuItem);
  }
}
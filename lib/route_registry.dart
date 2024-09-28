import 'package:flutter/material.dart';
import 'models/menu_item.dart';

class RouteRegistry {
  static final RouteRegistry _instance = RouteRegistry._internal();
  final Map<String, WidgetBuilder> _routes = {};
  final List<MenuItem> menuItems = [];

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

  void addMenuItem(MenuItem menuItem) {
    menuItems.add(menuItem);
  }

  // Method to retrieve all registered paths
  List<Uri> getAllPaths() {
    List<Uri> paths = [];
    for (var dropdown in menuItems) {
      paths.add(dropdown.path);
      if (dropdown.children != null) {
        for (var child in dropdown.children!) {
          paths.add(child.path);
        }
      }
    }
    return paths;
  }
}

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

  MenuItem get root {
    return MenuItem(
        label: 'ROOT, SHOULD NEVER BE SEEN',
        icon: Icons.abc,
        children: menuItems);
  }

  void addMenuItem(MenuItem menuItem) {
    menuItems.add(menuItem);
  }

  int? getNodeIndex(MenuItem nodeItem) {
    final index = menuItems.indexOf(nodeItem);
    if (index != -1) return index;
    return null;
  }

  // Method to retrieve all registered paths
  List<String> getAllPaths() {
    List<String> paths = [];
    for (var dropdown in menuItems) {
      if (dropdown.path != null) {
        paths.add(dropdown.path!);
      }
      if (dropdown.children.isNotEmpty) {
        for (var child in dropdown.children) {
          if (child.path != null) {
            paths.add(child.path!);
          }
        }
      }
    }
    return paths;
  }
}

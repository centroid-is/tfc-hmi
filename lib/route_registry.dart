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
    _mergeMenuItemRecursive(menuItems, menuItem);
  }

  void _mergeMenuItemRecursive(List<MenuItem> targetList, MenuItem newItem) {
    // Check if item with same path already exists
    for (var i = 0; i < targetList.length; i++) {
      final existingItem = targetList[i];
      if (existingItem.path == newItem.path) {
        // If it exists, merge its children recursively. Merge into a copy:
        // MenuItems are routinely const-constructed, and adding to a const
        // children list throws.
        if (newItem.children.isNotEmpty) {
          final mergedChildren = List<MenuItem>.of(existingItem.children);
          for (var child in newItem.children) {
            _mergeMenuItemRecursive(mergedChildren, child);
          }
          targetList[i] = existingItem.copyWith(children: mergedChildren);
        }
        return;
      }
    }

    // If not found, add it
    targetList.add(newItem);
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

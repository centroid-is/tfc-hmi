/// The registry's menu merge. The historical trap: merging children into an
/// already-registered item used to mutate that item's `children` list in
/// place, which throws for const-constructed MenuItems — and const is how
/// most built-in items are written.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/route_registry.dart';

void main() {
  late RouteRegistry registry;

  setUp(() {
    // The registry is a singleton; start each test from a clean menu.
    registry = RouteRegistry();
    registry.menuItems.clear();
  });

  test('items are listed in the order they were added', () {
    registry.addMenuItem(const MenuItem(
        label: 'Alarm View', path: '/alarm-view', icon: Icons.alarm));
    registry.addMenuItem(
        const MenuItem(label: 'Home', path: '/', icon: Icons.home));

    expect(registry.menuItems.map((m) => m.path), ['/alarm-view', '/']);
  });

  test('merging children into a const-constructed item does not throw', () {
    // The first registration is const, so its children list is unmodifiable.
    registry.addMenuItem(
        const MenuItem(label: 'Home', path: '/', icon: Icons.home));

    registry.addMenuItem(const MenuItem(
      label: 'Home',
      path: '/',
      icon: Icons.home,
      children: [
        MenuItem(label: 'Sub', path: '/sub', icon: Icons.pageview),
      ],
    ));

    expect(registry.menuItems, hasLength(1));
    expect(registry.menuItems.single.children.map((m) => m.path), ['/sub']);
  });

  test('merging is recursive and keeps existing children', () {
    registry.addMenuItem(const MenuItem(
      label: 'Advanced',
      path: '/advanced',
      icon: Icons.settings,
      children: [MenuItem(label: 'A', path: '/advanced/a', icon: Icons.abc)],
    ));
    registry.addMenuItem(const MenuItem(
      label: 'Advanced',
      path: '/advanced',
      icon: Icons.settings,
      children: [MenuItem(label: 'B', path: '/advanced/b', icon: Icons.abc)],
    ));

    expect(registry.menuItems.single.children.map((m) => m.path),
        ['/advanced/a', '/advanced/b']);
  });
}

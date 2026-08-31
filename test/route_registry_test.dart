/// The registry's menu merge. The historical trap: merging children into an
/// already-registered item used to mutate that item's `children` list in
/// place, which throws for const-constructed MenuItems — and const is how
/// most built-in items are written.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc_access/tfc_access.dart';

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

  group('route groups', () {
    setUp(() {
      // The declarations live on the same process-wide singleton as
      // `menuItems`, so they need the same escape hatch and the same
      // per-test reset.
      registry.clearRouteGroups();
    });

    tearDown(() {
      registry.clearRouteGroups();
    });

    test('a route registered without a group answers operate', () {
      // Two positional arguments and no named one: this is the call shape
      // every existing caller uses, and it must keep compiling untouched.
      registry.registerRoute('/alarm-view', (_) => const SizedBox());

      expect(registry.groupForRoute('/alarm-view'), AccessGroup.operate);
    });

    test('a route registered with a group answers that group', () {
      registry.registerRoute('/advanced/page-editor', (_) => const SizedBox(),
          group: AccessGroup.configure);

      expect(registry.groupForRoute('/advanced/page-editor'),
          AccessGroup.configure);
    });

    test('declareRouteGroup works for a path with no builder here', () {
      // The app's live route table is Beamer's, not this registry, so the
      // nine raised routes are declared without ever registering a builder.
      registry.declareRouteGroup(
          '/advanced/server-config', AccessGroup.administer);

      expect(registry.getBuilder('/advanced/server-config'), isNull);
      expect(registry.groupForRoute('/advanced/server-config'),
          AccessGroup.administer);
    });

    test('an undeclared path answers operate rather than throwing', () {
      expect(
          registry.groupForRoute('/nobody/mentioned/this'), AccessGroup.operate);
    });

    test('a null path answers operate', () {
      expect(registry.groupForRoute(null), AccessGroup.operate);
    });

    test('re-declaring a path replaces its group rather than accumulating', () {
      registry.declareRouteGroup('/advanced/x', AccessGroup.configure);
      registry.declareRouteGroup('/advanced/x', AccessGroup.administer);

      expect(registry.groupForRoute('/advanced/x'), AccessGroup.administer);
    });

    test('clearRouteGroups empties the declarations', () {
      registry.declareRouteGroup('/advanced/x', AccessGroup.administer);

      registry.clearRouteGroups();

      expect(registry.groupForRoute('/advanced/x'), AccessGroup.operate);
    });

    test('registering a builder with no group keeps a declared group', () {
      // Order matters: the nine are declared at startup, and a page could be
      // registered for the same path afterwards. A builder that says nothing
      // about groups must not silently unlock the route.
      registry.declareRouteGroup(
          '/advanced/server-config', AccessGroup.administer);

      registry.registerRoute(
          '/advanced/server-config', (_) => const SizedBox());

      expect(registry.groupForRoute('/advanced/server-config'),
          AccessGroup.administer);
    });
  });
}

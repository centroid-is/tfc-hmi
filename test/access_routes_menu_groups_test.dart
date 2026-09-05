import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/access_routes.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc_access/tfc_access.dart';

MenuItem _page(String label, String path, {AccessGroup? group}) => MenuItem(
      label: label,
      icon: Icons.article,
      path: path,
      requiredGroup: group,
    );

MenuItem _section(String label, List<MenuItem> children,
        {AccessGroup? group}) =>
    MenuItem(
      label: label,
      icon: Icons.folder,
      isSection: true,
      children: children,
      requiredGroup: group,
    );

void main() {
  late RouteRegistry registry;

  setUp(() {
    registry = RouteRegistry();
    registry.menuItems.clear();
    registry.clearRouteGroups();
  });

  tearDown(() {
    registry.menuItems.clear();
    registry.clearRouteGroups();
  });

  group('declareMenuRouteGroups', () {
    test('a page published for a group answers that group', () {
      declareMenuRouteGroups([
        _page('Recipes', '/recipes', group: AccessGroup.setpoints),
      ], registry);

      expect(accessGroupForRoute('/recipes'), AccessGroup.setpoints);
    });

    test('a page publishing nothing stays open to everyone', () {
      declareMenuRouteGroups([_page('Home', '/home')], registry);

      expect(accessGroupForRoute('/home'), AccessGroup.operate,
          reason: 'undeclared answers operate, which anonymous already holds');
    });

    test('a section covers the pages beneath it', () {
      declareMenuRouteGroups([
        _section('Diagnostics', [
          _page('IOs', '/diagnostics/ios'),
          _page('Drives', '/diagnostics/drives'),
        ], group: AccessGroup.configure),
      ], registry);

      expect(accessGroupForRoute('/diagnostics/ios'), AccessGroup.configure);
      expect(accessGroupForRoute('/diagnostics/drives'), AccessGroup.configure);
    });

    test('a page overrides the section it sits in', () {
      declareMenuRouteGroups([
        _section('Diagnostics', [
          _page('IOs', '/diagnostics/ios'),
          _page('Forcing', '/diagnostics/forcing', group: AccessGroup.force),
        ], group: AccessGroup.configure),
      ], registry);

      expect(accessGroupForRoute('/diagnostics/forcing'), AccessGroup.force,
          reason: 'the nearer declaration wins');
      expect(accessGroupForRoute('/diagnostics/ios'), AccessGroup.configure,
          reason: 'its sibling still inherits');
    });

    test('inheritance passes through an undeclared section', () {
      declareMenuRouteGroups([
        _section('Plant', [
          _section('Line 1', [_page('Cutter', '/plant/line1/cutter')]),
        ], group: AccessGroup.device),
      ], registry);

      expect(accessGroupForRoute('/plant/line1/cutter'), AccessGroup.device,
          reason: 'the nearest ANCESTOR that declares, not the nearest parent');
    });

    test('a nested section overrides its parent for its own subtree', () {
      declareMenuRouteGroups([
        _section('Plant', [
          _section('Safety', [_page('Gates', '/plant/safety/gates')],
              group: AccessGroup.administer),
          _page('Overview', '/plant/overview'),
        ], group: AccessGroup.device),
      ], registry);

      expect(accessGroupForRoute('/plant/safety/gates'),
          AccessGroup.administer);
      expect(accessGroupForRoute('/plant/overview'), AccessGroup.device);
    });

    // The one that is easy to get wrong, and the reason `null` means "write
    // nothing" rather than "write operate".
    test('a page declaring nothing does not unraise a built-in route', () {
      installRaisedRoutes(registry);
      final raised = accessGroupForRoute('/advanced/page-editor');
      expect(raised, isNot(AccessGroup.operate),
          reason: 'the fixture is only meaningful if the route starts raised');

      declareMenuRouteGroups([
        _page('Page Editor', '/advanced/page-editor'),
      ], registry);

      expect(accessGroupForRoute('/advanced/page-editor'), raised,
          reason: 'silence must leave installRaisedRoutes alone; writing a '
              'default here would quietly open the door');
    });

    test('a page CAN raise a route the built-ins left open', () {
      installRaisedRoutes(registry);
      declareMenuRouteGroups([
        _page('Recipes', '/recipes', group: AccessGroup.setpoints),
      ], registry);

      expect(accessGroupForRoute('/recipes'), AccessGroup.setpoints);
    });

    test('sections themselves are never declared — they are not routes', () {
      declareMenuRouteGroups([
        _section('Diagnostics', [_page('IOs', '/diagnostics/ios')],
            group: AccessGroup.configure),
      ], registry);

      expect(accessGroupForRoute('/diagnostics'), AccessGroup.operate,
          reason: 'a section has no path to gate; it disappears from the menu '
              'when everything beneath it is hidden');
    });
  });

  group('MenuItem.requiredGroup round-trips', () {
    test('through JSON, and is absent when unset', () {
      final published = _page('Recipes', '/recipes', group: AccessGroup.force);
      expect(MenuItem.fromJson(published.toJson()).requiredGroup,
          AccessGroup.force);

      final open = _page('Home', '/home');
      expect(open.toJson().containsKey('required_group'), isFalse,
          reason: 'pages written before this feature must not gain a key, and '
              'an unpublished page must not write one');
      expect(MenuItem.fromJson(open.toJson()).requiredGroup, isNull);
    });

    test('copyWith can clear it, which null alone cannot express', () {
      final published = _page('Recipes', '/recipes', group: AccessGroup.force);

      expect(published.copyWith(label: 'Renamed').requiredGroup,
          AccessGroup.force,
          reason: 'an unrelated edit must not silently unpublish the page');
      expect(published.copyWith(clearRequiredGroup: true).requiredGroup, isNull);
    });
  });
}

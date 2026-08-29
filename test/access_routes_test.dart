/// The six raised routes. This map is the entire blast radius of route
/// gating: a path that is missing from it, or spelled differently from
/// `centroid-hmi/lib/main.dart`, is a route that silently stays open.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/access_routes.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc_access/tfc_access.dart';

void main() {
  late RouteRegistry registry;

  setUp(() {
    // The registry is a process-wide singleton; the suite must not depend
    // on test order, nor leak declarations into other suites.
    registry = RouteRegistry();
    registry.clearRouteGroups();
  });

  tearDown(() {
    RouteRegistry().clearRouteGroups();
  });

  group('kRaisedRoutes', () {
    test('names exactly the six routes, each with its group', () {
      // Spelled literally rather than derived, so that a change to the map
      // has to be made twice on purpose.
      expect(kRaisedRoutes, {
        '/advanced/page-editor': AccessGroup.configure,
        '/advanced/alarm-editor': AccessGroup.configure,
        '/advanced/key-repository': AccessGroup.configure,
        '/advanced/server-config': AccessGroup.administer,
        '/advanced/ip-settings': AccessGroup.administer,
        '/advanced/preferences': AccessGroup.administer,
      });
    });

    test('has exactly six entries', () {
      expect(kRaisedRoutes, hasLength(6));
    });

    test('the three editors need configure', () {
      expect(kRaisedRoutes['/advanced/page-editor'], AccessGroup.configure);
      expect(kRaisedRoutes['/advanced/alarm-editor'], AccessGroup.configure);
      expect(kRaisedRoutes['/advanced/key-repository'], AccessGroup.configure);
    });

    test('the three station-configuration routes need administer', () {
      expect(kRaisedRoutes['/advanced/server-config'], AccessGroup.administer);
      expect(kRaisedRoutes['/advanced/ip-settings'], AccessGroup.administer);
      expect(kRaisedRoutes['/advanced/preferences'], AccessGroup.administer);
    });

    test('no entry is operate', () {
      // A raised route that resolves to `operate` is an open route wearing a
      // lock: anonymous holds `operate`, so the badge would lie.
      expect(kRaisedRoutes.values, isNot(contains(AccessGroup.operate)));
    });

    test('every key is an absolute path', () {
      // A relative path would never match a Beamer path, so the route would
      // stay open while the map claimed otherwise.
      for (final path in kRaisedRoutes.keys) {
        expect(path, startsWith('/'), reason: '$path is not absolute');
      }
    });
  });

  group('routeAllowedWhenRepositoryUnavailable', () {
    test('kServerConfigRoute is itself a raised route', () {
      // The exemption must name a route that is actually raised, or it
      // exempts nothing and the real Server Config route stays gated.
      expect(kRaisedRoutes, contains(kServerConfigRoute));
      expect(kServerConfigRoute, '/advanced/server-config');
    });

    test('answers true for the server config route', () {
      expect(routeAllowedWhenRepositoryUnavailable(kServerConfigRoute), isTrue);
    });

    test('answers false for every other raised route', () {
      for (final path in kRaisedRoutes.keys) {
        if (path == kServerConfigRoute) continue;
        expect(routeAllowedWhenRepositoryUnavailable(path), isFalse,
            reason: '$path must stay denied while the repository is down');
      }
    });

    test('is true for exactly one raised route', () {
      final exempt =
          kRaisedRoutes.keys.where(routeAllowedWhenRepositoryUnavailable);

      expect(exempt, [kServerConfigRoute]);
    });

    test('answers false for an unraised path', () {
      expect(routeAllowedWhenRepositoryUnavailable('/alarm-view'), isFalse);
    });

    test('answers false for null', () {
      expect(routeAllowedWhenRepositoryUnavailable(null), isFalse);
    });
  });

  group('installRaisedRoutes', () {
    test('declares each of the six into the registry', () {
      installRaisedRoutes();

      kRaisedRoutes.forEach((path, group) {
        expect(registry.groupForRoute(path), group, reason: path);
      });
    });

    test('leaves every other path answering operate', () {
      installRaisedRoutes();

      expect(registry.groupForRoute('/alarm-view'), AccessGroup.operate);
      expect(registry.groupForRoute('/advanced/about-linux'),
          AccessGroup.operate);
      expect(registry.groupForRoute('/advanced'), AccessGroup.operate);
      expect(registry.groupForRoute(null), AccessGroup.operate);
    });

    test('is idempotent', () {
      installRaisedRoutes();
      installRaisedRoutes();

      kRaisedRoutes.forEach((path, group) {
        expect(registry.groupForRoute(path), group, reason: path);
      });
      expect(registry.groupForRoute('/alarm-view'), AccessGroup.operate);
    });

    test('accepts an explicit registry', () {
      // Same singleton today, but the seam keeps the function testable if
      // the registry ever stops being process-wide.
      installRaisedRoutes(registry);

      expect(registry.groupForRoute(kServerConfigRoute),
          AccessGroup.administer);
    });
  });

  group('accessGroupForRoute', () {
    test('agrees with the registry for every path, known or not', () {
      installRaisedRoutes();

      for (final path in [
        ...kRaisedRoutes.keys,
        '/alarm-view',
        '/nobody/declared/this',
        null,
      ]) {
        expect(accessGroupForRoute(path), registry.groupForRoute(path),
            reason: '${path ?? 'null'}');
      }
    });

    test('answers operate before the routes are installed', () {
      expect(accessGroupForRoute(kServerConfigRoute), AccessGroup.operate);
    });

    test('answers the mapped group after they are installed', () {
      installRaisedRoutes();

      expect(accessGroupForRoute('/advanced/page-editor'),
          AccessGroup.configure);
      expect(accessGroupForRoute(kServerConfigRoute), AccessGroup.administer);
    });
  });
}

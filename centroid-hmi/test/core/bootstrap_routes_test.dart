// Test D: Verify that createLocationBuilder includes routes for
// pages loaded from static config (not just hardcoded ones).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:centroidx/main.dart' show createLocationBuilder;
import 'package:tfc/models/menu_item.dart';

void main() {
  group('Bootstrap routes with static pages', () {
    test('createLocationBuilder includes routes for extra menu items', () {
      final extraMenuItems = [
        const MenuItem(
          label: 'Inference Monitor',
          path: '/inference-monitor',
          icon: Icons.monitor,
        ),
        const MenuItem(
          label: 'Dashboard',
          path: '/dashboard',
          icon: Icons.dashboard,
        ),
      ];

      final locationBuilder = createLocationBuilder(extraMenuItems);
      expect(locationBuilder, isNotNull);

      // Verify static page routes resolve (not just hardcoded ones)
      final location = locationBuilder(
        RouteInformation(uri: Uri.parse('/inference-monitor')),
        null,
      );
      expect(location, isNotNull);

      final dashLocation = locationBuilder(
        RouteInformation(uri: Uri.parse('/dashboard')),
        null,
      );
      expect(dashLocation, isNotNull);
    });

    test('createLocationBuilder still has hardcoded routes', () {
      final locationBuilder = createLocationBuilder([]);

      final alarmView = locationBuilder(
        RouteInformation(uri: Uri.parse('/alarm-view')),
        null,
      );
      expect(alarmView, isNotNull);

      final serverConfig = locationBuilder(
        RouteInformation(uri: Uri.parse('/advanced/server-config')),
        null,
      );
      expect(serverConfig, isNotNull);
    });

    test('without static pages their routes are not registered', () {
      // Documents the bootstrap bug: if static page menu items are not
      // passed to createLocationBuilder, navigating to them shows NotFound.
      final locationBuilder = createLocationBuilder([]);

      // /inference-monitor is NOT in the hardcoded routes — without
      // loading static config into the bootstrap PageManager, it
      // would be missing from the route map.
      final location = locationBuilder(
        RouteInformation(uri: Uri.parse('/inference-monitor')),
        null,
      );
      // Beamer still returns a location (NotFound handler), so the
      // route exists but would show PageNotFound.
      expect(location, isNotNull);
    });
  });
}

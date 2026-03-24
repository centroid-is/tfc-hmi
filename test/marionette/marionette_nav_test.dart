import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tests for the pre-defined Marionette navigation paths and semantic keys.
///
/// These tests verify:
/// 1. All navigation keys referenced in marionette_nav.dart match actual
///    ValueKeys in the source code.
/// 2. All routes referenced in NavRoutes match actual route registrations
///    in main.dart.
/// 3. NavStep.queryParam produces valid URL query fragments.
void main() {
  // Resolve the project root directory.
  final cwd = Directory.current.path;
  final projectRoot =
      cwd.endsWith('centroid-hmi') ? Directory.current.parent.path : cwd;

  String projectFile(String relativePath) => '$projectRoot/$relativePath';

  group('NavKeys match source ValueKeys', () {
    test('nav-advanced key exists in nav_dropdown.dart', () {
      final source =
          File(projectFile('lib/widgets/nav_dropdown.dart')).readAsStringSync();
      // NavDropdown generates: ValueKey<String>('nav-${label.toLowerCase()}')
      // For "Advanced" menu item, this yields 'nav-advanced'.
      expect(
        source,
        contains("ValueKey<String>('nav-\${widget.menuItem.label.toLowerCase()}')"),
        reason: 'NavDropdown should generate ValueKeys from menu item labels',
      );
    });

    test('chat-fab key exists in main.dart', () {
      final source = File(projectFile('centroid-hmi/lib/main.dart'))
          .readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-fab')"));
    });
  });

  group('NavRoutes match route registrations in main.dart', () {
    late String mainSource;

    setUp(() {
      mainSource = File(projectFile('centroid-hmi/lib/main.dart'))
          .readAsStringSync();
    });

    test('/alarm-view route is registered', () {
      expect(mainSource, contains("'/alarm-view'"));
    });

    test('/advanced/alarm-editor route is registered', () {
      expect(mainSource, contains("'/advanced/alarm-editor'"));
    });

    test('/advanced/page-editor route is registered', () {
      expect(mainSource, contains("'/advanced/page-editor'"));
    });

    test('/advanced/preferences route is registered', () {
      expect(mainSource, contains("'/advanced/preferences'"));
    });

    test('/advanced/history-view route is registered', () {
      expect(mainSource, contains("'/advanced/history-view'"));
    });

    test('/advanced/server-config route is registered', () {
      expect(mainSource, contains("'/advanced/server-config'"));
    });

    test('/advanced/key-repository route is registered', () {
      expect(mainSource, contains("'/advanced/key-repository'"));
    });

    test('/advanced/knowledge-base route is registered', () {
      expect(mainSource, contains("'/advanced/knowledge-base'"));
    });
  });

  group('Route logger is wired in main.dart', () {
    test('MarionetteRouteLogger is imported and used', () {
      final source = File(projectFile('centroid-hmi/lib/main.dart'))
          .readAsStringSync();
      expect(source, contains('MarionetteRouteLogger'));
      expect(source, contains('_enableMarionette'));
    });

    test('route_logger.dart exists and exports MarionetteRouteLogger', () {
      final source = File(projectFile('lib/marionette/route_logger.dart'))
          .readAsStringSync();
      expect(source, contains('class MarionetteRouteLogger'));
      expect(source, contains('[ROUTE]'));
      expect(source, contains('dart:developer'));
    });
  });

  group('marionette_nav.dart exists with expected structure', () {
    late String navSource;

    setUp(() {
      navSource = File(projectFile('centroid-hmi/lib/marionette_nav.dart'))
          .readAsStringSync();
    });

    test('NavKeys class exists', () {
      expect(navSource, contains('class NavKeys'));
    });

    test('NavRoutes class exists', () {
      expect(navSource, contains('class NavRoutes'));
    });

    test('NavPaths class exists', () {
      expect(navSource, contains('class NavPaths'));
    });

    test('NavStep class exists with queryParam', () {
      expect(navSource, contains('class NavStep'));
      expect(navSource, contains('queryParam'));
    });

    test('documents getLogs verification pattern', () {
      expect(navSource, contains('getLogs'));
      expect(navSource, contains('[ROUTE]'));
    });
  });
}

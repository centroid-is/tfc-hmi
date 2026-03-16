import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/marionette/route_logger.dart';

/// A minimal BeamLocation for testing route logging.
class _TestLocation extends BeamLocation<BeamState> {
  _TestLocation(String path)
      : super(RouteInformation(uri: Uri.parse(path)));

  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) {
    return [
      BeamPage(
        key: ValueKey(state.uri.path),
        child: const SizedBox.shrink(),
      ),
    ];
  }

  @override
  List<Pattern> get pathPatterns => ['/*'];
}

void main() {
  group('MarionetteRouteLogger', () {
    test('logs initial route on construction without errors', () {
      // Arrange: create a delegate that starts at /home
      final delegate = BeamerDelegate(
        locationBuilder: (routeInfo, _) =>
            _TestLocation(routeInfo.uri.path),
        initialPath: '/home',
      );

      // Act: create the route logger.
      // We can't intercept dart:developer.log() in tests directly,
      // so we verify the logger was constructed without errors and
      // can be disposed cleanly.
      final logger = MarionetteRouteLogger(delegate);

      // The logger should have been created without throwing.
      logger.dispose();
    });

    test('does not throw on EmptyBeamLocation', () {
      // Create a delegate that hasn't navigated yet.
      final delegate = BeamerDelegate(
        locationBuilder: (routeInfo, _) =>
            _TestLocation(routeInfo.uri.path),
      );

      // Should not throw even if the beam history is empty.
      final logger = MarionetteRouteLogger(delegate);
      logger.dispose();
    });

    test('dispose removes listener without error', () {
      final delegate = BeamerDelegate(
        locationBuilder: (routeInfo, _) =>
            _TestLocation(routeInfo.uri.path),
        initialPath: '/start',
      );

      final logger = MarionetteRouteLogger(delegate);
      // Should not throw.
      logger.dispose();
      // Disposing again should also not throw (removeListener is idempotent).
      logger.dispose();
    });

    test('survives rapid delegate notifications', () {
      final delegate = BeamerDelegate(
        locationBuilder: (routeInfo, _) =>
            _TestLocation(routeInfo.uri.path),
        initialPath: '/start',
      );

      final logger = MarionetteRouteLogger(delegate);

      // Trigger multiple notifications rapidly — should not throw.
      for (var i = 0; i < 100; i++) {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        delegate.notifyListeners();
      }

      logger.dispose();
    });
  });

  group('MarionetteRouteLogger integration', () {
    testWidgets('logs route changes when navigating', (tester) async {
      late BeamerDelegate delegate;

      delegate = BeamerDelegate(
        locationBuilder: RoutesLocationBuilder(
          routes: {
            '/': (context, state, data) => const BeamPage(
                  key: ValueKey('/'),
                  child: Text('Home'),
                ),
            '/about': (context, state, data) => const BeamPage(
                  key: ValueKey('/about'),
                  child: Text('About'),
                ),
          },
        ),
      );

      final logger = MarionetteRouteLogger(delegate);

      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: BeamerParser(),
        ),
      );
      await tester.pumpAndSettle();

      // Should see Home page.
      expect(find.text('Home'), findsOneWidget);

      // Navigate to /about.
      delegate.beamToNamed('/about');
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget);

      // The route logger should have processed the route change without error.
      logger.dispose();
    });

    testWidgets('handles query parameters in route', (tester) async {
      late BeamerDelegate delegate;

      delegate = BeamerDelegate(
        locationBuilder: RoutesLocationBuilder(
          routes: {
            '/': (context, state, data) => const BeamPage(
                  key: ValueKey('/'),
                  child: Text('Home'),
                ),
            '/search': (context, state, data) => BeamPage(
                  key: const ValueKey('/search'),
                  child: Text('Search: ${state.queryParameters['q'] ?? ''}'),
                ),
          },
        ),
      );

      final logger = MarionetteRouteLogger(delegate);

      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: BeamerParser(),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to /search?q=test.
      delegate.beamToNamed('/search?q=test');
      await tester.pumpAndSettle();

      expect(find.text('Search: test'), findsOneWidget);

      // The route logger should have processed the route with query params.
      logger.dispose();
    });
  });
}

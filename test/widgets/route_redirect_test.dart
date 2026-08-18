/// RouteRedirect — the widget behind refused navigation: a deleted Home's
/// `/`, or an unpublished page's path. It must actually land the router on
/// its target, replacing the refused location in history.
library;

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/route_redirect.dart';

void main() {
  testWidgets('navigating to a redirect route lands on its target',
      (tester) async {
    final delegate = BeamerDelegate(
      initialPath: '/refused',
      locationBuilder: RoutesLocationBuilder(routes: {
        '/refused': (context, state, data) => const BeamPage(
              key: ValueKey('/refused'),
              child: RouteRedirect(target: '/real'),
            ),
        '/real': (context, state, data) => const BeamPage(
              key: ValueKey('/real'),
              child: Scaffold(body: Text('the real page')),
            ),
      }).call,
    );

    await tester.pumpWidget(MaterialApp.router(
      routerDelegate: delegate,
      routeInformationParser: BeamerParser(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('the real page'), findsOneWidget);
    expect(delegate.configuration.uri.path, '/real');
  });
}

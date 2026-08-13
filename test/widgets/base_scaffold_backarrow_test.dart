/// Regression coverage for the stale back-arrow bug: after
/// Home -> Advanced -> an Advanced sub-page -> Home, the app-bar used to keep
/// a back-arrow on Home because the arrow was gated purely on
/// `context.canBeamBack` (true whenever ANY beaming history exists) instead of
/// on route depth. The fix gates the arrow on whether the current route is a
/// top-level destination.
library;

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc/widgets/base_scaffold.dart';

/// The top-level menu shape used by the app: Home (`/`) and Alarm View are
/// top-level; Server Config lives under Advanced and is therefore NOT
/// top-level.
void _registerAppMenu() {
  final registry = RouteRegistry();
  registry.menuItems.clear();
  registry
      .addMenuItem(const MenuItem(label: 'Home', path: '/', icon: Icons.home));
  registry.addMenuItem(const MenuItem(
      label: 'Alarm View', path: '/alarm-view', icon: Icons.alarm));
  registry.addMenuItem(const MenuItem(
    label: 'Packing',
    icon: Icons.factory,
    children: [
      MenuItem(label: 'Line 1', path: '/packing/line-1', icon: Icons.pageview),
    ],
  ));
  registry.addMenuItem(const MenuItem(
    label: 'Advanced',
    path: '/advanced',
    icon: Icons.settings,
    children: [
      MenuItem(
          label: 'Server Config',
          path: '/advanced/server-config',
          icon: Icons.dns),
    ],
  ));
}

Widget _buildShell() {
  final delegate = BeamerDelegate(
    locationBuilder: RoutesLocationBuilder(routes: {
      '/': (context, state, data) => const BeamPage(
            key: ValueKey('/'),
            title: 'Home',
            child: BaseScaffold(title: 'Home', body: Text('home-body')),
          ),
      '/alarm-view': (context, state, data) => const BeamPage(
            key: ValueKey('/alarm-view'),
            title: 'Alarm View',
            child: BaseScaffold(
                title: 'Alarm View', body: Text('alarm-view-body')),
          ),
      '/advanced/server-config': (context, state, data) => const BeamPage(
            key: ValueKey('/advanced/server-config'),
            title: 'Server Config',
            child: BaseScaffold(
                title: 'Server Config', body: Text('server-config-body')),
          ),
      '/packing/line-1': (context, state, data) => const BeamPage(
            key: ValueKey('/packing/line-1'),
            title: 'Line 1',
            child: BaseScaffold(title: 'Line 1', body: Text('line-1-body')),
          ),
    }).call,
  );

  return ProviderScope(
    child: BeamerProvider(
      routerDelegate: delegate,
      child: MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: BeamerParser(),
      ),
    ),
  );
}

void main() {
  setUp(_registerAppMenu);
  tearDown(() => RouteRegistry().menuItems.clear());

  group('isTopLevelDestinationPath', () {
    test('registered top-level paths are top-level', () {
      expect(isTopLevelDestinationPath('/'), isTrue);
      expect(isTopLevelDestinationPath('/alarm-view'), isTrue);
    });

    test('Advanced sub-pages are NOT top-level', () {
      expect(isTopLevelDestinationPath('/advanced/server-config'), isFalse);
    });

    test('null path (no BeamState yet) defaults to top-level / no arrow', () {
      expect(isTopLevelDestinationPath(null), isTrue);
    });

    test('deleted-Home `/` stays top-level even without a menu item', () {
      RouteRegistry().menuItems.clear();
      expect(isTopLevelDestinationPath('/'), isTrue);
    });
  });

  group('back-arrow gate (reported flow)', () {
    testWidgets('no back-arrow on Home after Home -> Advanced sub-page -> Home',
        (tester) async {
      await tester.pumpWidget(_buildShell());
      await tester.pumpAndSettle();

      final context = tester.element(find.text('home-body'));

      // On Home to start: top-level, no arrow.
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      // Navigate to the Advanced sub-page.
      Beamer.of(context).beamToNamed('/advanced/server-config');
      await tester.pumpAndSettle();
      expect(find.text('server-config-body'), findsOneWidget);

      // Deep in Advanced: history exists AND the route is not top-level, so
      // the back-arrow IS shown and stays functional.
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Move to another top-level page (Alarm View) the way a bottom-nav tap
      // does: a forward beam, NOT beamBack(). This leaves a non-empty history
      // ([/, /advanced/server-config, /alarm-view]) so `canBeamBack` stays
      // true -- the exact condition that used to leave a stale back-arrow on a
      // top-level page.
      Beamer.of(context).beamToNamed('/alarm-view');
      await tester.pumpAndSettle();
      expect(find.text('alarm-view-body'), findsOneWidget);
      expect(Beamer.of(context).canBeamBack, isTrue,
          reason: 'history is non-empty, reproducing the bug precondition');

      // Alarm View is top-level, so despite canBeamBack the arrow must be gone.
      // (Old code gated purely on canBeamBack and wrongly showed it here.)
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      // And returning to Home likewise shows no arrow.
      Beamer.of(context).beamToNamed('/');
      await tester.pumpAndSettle();
      expect(find.text('home-body'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets(
        'a page nested under a user-created section shows the arrow — '
        'nesting is not only /advanced in this app', (tester) async {
      await tester.pumpWidget(_buildShell());
      await tester.pumpAndSettle();

      final context = tester.element(find.text('home-body'));

      Beamer.of(context).beamToNamed('/packing/line-1');
      await tester.pumpAndSettle();
      expect(find.text('line-1-body'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Round trip: back at the top level, the arrow is gone again.
      Beamer.of(context).beamToNamed('/alarm-view');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });
}

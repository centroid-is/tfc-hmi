/// The startup-URL boot seam, end to end: a stored URL resolved through
/// [resolveStartupPath] and handed to a [BeamerDelegate] wired exactly the
/// way `MyApp` wires it must actually be where the router lands on the
/// first frame — including nested pages and built-ins, and whatever the
/// platform reports as the initial route. Desktop embedders report `/`;
/// the eLinux embedder reports `''`, which defeats Beamer's own
/// `'/' -> initialPath` swap — the station bug behind #354 — so the router
/// is wired through the same normalizing RouteInformationProvider MyApp
/// uses, and every platform flavor is pinned here.
library;

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/route_registry.dart';

import 'package:centroidx/main.dart';
import 'package:centroidx/navigation.dart';

MenuItem _page(String label, String path) => MenuItem(label: label, path: path, icon: Icons.pageview);

/// Pages a small station would have: Home, a plain page, and a section
/// holding a nested page.
final _pageMenuItems = <MenuItem>[
  _page('Home', '/'),
  _page('Line', '/line'),
  MenuItem(label: 'Halls', path: '/halls', icon: Icons.folder, isSection: true, children: [
    _page('Packing', '/halls/packing'),
  ]),
];

/// Boots a router the way `main()` does: stored URL -> resolveStartupPath
/// against the assembled menu -> BeamerDelegate(initialPath), with the
/// location builder built from the same menu items. Returns the delegate so
/// the test can ask where the app actually ended up.
Future<BeamerDelegate> _boot(
  WidgetTester tester,
  String storedUrl, {
  // What the platform reports as the initial route: '/' on desktop
  // embedders, '' on eLinux. The router must land on the stored page
  // either way.
  String platformRoute = '/',
}) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = platformRoute;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final topLevel = buildTopLevelMenuItems(
    isLinux: false,
    pageMenuItems: _pageMenuItems,
  );
  // BaseScaffold draws the bottom NavigationBar from the RouteRegistry
  // singleton, the same one main() fills; it asserts on fewer than two
  // destinations, so the registry has to be populated for pages to build.
  RouteRegistry().menuItems.clear();
  for (final item in topLevel) {
    RouteRegistry().addMenuItem(item);
  }
  final locationBuilder = createLocationBuilder(
    _pageMenuItems,
    pagePaths: const ['/', '/line', '/halls', '/halls/packing'],
  );
  final startupPath = resolveStartupPath(storedUrl, menuItems: topLevel);
  // Mirror main(): the top-level destinations clear beaming history, the
  // Advanced section excluded — a nested startup page lives UNDER one of
  // these, so the set must not swallow it.
  final topLevelPaths = <String>{
    '/',
    for (final item in topLevel)
      if (item.path != null && item.path != '/advanced') item.path!,
  };
  final delegate = BeamerDelegate(
    initialPath: startupPath,
    notFoundPage: const BeamPage(child: Text('not found')),
    clearBeamingHistoryOn: topLevelPaths,
    locationBuilder: (routeInformation, context) => locationBuilder(routeInformation, context),
  );
  // Mirror MyApp: the initial route travels through the normalizing
  // provider, not straight from the platform into Beamer.
  final routeInformationProvider = PlatformRouteInformationProvider(
    initialRouteInformation: RouteInformation(
      uri: Uri.parse(normalizeInitialPlatformRoute(
          tester.binding.platformDispatcher.defaultRouteName)),
    ),
  );
  addTearDown(routeInformationProvider.dispose);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      routerDelegate: delegate,
      routeInformationParser: BeamerParser(),
      routeInformationProvider: routeInformationProvider,
    ),
  ));
  await tester.pump();
  return delegate;
}

void main() {
  testWidgets('a stored top-level page is where the app boots', (tester) async {
    final delegate = await _boot(tester, '/line');
    expect(delegate.configuration.uri.path, '/line');
  });

  testWidgets('a stored nested page is where the app boots', (tester) async {
    final delegate = await _boot(tester, '/halls/packing');
    expect(delegate.configuration.uri.path, '/halls/packing');
  });

  testWidgets('a stored built-in destination is where the app boots', (tester) async {
    final delegate = await _boot(tester, '/alarm-view');
    expect(delegate.configuration.uri.path, '/alarm-view');
  });

  testWidgets('nothing stored boots on /', (tester) async {
    final delegate = await _boot(tester, '/');
    expect(delegate.configuration.uri.path, '/');
  });

  testWidgets('a page deleted since it was chosen falls back to /', (tester) async {
    final delegate = await _boot(tester, '/gone');
    expect(delegate.configuration.uri.path, '/');
  });

  testWidgets('eLinux: an empty platform route still boots the stored page', (tester) async {
    final delegate = await _boot(tester, '/halls/packing', platformRoute: '');
    expect(delegate.configuration.uri.path, '/halls/packing');
  });

  testWidgets('a bare platform route name counts as no opinion', (tester) async {
    final delegate = await _boot(tester, '/halls/packing', platformRoute: 'main');
    expect(delegate.configuration.uri.path, '/halls/packing');
  });

  testWidgets('a real deep link from the platform wins over the stored page', (tester) async {
    final delegate = await _boot(tester, '/halls/packing', platformRoute: '/line');
    expect(delegate.configuration.uri.path, '/line');
  });

  testWidgets('eLinux: an empty platform route with nothing stored boots /', (tester) async {
    final delegate = await _boot(tester, '/', platformRoute: '');
    expect(delegate.configuration.uri.path, '/');
  });
}

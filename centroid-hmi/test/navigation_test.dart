/// The app's menu shape and route fallbacks:
///  - god mode gates Key Repository (and the editor entries) out of the
///    Advanced menu; Server Config stays visible for commissioning,
///  - History View sits at the top level, not under Advanced,
///  - a deleted Home leaves `/` redirecting to the first available page,
///  - unpublished (draft) pages refuse direct navigation by redirecting.
library;

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/widgets/route_redirect.dart';

import 'package:centroidx/main.dart';
import 'package:centroidx/navigation.dart';

MenuItem _page(String label, String path) => MenuItem(label: label, path: path, icon: Icons.pageview);

MenuItem? _byPath(List<MenuItem> items, String path) {
  for (final item in items) {
    if (item.path == path) return item;
  }
  return null;
}

void main() {
  group('buildTopLevelMenuItems', () {
    List<MenuItem> build({required bool god}) {
      return buildTopLevelMenuItems(
        god: god,
        isLinux: false,
        pageMenuItems: [_page('Home', '/')],
      );
    }

    test(
        'without god mode, Key Repository and the editors are hidden but '
        'Server Config stays — commissioning must not need an env var', () {
      final advanced = _byPath(build(god: false), '/advanced');
      final paths = advanced?.children.map((c) => c.path).toList() ?? [];
      expect(paths, contains('/advanced/server-config'));
      expect(paths, isNot(contains('/advanced/key-repository')));
      expect(paths, isNot(contains('/advanced/page-editor')));
      expect(paths, isNot(contains('/advanced/preferences')));
      expect(paths, isNot(contains('/advanced/alarm-editor')));
    });

    test('god mode reveals them', () {
      final advanced = _byPath(build(god: true), '/advanced')!;
      final paths = advanced.children.map((c) => c.path).toList();
      expect(
          paths,
          containsAll([
            '/advanced/server-config',
            '/advanced/key-repository',
            '/advanced/page-editor',
            '/advanced/preferences',
            '/advanced/alarm-editor',
          ]));
    });

    test('History View defaults under Advanced, like before', () {
      final items = build(god: true);
      expect(_byPath(items, '/history-view'), isNull, reason: 'not top-level until the operator moves it');
      final advanced = _byPath(items, '/advanced')!;
      expect(advanced.children.map((c) => c.path), contains('/history-view'));
    });

    test('a promoted History View moves to the top level and out of Advanced', () {
      final items = buildTopLevelMenuItems(
        god: true,
        isLinux: false,
        pageMenuItems: [_page('Home', '/')],
        historyAtTopLevel: true,
      );
      expect(_byPath(items, '/history-view'), isNotNull);
      final advanced = _byPath(items, '/advanced')!;
      expect(advanced.children.map((c) => c.path), isNot(contains('/history-view')));
    });

    test('historyViewIsTopLevel is membership in the stored order', () {
      expect(historyViewIsTopLevel(const []), isFalse);
      expect(historyViewIsTopLevel(const ['/', '/alarm-view']), isFalse);
      expect(historyViewIsTopLevel(const ['/history-view']), isTrue);
    });

    test('Alarm View is a top-level entry', () {
      expect(_byPath(build(god: false), '/alarm-view'), isNotNull);
    });

    test('Home is not pinned: it appears only when the page manager has it', () {
      final items = buildTopLevelMenuItems(
        god: false,
        isLinux: false,
        pageMenuItems: [_page('First', '/first')],
      );
      expect(_byPath(items, '/'), isNull);
      expect(_byPath(items, '/first'), isNotNull);
    });

    test(
        'pages come first in registration order, built-ins after, Advanced '
        'pinned last (the persisted order is applied later by '
        'PageManager.sortTopLevel on the registry)', () {
      final items = buildTopLevelMenuItems(
        god: true,
        isLinux: false,
        pageMenuItems: [_page('Home', '/'), _page('Chiller', '/chiller')],
        historyAtTopLevel: true,
      );
      expect(items.map((m) => m.path).take(4), ['/', '/chiller', '/alarm-view', '/history-view']);
      expect(items.last.path, '/advanced', reason: 'Advanced stays pinned last, outside the ordering');
    });
  });

  group('firstMenuPath', () {
    test('finds the first path depth-first', () {
      expect(
        firstMenuPath([
          const MenuItem(label: 'Section', icon: Icons.folder, children: [
            MenuItem(label: 'Leaf', path: '/leaf', icon: Icons.pageview),
          ]),
          _page('Other', '/other'),
        ]),
        '/leaf',
      );
    });

    test('is null when nothing is reachable', () {
      expect(firstMenuPath(const []), isNull);
    });
  });

  group('createLocationBuilder', () {
    /// Builds the BeamPage a route would produce, with a real BuildContext.
    Future<BeamPage> buildRoute(WidgetTester tester, RoutesLocationBuilder lb, String path) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox.shrink();
      }));
      final builder = lb.routes[path];
      expect(builder, isNotNull, reason: 'expected a route for $path');
      return builder!(context, BeamState(), null) as BeamPage;
    }

    testWidgets('with a Home page, / is served normally', (tester) async {
      final lb = createLocationBuilder(
        [_page('Home', '/')],
        pagePaths: const ['/'],
      );
      final page = await buildRoute(tester, lb, '/');
      expect(page.child, isNot(isA<RouteRedirect>()));
    });

    testWidgets('with Home deleted, / redirects to the first available page', (tester) async {
      final lb = createLocationBuilder(
        [_page('Chiller', '/chiller'), _page('Freezer', '/freezer')],
        pagePaths: const ['/chiller', '/freezer'],
      );
      final page = await buildRoute(tester, lb, '/');
      expect(page.child, isA<RouteRedirect>());
      expect((page.child as RouteRedirect).target, '/chiller');
    });

    testWidgets('an unpublished page redirects instead of dead-ending', (tester) async {
      // The draft is in pagePaths (the manager knows it) but not in the
      // menu items (getRootMenuItems dropped it).
      final lb = createLocationBuilder(
        [_page('Home', '/')],
        pagePaths: const ['/', '/draft'],
      );
      final page = await buildRoute(tester, lb, '/draft');
      expect(page.child, isA<RouteRedirect>());
      expect((page.child as RouteRedirect).target, '/');
    });

    testWidgets('History View is routable at both old and new addresses', (tester) async {
      final lb = createLocationBuilder([_page('Home', '/')]);
      expect(lb.routes.containsKey('/history-view'), isTrue);
      expect(lb.routes.containsKey('/advanced/history-view'), isTrue);
    });

    testWidgets('no reachable pages at all leaves no bogus redirect', (tester) async {
      // Every page a draft: nowhere to send anyone. `/` stays unrouted and
      // beamer's not-found page takes it, rather than a redirect loop.
      final lb = createLocationBuilder(const [], pagePaths: const ['/draft']);
      expect(lb.routes.containsKey('/'), isFalse);
      expect(lb.routes.containsKey('/draft'), isFalse);
    });
  });
}

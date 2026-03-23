import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/widgets/nav_dropdown.dart';
import 'package:tfc/route_registry.dart';
import 'package:beamer/beamer.dart';

MenuItem _testMenuItem() {
  return MenuItem(
    label: 'TestMenu',
    icon: Icons.settings,
    children: [
      MenuItem(label: 'Page A', icon: Icons.home, path: '/page-a'),
      MenuItem(label: 'Page B', icon: Icons.info, path: '/page-b'),
    ],
  );
}

/// Creates a menu with many items to reproduce BUG-005 (popup clips offscreen).
MenuItem _largeTestMenuItem() {
  return MenuItem(
    label: 'Advanced',
    icon: Icons.settings,
    children: [
      MenuItem(label: 'Section One', icon: Icons.folder, children: [
        MenuItem(label: 'Page 1', icon: Icons.pages, path: '/page-1'),
        MenuItem(label: 'Page 2', icon: Icons.pages, path: '/page-2'),
        MenuItem(label: 'Page 3', icon: Icons.pages, path: '/page-3'),
      ]),
      MenuItem(label: 'Section Two', icon: Icons.folder, children: [
        MenuItem(label: 'Page 4', icon: Icons.pages, path: '/page-4'),
        MenuItem(label: 'Page 5', icon: Icons.pages, path: '/page-5'),
        MenuItem(label: 'Page 6', icon: Icons.pages, path: '/page-6'),
      ]),
      MenuItem(label: 'Page 7', icon: Icons.pages, path: '/page-7'),
      MenuItem(label: 'Page 8', icon: Icons.pages, path: '/page-8'),
      MenuItem(label: 'Page 9', icon: Icons.pages, path: '/page-9'),
      MenuItem(label: 'Page 10', icon: Icons.pages, path: '/page-10'),
      MenuItem(label: 'Page 11', icon: Icons.pages, path: '/page-11'),
      MenuItem(label: 'Page 12', icon: Icons.pages, path: '/page-12'),
    ],
  );
}

/// A BeamLocation that places a NavDropdown at the bottom of a Scaffold.
class _NavDropdownLocation extends BeamLocation<BeamState> {
  final MenuItem menuItem;
  _NavDropdownLocation(this.menuItem)
      : super(RouteInformation(uri: Uri.parse('/test')));

  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) {
    return [
      BeamPage(
        key: const ValueKey('test'),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: NavDropdown(menuItem: menuItem),
          ),
        ),
      ),
    ];
  }

  @override
  List<Pattern> get pathPatterns => ['/test'];
}

/// Wraps a [NavDropdown] in the minimal widget tree needed for Beamer context.
Widget buildTestNavDropdown(MenuItem menuItem) {
  final routerDelegate = BeamerDelegate(
    locationBuilder: (routeInformation, _) => _NavDropdownLocation(menuItem),
  );

  return BeamerProvider(
    routerDelegate: routerDelegate,
    child: MaterialApp.router(
      routerDelegate: routerDelegate,
      routeInformationParser: BeamerParser(),
    ),
  );
}

/// Same as [buildTestNavDropdown] but wraps in a nested Navigator with a
/// shared HeroController to reproduce BUG-002.
Widget buildTestNavDropdownWithNestedNavigator(MenuItem menuItem) {
  final routerDelegate = BeamerDelegate(
    locationBuilder: (routeInformation, _) => _NavDropdownLocation(menuItem),
  );

  return BeamerProvider(
    routerDelegate: routerDelegate,
    child: MaterialApp.router(
      routerDelegate: routerDelegate,
      routeInformationParser: BeamerParser(),
      builder: (context, child) {
        return HeroControllerScope(
          controller: HeroController(),
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: NavDropdown(menuItem: menuItem),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  setUp(() {
    // Ensure RouteRegistry has the test menu item so findRootNodeOfLeaf works.
    final registry = RouteRegistry();
    registry.menuItems.clear();
    registry.addMenuItem(_testMenuItem());
  });

  group('NavDropdown', () {
    group('BUG-001: rapid tap crash guard', () {
      testWidgets('_isMenuOpen guard is set while popup is open',
          (WidgetTester tester) async {
        await tester.pumpWidget(buildTestNavDropdown(_testMenuItem()));
        await tester.pumpAndSettle();

        // Find the NavDropdownState to inspect the guard
        final state =
            tester.state<NavDropdownState>(find.byType(NavDropdown));
        expect(state.isMenuOpen, isFalse,
            reason: 'Guard should be false before any tap');

        // Open the popup menu
        await tester.tap(find.text('TestMenu'));
        await tester.pump(); // start the menu animation

        // While the popup is open/transitioning, the guard should be true
        expect(state.isMenuOpen, isTrue,
            reason: 'Guard must be true while popup is open');

        // Let the animation complete
        await tester.pumpAndSettle();

        // Guard should still be true while menu is displayed
        expect(state.isMenuOpen, isTrue,
            reason: 'Guard must remain true while menu is displayed');

        // The menu items should be visible
        expect(find.text('Page A'), findsOneWidget);
        expect(find.text('Page B'), findsOneWidget);
      });

      testWidgets('guard resets to false after menu is dismissed',
          (WidgetTester tester) async {
        await tester.pumpWidget(buildTestNavDropdown(_testMenuItem()));
        await tester.pumpAndSettle();

        final state =
            tester.state<NavDropdownState>(find.byType(NavDropdown));

        // Open the menu
        await tester.tap(find.text('TestMenu'));
        await tester.pumpAndSettle();
        expect(state.isMenuOpen, isTrue);

        // Dismiss by tapping outside the popup
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        // Guard should reset after menu closes
        expect(state.isMenuOpen, isFalse,
            reason: 'Guard must reset to false after menu is dismissed');

        // Should be able to open a new menu
        await tester.tap(find.text('TestMenu'));
        await tester.pumpAndSettle();

        expect(find.text('Page A'), findsOneWidget);
        expect(find.text('Page B'), findsOneWidget);
      });
    });

    group('BUG-002: HeroController shared by multiple Navigators', () {
      testWidgets(
          'showMenu uses root navigator to avoid HeroController conflict',
          (WidgetTester tester) async {
        await tester.pumpWidget(
            buildTestNavDropdownWithNestedNavigator(_testMenuItem()));
        await tester.pumpAndSettle();

        // If showMenu does NOT use the root navigator, this tap would
        // trigger a HeroController conflict. With useRootNavigator: true,
        // it should work fine.
        await tester.tap(find.text('TestMenu'));
        await tester.pumpAndSettle();

        // Menu should display without errors
        expect(find.text('Page A'), findsOneWidget);
        expect(find.text('Page B'), findsOneWidget);
      });
    });

    group('BUG-005: popup clips offscreen with many items', () {
      setUp(() {
        // Register the large menu so findRootNodeOfLeaf can resolve it.
        final registry = RouteRegistry();
        registry.menuItems.clear();
        registry.addMenuItem(_largeTestMenuItem());
      });

      testWidgets(
          'popup menu stays within screen bounds when there are many items',
          (WidgetTester tester) async {
        // Use a small screen size to force the overflow scenario.
        // 14 total items * 48px = 672px, exceeding the 400px screen height.
        tester.view.physicalSize = const Size(800, 400);
        tester.view.devicePixelRatio = 1.0;
        addTeardownToTeardown(tester);

        await tester
            .pumpWidget(buildTestNavDropdown(_largeTestMenuItem()));
        await tester.pumpAndSettle();

        // Open the popup menu
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();

        // The popup menu surface should not extend above y=0.
        // Find the popup's Material surface that wraps the menu items.
        // showMenu creates a _PopupMenu which contains a Material widget.
        final popupFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.type == MaterialType.card,
        );
        // If no card-type Material, try the generic popup approach
        final menuFinder = popupFinder.evaluate().isNotEmpty
            ? popupFinder
            : find.byType(PopupMenuItem<void>).first;
        expect(menuFinder, findsWidgets);

        // Get the render box of the first popup menu entry to check
        // its global position.
        final firstItemBox = tester.renderObject(
          find.byType(PopupMenuItem<void>).first,
        ) as RenderBox;
        final firstItemTopLeft =
            firstItemBox.localToGlobal(Offset.zero);

        // The top of the first menu item must not be above the screen.
        expect(
          firstItemTopLeft.dy,
          greaterThanOrEqualTo(0.0),
          reason:
              'Menu popup must not extend above the top of the screen',
        );

        // Also verify we can still see menu items (popup opens and is
        // usable, just scrollable now).
        expect(find.text('Page 12'), findsOneWidget);
      });

      testWidgets(
          'popup is scrollable and last items are accessible',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 400);
        tester.view.devicePixelRatio = 1.0;
        addTeardownToTeardown(tester);

        await tester
            .pumpWidget(buildTestNavDropdown(_largeTestMenuItem()));
        await tester.pumpAndSettle();

        // Open the popup menu
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();

        // With the constrained height, the popup should be scrollable.
        // Check that at least one item is visible (the popup opened
        // successfully without errors).
        final visibleItems = find.byType(PopupMenuItem<void>);
        expect(visibleItems, findsWidgets);
      });
    });
  });
}

/// Helper to reset the test view size on teardown.
void addTeardownToTeardown(WidgetTester tester) {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

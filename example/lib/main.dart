import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import 'package:tfc_hmi/route_registry.dart';
import 'package:tfc_hmi/models/menu_item.dart';
import 'package:tfc_hmi/transition_delegate.dart';
import 'package:tfc_hmi/pages/connections.dart';
import 'pages/pages.dart';

void main() {
  // Initialize the RouteRegistry
  final registry = RouteRegistry();

  // this is a bit of duplication
  registry.addMenuItem(MenuItem(
    label: 'Home',
    path: Uri.parse('/'),
    icon: Icons.home,
    hoverText: 'Home',
  ));

  registry.addMenuItem(MenuItem(
    label: 'Settings',
    path: Uri.parse('/settings'),
    icon: Icons.settings,
    hoverText: 'Settings',
    children: [
      MenuItem(
        label: 'Profile',
        path: Uri.parse('/settings/profile'),
        icon: Icons.person,
        hoverText: 'Profile Settings',
      ),
      MenuItem(
        label: 'Privacy',
        path: Uri.parse('/settings/privacy'),
        icon: Icons.lock,
        hoverText: 'Privacy Settings',
      ),
      MenuItem(
        label: 'Connections',
        path: Uri.parse('/settings/connections'),
        icon: Icons.link,
        hoverText: 'Connections',
      ),
    ],
  ));

  registry.addMenuItem(MenuItem(
    label: 'Controls',
    path: Uri.parse('/controls'),
    icon: Icons.tune,
    hoverText: 'Controls',
  ));

  runApp(MyApp());
}

// todo this is a bit of duplication
final simpleLocationBuilder = RoutesLocationBuilder(routes: {
  '/': (context, state, args) => const BeamPage(
        key: ValueKey('/'),
        title: 'Home',
        child: HomePage(),
      ),
  '/settings/profile': (context, state, args) => const BeamPage(
        key: ValueKey('/settings/profile'),
        title: 'Profile Settings',
        child: ProfileSettingsPage(),
      ),
  '/settings/privacy': (context, state, args) => const BeamPage(
        key: ValueKey('/settings/privacy'),
        title: 'Privacy Settings',
        child: PrivacyPage(),
      ),
  '/settings/connections': (context, state, args) => BeamPage(
        key: const ValueKey('/settings/connections'),
        title: 'Connections',
        child: ConnectionPage(),
      ),
  '/controls': (context, state, args) => const BeamPage(
        key: ValueKey('/controls'),
        title: 'Controls',
        child: ControlsPage(),
      ),
});

class MyApp extends StatelessWidget {
  final routerDelegate = BeamerDelegate(
    transitionDelegate: const MyNoAnimationTransitionDelegate(),
    locationBuilder: (routeInformation, context) =>
        simpleLocationBuilder(routeInformation, context),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Example App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      routerDelegate: routerDelegate,
      routeInformationParser: BeamerParser(),
    );
  }
}

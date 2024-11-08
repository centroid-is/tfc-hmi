import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import 'package:tfc_hmi/theme.dart';
import 'package:tfc_hmi/route_registry.dart';
import 'package:tfc_hmi/models/menu_item.dart';
import 'package:tfc_hmi/transition_delegate.dart';
import 'package:tfc_hmi/pages/connections.dart';
import 'package:tfc_hmi/pages/ip_settings.dart';
import 'package:tfc_hmi/pages/viewtheme.dart';
import 'package:provider/provider.dart';
import 'pages/pages.dart';

void main() {
  // Initialize the RouteRegistry
  final registry = RouteRegistry();

  // this is a bit of duplication
  registry.addMenuItem(MenuItem(
    label: 'Home',
    path: Uri.parse('/'),
    icon: Icons.home,
  ));

  registry.addMenuItem(MenuItem(
    label: 'Settings',
    path: Uri.parse('/settings'),
    icon: Icons.settings,
    children: [
      MenuItem(
        label: 'Profile',
        path: Uri.parse('/settings/profile'),
        icon: Icons.person,
      ),
      MenuItem(
        label: 'Privacy',
        path: Uri.parse('/settings/privacy'),
        icon: Icons.lock,
      ),
      MenuItem(
        label: 'Core',
        path: Uri.parse('/settings/core'),
        icon: Icons.settings_remote_outlined,
        children: [
          MenuItem(
            label: 'Connections',
            path: Uri.parse('/settings/core/connections'),
            icon: Icons.link,
          ),
          MenuItem(
            label: 'IP Settings',
            path: Uri.parse('/settings/core/ip'),
            icon: Icons.network_cell_outlined,
          ),
          MenuItem(
            label: 'IP Settings',
            path: Uri.parse('/settings/core/ip'),
            icon: Icons.network_cell_outlined,
          ),
        ],
      ),
    ],
  ));

  registry.addMenuItem(MenuItem(
    label: 'Theme',
    path: Uri.parse('/theme'),
    icon: Icons.photo,
  ));

  registry.addMenuItem(MenuItem(
    label: 'Controls',
    path: Uri.parse('/controls'),
    icon: Icons.tune,
  ));

  runApp(ChangeNotifierProvider(
    create: (_) => ThemeNotifier(),
    child: MyApp(),
  ));
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
  '/settings/core/connections': (context, state, args) => BeamPage(
        key: const ValueKey('/settings/core/connections'),
        title: 'Connections',
        child: ConnectionPage(),
      ),
  '/settings/core/ip': (context, state, args) => const BeamPage(
        key: ValueKey('/settings/core/ip'),
        title: 'IP Settings',
        child: IpSettingsPage(),
      ),
  '/controls': (context, state, args) => const BeamPage(
        key: ValueKey('/controls'),
        title: 'Controls',
        child: ControlsPage(),
      ),
  '/theme': (context, state, args) => const BeamPage(
      key: ValueKey('/theme'), title: 'Theme', child: ViewTheme())
});

class MyApp extends StatelessWidget {
  final routerDelegate = BeamerDelegate(
    transitionDelegate: const MyNoAnimationTransitionDelegate(),
    locationBuilder: (routeInformation, context) =>
        simpleLocationBuilder(routeInformation, context),
  );

  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final (light, dark) = solarized();
    return Consumer<ThemeNotifier>(builder: (context, themeNotifier, child) {
      return MaterialApp.router(
        title: 'Example App',
        themeMode: themeNotifier.themeMode,
        theme: light,
        darkTheme: dark,
        routerDelegate: routerDelegate,
        routeInformationParser: BeamerParser(),
      );
    });
  }
}

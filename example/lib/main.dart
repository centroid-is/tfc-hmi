import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import 'package:tfc_hmi/theme.dart';
import 'package:tfc_hmi/route_registry.dart';
import 'package:tfc_hmi/models/menu_item.dart';
import 'package:tfc_hmi/transition_delegate.dart';
import 'package:tfc_hmi/pages/connections.dart';
import 'package:tfc_hmi/pages/ip_settings.dart';
import 'package:tfc_hmi/pages/not_found.dart';
import 'package:tfc_hmi/pages/viewtheme.dart';
import 'package:tfc_hmi/pages/system.dart';
import 'package:provider/provider.dart';
import 'pages/pages.dart';

void main() {
  // Initialize the RouteRegistry
  final registry = RouteRegistry();

  // this is a bit of duplication
  registry.addMenuItem(const MenuItem(
    label: 'Home',
    path: '/',
    icon: Icons.home,
  ));

  registry.addMenuItem(const MenuItem(
    label: 'Settings',
    path: null,
    icon: Icons.settings,
    children: [
      MenuItem(
        label: 'Profile',
        path: '/settings/profile',
        icon: Icons.person,
      ),
      MenuItem(
        label: 'Privacy',
        path: '/settings/privacy',
        icon: Icons.lock,
      ),
      MenuItem(
        label: 'Core',
        path: '/settings/core',
        icon: Icons.settings_remote_outlined,
        children: [
          MenuItem(
            label: 'Connections',
            path: '/settings/core/connections',
            icon: Icons.link,
          ),
          MenuItem(
            label: 'IP Settings',
            path: '/settings/core/ip',
            icon: Icons.network_cell_outlined,
          ),
        ],
      ),
    ],
  ));

  registry.addMenuItem(const MenuItem(
    label: 'Theme',
    path: '/theme',
    icon: Icons.photo,
  ));

  registry.addMenuItem(const MenuItem(
    label: 'System',
    path: '/system',
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
  '/system': (context, state, args) => const BeamPage(
        key: ValueKey('/system'),
        title: 'System',
        child: SystemsPage(),
      ),
  '/theme': (context, state, args) => const BeamPage(
      key: ValueKey('/theme'), title: 'Theme', child: ViewTheme())
});

class MyApp extends StatelessWidget {
  final routerDelegate = BeamerDelegate(
    notFoundPage: const BeamPage(child: PageNotFound()),
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

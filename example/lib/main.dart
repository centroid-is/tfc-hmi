import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import 'package:dbus/dbus.dart';
import 'package:tfc_hmi/theme.dart';
import 'package:tfc_hmi/route_registry.dart';
import 'package:tfc_hmi/models/menu_item.dart';
import 'package:tfc_hmi/transition_delegate.dart';
import 'package:tfc_hmi/pages/ipc_connections.dart';
import 'package:tfc_hmi/pages/ip_settings.dart';
import 'package:tfc_hmi/pages/not_found.dart';
import 'package:tfc_hmi/pages/viewtheme.dart';
import 'package:tfc_hmi/pages/system.dart';
import 'package:tfc_hmi/pages/config_list.dart';
import 'package:tfc_hmi/pages/login.dart';
import 'package:provider/provider.dart';
import 'package:tfc_hmi/widgets/tfc_operations.dart';
import 'package:tfc_hmi/widgets/base_scaffold.dart';
import 'pages/pages.dart';

void main() async {
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
          MenuItem(
            label: 'Configs',
            path: '/settings/core/configs',
            icon: Icons.settings_outlined,
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

  // Run the login flow first
  final themeNotifier = await ThemeNotifier.create();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => themeNotifier),
      ],
      child: LoginApp(onLoginSuccess: (DBusClient client) {
        // After successful login, run the main app
        runApp(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => themeNotifier),
              Provider<DBusClient>.value(value: client),
              ChangeNotifierProxyProvider<DBusClient,
                  GlobalAppBarLeftWidgetProvider>(
                create: (context) =>
                    OperationModeAppBarLeftWidgetProvider(client),
                update: (context, client, previous) =>
                    previous ?? OperationModeAppBarLeftWidgetProvider(client),
              ),
            ],
            child: MyApp(),
          ),
        );
      }),
    ),
  );
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
        child: ConnectionsPage(dbusClient: context.read<DBusClient>()),
      ),
  '/settings/core/configs': (context, state, data) => BeamPage(
        key: const ValueKey('/settings/core/configs'),
        title: 'All Configs',
        child: ConfigListPage(
          dbusClient: context.read<DBusClient>(),
        ),
      ),
  '/settings/core/ip': (context, state, args) => BeamPage(
        key: const ValueKey('/settings/core/ip'),
        title: 'IP Settings',
        child: IpSettingsPage(
          dbusClient: context.read<DBusClient>(),
        ),
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

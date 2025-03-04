import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import 'package:dbus/dbus.dart';
import 'package:tfc/theme.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/transition_delegate.dart';
import 'package:tfc/pages/ipc_connections.dart';
import 'package:tfc/pages/ip_settings.dart';
import 'package:tfc/pages/not_found.dart';
import 'package:tfc/pages/viewtheme.dart';
import 'package:tfc/pages/system.dart';
import 'package:tfc/pages/config_list.dart';
import 'package:tfc/pages/login.dart';
import 'package:provider/provider.dart';
import 'package:tfc/widgets/tfc_operations.dart';
import 'package:tfc/widgets/base_scaffold.dart';
import 'package:tfc/pages/page_view.dart';
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

  registry.addMenuItem(const MenuItem(
    label: 'Asset View',
    path: '/asset-view',
    icon: Icons.lock,
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
      key: ValueKey('/theme'), title: 'Theme', child: ViewTheme()),
  '/asset-view': (context, state, args) => BeamPage(
        key: const ValueKey('/asset-view'),
        title: 'Asset View',
        child: AssetView(
          config: AssetViewConfig.fromJson(
            {
              "groups": [
                {
                  "name": "slow",
                  "assets": [
                    {
                      "asset_name": "LEDConfig",
                      "key": "Slow LED 1",
                      "on_color": {"red": 1.0, "green": 0.0, "blue": 0.0},
                      "off_color": {"red": 0.2, "green": 0.0, "blue": 0.0},
                      "text_pos": "above",
                      "coordinates": {"x": 0.2, "y": 0.3},
                      "size": {"width": 40.0, "height": 40.0}
                    },
                    {
                      "asset_name": "CircleButtonConfig",
                      "key": "Slow Button 1",
                      "outward_color": {"red": 0.0, "green": 1.0, "blue": 0.0},
                      "inward_color": {"red": 0.0, "green": 0.2, "blue": 0.0},
                      "text_pos": "below",
                      "coordinates": {"x": 0.4, "y": 0.3},
                      "size": {"width": 50.0, "height": 50.0}
                    }
                  ]
                },
                {
                  "name": "fast",
                  "assets": [
                    {
                      "asset_name": "LEDConfig",
                      "key": "Fast LED 1",
                      "on_color": {"red": 0.0, "green": 0.0, "blue": 1.0},
                      "off_color": {"red": 0.0, "green": 0.0, "blue": 0.2},
                      "text_pos": "right",
                      "coordinates": {"x": 0.6, "y": 0.7},
                      "size": {"width": 40.0, "height": 40.0}
                    },
                    {
                      "asset_name": "CircleButtonConfig",
                      "key": "Fast Button 1",
                      "outward_color": {"red": 1.0, "green": 1.0, "blue": 0.0},
                      "inward_color": {"red": 0.2, "green": 0.2, "blue": 0.0},
                      "text_pos": "left",
                      "coordinates": {"x": 0.8, "y": 0.7},
                      "size": {"width": 50.0, "height": 50.0}
                    }
                  ]
                }
              ]
            },
          ),
        ),
      ),
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

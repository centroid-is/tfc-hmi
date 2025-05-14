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
import 'package:tfc/widgets/tfc_operations.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/pages/page_editor.dart';
import 'pages/pages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/providers/dbus.dart';
import 'package:tfc/providers/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io' show Platform;

void main() async {
  // Initialize the RouteRegistry
  final registry = RouteRegistry();

  // this is a bit of duplication
  registry.addMenuItem(const MenuItem(
    label: 'Home',
    path: '/',
    icon: Icons.home,
  ));

  // Only add DBus-dependent settings on Linux
  if (Platform.isLinux) {
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
  }

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

  registry.addMenuItem(const MenuItem(
    label: 'Page Editor',
    path: '/page-editor',
    icon: Icons.edit,
  ));

  WidgetsFlutterBinding.ensureInitialized();
  // Use a single ProviderScope at the root.
  runApp(const ProviderScope(child: AppInitializer()));
}

/// This widget handles the login flow before showing the main app.
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  DBusClient? _dbusClient;

  @override
  Widget build(BuildContext context) {
    // Skip login on non-Linux platforms
    if (!Platform.isLinux) {
      return ProviderScope(
        overrides: [
          dbusProvider.overrideWithValue(null),
        ],
        child: MyApp(),
      );
    }

    // Show login flow on Linux
    if (_dbusClient == null) {
      return LoginApp(
        onLoginSuccess: (DBusClient client) {
          setState(() {
            _dbusClient = client;
          });
        },
      );
    }
    // Once logged in, override the dbusProvider and show the main app.
    return ProviderScope(
      overrides: [
        dbusProvider.overrideWithValue(_dbusClient!),
      ],
      child: MyApp(),
    );
  }
}

// todo this is a bit of duplication
final simpleLocationBuilder = RoutesLocationBuilder(routes: {
  '/': (context, state, args) => const BeamPage(
        key: ValueKey('/'),
        title: 'Home',
        child: HomePage(),
      ),
  // Only include DBus-dependent routes on Linux
  if (Platform.isLinux) ...{
    '/settings/profile': (context, state, args) => const BeamPage(
          key: ValueKey('/settings/profile'),
          title: 'Profile Settings',
          child: ProfileSettingsPage(),
        ),
    '/settings/core/connections': (context, state, args) => BeamPage(
          key: const ValueKey('/settings/core/connections'),
          title: 'Connections',
          child: Consumer(
            builder: (context, ref, _) => ConnectionsPage(
              dbusClient: ref.watch(dbusProvider)!,
            ),
          ),
        ),
    '/settings/core/configs': (context, state, data) => BeamPage(
          key: const ValueKey('/settings/core/configs'),
          title: 'All Configs',
          child: Consumer(
            builder: (context, ref, _) => ConfigListPage(
              dbusClient: ref.watch(dbusProvider)!,
            ),
          ),
        ),
    '/settings/core/ip': (context, state, args) => BeamPage(
          key: const ValueKey('/settings/core/ip'),
          title: 'IP Settings',
          child: Consumer(
            builder: (context, ref, _) => IpSettingsPage(
              dbusClient: ref.watch(dbusProvider)!,
            ),
          ),
        ),
  },
  // Non-DBus dependent routes
  '/theme': (context, state, args) => const BeamPage(
      key: ValueKey('/theme'), title: 'Theme', child: ViewTheme()),
  '/system': (context, state, args) => const BeamPage(
        key: ValueKey('/system'),
        title: 'System',
        child: SystemsPage(),
      ),
  '/asset-view': (context, state, args) => BeamPage(
        key: const ValueKey('/asset-view'),
        title: 'Asset View',
        child: Consumer(
          builder: (context, ref, _) => FutureBuilder<SharedPreferences>(
            future: SharedPreferences.getInstance(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final prefs = snapshot.data!;
              final jsonString = prefs.getString('page_editor_data');
              print('jsonString: $jsonString');
              if (jsonString == null) {
                return const Center(child: Text('No saved layout found'));
              }

              final json = jsonDecode(jsonString);
              return AssetView(
                config: AssetViewConfig.fromJson(json),
              );
            },
          ),
        ),
      ),
  '/page-editor': (context, state, args) => BeamPage(
        key: const ValueKey('/page-editor'),
        title: 'Page Editor',
        child: PageEditor(),
      ),
});

class MyApp extends ConsumerWidget {
  MyApp({super.key})
      : routerDelegate = BeamerDelegate(
          notFoundPage: const BeamPage(child: PageNotFound()),
          transitionDelegate: const MyNoAnimationTransitionDelegate(),
          locationBuilder: (routeInformation, context) =>
              simpleLocationBuilder(routeInformation, context),
        );

  final BeamerDelegate routerDelegate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeNotifierProvider);
    final (light, dark) = solarized();

    return MaterialApp.router(
      title: 'Example App',
      themeMode: themeAsync.when(
        data: (themeMode) => themeMode,
        loading: () => ThemeMode.system,
        error: (_, __) => ThemeMode.system,
      ),
      theme: light,
      darkTheme: dark,
      routerDelegate: routerDelegate,
      routeInformationParser: BeamerParser(),
    );
  }
}

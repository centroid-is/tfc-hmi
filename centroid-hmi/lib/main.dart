import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beamer/beamer.dart';
import 'package:dbus/dbus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:amplify_secure_storage_dart/amplify_secure_storage_dart.dart';

import 'package:tfc/route_registry.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/pages/page_editor.dart';
import 'package:tfc/pages/not_found.dart';
import 'package:tfc/pages/preferences.dart';
import 'package:tfc/pages/alarm_editor.dart';
import 'package:tfc/pages/alarm_view.dart';
import 'package:tfc/pages/ip_settings.dart';
import 'package:tfc/pages/dbus_login.dart';
import 'package:tfc/pages/history_view.dart';
import 'package:tfc/pages/server_config.dart';
import 'package:tfc/transition_delegate.dart';
import 'package:tfc/providers/theme.dart';
import 'package:tfc/core/preferences.dart';
import 'package:tfc/page_creator/page.dart';

import 'package:tfc/theme.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/widgets/base_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AmplifySecureStorageDart.registerWith();

  // Register your custom asset type
  // AssetRegistry.registerFromJsonFactory<ChecklistsConfig>(ChecklistsConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<ChecklistsConfig>(ChecklistsConfig.preview);

  // AssetRegistry.registerFromJsonFactory<SpeedBatcherConfig>(SpeedBatcherConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<SpeedBatcherConfig>(SpeedBatcherConfig.preview);

  // AssetRegistry.registerFromJsonFactory<AirCabConfig>(AirCabConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<AirCabConfig>(AirCabConfig.preview);

  // AssetRegistry.registerFromJsonFactory<ElCabConfig>(ElCabConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<ElCabConfig>(ElCabConfig.preview);

  // AssetRegistry.registerFromJsonFactory<RecipesConfig>(RecipesConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<RecipesConfig>(RecipesConfig.preview);

  // AssetRegistry.registerFromJsonFactory<GateStatusConfig>(GateStatusConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<GateStatusConfig>(GateStatusConfig.preview);

  final registry = RouteRegistry();

  final environmentVariableIsGod = Platform.environment['TFC_GOD'] == 'true';

  registry.addMenuItem(const MenuItem(label: 'Home', path: '/', icon: Icons.home));

  registry.addMenuItem(const MenuItem(label: 'Alarm View', path: '/alarm-view', icon: Icons.alarm));

  // This is not ideal, if a second HMI adds a page, we will need to restart the app twice
  final prefs = SharedPreferencesWrapper(SharedPreferencesAsync());
  final pageManager = PageManager(pages: {}, prefs: prefs);
  await pageManager.load();

  // Sort pages by navigationPriority first, then map to menu items
  final sortedPages = pageManager.pages.values.toList()
    ..sort((a, b) => (a.navigationPriority ?? 0).compareTo(b.navigationPriority ?? 0));
  final extraMenuItems = sortedPages.map((page) => page.menuItem).toList();

  for (final menuItem in extraMenuItems) {
    registry.addMenuItem(menuItem);
  }

  registry.addMenuItem(
    MenuItem(
      label: 'Advanced',
      path: '/advanced',
      icon: Icons.settings,
      children: [
        MenuItem(label: 'IP Settings', path: '/advanced/ip-settings', icon: Icons.settings_ethernet),
        if (environmentVariableIsGod) MenuItem(label: 'Page Editor', path: '/advanced/page-editor', icon: Icons.edit),
        if (environmentVariableIsGod)
          MenuItem(label: 'Preferences', path: '/advanced/preferences', icon: Icons.settings),
        if (environmentVariableIsGod)
          MenuItem(label: 'Alarm Editor', path: '/advanced/alarm-editor', icon: Icons.alarm),
        MenuItem(label: 'History View', path: '/advanced/history-view', icon: Icons.history),
        MenuItem(label: 'Server Config', path: '/advanced/server-config', icon: FontAwesomeIcons.server),
      ],
    ),
  );

  final locationBuilder = createLocationBuilder(extraMenuItems);

  runApp(ProviderScope(child: MyApp(locationBuilder: locationBuilder)));
}

Completer<DBusClient> dbusCompleter = Completer();

RoutesLocationBuilder createLocationBuilder(List<MenuItem> extraMenuItems) {
  final routes = {
    // '/': (context, state, args) => BeamPage(
    //       // this will be replaced most likely
    //       key: const ValueKey('/'),
    //       title: 'Home',
    //       child: Consumer(
    //         builder: (context, ref, _) {
    //           return AssetView(
    //             pageName: 'Home',
    //           );
    //         },
    //       ),
    //     ),
    '/advanced/ip-settings': (context, state, args) => BeamPage(
          key: const ValueKey('/advanced/ip-settings'),
          title: 'IP Settings',
          child: Consumer(
            builder: (context, ref, _) {
              // I dont like this but lets continue
              return FutureBuilder<DBusClient>(
                future: dbusCompleter.future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return BaseScaffold(
                      title: 'IP Settings',
                      body: Center(
                        child: LoginForm(
                          onLoginSuccess: (newDbusClient) async {
                            logger.i('Login successful');
                            await Future.delayed(const Duration(milliseconds: 100));
                            dbusCompleter.complete(newDbusClient);
                          },
                        ),
                      ),
                    );
                  }
                  return IpSettingsPage(dbusClient: snapshot.data!);
                },
              );
            },
          ),
        ),
    '/advanced/page-editor': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/page-editor'), title: 'Page Editor', child: PageEditor()),
    '/advanced/preferences': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/preferences'), title: 'Preferences', child: PreferencesPage()),
    '/advanced/alarm-editor': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/alarm-editor'), title: 'Alarm Editor', child: AlarmEditorPage()),
    '/advanced/history-view': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/history-view'), title: 'History View', child: HistoryViewPage()),
    '/advanced/server-config': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/server-config'), title: 'Server Config', child: ServerConfigPage()),
    '/alarm-view': (context, state, args) =>
        BeamPage(key: const ValueKey('/alarm-view'), title: 'Alarm View', child: AlarmViewPage()),
  };

  addRoute(MenuItem menuItem) {
    if (menuItem.path == null) {
      return;
    }
    if (menuItem.children.isEmpty) {
      routes[menuItem.path!] = (context, state, args) => BeamPage(
            key: ValueKey(menuItem.path!),
            title: menuItem.label,
            child: Consumer(
              builder: (context, ref, _) {
                return AssetView(pageName: menuItem.label);
              },
            ),
          );
      return;
    }
    // Currently only supports one child per parent
    addRoute(menuItem.children.first);
  }

  for (final menuItem in extraMenuItems) {
    addRoute(menuItem);
  }

  return RoutesLocationBuilder(routes: routes);
}

class MyApp extends ConsumerWidget {
  MyApp({super.key, required RoutesLocationBuilder locationBuilder})
      : routerDelegate = BeamerDelegate(
          notFoundPage: const BeamPage(child: PageNotFound()),
          transitionDelegate: MyNoAnimationTransitionDelegate(),
          locationBuilder: (routeInformation, context) => locationBuilder(routeInformation, context),
        );

  final BeamerDelegate routerDelegate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeNotifierProvider);
    final (light, dark) = solarized();

    final app = MaterialApp.router(
      title: 'Síldarvinnslan',
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

    return BeamerProvider(routerDelegate: routerDelegate, child: app);
  }
}

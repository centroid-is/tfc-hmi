// example/lib/main.dart
import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import 'package:tfc_hmi/route_registry.dart';
import 'package:tfc_hmi/models/menu_item.dart';
import 'package:tfc_hmi/auto_location.dart';
import 'pages/pages.dart';
// import 'pages/settings_page.dart';
// import 'pages/profile_settings_page.dart';
// import 'pages/privacy_page.dart';
// import 'pages/controls_page.dart';
// import 'pages/volume_page.dart';
// import 'pages/brightness_page.dart';

void main() {
  // Initialize the RouteRegistry
  final registry = RouteRegistry();

  // Register routes
  registry.registerRoute('/', (context) => HomePage());
  registry.registerRoute('/settings', (context) => SettingsPage());
  registry.registerRoute(
      '/settings/profile', (context) => ProfileSettingsPage());
  registry.registerRoute('/settings/privacy', (context) => PrivacyPage());
  registry.registerRoute('/controls', (context) => ControlsPage());
  registry.registerRoute('/controls/volume', (context) => VolumePage());
  registry.registerRoute('/controls/brightness', (context) => BrightnessPage());

  // Define navigation items
  registry.addStandardMenuItem(MenuItem(
    label: 'Home',
    path: '/',
    icon: Icons.home,
    hoverText: 'Home',
  ));

  registry.addDropdownMenuItem(MenuItem(
    label: 'Settings',
    path: '/settings',
    icon: Icons.settings,
    hoverText: 'Settings',
    children: [
      MenuItem(
        label: 'Profile',
        path: '/settings/profile',
        icon: Icons.person,
        hoverText: 'Profile Settings',
      ),
      MenuItem(
        label: 'Privacy',
        path: '/settings/privacy',
        icon: Icons.lock,
        hoverText: 'Privacy Settings',
      ),
    ],
  ));

  registry.addStandardMenuItem(MenuItem(
    label: 'Controls',
    path: '/controls',
    icon: Icons.tune,
    hoverText: 'Controls',
  ));

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final routerDelegate = BeamerDelegate(
    locationBuilder: (routeInformation, _) => AutoLocation(),
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

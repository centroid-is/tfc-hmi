// example/lib/pages/home_page.dart
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Home Page'),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Settings Page'),
    );
  }
}

class ProfileSettingsPage extends StatelessWidget {
  const ProfileSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Profile Settings Page'),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Privacy Page'),
    );
  }
}

class ControlsPage extends StatelessWidget {
  const ControlsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Controls Page'),
    );
  }
}

class VolumePage extends StatelessWidget {
  const VolumePage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Volume Page'),
    );
  }
}

class BrightnessPage extends StatelessWidget {
  const BrightnessPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Brightness Page'),
    );
  }
}



  // registry.registerRoute(
  //     '/settings/profile', (context) => ProfileSettingsPage());
  // registry.registerRoute('/settings/privacy', (context) => PrivacyPage());
  // registry.registerRoute('/controls', (context) => ControlsPage());
  // registry.registerRoute('/controls/volume', (context) => VolumePage());
  // registry.registerRoute('/controls/brightness', (context) => BrightnessPage());

// Repeat for other pages like ProfileSettingsPage, PrivacyPage, ControlsPage, etc.

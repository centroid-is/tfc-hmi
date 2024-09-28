import 'package:flutter/material.dart';
import 'package:tfc_hmi/widgets/base_scaffold.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Home Page',
      body: Center(
        child: Text('Home Page'),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Settings Page',
      body: Center(
        child: Text('Settings Page'),
      ),
    );
  }
}

class ProfileSettingsPage extends StatelessWidget {
  const ProfileSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Profile Settings Page',
      body: Center(
        child: Text('Profile Settings Page'),
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Privacy Page',
      body: Center(
        child: Text('Privacy Page'),
      ),
    );
  }
}

class ControlsPage extends StatelessWidget {
  const ControlsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Controls Page',
      body: Center(
        child: Text('Controls Page'),
      ),
    );
  }
}

class VolumePage extends StatelessWidget {
  const VolumePage({super.key});
  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Volume Page',
      body: Center(
        child: Text('Volume Page'),
      ),
    );
  }
}

class BrightnessPage extends StatelessWidget {
  const BrightnessPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Brightness Page',
      body: Center(
        child: Text('Brightness Page'),
      ),
    );
  }
}

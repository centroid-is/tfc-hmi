import 'package:flutter/material.dart';
import 'package:tfc/widgets/base_scaffold.dart';
import 'package:tfc/painter/fish/trout.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Home Page',
      body: Container(
          child: Center(
        child: TroutWidget(size: 200),
        // Text('Home Page', style: Theme.of(context).textTheme.displayLarge),
      )),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Settings Page',
      body: Container(
        child: Center(
            child: Text('Settings Page',
                style: Theme.of(context).textTheme.displayLarge)),
      ),
    );
  }
}

class ProfileSettingsPage extends StatelessWidget {
  const ProfileSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Profile Settings Page',
      body: Container(
        child: const Center(
          child: Text(
            'Profile Settings Page',
          ),
        ),
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Privacy Page',
      body: Container(
        child: const Center(
          child: Text(
            'Privacy Page',
          ),
        ),
      ),
    );
  }
}

class VolumePage extends StatelessWidget {
  const VolumePage({super.key});
  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Volume Page',
      body: Container(
        child: const Center(
          child: Text(
            'Volume Page',
          ),
        ),
      ),
    );
  }
}

class BrightnessPage extends StatelessWidget {
  const BrightnessPage({super.key});
  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Brightness Page',
      body: Container(
        child: const Center(
          child: Text(
            'Brightness Page',
          ),
        ),
      ),
    );
  }
}

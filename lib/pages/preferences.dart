import 'package:flutter/material.dart';
import '../widgets/preferences.dart';
import '../widgets/base_scaffold.dart';

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'Preferences',
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: PreferencesWidget(),
      ),
    );
  }
}

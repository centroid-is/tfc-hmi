import 'package:flutter/material.dart';
import '../widgets/preferences.dart';
import '../widgets/base_scaffold.dart';

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
        title: 'Preferences',
        body: ListView(
          padding: const EdgeInsets.all(0),
          children: [
            const DatabaseConfigWidget(),
            const SizedBox(height: 16),
            const McpServerSection(),
            const SizedBox(height: 16),
            SizedBox(height: 600, child: const PreferencesKeysWidget()),
          ],
        ));
  }
}

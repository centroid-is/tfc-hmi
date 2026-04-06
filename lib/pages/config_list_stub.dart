/// Web stub for config_list.dart.
/// Loaded via conditional import on web where dbus is unavailable.
library;
import 'package:flutter/material.dart';

class ConfigListPage extends StatelessWidget {
  final dynamic dbusClient;

  const ConfigListPage({super.key, required this.dbusClient});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Not available on web'));
  }
}

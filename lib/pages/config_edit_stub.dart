/// Web stub for config_edit.dart.
/// Loaded via conditional import on web where dbus is unavailable.
library;
import 'package:flutter/material.dart';

class ConfigEditDialog extends StatelessWidget {
  final dynamic dbusClient;
  final String serviceName;
  final String objectPath;

  const ConfigEditDialog({
    super.key,
    required this.dbusClient,
    required this.serviceName,
    required this.objectPath,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Not available on web'));
  }
}

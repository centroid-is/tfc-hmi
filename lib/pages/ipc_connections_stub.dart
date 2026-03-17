/// Web stub for ipc_connections.dart.
/// Loaded via conditional import on web where dbus is unavailable.
library;
import 'package:flutter/material.dart';

class ConnectionsPage extends StatelessWidget {
  final dynamic dbusClient;

  const ConnectionsPage({super.key, required this.dbusClient});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Not available on web'));
  }
}

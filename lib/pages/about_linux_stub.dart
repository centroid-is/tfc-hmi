/// Web stub for about_linux.dart.
/// Loaded via conditional import on web where dbus/nm are unavailable.
library;
import 'package:flutter/material.dart';

class AboutLinuxPage extends StatelessWidget {
  final dynamic dbusClient;

  const AboutLinuxPage({super.key, this.dbusClient});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Not available on web'));
  }
}

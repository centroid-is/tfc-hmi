/// Web stub for dbus_login.dart.
/// Loaded via conditional import on web where dbus/dartssh2 are unavailable.
library;
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class LoginForm extends StatelessWidget {
  final void Function(dynamic) onLoginSuccess;
  final bool showLogo;
  final double? width;

  const LoginForm({
    super.key,
    required this.onLoginSuccess,
    this.showLogo = true,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Not available on web'));
  }
}

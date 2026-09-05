/// Supplies a [DBusClient] to the pages that need one.
///
/// The login form these pages used to open with is a *bus selector*, not an
/// authenticator: `ConnectionType.system` calls `DBusClient.system()`, which
/// opens the bind-mounted socket and asks for no credentials at all. Only
/// `ConnectionType.remote` — SSH to another machine — genuinely needs any.
///
/// So on a station that has never been configured for a remote bus, the form
/// stood between the operator and read-only information they were always
/// entitled to see: the hostname, the IP addresses, and now whether the clock
/// is synchronised. This gate connects to the local bus directly in that case
/// and shows the form only when it is actually load-bearing.
///
/// Authorisation still applies where it should — polkit checks every setter
/// regardless of how the client connected.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';

import '../pages/dbus_login.dart';
import 'base_scaffold.dart';

/// Whether the gate can skip the login form.
///
/// Saved credentials win: an operator who configured a remote bus, with or
/// without auto-login, means to keep using it, and silently connecting to the
/// local one instead would quietly point the page at the wrong machine.
bool shouldConnectSystemBus({
  required bool hasSystemBus,
  required bool hasSavedCredentials,
}) =>
    hasSystemBus && !hasSavedCredentials;

/// Reads whether a remote bus has been configured on this station.
///
/// Deliberately only looks for a host: [ConnectionType] defaults to `remote`
/// in the login form's own loader even on a station that has never been
/// touched, so the type alone would make every station look configured.
Future<bool> hasSavedDbusCredentials() async {
  try {
    final credentials = await loadSavedDbusCredentials();
    return credentials.type == ConnectionType.remote &&
        (credentials.host?.isNotEmpty ?? false);
  } catch (_) {
    // Unreadable preferences must not strand the page behind a form.
    return false;
  }
}

class DbusGate extends StatefulWidget {
  /// Shown on the scaffold while connecting or while asking for credentials.
  final String title;

  /// Builds the page. [switchConnection] lets it offer a way back to the
  /// login form; without it, auto-connecting would make a remote bus
  /// unreachable on a station that has no saved credentials.
  final Widget Function(
    BuildContext context,
    DBusClient client,
    VoidCallback switchConnection,
  ) builder;

  /// Process-wide cache so the two pages that use a bus share one connection
  /// and one login.
  final Completer<DBusClient> shared;

  /// Test seams.
  final Future<DBusClient> Function()? connectSystemBus;
  final Future<bool> Function()? hasSavedCredentials;

  const DbusGate({
    super.key,
    required this.title,
    required this.builder,
    required this.shared,
    this.connectSystemBus,
    this.hasSavedCredentials,
  });

  @override
  State<DbusGate> createState() => _DbusGateState();
}

class _DbusGateState extends State<DbusGate> {
  DBusClient? _client;

  /// Set when the operator asked for the form explicitly, so a successful
  /// auto-connect does not immediately dismiss it again.
  bool _forceLogin = false;

  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    if (widget.shared.isCompleted) {
      final client = await widget.shared.future;
      if (mounted) {
        setState(() {
          _client = client;
          _connecting = false;
        });
      }
      return;
    }

    final hasSaved = await (widget.hasSavedCredentials ?? hasSavedDbusCredentials)();
    final connect = widget.connectSystemBus ?? _systemBus;

    if (!shouldConnectSystemBus(
      hasSystemBus: widget.connectSystemBus != null || Platform.isLinux,
      hasSavedCredentials: hasSaved,
    )) {
      if (mounted) setState(() => _connecting = false);
      return;
    }

    try {
      final client = await connect();
      if (!widget.shared.isCompleted) widget.shared.complete(client);
      if (mounted) {
        setState(() {
          _client = client;
          _connecting = false;
        });
      }
    } catch (e) {
      // No socket, or a bus that will not talk to us: fall back to the form,
      // which can at least reach another machine.
      if (mounted) {
        setState(() {
          _error = e.toString();
          _connecting = false;
        });
      }
    }
  }

  static Future<DBusClient> _systemBus() async {
    final client = DBusClient.system();
    // Prove the socket is really there; constructing the client alone does
    // not connect, so a broken mount would surface as a failure deep inside
    // the page instead of here.
    await client.ping().timeout(const Duration(seconds: 5));
    return client;
  }

  void _switchConnection() => setState(() {
        _forceLogin = true;
        _client = null;
      });

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return BaseScaffold(
        title: widget.title,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final client = _client;
    if (client != null && !_forceLogin) {
      return widget.builder(context, client, _switchConnection);
    }

    return BaseScaffold(
      title: widget.title,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Could not reach the local system bus: $_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            LoginForm(
              onLoginSuccess: (client) async {
                if (!widget.shared.isCompleted) widget.shared.complete(client);
                if (mounted) {
                  setState(() {
                    _client = client;
                    _forceLogin = false;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

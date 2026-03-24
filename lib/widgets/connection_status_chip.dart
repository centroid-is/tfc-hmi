import 'package:flutter/material.dart';
import 'package:tfc_dart/core/state_man.dart' show ConnectionStatus;

/// A pill-shaped chip that displays connection status with color coding.
///
/// Used by OPC UA, JBTM, and Modbus server config cards to show whether
/// the server is connected, connecting, disconnected, or not yet active.
class ConnectionStatusChip extends StatelessWidget {
  final ConnectionStatus? status;
  final bool stateManLoading;

  const ConnectionStatusChip({
    super.key,
    required this.status,
    this.stateManLoading = false,
  });

  Color _color() {
    if (status == null) {
      return stateManLoading ? Colors.orange : Colors.grey;
    }
    return switch (status!) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting => Colors.orange,
      ConnectionStatus.disconnected => Colors.red,
    };
  }

  String _label() {
    if (status == null) {
      return stateManLoading ? 'Loading...' : 'Not active';
    }
    return switch (status!) {
      ConnectionStatus.connected => 'Connected',
      ConnectionStatus.connecting => 'Connecting...',
      ConnectionStatus.disconnected => 'Disconnected',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final label = _label();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

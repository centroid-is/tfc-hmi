import 'dart:async';

import 'msocket.dart';

/// Per-device connection health metrics.
///
/// Tracks uptime (time since last connected), reconnect count, and
/// records-per-second throughput for downstream monitoring.
///
/// Usage:
/// ```dart
/// final metrics = ConnectionHealthMetrics(socket);
/// print(metrics.uptime);            // Duration since last connected
/// print(metrics.reconnectCount);    // Number of reconnections
/// print(metrics.recordsPerSecond);  // Throughput in last 1s window
/// metrics.notifyRecord();           // Call when a record is received
/// metrics.dispose();                // Clean up when done
/// ```
class ConnectionHealthMetrics {
  final MSocket _socket;
  StreamSubscription<ConnectionStatus>? _statusSub;

  DateTime? _lastConnectedAt;
  int _reconnectCount = 0;
  bool _firstConnected = false;
  bool _isConnected = false;

  /// Rolling window of record receipt timestamps for throughput calculation.
  final List<DateTime> _recordTimestamps = [];

  /// Create health metrics that track the given [socket]'s connection status.
  ConnectionHealthMetrics(this._socket) {
    _statusSub = _socket.statusStream.listen(_onStatus);
  }

  void _onStatus(ConnectionStatus status) {
    if (status == ConnectionStatus.connected) {
      _lastConnectedAt = DateTime.now();
      _isConnected = true;
      if (_firstConnected) {
        // This is a reconnection (not the very first connect)
        _reconnectCount++;
      } else {
        _firstConnected = true;
      }
    } else if (status == ConnectionStatus.disconnected) {
      _isConnected = false;
    }
  }

  /// Duration since last connected. Returns [Duration.zero] when disconnected.
  Duration get uptime {
    if (!_isConnected || _lastConnectedAt == null) return Duration.zero;
    return DateTime.now().difference(_lastConnectedAt!);
  }

  /// Number of reconnections (first connect is not counted).
  int get reconnectCount => _reconnectCount;

  /// Throughput: number of records received in the last 1-second window.
  double get recordsPerSecond {
    _pruneOldTimestamps();
    return _recordTimestamps.length.toDouble();
  }

  /// Call this when a record is received to update throughput tracking.
  void notifyRecord() {
    _recordTimestamps.add(DateTime.now());
  }

  /// Prune timestamps older than 1 second.
  void _pruneOldTimestamps() {
    final cutoff = DateTime.now().subtract(Duration(seconds: 1));
    _recordTimestamps.removeWhere((t) => t.isBefore(cutoff));
  }

  /// Clean up: cancel status subscription.
  void dispose() {
    _statusSub?.cancel();
    _statusSub = null;
  }
}

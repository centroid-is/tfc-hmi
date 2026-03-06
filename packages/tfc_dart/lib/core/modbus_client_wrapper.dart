import 'dart:async';

import 'package:logger/logger.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:rxdart/rxdart.dart';

import 'state_man.dart' show ConnectionStatus;

/// Wraps [ModbusClientTcp] with persistent connection lifecycle management:
/// auto-reconnect with exponential backoff, BehaviorSubject status streaming,
/// connect/disconnect/dispose lifecycle, and factory injection for testability.
///
/// Follows the MSocket connection loop pattern from jbtm.
class ModbusClientWrapper {
  final String host;
  final int port;
  final int unitId;
  final ModbusClientTcp Function(String host, int port, int unitId)
      _clientFactory;

  final _status =
      BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.disconnected);

  ModbusClientTcp? _client;

  /// When true the connection loop exits at the next check point.
  bool _stopped = true;

  /// Terminal flag -- once disposed, the wrapper cannot be reused.
  bool _disposed = false;

  static const _initialBackoff = Duration(milliseconds: 500);
  static const _maxBackoff = Duration(seconds: 5);
  Duration _backoff = _initialBackoff;

  static final _log = Logger(
    printer: SimplePrinter(),
    level: Level.info,
  );

  /// Creates a wrapper for a Modbus device at [host]:[port] with [unitId].
  ///
  /// Provide [clientFactory] to inject a custom/mock ModbusClientTcp for
  /// testing. The default factory creates a real ModbusClientTcp with
  /// [ModbusConnectionMode.doNotConnect] so the wrapper owns the connection
  /// loop.
  ModbusClientWrapper(
    this.host,
    this.port,
    this.unitId, {
    ModbusClientTcp Function(String, int, int)? clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultFactory;

  static ModbusClientTcp _defaultFactory(String host, int port, int unitId) {
    return ModbusClientTcp(
      host,
      serverPort: port,
      unitId: unitId,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 3),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Current connection status (synchronous).
  ConnectionStatus get connectionStatus => _status.value;

  /// Connection status stream with replay of current value to new subscribers.
  Stream<ConnectionStatus> get connectionStream => _status.stream;

  /// The underlying Modbus client, if connected. Null when disconnected.
  ModbusClientTcp? get client => _client;

  /// Starts the connection loop (fire-and-forget). The loop runs until
  /// [disconnect] or [dispose] is called. Status changes are emitted via
  /// [connectionStream].
  void connect() {
    if (_disposed) return;
    _stopped = false;
    _connectionLoop();
  }

  /// Stops the reconnect loop and disconnects the client. The wrapper can be
  /// reconnected by calling [connect] again. Streams remain open.
  void disconnect() {
    _stopped = true;
    _cleanupClient();
  }

  /// Terminal shutdown -- stops reconnect, disconnects, and closes all streams.
  /// The wrapper cannot be reused after dispose.
  void dispose() {
    _stopped = true;
    _disposed = true;
    _cleanupClient();
    if (!_status.isClosed) {
      _status.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Connection loop (follows MSocket._connectionLoop pattern)
  // ---------------------------------------------------------------------------

  Future<void> _connectionLoop() async {
    while (!_stopped) {
      if (!_status.isClosed) {
        _status.add(ConnectionStatus.connecting);
      }

      try {
        _client = _clientFactory(host, port, unitId);
        final connected = await _client!.connect();

        if (_stopped) {
          await _cleanupClientInstance();
          break;
        }

        if (!connected) {
          throw StateError('connect() returned false');
        }

        // Connected successfully
        if (!_status.isClosed) {
          _status.add(ConnectionStatus.connected);
        }
        _backoff = _initialBackoff;

        // Block until connection drops or stopped
        await _awaitDisconnect();
      } catch (e) {
        _log.i('ModbusClientWrapper($host:$port) connection error: $e');
      }

      // Socket is gone -- clean up
      await _cleanupClientInstance();
      if (!_stopped && !_status.isClosed) {
        _status.add(ConnectionStatus.disconnected);
      }
      if (_stopped) break;

      // Exponential backoff delay
      await Future.delayed(_backoff);
      if (_stopped) break;
      _backoff = _clampDuration(_backoff * 2, Duration.zero, _maxBackoff);
    }
  }

  /// Polls [_client.isConnected] until the connection drops or [_stopped] is
  /// set. Returns when disconnect is detected.
  Future<void> _awaitDisconnect() async {
    while (!_stopped && _client != null && _client!.isConnected) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Disconnects and nulls out the current client instance.
  Future<void> _cleanupClientInstance() async {
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {
        // Ignore errors during cleanup
      }
    }
  }

  /// Stops the client and emits disconnected status if appropriate.
  void _cleanupClient() {
    _cleanupClientInstance();
    if (!_status.isClosed &&
        _status.value != ConnectionStatus.disconnected) {
      _status.add(ConnectionStatus.disconnected);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Duration _clampDuration(
      Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

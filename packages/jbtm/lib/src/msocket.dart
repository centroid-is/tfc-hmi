import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';

/// Connection status for [MSocket].
enum ConnectionStatus { connected, connecting, disconnected }

/// A protocol-agnostic TCP socket with SO_KEEPALIVE and auto-reconnect.
///
/// Connects to a TCP server, streams raw bytes as [Uint8List], configures
/// SO_KEEPALIVE for fast disconnect detection, and exposes connection status.
///
/// Usage:
/// ```dart
/// final socket = MSocket('192.168.1.100', 4001);
/// socket.connect();
/// socket.dataStream.listen((data) => print(data));
/// socket.statusStream.listen((status) => print(status));
/// // When done:
/// socket.dispose();
/// ```
class MSocket {
  /// The host to connect to.
  final String host;

  /// The port to connect to.
  final int port;

  final _logger = Logger();

  final _status =
      BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.disconnected);
  final _dataController = StreamController<Uint8List>.broadcast();

  Socket? _socket;
  bool _disposed = false;

  static const _initialBackoff = Duration(milliseconds: 500);
  static const _maxBackoff = Duration(seconds: 5);
  Duration _backoff = _initialBackoff;

  MSocket(this.host, this.port);

  /// Raw byte stream. Lives for the lifetime of MSocket.
  /// Pauses during disconnect, resumes on reconnect.
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// Connection status with replay. New listeners get current state.
  Stream<ConnectionStatus> get statusStream => _status.stream;

  /// Current status (synchronous).
  ConnectionStatus get status => _status.value;

  /// Start the connection loop. Returns immediately.
  /// Status transitions visible via [statusStream].
  void connect() {
    _disposed = false;
    _connectionLoop();
  }

  /// Force-close socket, cancel reconnect timer. Terminal operation.
  void dispose() {
    _disposed = true;
    _destroySocket();
    _dataController.close();
    _status.close();
  }

  Future<void> _connectionLoop() async {
    while (!_disposed) {
      if (!_status.isClosed) _status.add(ConnectionStatus.connecting);
      try {
        _socket = await Socket.connect(host, port,
            timeout: const Duration(seconds: 3));
        if (_disposed) {
          _destroySocket();
          break;
        }
        _configureKeepalive(_socket!);
        _socket!.setOption(SocketOption.tcpNoDelay, true);
        if (!_status.isClosed) _status.add(ConnectionStatus.connected);
        _backoff = _initialBackoff;

        // Forward data to the long-lived data stream.
        // Use a Completer to track when the socket stream ends.
        final done = Completer<void>();
        _socket!.listen(
          (data) {
            if (!_disposed && !_dataController.isClosed) {
              _dataController.add(data);
            }
          },
          onError: (Object e) {
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
        await done.future;
      } catch (e) {
        if (!_disposed) {
          _logger.e('Connection error: $e');
        }
      }

      // Socket is gone -- clean up
      _destroySocket();
      if (!_disposed && !_status.isClosed) {
        _status.add(ConnectionStatus.disconnected);
      }
      if (_disposed) break;
      await Future.delayed(_backoff);
      if (_disposed) break;
      _backoff = _clampDuration(_backoff * 2, Duration.zero, _maxBackoff);
    }
  }

  /// Configure SO_KEEPALIVE with platform-specific constants.
  ///
  /// Values: idle=5s, interval=2s, count=3 (~11s detection).
  /// Reference: centroid-is/postgresql-dart PR #1.
  void _configureKeepalive(Socket socket) {
    try {
      if (Platform.isMacOS || Platform.isIOS) {
        // macOS/iOS: SOL_SOCKET level, SO_KEEPALIVE=0x0008
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelSocket, 0x0008, 1));
        // IPPROTO_TCP=6, TCP_KEEPALIVE=0x10 (idle time in seconds)
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelTcp, 0x10, 5));
        // TCP_KEEPINTVL=0x101 (interval between probes in seconds)
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelTcp, 0x101, 2));
        // TCP_KEEPCNT=0x102 (number of probes before declaring dead)
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelTcp, 0x102, 3));
      } else if (Platform.isWindows) {
        // Windows: SOL_SOCKET level, SO_KEEPALIVE=0x0008
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelSocket, 0x0008, 1));
        // Windows 10 1709+ supports fine-grained keepalive options.
        // Older versions fall back to SO_KEEPALIVE with OS defaults.
        try {
          // TCP_KEEPIDLE=3 (idle time in seconds)
          socket.setRawOption(
              RawSocketOption.fromInt(RawSocketOption.levelTcp, 3, 5));
          // TCP_KEEPINTVL=17 (interval between probes in seconds)
          socket.setRawOption(
              RawSocketOption.fromInt(RawSocketOption.levelTcp, 17, 2));
          // TCP_KEEPCNT=16 (number of probes before declaring dead)
          socket.setRawOption(
              RawSocketOption.fromInt(RawSocketOption.levelTcp, 16, 3));
        } on SocketException {
          // Older Windows versions don't support fine-grained keepalive
          // options. SO_KEEPALIVE is still enabled with OS defaults.
        }
      } else if (Platform.isLinux || Platform.isAndroid) {
        // Linux/Android: SOL_SOCKET level, SO_KEEPALIVE=0x0009
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelSocket, 0x0009, 1));
        // IPPROTO_TCP=6, TCP_KEEPIDLE=4 (idle time in seconds)
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelTcp, 4, 5));
        // TCP_KEEPINTVL=5 (interval between probes in seconds)
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelTcp, 5, 2));
        // TCP_KEEPCNT=6 (number of probes before declaring dead)
        socket.setRawOption(
            RawSocketOption.fromInt(RawSocketOption.levelTcp, 6, 3));
      }
    } catch (e) {
      _logger.w('Failed to configure keepalive: $e');
    }
  }

  void _destroySocket() {
    _socket?.destroy();
    _socket = null;
  }

  /// Clamp a [Duration] between [min] and [max].
  static Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

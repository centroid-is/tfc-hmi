import 'dart:async';
import 'dart:io';

/// A reusable TCP test server for unit testing socket-based classes.
///
/// Binds to loopback on an OS-assigned port. Tracks connected clients,
/// allows sending data to all clients, and supports programmatic disconnect
/// to simulate device reboots.
class TestTcpServer {
  /// Optional callback invoked when a new client connects.
  final void Function(Socket client)? onConnect;

  ServerSocket? _server;
  final List<Socket> _clients = [];
  Completer<void>? _clientCompleter;

  TestTcpServer({this.onConnect});

  /// Starts the server. Returns the OS-assigned port number.
  Future<int> start() async {
    _server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((socket) {
      _clients.add(socket);
      // Catch errors on the IOSink done future to prevent unhandled
      // async errors when the client destroys the connection (RST).
      socket.done.catchError((_) {}).whenComplete(() {
        _clients.remove(socket);
      });
      onConnect?.call(socket);
      _clientCompleter?.complete();
      _clientCompleter = null;
    });
    return _server!.port;
  }

  /// The port the server is listening on.
  int get port => _server!.port;

  /// Number of currently connected clients.
  int get clientCount => _clients.length;

  /// Send raw bytes to all connected clients.
  void sendToAll(List<int> data) {
    for (final client in List.of(_clients)) {
      try {
        client.add(data);
      } catch (_) {
        // Client may already be destroyed
      }
    }
  }

  /// Wait for the next client connection.
  ///
  /// Completes immediately if a client connects, or waits until one does.
  Future<void> waitForClient() {
    if (_clients.isNotEmpty) return Future.value();
    _clientCompleter ??= Completer<void>();
    return _clientCompleter!.future;
  }

  /// Disconnect all clients (simulates device reboot).
  void disconnectAll() {
    for (final client in List.of(_clients)) {
      client.destroy();
    }
    _clients.clear();
  }

  /// Fully shut down the server. Safe to call even if [start] was never called.
  Future<void> shutdown() async {
    disconnectAll();
    await _server?.close();
  }
}

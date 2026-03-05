import 'dart:async';
import 'dart:io';

/// TCP proxy for testing network disruption scenarios.
///
/// Uses port 0 (OS-assigned) to avoid port conflicts between tests.
///
/// Features:
/// - [bufferServerToClient]: buffer server->client responses while still
///   forwarding client->server traffic (keeps the server-side connection alive).
/// - [reject]: destroy existing connections and reject new ones instantly.
///   The ServerSocket stays open so the client gets an immediate RST on all
///   platforms (unlike closing the socket, which causes a slow connect-timeout
///   on Windows instead of ECONNREFUSED).
class TcpProxy {
  final int listenPort;
  final int targetPort;
  ServerSocket? _server;
  final List<_Pair> _pairs = [];
  bool _rejecting = false;

  /// When true, server->client traffic is buffered (not forwarded).
  /// Client->server traffic is always forwarded (keeps the server-side
  /// subscription alive). Use [flush] to release buffered responses.
  bool bufferServerToClient = false;

  TcpProxy({this.listenPort = 0, required this.targetPort});

  /// The actual port after [start] (OS-assigned when [listenPort] is 0).
  int get port => _server!.port;

  bool get isRunning => _server != null && !_rejecting;

  Future<void> start() async {
    _rejecting = false;
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, listenPort);
    _server!.listen(_handleConnection);
  }

  void _handleConnection(Socket clientSocket) async {
    if (_rejecting) {
      try {
        clientSocket.destroy();
      } catch (_) {}
      return;
    }
    try {
      final serverSocket = await Socket.connect(
          InternetAddress.loopbackIPv4, targetPort,
          timeout: Duration(seconds: 5));
      if (_rejecting) {
        try {
          clientSocket.destroy();
        } catch (_) {}
        try {
          serverSocket.destroy();
        } catch (_) {}
        return;
      }
      final pair = _Pair(clientSocket, serverSocket, this);
      _pairs.add(pair);
      pair.start(() => _pairs.remove(pair));
    } catch (e) {
      try {
        clientSocket.destroy();
      } catch (_) {}
    }
  }

  /// Flush all buffered server->client responses.
  void flush() {
    for (final p in _pairs) {
      p.flushBuffer();
    }
  }

  /// Reject mode: destroy existing connections and reject new ones instantly.
  /// The ServerSocket stays open so the client gets an immediate RST
  /// (not a slow connect-timeout on Windows).
  Future<void> reject() async {
    _rejecting = true;
    for (final conn in List.of(_pairs)) {
      conn.close();
    }
    _pairs.clear();
    await Future.delayed(Duration(milliseconds: 100));
    for (final conn in List.of(_pairs)) {
      conn.close();
    }
    _pairs.clear();
  }

  /// Fully shut down (for tearDown).
  Future<void> shutdown() async {
    _rejecting = true;
    final s = _server;
    _server = null;
    await s?.close();
    for (final conn in List.of(_pairs)) {
      conn.close();
    }
    _pairs.clear();
  }
}

class _Pair {
  final Socket client;
  final Socket server;
  final TcpProxy proxy;
  StreamSubscription? _clientSub;
  StreamSubscription? _serverSub;
  bool _closed = false;
  final List<List<int>> _serverBuffer = [];

  _Pair(this.client, this.server, this.proxy);

  void start(void Function() onClose) {
    client.done.catchError((_) {});
    server.done.catchError((_) {});
    _clientSub = client.listen(
      (data) {
        // Client->server always forwarded
        try {
          server.add(data);
        } catch (_) {}
      },
      onDone: () => _doClose(onClose),
      onError: (_) => _doClose(onClose),
    );
    _serverSub = server.listen(
      (data) {
        if (proxy.bufferServerToClient) {
          _serverBuffer.add(List.from(data));
        } else {
          try {
            client.add(data);
          } catch (_) {}
        }
      },
      onDone: () => _doClose(onClose),
      onError: (_) => _doClose(onClose),
    );
  }

  void flushBuffer() {
    if (_closed || _serverBuffer.isEmpty) return;
    for (final data in _serverBuffer) {
      try {
        client.add(data);
      } catch (_) {}
    }
    _serverBuffer.clear();
  }

  void _doClose(void Function() onClose) {
    if (_closed) return;
    close();
    onClose();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _clientSub?.cancel();
    _serverSub?.cancel();
    try {
      client.destroy();
    } catch (_) {}
    try {
      server.destroy();
    } catch (_) {}
  }
}

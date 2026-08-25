import 'dart:async';
import 'dart:io';

/// TCP proxy for testing network disruption scenarios.
///
/// Uses port 0 (OS-assigned) to avoid port conflicts between tests.
///
/// Features:
/// - [bufferServerToClient]: buffer server→client responses while still
///   forwarding client→server traffic (keeps the server-side connection alive).
/// - [reject]: destroy existing connections and reject new ones instantly.
///   The ServerSocket stays open so the client gets an immediate RST on all
///   platforms (unlike closing the socket, which causes a slow connect-timeout
///   on Windows instead of ECONNREFUSED).
class TcpProxy {
  final int listenPort;
  final int targetPort;
  ServerSocket? _server;
  final List<_Pair> _pairs = [];
  final List<Socket> _blackholed = [];
  bool _rejecting = false;
  bool _frozen = false;

  /// When true, server→client traffic is buffered (not forwarded).
  /// Client→server traffic is always forwarded (keeps the server-side
  /// subscription alive). Use [flush] to release buffered responses.
  bool bufferServerToClient = false;

  TcpProxy({this.listenPort = 0, required this.targetPort});

  /// The actual port after [start] (OS-assigned when [listenPort] is 0).
  int get port => _server!.port;

  /// Client/server socket pairs the proxy is still holding open.
  ///
  /// Every connection to Postgres in these tests is really the proxy's own
  /// upstream socket, so `pg_stat_activity` counts pairs, not client sockets.
  /// That makes this the difference between "the client never closed" and "the
  /// client closed and the proxy did not pass it on" -- two different bugs
  /// that look identical from the server.
  int get livePairs => _pairs.length;

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
    if (_frozen) {
      // Frozen: accept the connection so the client's socket table shows
      // Established, then never speak and never forward — the OPC UA client
      // sends HEL and waits on a wire that stays silent forever. This is the
      // ".74" shape from docs/opcua-frozen-session-repro.md: a connect that
      // wedges without ever surfacing an error.
      _blackholed.add(clientSocket);
      clientSocket.done.catchError((_) {});
      clientSocket.listen((_) {}, onError: (_) {}, onDone: () {});
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

  /// Flush all buffered server→client responses.
  void flush() {
    for (final p in _pairs) {
      p.flushBuffer();
    }
  }

  /// Freeze mode — the frozen-session lifecycle from
  /// docs/opcua-frozen-session-repro.md: every existing pair keeps its
  /// client-side socket open (Established in the socket table) but stops
  /// forwarding in BOTH directions, and its server side is torn down (the
  /// server sees the peer vanish, like the plant servers that later sent
  /// FIN). New connections are accepted and then blackholed. From the
  /// client's perspective nothing errors — traffic just stops.
  void freeze() {
    _frozen = true;
    for (final pair in List.of(_pairs)) {
      pair.freeze();
    }
  }

  /// Leave freeze mode: NEW connections forward to the server again.
  /// Connections wedged during the freeze stay dead — the plant sockets
  /// never came back either; recovery requires the client to reconnect.
  void unfreeze() {
    _frozen = false;
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
    for (final sock in _blackholed) {
      try {
        sock.destroy();
      } catch (_) {}
    }
    _blackholed.clear();
  }
}

class _Pair {
  final Socket client;
  final Socket server;
  final TcpProxy proxy;
  StreamSubscription? _clientSub;
  StreamSubscription? _serverSub;
  bool _closed = false;
  bool _frozen = false;
  final List<List<int>> _serverBuffer = [];

  _Pair(this.client, this.server, this.proxy);

  void start(void Function() onClose) {
    client.done.catchError((_) {});
    server.done.catchError((_) {});
    _clientSub = client.listen(
      (data) {
        if (_frozen) return; // dropped on the floor, no error to the client
        // Client→server always forwarded
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

  /// Keep the client socket Established but silence the wire: stop reading
  /// the server side and destroy it (the real server sees the peer die),
  /// drop anything the client sends. Crucially the client-side socket is
  /// neither closed nor errored — it looks healthy forever.
  void freeze() {
    if (_closed || _frozen) return;
    _frozen = true;
    _serverSub?.cancel();
    _serverSub = null;
    try {
      server.destroy();
    } catch (_) {}
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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jbtm/src/msocket.dart';

/// A TCP proxy that connects to a single M2400 device upstream and fans out
/// raw bytes to multiple downstream clients.
///
/// The M2400 only accepts one client at a time, so this proxy acts as a
/// multiplexer: it maintains a single upstream connection (via [MSocket] with
/// auto-reconnect) and accepts any number of downstream TCP clients.
///
/// Operates at the raw byte level — no framing or parsing. Downstream clients
/// receive the exact bytes sent by the device.
class M2400Proxy {
  final String upstreamHost;
  final int upstreamPort;
  final int _requestedListenPort;
  final InternetAddress listenAddress;

  MSocket? _upstream;
  ServerSocket? _server;
  final List<Socket> _clients = [];
  final _subscriptions = <StreamSubscription<dynamic>>[];

  M2400Proxy({
    required this.upstreamHost,
    required this.upstreamPort,
    required int listenPort,
    InternetAddress? listenAddress,
  })  : _requestedListenPort = listenPort,
        listenAddress = listenAddress ?? InternetAddress.anyIPv4;

  /// The actual port the proxy is listening on (valid after [start]).
  int get listenPort => _server?.port ?? _requestedListenPort;

  /// Number of currently connected downstream clients.
  int get clientCount => _clients.length;

  /// The upstream connection status.
  Stream<ConnectionStatus> get upstreamStatus =>
      _upstream?.statusStream ?? const Stream.empty();

  /// Start the proxy: bind the listen socket and connect upstream.
  Future<void> start() async {
    _server = await ServerSocket.bind(listenAddress, _requestedListenPort);
    _server!.listen(_onClientConnect);

    _upstream = MSocket(upstreamHost, upstreamPort);

    _subscriptions.add(
      _upstream!.dataStream.listen(_fanOut),
    );

    _upstream!.connect();
  }

  /// Shut down: close listen socket, disconnect all clients, dispose upstream.
  Future<void> shutdown() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    for (final client in List.of(_clients)) {
      client.destroy();
    }
    _clients.clear();

    await _server?.close();
    _server = null;

    _upstream?.dispose();
    _upstream = null;
  }

  /// Optional callback when a downstream client connects or disconnects.
  void Function(int clientCount)? onClientCountChanged;

  void _onClientConnect(Socket client) {
    _clients.add(client);
    onClientCountChanged?.call(_clients.length);

    // Prevent unhandled async errors on the IOSink done future.
    client.done.catchError((_) {});

    // Drain reads and detect disconnect via onDone/onError.
    //
    // Both paths must destroy() the socket, not just drop it from _clients.
    // onDone fires on a peer FIN, which shuts the read half only; dart:io
    // frees the descriptor when *both* halves are shut, and Socket carries no
    // NativeFinalizer, so a dropped-but-not-destroyed Socket keeps its
    // descriptor for the life of the process. destroy() is idempotent, so an
    // onError-then-onDone double fire is harmless.
    void releaseClient() {
      _clients.remove(client);
      client.destroy();
      onClientCountChanged?.call(_clients.length);
    }

    client.listen(
      (_) {},
      onError: (_) => releaseClient(),
      onDone: releaseClient,
    );
  }

  void _fanOut(Uint8List data) {
    for (final client in List.of(_clients)) {
      try {
        client.add(data);
      } catch (_) {
        // Client may be closing; cleaned up by done handler.
      }
    }
  }
}

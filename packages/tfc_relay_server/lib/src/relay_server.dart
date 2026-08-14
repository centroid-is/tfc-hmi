/// The listening end: a shelf HTTP server whose one route upgrades WebSocket
/// connections, and one [RelaySession] per upgraded connection.
///
/// This file is where the three pieces the rest of the package builds
/// separately are finally wired together — the send buffer, the session sink
/// and the channel adapter — and it is the only place in the package that
/// knows a socket exists. `RelaySession` deliberately does not (see its own
/// doc): that is what lets every session property be asserted over an
/// in-memory pair in milliseconds, and it is why this file's own test file is
/// short.
///
/// **The accepted divergence from design §5.** The design says the fan-out
/// tick should "drain when the previous write completes", and `dart:io`
/// WebSockets offer no way to know when that is: no `bufferedAmount`, no
/// `flush()`, and an `add` that returns `void` (03-RESEARCH Finding 5, option
/// (a); 03-CONTEXT records the decision). So the safety net is the other one
/// the design already carries — tick-paced draining plus
/// `ConflatingSendBuffer`'s own `poll` verdicts, which measure the backlog the
/// server can see rather than the one the kernel is holding. This is a
/// recorded decision, not an omission, and anyone who later finds a genuine
/// completion signal on this transport should revisit it here first.
///
/// **The single outbound chokepoint.** [writeFrame] is the only function in
/// this package that calls `ws.sink.add`. Everything the server says — RPC
/// answers, write acks, status, and from 03-07 the drained telemetry frame —
/// goes through it, because a second write path is a frame that skips the
/// buffer and therefore skips backpressure accounting entirely.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'error_reporter.dart';
import 'handle_table.dart';
import 'relay_session.dart';
import 'server_config.dart';
import 'session_sink.dart';
import 'tick_engine.dart';
import 'token_validator.dart';
import 'ws_channel.dart';

/// Writes one already-encoded frame to [socket].
///
/// **The one `ws.sink.add` in this package.** Named, top-level and boring on
/// purpose: `grep -rn "sink.add" lib/src/` is meant to return exactly this
/// line, so "does anything bypass the send buffer?" is a question with a
/// mechanical answer. 03-07's tick engine writes its drained frames through
/// here.
void writeFrame(WebSocketChannel socket, String frame) =>
    socket.sink.add(frame);

/// The sessions a server is currently holding.
///
/// A thin holder rather than a bare `List`, for two reasons that arrive later:
/// 03-05 hangs subscription counts off it and 03-11's reaper sweeps it. What
/// it owes today is a count a test can read and the two events a fixture needs
/// to know when a connection has appeared or gone — polling for either is how
/// a socket test becomes a timing test.
final class SessionRegistry {
  final _sessions = <RelaySession>[];
  final _opened = StreamController<RelaySession>.broadcast();
  final _gone = StreamController<RelaySession>.broadcast();

  /// How many sessions are live right now.
  int get sessionCount => _sessions.length;

  /// The live sessions, in the order they connected.
  List<RelaySession> get sessions => List.unmodifiable(_sessions);

  /// Fires once per session, as it is registered.
  Stream<RelaySession> get opened => _opened.stream;

  /// Fires once per session, as it is removed.
  Stream<RelaySession> get gone => _gone.stream;

  void add(RelaySession session) {
    _sessions.add(session);
    if (!_opened.isClosed) _opened.add(session);
  }

  void remove(RelaySession session) {
    if (!_sessions.remove(session)) return;
    if (!_gone.isClosed) _gone.add(session);
  }

  /// Releases the event controllers. The sessions themselves are closed by
  /// [RelayServer.close], which calls this last.
  Future<void> dispose() async {
    _sessions.clear();
    await _opened.close();
    await _gone.close();
  }
}

/// How one connection ended, from both sides.
///
/// Both fields exist because they disagree, and the disagreement is the point.
/// A code the server *sent* is recorded by the session; a code the server
/// *observed* on its own socket is only meaningful when the client initiated
/// the close — after a self-initiated close it is `null`
/// (`web_socket_channel` #1698). So a record with a `serverCloseCode` and no
/// `clientCloseCode` is an eviction, and the reverse is a client that went
/// away. Anything that reads only one field cannot tell those apart, and they
/// call for opposite operator responses.
final class ConnectionClose {
  const ConnectionClose({this.clientCloseCode, this.serverCloseCode});

  /// What this end's socket observed. Trustworthy only for a close the client
  /// initiated; 1005 there means "went away with no status".
  final int? clientCloseCode;

  /// What the session recorded itself as sending, or null if it sent nothing.
  final int? serverCloseCode;

  @override
  String toString() => 'ConnectionClose(client: $clientCloseCode, '
      'server: $serverCloseCode)';
}

/// The gateway's listening end.
///
/// ```dart
/// final server = RelayServer(api: stateMan, config: ServerConfig());
/// await server.start();
/// print('listening on ${server.port}');
/// ```
final class RelayServer {
  RelayServer({
    required this.api,
    ServerConfig? config,
    HandleTable? handles,
    this.validator = const PermissiveTokenValidator(),
    this.serverSupported = const [protocolVersion],
    this.onError = reportToStderr,
  })  : config = config ?? ServerConfig(),
        handles = handles ?? HandleTable();

  /// Where this server reports an error nobody asked for: an unhandled peer
  /// error, a session that threw inside the tick, a sweep that failed.
  ///
  /// Defaults to [reportToStderr] rather than to null, because the alternative
  /// is the state this package shipped in — every failure swallowed, and a
  /// gateway that cannot say what went wrong. A test supplies a collector and
  /// asserts on it; an embedder supplies its own logger.
  final RelayErrorHandler onError;

  /// The subprotocol this gateway answers to, when a client asks for one.
  ///
  /// Panels do not: `WebSocketChannel.connect` sends no
  /// `Sec-WebSocket-Protocol` header unless told to, and `shelf_web_socket`
  /// then selects none and sends none back. It is declared so that a browser
  /// client — Phase 6's web bundle — can pin the protocol it expects and be
  /// refused early rather than after a hello it cannot parse.
  static const subprotocol = 'tfc-relay.v1';

  /// The source every session serves. One instance, shared: two panels
  /// watching one motor must be served by one upstream subscription.
  final StateManApi api;

  final ServerConfig config;

  /// The server-global key→handle table, shared across sessions so an
  /// encode-once body stays byte-identical for every client that gets it.
  final HandleTable handles;

  final TokenValidator validator;

  /// The protocol versions this build can speak, newest last.
  final List<String> serverSupported;

  final SessionRegistry _sessions = SessionRegistry();
  final _connections = <_Connection>[];
  final _closeLedger = <ConnectionClose>[];

  HttpServer? _http;
  var _closed = false;

  /// The one tick engine, built by [start] and stopped by [close].
  ///
  /// Exactly one per server, holding the server's only timer and the one
  /// [FrameEncoder] whose cache is shared by every session that ticks
  /// together — that sharing is what makes two panels watching one motor cost
  /// one encode instead of two.
  TickEngine? get engine => _engine;
  TickEngine? _engine;

  /// The sessions this server is holding.
  SessionRegistry get sessions => _sessions;

  /// How the last few connections ended, oldest first.
  ///
  /// Bounded at [_ledgerLimit]: a gateway that ran for a month would otherwise
  /// hold one record per connection ever made, which is a leak with a
  /// diagnostic excuse. What it is for is the question an operator asks after
  /// a panel drops — "did it leave, or did we evict it?" — and 03-08's
  /// close-code sweep.
  List<ConnectionClose> get closeLedger => List.unmodifiable(_closeLedger);

  static const _ledgerLimit = 64;

  /// The bound port. Throws before [start] has completed, because a caller
  /// that reads it early wants to be told that rather than shown a 0.
  int get port {
    final http = _http;
    if (http == null) {
      throw StateError('the server has no port until `start()` has completed; '
          'await it before reading one');
    }
    return http.port;
  }

  /// Binds loopback on an ephemeral port and starts accepting upgrades.
  ///
  /// Loopback specifically (threat T-03-11): exposing the gateway on a public
  /// interface is a Phase 6 deployment decision with a firewall attached to
  /// it, not something a default should do quietly. Port 0 so two servers can
  /// run in one test process without agreeing on a number.
  Future<void> start() async {
    if (_closed) {
      throw StateError('a closed RelayServer cannot be restarted: its sessions '
          'are gone and its registry is disposed. Build a new one');
    }
    _http = await shelf_io.serve(
      webSocketHandler(
        _onConnect,
        protocols: const [subprotocol],
        // From the config, never a literal (threat T-03-10). Empty — the
        // default — rejects every browser `Origin` with 403 and leaves
        // origin-less clients, which is what the panels are, untouched.
        allowedOrigins: config.allowedOrigins,
        // NAT keepalive, and a backstop for a client whose heartbeat logic is
        // broken while its socket still works. **Never the liveness reaper**:
        // Finding 7 measured half-open detection through the ping at 1.85x
        // the interval, which at 20 s is a ~37 s window. 03-11's app-level
        // heartbeat is the reaper.
        pingInterval: config.pingInterval,
      ),
      InternetAddress.loopbackIPv4,
      0,
    );
    // After the bind, so a server that failed to bind has no timer running
    // against an empty registry, and one engine for the whole process — see
    // `tick_engine.dart` on why this is never per session.
    _engine = TickEngine(
      registry: _sessions,
      config: config,
      onSessionError: onError,
    )..start();
  }

  /// Builds one session for one upgraded connection.
  ///
  /// Never throws. A wiring failure here would otherwise land in the ambient
  /// isolate — `socket_harness.dart:50-56`'s rule — and be attributed to
  /// whichever test happened to be running; it is delivered to the connection
  /// that caused it instead.
  void _onConnect(WebSocketChannel ws, String? negotiated) {
    if (_closed) {
      // Accepted while the drain was running. Refused with the same code every
      // drained session gets, because from the panel's side it is the same
      // event: this gateway is going away, reconnect rather than alarm.
      unawaited(ws.sink
          .close(CloseCodes.serverDraining, 'server draining')
          .catchError((Object _) {}));
      return;
    }
    try {
      final buffer = ConflatingSendBuffer(
        maxPending: config.maxPending,
        peakThreshold: config.peakThreshold,
        peakWindowMs: config.peakWindowMs,
        maxPendingBytes: config.maxPendingBytes,
      );
      final sink = SessionSink(buffer, socket: ws.sink);

      // Built by hand, and this is the line the trap is about (Finding 1):
      // `rpc.Peer(ws.cast<String>())` — the documented idiom — binds the
      // socket's sink with `addStream` for the life of the connection, and
      // every later writer, the fan-out tick included, gets "Bad state: Cannot
      // add event while adding stream" on its first push. Cast the *stream*,
      // which is a cheap view, and keep ownership of the sink.
      final channel = StreamChannel<String>(
        mutedRepublish(ws.stream.cast<String>()),
        sink,
      );

      final connection = _Connection(ws: ws, buffer: buffer, sink: sink);
      _connections.add(connection);

      final session = RelaySession.serve(
        channel: channel,
        api: api,
        config: config,
        handles: handles,
        buffer: buffer,
        validator: validator,
        serverSupported: serverSupported,
        closeChannel: connection.closeSocket,
        emitFrame: connection.write,
        // Synchronous, and the asynchronous `_release` below does *not*
        // replace it. A session evicted inside a tick — backpressure, the
        // heartbeat reaper — must be gone from the registry by the time that
        // tick's remaining work runs; `session.closed` completes a turn or
        // more later, after the peer has shut down, and until then the engine
        // would keep fanning out to a client the server has already evicted.
        // `remove` is idempotent and fires `gone` once, so the two paths
        // meeting is not a double report.
        onClosing: _sessions.remove,
        onError: onError,
      );
      connection.session = session;
      _sessions.add(session);

      unawaited(session.closed.then((_) => _release(connection)));
    } catch (error, stack) {
      unawaited(_failConnection(ws, error, stack));
    }
  }

  /// Tells one client its session could not be built, then closes it.
  ///
  /// A notification rather than an error response: there is no request to
  /// answer — the failure happened before the client said anything — and a
  /// socket that closes with no explanation is indistinguishable from a
  /// crashed server, which is the reconnect behaviour we do not want.
  ///
  /// **Built through [StatusParams], not by hand** (03-REVIEW WR-06). This
  /// used to send `{'fatal': '...'}` under the `status` method, and `status`
  /// is `StatusParams` — `{alias, state, error?}`. A client routing the
  /// notification through `StatusParams.fromJson` hit `json['alias'] as String`
  /// on null and threw a TypeError on the *notification* path, where there is
  /// no request to fail and the error is swallowed. So the one frame whose job
  /// is to explain a fatal wiring failure was the one frame a conforming
  /// client could not read. Going through the DTO makes a future drift a
  /// compile error instead.
  ///
  /// The underlying `$error` rides in `error:`, which is the field the
  /// contract has for it — not spliced into free text that nothing can parse.
  Future<void> _failConnection(
      WebSocketChannel ws, Object error, StackTrace stack) async {
    onError(error, stack, 'session wiring');
    try {
      writeFrame(
        ws,
        jsonEncode({
          'jsonrpc': '2.0',
          'method': Methods.status,
          'params': StatusParams(
            alias: 'gateway',
            state: 'unhealthy',
            error: 'the server could not build a session for this connection: '
                '$error',
          ).toJson(),
        }),
      );
      await ws.sink.close(1000, 'session wiring failed');
    } catch (_) {
      // The socket was already gone. There is nowhere left to deliver the
      // failure to, and throwing here would put it exactly where this method
      // exists to keep it out of.
    }
  }

  void _release(_Connection connection) {
    if (connection.released) return;
    final session = connection.session;
    if (session != null) _sessions.remove(session);
    _connections.remove(connection);
    _record(connection.finish());
  }

  void _record(ConnectionClose close) {
    _closeLedger.add(close);
    if (_closeLedger.length > _ledgerLimit) _closeLedger.removeAt(0);
  }

  /// Stops serving. Idempotent, and ordered.
  ///
  /// **The listener first** (03-REVIEW WR-05). The doc used to say "the
  /// listener last, so nothing new arrives while the drain is running", which
  /// is the opposite of what closing it last achieves: a connection accepted
  /// between the session-drain loop and the listener close built a whole
  /// session — peer, listeners on the backing `StateManApi`, buffer — and
  /// registered it, and `_sessions.dispose()` then cleared the registry
  /// *without closing anything*, so that session's listeners stayed attached
  /// to the source and its socket stayed open. That is precisely the leak
  /// `teardown_test.dart` exists to police, on the one path it could not see.
  ///
  /// The engine next, so no tick can start fanning out to a session that is
  /// halfway through its own teardown — and so the process has no timer left
  /// holding it open. Sessions after that, each with
  /// [CloseCodes.serverDraining] so a panel knows to reconnect rather than
  /// alarm: a client disconnected with no code cannot tell a restart from a
  /// crash. Completes only when every session has.
  ///
  /// [_onConnect] is guarded as well, and the guard is not redundant:
  /// `force: true` does not retract a connection already handed to the
  /// handler, and `_closed` is set synchronously here while the close itself
  /// is awaited.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _http?.close(force: true);
    _http = null;

    await _engine?.stop();
    _engine = null;

    for (final session in _sessions.sessions) {
      await session.close(CloseCodes.serverDraining, 'server draining');
    }
    for (final connection in _connections.toList()) {
      _release(connection);
    }

    await _sessions.dispose();
  }
}

/// One socket, its buffer, and the two ways a frame gets from one to the
/// other: the tick engine's [_Connection.write], and the out-of-band priority
/// flush the teardown path needs.
final class _Connection {
  _Connection({
    required WebSocketChannel ws,
    required this.buffer,
    required this.sink,
  }) : _ws = ws;

  final WebSocketChannel _ws;
  final ConflatingSendBuffer buffer;
  final SessionSink sink;

  RelaySession? session;
  var _finished = false;

  /// Whether [finish] has already run.
  ///
  /// Both paths into it are real and can race: the session completing on its
  /// own, and the server draining. Recording one connection twice would put a
  /// disconnect in the ledger that never happened.
  bool get released => _released;
  var _released = false;

  /// The session's `emitFrame`: one already-encoded frame onto this socket.
  ///
  /// Everything the tick engine produces for this client arrives here — the
  /// drained priority lane, the `u` updates, the tick notification — and it is
  /// the reason `_Connection` no longer owns a timer. Until 03-07 this class
  /// pumped its own buffer on its own `Timer.periodic`, which is one timer per
  /// connected panel; the engine replaced all of them with the server's single
  /// one (`tick_engine.dart`, Finding 8).
  void write(String frame) {
    if (_finished) return;
    writeFrame(_ws, frame);
  }

  /// Puts the priority lane on the wire *now*, outside the tick.
  ///
  /// Only the priority lane, and only on the way out: this runs from
  /// [closeSocket], where the telemetry that is still pending belongs to a
  /// client that is being disconnected in the next statement. Dropping it is
  /// correct — resync is a snapshot, never a replayed backlog — while the
  /// refusal that explains the close must land, and that is what the priority
  /// lane is for.
  ///
  /// Deliberately **not** calling `buffer.poll`: a backpressure verdict here
  /// would be an eviction decided during a teardown that is already underway.
  void flushPriority() {
    if (_finished) return;
    final frame = buffer.drain();
    for (final message in frame.priority) {
      writeFrame(_ws, message is String ? message : jsonEncode(message));
    }
  }

  /// The session's `closeChannel`: flush, then close the socket with the code.
  ///
  /// The flush is load-bearing and not obvious. A refusal that explains a
  /// close — the 4005 body naming both version lists, say — is written into
  /// the buffer by the peer and would otherwise wait up to a full tick for the
  /// engine, while `RelaySession._requestClose` schedules the close on the very
  /// next turn of the event loop. The client would then get the close and
  /// never the explanation. Flushing here puts both frames on the wire in
  /// order, which is what the whole close-code discipline is for.
  Future<void> closeSocket(int code, String reason) async {
    flushPriority();
    _finished = true;
    try {
      await _ws.sink.close(code, reason);
    } catch (_) {
      // The far end is already gone. That is the ordinary shape of a
      // disconnect, not news.
    }
  }

  /// Releases the connection and reports how it ended.
  ///
  /// The observation is snapshotted *before* this end closes its own sink: for
  /// a client-initiated close the socket is already carrying the client's code
  /// (1005 when it sent none) and reading it later risks racing our own close.
  ConnectionClose finish() {
    _released = true;
    final close = ConnectionClose(
      clientCloseCode: _ws.closeCode,
      serverCloseCode: session?.sentCloseCode,
    );
    _finished = true;
    sink.finish();
    unawaited(_ws.sink.close().catchError((Object _) {}));
    return close;
  }
}

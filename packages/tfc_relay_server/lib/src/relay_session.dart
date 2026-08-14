/// One connected client: the JSON-RPC peer, the handler table, and the two
/// pieces of armor every handler is born with.
///
/// The direct ancestor is `served_state_man.dart` in the contract kit — a
/// `Peer` over a `StreamChannel<String>` serving a `StateManApi`, with a
/// registration ledger, error armor and an ordered teardown. This is that
/// class with a gate in front of it and a socket underneath (03-04), and three
/// things are copied from it rather than rewritten, on purpose:
///
///  * the `.._start()` cascade, so registration and listening are one
///    expression and a session cannot exist half-registered;
///  * `registeredMethods`, so the wire surface can be asserted in *both*
///    directions — a declared name with no handler, and a handler nobody
///    declared;
///  * `_answer`/`_substitute`, verbatim, including the explanation. That one
///    is the 02-05 hang trap and the highest-risk item in this phase.
///
/// **What this class does not do.** It does not know what a socket is. The
/// channel arrives built (see `ws_channel.dart`), which is what lets every
/// property below be tested over an in-memory pair in milliseconds instead of
/// over a port. It also does not close its own transport: it closes the peer
/// and then hands the close code to the closer its caller supplied, because
/// only the caller knows whether there is a WebSocket down there and only a
/// WebSocket can carry a 4xxx code.
library;

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'error_codes.dart';
import 'handle_table.dart';
import 'server_config.dart';
import 'session_handlers.dart';
import 'subscription_registry.dart';
import 'token_validator.dart';

/// The moment the last inbound frame arrived, updated by a tap on the read
/// side.
///
/// A tiny mutable holder rather than a field on the session, because the tap
/// has to exist *before* the `Peer` does and the `Peer` has to exist before
/// the session does — and the alternative, a `late` peer assigned after
/// construction, is how a session comes to exist half-built.
final class _LastSeen {
  _LastSeen(this._now) : at = _now();
  final int Function() _now;
  int at;

  String touch(String frame) {
    at = _now();
    return frame;
  }
}

/// One client session.
final class RelaySession {
  RelaySession._(
    this.peer,
    this.api,
    this.config,
    this.handles,
    this.buffer,
    this.validator,
    this._gate,
    this._lastSeen,
    this._now,
    this._closeChannel,
    this._emitFrame,
  );

  /// Serves [api] over [channel] and starts listening immediately.
  ///
  /// [channel] is already a channel of whole JSON strings, and its sink is
  /// already whoever's the caller decided it should be — the session sink for
  /// a real client, the raw pair end for a test.
  ///
  /// [emitFrame] is how an already-encoded frame the **tick engine** produced
  /// leaves this session — the drained priority lane, the `u` updates and the
  /// tick notification. It cannot be the channel's own sink: that sink is the
  /// [SessionSink], which puts everything it is given *into* the buffer, so a
  /// tick that wrote its drained frames back through it would refill the lane
  /// it had just emptied and nothing would ever reach the wire. Optional,
  /// because a session driven by no engine never produces one; when it is
  /// absent [emit] drops the frame rather than throwing, since the caller is
  /// the timer and an exception there takes the whole server's tick down with
  /// it.
  ///
  /// [closeChannel] is how a close *code* reaches the client. Optional,
  /// because an in-memory channel has nowhere to put one; without it [close]
  /// still records the code and tears the session down, which is what every
  /// assertion in this phase reads (`web_socket_channel` #1698: a socket's own
  /// `closeCode` is unreliable for a close it initiated).
  static RelaySession serve({
    required StreamChannel<String> channel,
    required StateManApi api,
    required ServerConfig config,
    required HandleTable handles,
    required ConflatingSendBuffer buffer,
    TokenValidator validator = const PermissiveTokenValidator(),
    List<String> serverSupported = const [protocolVersion],
    Future<void> Function(int code, String reason)? closeChannel,
    void Function(String frame)? emitFrame,
    int Function()? now,
  }) {
    final clock = now ?? () => DateTime.now().millisecondsSinceEpoch;
    final lastSeen = _LastSeen(clock);
    return RelaySession._(
      rpc.Peer(
          StreamChannel<String>(channel.stream.map(lastSeen.touch), channel.sink)),
      api,
      config,
      handles,
      buffer,
      validator,
      HelloGate(serverSupported: serverSupported),
      lastSeen,
      clock,
      closeChannel,
      emitFrame,
    ).._start();
  }

  /// The source being served. Untouched by this plan's two methods; 03-05's
  /// `subscribe` is the first handler that reads it.
  final StateManApi api;

  /// The JSON-RPC endpoint. Exposed so a test can assert on its state.
  final rpc.Peer peer;

  final ServerConfig config;

  /// The server-global key→handle table. Shared across sessions on purpose:
  /// two panels watching one motor must be handed the same integer, or the
  /// encode-once body stops being byte-identical.
  final HandleTable handles;

  /// This session's outbound buffer. Everything the tick engine will drain.
  final ConflatingSendBuffer buffer;

  /// What this session is currently watching.
  ///
  /// Public because "the release is asserted by registry inspection" (SRV-02)
  /// is only true of a registry something can look into, and because the tick
  /// engine and the reaper both read it from outside the session.
  late final SubscriptionRegistry subscriptions = SubscriptionRegistry(
      maxSubscriptions: config.maxSubscriptionsPerSession);

  final TokenValidator validator;

  final HelloGate _gate;
  final _LastSeen _lastSeen;
  final int Function() _now;
  final Future<void> Function(int code, String reason)? _closeChannel;
  final void Function(String frame)? _emitFrame;

  /// Puts one already-encoded [frame] on this session's transport.
  ///
  /// The tick engine's write seam, and the only way out of a session that does
  /// not go through the buffer first — because by the time the engine calls
  /// this, the buffer is what the frame came *out* of.
  void emit(String frame) => _emitFrame?.call(frame);

  /// The negotiated protocol, and the session's identity — all null until a
  /// `hello` is accepted.
  String? get protocol => _protocol;
  String? _protocol;

  String? get sessionId => _sessionId;
  String? _sessionId;

  String? get epoch => _epoch;
  String? _epoch;

  /// When the last inbound frame arrived, on the session's clock.
  ///
  /// The heartbeat reaper (03-11) sweeps on this. A tap on the read side
  /// rather than a touch in each handler, because a frame the peer *rejects*
  /// is still evidence the client is alive.
  int get lastSeenMs => _lastSeen.at;

  /// The close code this session sent, recorded by the session itself.
  ///
  /// Never read off the socket: `closeCode` is unreliable for a close the
  /// server initiated (`web_socket_channel` #1698), so both ends track what
  /// they sent. Every close-code assertion in this phase reads this field.
  int? get sentCloseCode => _sentCloseCode;
  int? _sentCloseCode;

  /// Completes when the session has stopped serving.
  Future<void> get closed => _done.future;
  final _done = Completer<void>();

  var _closed = false;

  /// Every name [_on] has registered, in registration order.
  ///
  /// Kept so the wire surface can be asserted against the handlers in *both*
  /// directions: a declared name with no handler answers METHOD_NOT_FOUND from
  /// a table claiming to carry it, and a handler with no declared name is
  /// surface nobody counted. 03-08 freezes this set.
  Set<String> get registeredMethods => Set.unmodifiable(_registered);
  final _registered = <String>{};

  /// Registers [handler] under [method], with the gate and the error armor
  /// wrapped around it.
  ///
  /// **The composition is the point.** Gating lives here, at the one seam
  /// where a method enters the table, so a handler added in 03-05 or 03-07 is
  /// gated and armored by construction. A per-handler check would be a rule
  /// every future plan has to remember, and the one it forgot would be the
  /// method that serves plant data to a client that never authenticated.
  void _on(String method, Future<Object?> Function(rpc.Parameters) handler) {
    _registered.add(method);
    peer.registerMethod(
        method,
        (rpc.Parameters params) =>
            _gated(method, () => _answer(method, () async => handler(params))));
  }

  void _start() {
    // Every one of these goes through `_on`, and there is no second path. The
    // table is exactly {hello, ping, subscribe, unsubscribe} for this phase;
    // Phase 5 adds `write`/`writeStatus` and Phase 10 the data services, and
    // 03-08 freezes the set against a hand-written literal so each addition is
    // a deliberate edit to a test that explains its cost.
    final handlers = SessionHandlers(
      api: api,
      config: config,
      handles: handles,
      buffer: buffer,
      subscriptions: subscriptions,
      // The epoch is minted by `hello`, which cannot have run yet; the gate
      // guarantees no subscribe reaches a handler before it has.
      epochOf: () => _epoch ?? '',
    );
    _on(Methods.hello, _hello);
    _on(Methods.ping, _ping);
    _on(Methods.subscribe, handlers.subscribe);
    _on(Methods.unsubscribe, handlers.unsubscribe);
    unawaited(peer.listen().then((_) {
      if (!_done.isCompleted) _done.complete();
    }, onError: (Object _) {
      if (!_done.isCompleted) _done.complete();
    }));
  }

  /// Applies the handshake gate to [method] before [work] runs.
  ///
  /// The switch is exhaustive over `GateAction` with no default arm, so a new
  /// verdict added to the gate is a compile error here rather than a request
  /// that quietly proceeds.
  Future<Object?> _gated(String method, Future<Object?> Function() work) async {
    final action = _gate.checkRequest(method);
    switch (action) {
      case GateAllow():
        return await work();
      case GateReject(:final kind):
        throw rpc.RpcException(
            kind == 'already_helloed'
                ? ServerErrorCodes.alreadyHelloed
                : ServerErrorCodes.helloRequired,
            '$method refused: $kind',
            data: _substitute(method));
      case GateClose(:final closeCode, :final supported, :final requested):
        _requestClose(closeCode, 'protocol mismatch');
        throw rpc.RpcException(
            ServerErrorCodes.versionMismatch, '$method refused: no common '
                'protocol version',
            data: {
              ..._substitute(method),
              'supported': supported,
              'requested': requested,
            });
      case GateClosed():
        throw rpc.RpcException(ServerErrorCodes.helloRequired,
            '$method refused: this session has been closed',
            data: _substitute(method));
      case GateAccept():
        // Unreachable from `checkRequest`, which never accepts — acceptance is
        // `negotiate`'s answer and belongs to the hello handler. Named anyway,
        // because that is what makes the switch total.
        return await work();
    }
  }

  /// Answers [method], with every failure turned into an encodable error.
  ///
  /// The wrapper exists for one reason, and it is the trap 02-05 documented on
  /// the write path: `RpcException.serialize` copies the offending **request**
  /// into the error response unless `data` already carries a `request` key
  /// (`json_rpc_2-4.1.0/lib/src/exception.dart:46-57`), and json_rpc_2's own
  /// wrapping of an uncaught error does the same. A request that `jsonEncode`
  /// cannot re-emit — one carrying an Infinity decoded from `1e999` — therefore
  /// produces an error response that cannot be sent, the refusal is thrown away
  /// inside the peer, and the caller waits forever on a path with no deadline.
  /// Substituting `request` here is what keeps the answer sendable, so a
  /// failure arrives as a failure.
  ///
  /// [TypeError] keeps its own code on the way out, because it is what a typed
  /// decode throws when a client sends a field of the wrong type, and that is
  /// a different instruction to the client than "the server broke".
  Future<Object?> _answer(String method, Future<Object?> Function() work) async {
    try {
      return await work();
    } on rpc.RpcException {
      rethrow;
    } on TypeError catch (error) {
      throw rpc.RpcException(ServerErrorCodes.typeMismatch, '$error',
          data: _substitute(method));
    } catch (error) {
      throw rpc.RpcException(
          ServerErrorCodes.handlerFailed, '$method failed: $error',
          data: _substitute(method));
    }
  }

  static Map<String, Object?> _substitute(String method) => {
        'method': method,
        'request': 'omitted: echoing a request that may carry a non-finite '
            'number is what makes the error itself unencodable, and an '
            'unencodable error on a path with no deadline is a hang',
      };

  /// The handshake. Credential first, version second, identity third.
  ///
  /// The order matters: a rejected credential must not advance the gate's
  /// state, or a client that failed to authenticate would have spent the one
  /// `hello` the session allows.
  Future<Object?> _hello(rpc.Parameters params) async {
    // Every decode on the ingress path is sanitized first: `jsonDecode('1e999')`
    // yields Infinity silently, and Infinity anywhere in a value the server
    // later re-emits is a frame that cannot be encoded.
    final decoded = sanitize(params.asMap).value as Map;
    final hello = HelloParams.fromJson(decoded.cast<String, Object?>());

    switch (await validator.validate(hello)) {
      case TokenRejected(:final reason):
        _requestClose(CloseCodes.authExpired, 'credential rejected');
        throw rpc.RpcException(
            ServerErrorCodes.unauthorized, 'hello refused: $reason',
            data: _substitute(Methods.hello));
      case TokenAccepted():
        break;
    }

    final action = _gate.negotiate(hello);
    switch (action) {
      case GateAccept(:final protocol):
        _protocol = protocol;
        final id = newUlid();
        _sessionId = id;
        _epoch = newUlid();
        return HelloResult(
          protocol: protocol,
          server: const PeerInfo('tfc-relay-gateway', '0.1.0'),
          sessionId: id,
          epoch: _epoch!,
          // Always false this phase: nothing is resumable until 03-09, and a
          // client told its cache survived when it did not shows stale plant
          // data under a healthy-looking link.
          resumed: false,
          serverTime: _now(),
        ).toJson();
      case GateClose(:final closeCode, :final supported, :final requested):
        _requestClose(closeCode, 'no common protocol version');
        throw rpc.RpcException(ServerErrorCodes.versionMismatch,
            'hello refused: no common protocol version',
            data: {
              ..._substitute(Methods.hello),
              'supported': supported,
              'requested': requested,
            });
      case GateReject(:final kind):
        throw rpc.RpcException(ServerErrorCodes.alreadyHelloed,
            'hello refused: $kind',
            data: _substitute(Methods.hello));
      case GateClosed():
        throw rpc.RpcException(ServerErrorCodes.helloRequired,
            'hello refused: this session has been closed',
            data: _substitute(Methods.hello));
      case GateAllow():
        // `negotiate` never merely allows; it accepts, rejects or closes.
        throw StateError('the gate allowed a hello without negotiating it');
    }
  }

  /// The app-level heartbeat. Answers with the server's clock so a client can
  /// re-derive its offset without a second handshake.
  Future<Object?> _ping(rpc.Parameters _) async => {'serverTime': _now()};

  /// Records [code] and schedules the teardown for after the answer.
  ///
  /// Recorded synchronously, torn down on the next turn of the event loop: the
  /// refusal that explains the close is still being written when this is
  /// called, and closing the peer underneath it would leave the client
  /// disconnected with no idea why — which is the failure this whole close-code
  /// discipline exists to prevent.
  void _requestClose(int code, String reason) {
    _sentCloseCode ??= code;
    Timer.run(() => unawaited(close(code, reason)));
  }

  /// Stops serving, in the order Finding 9 measured. Idempotent.
  ///
  /// The code is recorded first so it is readable even if the transport is
  /// already gone; the peer is closed next, which is what stops handlers from
  /// running; the transport is closed last, with the code, because a socket
  /// closed before the peer swallows the peer's final frames.
  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    _sentCloseCode ??= code;
    // Detach before the peer goes: a listener still attached to the upstream
    // store keeps pushing this client's values into a buffer that will never
    // be drained again, and a hundred of those is a shift's worth of memory
    // held for panels that went home (Finding 9's checklist, step 2).
    subscriptions.clear();
    await peer.close();
    await _closeChannel?.call(code, reason);
    if (!_done.isCompleted) _done.complete();
  }
}

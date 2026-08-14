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
import 'dart:convert';

import 'package:json_rpc_2/error_code.dart' as rpc_errors;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'error_codes.dart';
import 'error_reporter.dart';
import 'handle_table.dart';
import 'server_config.dart';
import 'session_handlers.dart';
import 'subscription_registry.dart';
import 'token_validator.dart';
import 'value_handlers.dart';
import 'write_outcome_log.dart';

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
    this._onClosing,
    this._writeOutcomes,
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
    WriteOutcomeLog? writeOutcomes,
    Future<void> Function(int code, String reason)? closeChannel,
    void Function(String frame)? emitFrame,
    void Function(RelaySession session)? onClosing,
    RelayErrorHandler? onError,
    int Function()? now,
  }) {
    final clock = now ?? () => DateTime.now().millisecondsSinceEpoch;
    final lastSeen = _LastSeen(clock);
    return RelaySession._(
      rpc.Peer(
          StreamChannel<String>(
              channel.stream
                  .map(lastSeen.touch)
                  .map((frame) => _underCeiling(frame, config.maxFrameBytes))
                  .map(_defuse),
              channel.sink),
          onUnhandledError: onError == null
              ? null
              // `ErrorCallback`'s two parameters are `dynamic`
              // (json_rpc_2/src/server.dart:18), so they are narrowed here
              // rather than at every call site of ours.
              : (dynamic error, dynamic stack) => onError(
                  error as Object,
                  stack is StackTrace ? stack : StackTrace.current,
                  'session peer')),
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
      onClosing,
      writeOutcomes ??
          WriteOutcomeLog(ttl: config.writeOutcomeTtl, now: clock),
    ).._start();
  }

  /// Refuses one inbound frame that is over the ingress ceiling, before
  /// anything decodes it.
  ///
  /// **03-REVIEW WR-04 / threat T-03-29.** There was no frame-size limit
  /// anywhere in the path, and json_rpc_2's parse-error responder echoes the
  /// *entire* offending text back (`utils.dart:60-70`), into the priority lane,
  /// held until the next tick. A client sending garbage faster than the tick
  /// drains grew the server's heap by megabytes per frame with no verdict
  /// available to stop it.
  ///
  /// A `FormatException` rather than a stream error, and one carrying **no
  /// source**: that is what makes json_rpc_2 answer `-32700` to the sender and
  /// carry on, and the missing source is what keeps the refusal from echoing
  /// the very megabytes it is refusing. The session survives — an oversized
  /// request must cost the request, not the panel that sent it.
  ///
  /// The ceiling is on the decoded *string* length rather than on wire bytes.
  /// For the plant's ASCII tag names the two are the same number; for a frame
  /// full of Icelandic þ/ð/æ the UTF-8 encoding is larger, so this is the
  /// slightly permissive direction, which is the right one for a limit whose
  /// job is to refuse an order of magnitude rather than a byte.
  static String _underCeiling(String frame, int maxFrameBytes) {
    if (frame.length <= maxFrameBytes) return frame;
    throw FormatException('frame of ${frame.length} bytes exceeds the '
        '$maxFrameBytes byte ingress ceiling');
  }

  /// Takes the poison out of one inbound frame before the `Peer` ever sees it.
  ///
  /// **The one place `1e999` is disarmed for paths this class does not own.**
  /// `_answer` and the fallback below can only armor errors that pass through
  /// them. Two shapes never do: an envelope json_rpc_2 itself rejects (missing
  /// `method`, wrong `jsonrpc`, a non-object `params` — every throw in
  /// `Server._validateRequest`), and an `id` that is itself non-finite, which
  /// `RpcException.serialize` copies into the response before any of our code
  /// runs (`exception.dart:60` accepts any `num` as an id, and Infinity is
  /// one). Both produce a response `jsonEncode` refuses; json_rpc_2 discards
  /// the refusal inside the Peer and the client waits forever on a healthy
  /// link. That is the 02-05 hang, reachable by anything that can open a
  /// socket.
  ///
  /// So the frame is decoded, sanitized and re-encoded here, at the boundary,
  /// which is where CLAUDE.md says wire hazards belong. The cost is one extra
  /// `jsonDecode` per **inbound** frame — requests only, never the telemetry
  /// fan-out, which is the path Finding 2 measured — and the re-encode is paid
  /// only by a frame that actually carried a non-finite number.
  ///
  /// **Anything that goes wrong here leaves the frame exactly as it was.** A
  /// frame that is not JSON at all is json_rpc_2's parse error to answer (its
  /// echo is the source *text*, a String, which encodes); one nested past
  /// [maxValueDepth] makes `sanitize` throw, and today that is a per-request
  /// refusal from the handler's own sanitize rather than a dead session.
  /// Turning either into a stream error would close the session over a frame
  /// the server currently answers.
  static String _defuse(String frame) {
    try {
      final sanitized = sanitize(jsonDecode(frame));
      if (!sanitized.hadNonFinite) return frame;
      return jsonEncode(sanitized.value);
    } catch (_) {
      return frame;
    }
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

  /// Called synchronously, once, at the top of [close] — before the peer, the
  /// subscriptions or the transport are touched.
  ///
  /// The server hangs the registry removal off it. A hook rather than a
  /// registry reference because the session does not know what a server is
  /// (see this library's doc), and every in-memory test in this phase builds
  /// one without either.
  final void Function(RelaySession session)? _onClosing;

  /// The gateway's write outcome log, shared with every other session on this
  /// server. Defaulted to one of this session's own when nobody supplied one,
  /// which is the in-memory test shape — and which is exactly the per-socket
  /// lifetime 04-REVIEW CR-02 is about, so a session built that way can only
  /// ever answer about writes it handled itself.
  final WriteOutcomeLog _writeOutcomes;

  /// Puts one already-encoded [frame] on this session's transport.
  ///
  /// The tick engine's write seam, and the only way out of a session that does
  /// not go through the buffer first — because by the time the engine calls
  /// this, the buffer is what the frame came *out* of.
  void emit(String frame) => _emitFrame?.call(frame);

  /// Acts on one [verdict] from this session's send buffer. Returns whether
  /// the session survived it.
  ///
  /// **Why the switch lives here rather than at the caller.** The close code a
  /// backpressure eviction carries is decided by the thing that measured the
  /// backlog, and it reaches the client by being *carried* — `verdict.closeCode`
  /// and `verdict.reason`, never a constant re-typed at this call site. A
  /// session that named 4004 for its own reasons and a buffer that named it for
  /// the measured one can drift apart the moment either is edited, and the
  /// symptom of that drift is a client told the wrong thing about why it was
  /// disconnected — which is precisely the repudiation T-03-27 is about. One
  /// switch, in one place, over the sealed type.
  ///
  /// The switch is exhaustive with no `default:` and no `_ =>` arm, and
  /// [BufferOk] is an explicit no-op rather than a fall-through: a third
  /// verdict added to `BufferVerdict` must be a compile error here, not a
  /// silently ignored eviction policy.
  bool applyVerdict(BufferVerdict verdict) {
    switch (verdict) {
      case BufferDisconnect(:final closeCode, :final reason):
        unawaited(close(closeCode, reason));
        return false;
      case BufferOk():
        return true;
    }
  }

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
  ///
  /// **WebSocket pongs deliberately do not move it.** `dart:io` answers the
  /// server's pings inside the socket and surfaces nothing on the stream, so
  /// only frames the *application* sent land here. That is the whole
  /// distinction Finding 7 rests on: a panel whose process is wedged while its
  /// kernel still answers pings is exactly the client the ping cannot see, and
  /// a liveness field that counted pongs would be the ping wearing the
  /// heartbeat's name.
  int get lastSeenMs => _lastSeen.at;

  /// How long this session has been silent, **on its own clock**.
  ///
  /// The reaper asks the session rather than doing the arithmetic itself, and
  /// that is not a stylistic preference — it is the only spelling that cannot
  /// be wrong. `TickEngine`'s clock is an uptime `Stopwatch` (it measures
  /// callback *arrivals*, so it must not move when NTP steps the machine)
  /// while this one is wall-clock epoch milliseconds (`HelloResult.serverTime`
  /// is what a client derives its offset from, so it must be). Subtracting one
  /// from the other in the sweep would yield a silence of roughly negative
  /// fifty-five years, no session would ever exceed the deadline, and the
  /// reaper would look implemented and reap nothing.
  int silentForMs() => _now() - _lastSeen.at;

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
    // Every one of these goes through `_on`, and there is no second path.
    //
    // The table is nine names. Phase 3 registered four; 04-02 added `write`,
    // `writeStatus`, `read`, `readFresh` and `readMany`, pulled forward from
    // Phase 5 because 04-RESEARCH Finding 4 ran the method sweep against a
    // live gateway and found all five answering `-32601`, which put 28 of the
    // contract suite's 44 checks out of reach over the real transport. Only
    // the plumbing moved: Phase 5 still owns write *semantics* (three-state
    // depth beyond forwarding, idempotency windows, hold-to-run), Phase 6 owns
    // authorization, and Phase 10 adds the data services. 03-08's rule stands
    // — the set is frozen against a hand-written literal in `surface_test.dart`
    // so each addition is a deliberate edit to a test that explains its cost.
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
    // The handlers are per session; the outcome log they write to is not.
    // 04-REVIEW CR-02: `writeStatus` is only ever asked by a client that has
    // just reconnected, so a per-socket log was empty every time it was
    // consulted and answered `not_received` — the one verdict that licenses
    // re-actuating a machine — for the commands whose fate was unknown.
    // T-04-05's cross-client concern is answered in `write_outcome_log.dart`:
    // the `cmd` is an 80-bit-random ULID, and Phase 6's identity narrows it
    // further without moving the log back inside a socket's lifetime.
    final values = ValueHandlers(
      api: api,
      config: config,
      now: _now,
      outcomes: _writeOutcomes,
      // Minted by `hello`, which cannot have run yet — read through a callback
      // for the same reason the epoch is.
      ownerOf: () => _sessionId,
    );
    _on(Methods.hello, _hello);
    _on(Methods.ping, _ping);
    _on(Methods.subscribe, handlers.subscribe);
    _on(Methods.unsubscribe, handlers.unsubscribe);
    _on(Methods.write, values.write);
    _on(Methods.writeStatus, values.writeStatus);
    _on(Methods.read, values.read);
    _on(Methods.readFresh, values.readFresh);
    _on(Methods.readMany, values.readMany);
    // Method-not-found, answered by us rather than by json_rpc_2.
    //
    // Left to the library, `Server._tryFallbacks` throws
    // `RpcException.methodNotFound(name)` — constructed with no `data`
    // (`exception.dart:33-34`) — and the serializer then echoes the raw
    // request into the response. A registered fallback puts that refusal back
    // inside `_answer`'s armor, so an unknown method name is answered the same
    // way every known one's refusal is. It does not gate: an unknown name is
    // unknown whether or not the client has said hello, and answering
    // "unknown method" before the handshake tells an attacker nothing it could
    // not learn by reading this file.
    peer.registerFallback((rpc.Parameters params) async {
      throw rpc.RpcException(rpc_errors.METHOD_NOT_FOUND,
          'Unknown method "${params.method}".',
          data: _substitute(params.method));
    });
    unawaited(peer.listen().then(
        (_) => _transportEnded(),
        onError: (Object _) => _transportEnded()));
  }

  /// The client's end vanished — a graceful close, a reset, a yanked cable.
  ///
  /// **This is a teardown, not just a completion, and that is the 03-11 fix.**
  /// Before it, the peer's listen completing merely completed [closed] and the
  /// server released the connection; nothing ever called [close], so
  /// `subscriptions.clear()` never ran and every listener the session had
  /// attached to the backing source stayed attached. `teardown_test.dart`
  /// measured the consequence at 2.50 leaked listeners per kill cycle — one
  /// per subscribed key — which over a day of flapping plant network is a
  /// gateway pushing values for panels that went home.
  ///
  /// **With no close code, deliberately.** A code recorded here would be a
  /// code the server never sent, and `ConnectionClose` distinguishes "we
  /// evicted it" from "it left" by exactly that field. A ledger that invented
  /// one would make every disconnect look deliberate, and "it left" and "we
  /// evicted it for backpressure" call for opposite operator responses.
  void _transportEnded() =>
      unawaited(_teardown(null, 'the client\'s transport ended'));

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
    } on rpc.RpcException catch (error) {
      // A handler that supplied its own `data` has already thought about the
      // echo; one that did not must not be allowed to make that choice by
      // omission. Six refusals in `session_handlers.dart` did exactly that,
      // and each of them was a hang waiting for a request that carried
      // `1e999` in any sibling field. Substituting *here* — at the choke point
      // every handler's failure passes through — is what makes the property
      // structural instead of a rule each future handler has to remember.
      if (error.data != null) rethrow;
      throw rpc.RpcException(error.code, error.message,
          data: _substitute(method));
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
          // An open map, and it stays one (04-RESEARCH A4): the live handshake
          // returns `{}` today, so every key added here is additive and no
          // deployed client has to know about it. A typed DTO would make the
          // next key a breaking change.
          //
          // `tickMs` is the gateway's real cadence, from the config this
          // session was built with. The client's per-subscription staleness
          // arithmetic is derived from it (Finding 5), and the alternative —
          // a constant on the client that must match a server config nobody
          // diffs — fails silently a year later, as values an operator
          // believes are fresh.
          capabilities: {'tickMs': config.tick.inMilliseconds},
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
  ///
  /// **Everything before the first `await` is the synchronous half, and that
  /// is deliberate.** A close decided inside a tick — a backpressure eviction,
  /// the heartbeat reaper — must take the session out of the registry in the
  /// same turn it was decided in. This method is a `Future` because it has to
  /// await the peer, and a caller that only `unawaited`s it would otherwise
  /// leave a window in which the server is still selecting a client it has
  /// already given up on: the next tick fans out to it, the reaper sweeps it,
  /// and the frames go to a socket that is halfway through closing.
  Future<void> close(int code, String reason) => _teardown(code, reason);

  /// The one teardown, and the only thing in this class that releases
  /// anything.
  ///
  /// **Four callers, one body.** The heartbeat sweep, a backpressure verdict
  /// (`applyVerdict`), a protocol refusal (`_requestClose`) and an explicit
  /// server drain all arrive here through [close]; a dead transport arrives
  /// through [_transportEnded]. Five paths and one guard is what makes
  /// "released exactly once" a property of the class rather than a rule each
  /// caller has to remember — and the fifth path is the one that was missing,
  /// which is precisely why it leaked.
  ///
  /// [code] is null when the *client* ended the connection: see
  /// [_transportEnded]. A null code skips step 6 — there is no socket left to
  /// carry it and no decision of ours to announce.
  ///
  /// **Finding 9's order, and every step of it is load-bearing:**
  ///
  ///  1. the close code is recorded *first*, so it is readable even if the
  ///     transport is already gone (Finding 6 / `web_socket_channel` #1698);
  ///  2. the registry entry comes out next, synchronously — see below;
  ///  3. every subscription is detached from the backing `StateManApi`, because
  ///     a listener still attached keeps pushing this client's values into a
  ///     buffer that will never be drained again;
  ///  4. `await peer.close()`, which is what stops handlers from running;
  ///  5. the transport closes last, *with* the code, because a socket closed
  ///     before the peer swallows the peer's final frames — including the
  ///     refusal that explains the close;
  ///  6. the buffer is released, and only now: `_Connection.closeSocket`
  ///     flushes the priority lane on its way out, so a buffer emptied before
  ///     step 5 would throw away the very frame that tells the client why it
  ///     was disconnected. Handles are **not** released — permanence is the
  ///     03-CONTEXT ruling, and `teardown_test.dart` asserts the table's size
  ///     is constant across two hundred cycles rather than returning to
  ///     baseline.
  ///
  /// **Everything before the first `await` is the synchronous half, and that
  /// is deliberate.** A close decided inside a tick — a backpressure eviction,
  /// the heartbeat reaper — must take the session out of the registry in the
  /// same turn it was decided in. This method is a `Future` because it has to
  /// await the peer, and a caller that only `unawaited`s it would otherwise
  /// leave a window in which the server is still selecting a client it has
  /// already given up on: the next tick fans out to it, the reaper sweeps it,
  /// and the frames go to a socket that is halfway through closing.
  Future<void> _teardown(int? code, String reason) async {
    if (_closed) return;
    _closed = true;
    if (code != null) _sentCloseCode ??= code;
    _onClosing?.call(this);
    subscriptions.clear();
    await peer.close();
    if (code != null) await _closeChannel?.call(code, reason);
    // Step 6. `drain()` is the only release the buffer offers — it empties
    // both lanes and hands back what it held, which is discarded here because
    // by this line there is nowhere left to send it. The reference itself is
    // final and cannot be nulled; it does not need to be, because the session
    // left the registry at step 2 and the buffer goes wherever the session
    // goes. What must not survive is the *contents*: a conflated frame per
    // subscribed handle, held for a client that is gone.
    buffer.drain();
    if (!_done.isCompleted) _done.complete();
  }
}

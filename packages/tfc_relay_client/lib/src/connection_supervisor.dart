/// The four-state machine that owns one connection's life, and the loop that
/// builds the next one when it dies.
///
/// Source: 04-RESEARCH Finding 2, whose state table is this file's spec:
///
/// | State | Entered when | Backoff |
/// |---|---|---|
/// | `connecting` | an attempt starts | — |
/// | `resyncing` | socket up, hello answered, subscriptions re-establishing | **not** reset |
/// | `ready` | every subscription has its snapshot | **reset** |
/// | `down` | the attempt failed, or an established link dropped | next attempt scheduled |
///
/// **The one line CLI-02 is about.** The schedule is put back to its
/// attempt-0 window on entry to `ready` and nowhere else. A gateway that
/// accepts sockets and closes them before the snapshot lands is exactly the
/// flap that bites: reset on entry to `resyncing` and every panel in the
/// factory redials from the same 40 ms window, in a wave, against a gateway
/// still replaying snapshots for the previous wave. The herd is
/// self-sustaining — the synchronised retry is what keeps the gateway too busy
/// to finish, which is what keeps the retries synchronised — so the rule is
/// that a link earns its forgiveness by *delivering a snapshot*, not by
/// answering the phone. `reconnect_test.dart`'s
/// `a server that closes before the snapshot does not earn a reset` is the arm
/// that fails the wrong version; every happy-path reconnect case passes under
/// it, which is why that one arm exists.
///
/// **Nothing here reads a close code.** Finding 2 drove a protocol mismatch
/// against the real gateway and saw 4005, then drove a `killOnce` through the
/// fault proxy and saw **1002 with an empty reason** — a yanked cable is
/// indistinguishable-by-code from a protocol error. So the stop decision is
/// taken from the thing that actually carries meaning: the gateway *answered*
/// the handshake and refused it by version. Everything else — a cut cable, a
/// 4002 drain, a socket that ends with no code at all — means the link went
/// away, and the answer to that is always to come back.
///
/// **A fresh peer per connection, and one teardown for both ends of it.** The
/// lifecycle half is `tfc_relay_server`'s `relay_session.dart:418-440`, copied
/// with its reasoning: `listen()` is routed to the same teardown on completion
/// *and* on error, because the server's 03-11 defect was a completion path
/// that released the connection without ever running the teardown, measured at
/// 2.50 leaked listeners per kill cycle. The client does this on every
/// reconnect attempt, and a panel whose gateway is rebooting does it for as
/// long as the reboot takes.
///
/// **Handlers are born with armor.** Every notification body and the fallback
/// carry the pre-substituted `data` from `relay_session.dart:521-526`. Echoing
/// a request that may hold a non-finite number is what makes the *error*
/// unencodable, and an unencodable error hangs every error path on that peer
/// (STATE line 77, the 02-05 trap).
///
/// What breaks in the plant without this file: the panel connects once and
/// never again. A gateway restart at shift change leaves every screen in the
/// control room grey until somebody walks around power-cycling them.
library;

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'backoff.dart';
import 'client_config.dart';
import 'clock_offset.dart';
import 'deadline.dart';
import 'freshness_watchdog.dart';
import 'readiness_barrier.dart';
import 'resync_engine.dart';
import 'subscription_state.dart';
import 'ws_transport.dart';

/// Where a connection is in its life. Four, and no fifth — every switch over
/// this enum in the client is exhaustive with no fallthrough arm, so a fifth
/// state would be a compile error rather than a transition nobody handles.
enum LinkState {
  /// An attempt is in flight. The cache is retained and shown as stale.
  connecting,

  /// The socket is up and the handshake answered; snapshots are on their way.
  /// The link is up and the values are not yet trustworthy.
  resyncing,

  /// Every subscription is holding its snapshot. Normal.
  ready,

  /// The attempt failed, or an established link dropped. Next attempt
  /// scheduled unless the gateway refused this build outright.
  down,
}

/// The JSON-RPC error code the gateway refuses an unspeakable protocol with.
///
/// Declared here rather than imported: the server's `ServerErrorCodes` lives
/// in a package this one depends on only for its tests, and a production file
/// may not reach into a dev dependency. The number is the contract, and
/// `reconnect_test.dart` drives it verbatim.
const int _versionMismatch = -32004;

/// The code this client reports its own handler failures under.
const int _handlerFailed = -32000;

/// Builds a socket, builds a peer, drives hello through resubscribe to a
/// snapshot, feeds the watchdog, and schedules the next attempt when the link
/// dies.
final class ConnectionSupervisor {
  ConnectionSupervisor({
    required this.uri,
    required this.config,
    required this.backoff,
    required this.barrier,
    required this.watchdog,
    required this.subscriptions,
    required this.storeFor,
    this.client = const PeerInfo('tfc_relay_client', '0.1.0'),
    void Function(StatusParams status)? onStatus,
    void Function(String reason)? onBye,
    int Function()? now,
    Future<ConnectAttempt> Function(Uri uri)? dial,
  })  : _onStatus = onStatus,
        _onBye = onBye,
        _now = now ?? _wallClock,
        _dial = dial ?? connect {
    _resync = ResyncEngine(
      storeFor: storeFor,
      subscribe: _subscribe,
      subscriptions: subscriptions,
    );
  }

  /// Where the gateway is. One address; a panel dials the gateway its config
  /// names and does not go looking for another one.
  final Uri uri;

  final ClientConfig config;

  /// The schedule. Reset in exactly one place — see [_enter].
  final Backoff backoff;

  /// The rendezvous every call that touches the wire waits on.
  final ReadinessBarrier barrier;

  /// The link deadline, fed by every inbound frame of any kind.
  final FreshnessWatchdog watchdog;

  /// The pages this panel is showing. Owned by the caller: this class
  /// re-establishes them, it does not decide which exist.
  final Map<String, SubscriptionState> subscriptions;

  /// One cache per subscription — see `resync_engine.dart` on why a shared one
  /// manufactures a permanent false-gap loop.
  final ValueStore Function(String sub) storeFor;

  /// Who this panel says it is at the handshake.
  final PeerInfo client;

  final void Function(StatusParams status)? _onStatus;
  final void Function(String reason)? _onBye;
  final int Function() _now;

  /// How one attempt reaches the gateway. Defaults to [connect], the real
  /// dial, and is overridden only by a harness.
  ///
  /// The seam exists because the shared contract suite calls
  /// `StateManApi Function() make` **synchronously** (04-RESEARCH Finding 6)
  /// while a `RelayServer` only learns its port from an asynchronous
  /// ephemeral bind (`relay_server.dart:219-247`, port 0 on purpose). Without
  /// this, a contract leg would have to guess a port number before anything
  /// was listening on it, and a guessed port that collides is a flaky suite
  /// blaming the client. Overriding the dial rather than the [uri] keeps the
  /// retry policy exactly where the operator can see it: this is one attempt
  /// in, one [ConnectAttempt] out, same as the real one, so backoff, the
  /// generation counter and the health line are all unchanged.
  final Future<ConnectAttempt> Function(Uri uri) _dial;

  final StreamController<LinkState> _states =
      StreamController<LinkState>.broadcast();

  final List<Duration> _waits = <Duration>[];

  /// How many scheduled waits [debugScheduledWaits] keeps.
  static const int _waitHistory = 64;

  late final ResyncEngine _resync;

  LinkState _state = LinkState.down;
  rpc.Peer? _peer;
  ClockOffset _clockOffset = ClockOffset.none;
  Timer? _retry;
  bool _stopped = false;
  String? _stopReason;
  String? _lastDownReason;
  bool _disposed = false;

  /// Which connection the callbacks in flight belong to.
  ///
  /// Bumped the moment a connection is retired, so a `listen()` that completes
  /// after the teardown has already run — the ordinary shape of a socket that
  /// died while a call was on it — is recognised as belonging to a connection
  /// that no longer exists instead of scheduling a second reconnect for the
  /// same failure.
  int _generation = 0;

  /// Every transition, in order, for the operator-facing link indicator.
  ///
  /// Broadcast, and a caller subscribes **before** starting: the session can
  /// register in the same event-loop turn the connect completes in
  /// (`ws_fault_test.dart:118-121`), so a listener attached afterwards waits
  /// for a transition that already happened.
  Stream<LinkState> get states => _states.stream;

  LinkState get state => _state;

  /// The current connection's peer, or null when there is none.
  ///
  /// The seam `callWithDeadline` reads — as a getter, because this field is
  /// swapped on every reconnect and a call must capture it once before it
  /// suspends.
  rpc.Peer? get peer => _peer;

  /// The skew captured at the last hello. [ClockOffset.none] before the first.
  ClockOffset get clockOffset => _clockOffset;

  /// The subscription bookkeeping, exposed so the client above can read the
  /// configuration complaints a resubscribe collected.
  ResyncEngine get resync => _resync;

  /// Whether the loop has given up for good.
  bool get stopped => _stopped;

  /// Why, in words an integrator can act on.
  String? get stopReason => _stopReason;

  /// Why the last connection ended, for the operator-facing health line.
  ///
  /// Carried because "attempt failed" with no cause is a phone call to the
  /// integrator — `ws_transport.dart` makes the same argument about the value
  /// it hands back from a refused dial.
  String? get lastDownReason => _lastDownReason;

  /// Every delay this supervisor has waited before an attempt, in order.
  ///
  /// The schedule's observable history. `reconnect_test.dart` asserts the band
  /// these were drawn from, which is the only honest claim about a jittered
  /// number.
  List<Duration> get debugScheduledWaits =>
      List<Duration>.unmodifiable(_waits);

  /// Every timer this client owns: the watchdog's one deadline, plus the one
  /// pending reconnect when an attempt is scheduled.
  ///
  /// Never more than two, whatever else is going on. The count is the design —
  /// a panel that flaps all shift accumulates one orphaned timer per cycle if
  /// the teardown misses one, and the one that is missed fires into a
  /// connection that no longer exists.
  int get debugTimerCount =>
      watchdog.debugTimerCount + (_retry == null ? 0 : 1);

  /// Begins dialling. Never throws.
  ///
  /// A gateway that is not up yet is the *normal* state of a panel at
  /// power-on — it boots with the rest of the line, on a switch still learning
  /// MAC addresses — so a start that threw would leave the screen grey until
  /// somebody drove to the factory.
  void start() {
    if (_disposed || _stopped) return;
    if (_state != LinkState.down || _retry != null) return;
    unawaited(_attempt());
  }

  /// The client is going away.
  ///
  /// Order matters: retire the generation first so nothing in flight schedules
  /// another attempt, then drop the timers, then the peer, then release
  /// everyone waiting on the barrier with an error they can show.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _retry?.cancel();
    _retry = null;
    watchdog.dispose();
    barrier.dispose();
    final peer = _peer;
    _peer = null;
    if (peer != null) await peer.close().catchError((Object _) {});
    await _states.close();
  }

  /// One attempt, from the dial to whatever ends it.
  Future<void> _attempt() async {
    if (_disposed || _stopped) return;
    final gen = ++_generation;
    _enter(LinkState.connecting);

    final ConnectAttempt attempt;
    try {
      attempt = await _dial(uri);
    } catch (error) {
      // `connect` reports a refused dial as a value, so a throw here is
      // something else entirely — a bad URI, a DNS failure. Same answer: the
      // gateway is not reachable, come back.
      _down(gen, 'the dial failed: $error');
      return;
    }
    if (_disposed || gen != _generation) return;

    // Sealed, two arms, and no fallthrough: a third outcome added to
    // `ConnectAttempt` is a compile error here rather than a dial whose result
    // nobody looked at.
    switch (attempt) {
      case ConnectFailed(:final error):
        _down(gen, 'the gateway did not answer: $error');
      case ConnectSucceeded(:final channel):
        await _serve(gen, channel);
    }
  }

  /// The socket is up: build the peer, arm it, and drive it to a snapshot.
  Future<void> _serve(int gen, StreamChannel<String> channel) async {
    final peer = rpc.Peer(channel);
    _peer = peer;

    peer.registerMethod(Methods.update,
        (rpc.Parameters p) => _armored(Methods.update, () => _update(p)));
    peer.registerMethod(Methods.tick,
        (rpc.Parameters p) => _armored(Methods.tick, () => _tick(p)));
    peer.registerMethod(Methods.resync,
        (rpc.Parameters p) => _armored(Methods.resync, () => _resynced(p)));
    peer.registerMethod(Methods.status,
        (rpc.Parameters p) => _armored(Methods.status, () => _status(p)));
    peer.registerMethod(Methods.bye,
        (rpc.Parameters p) => _armored(Methods.bye, () => _bye(p)));
    // A name this build does not know is answered by us, inside the same
    // armor, rather than by the library — whose refusal echoes the raw request
    // back into the response, which is the unencodable-error hang when the
    // request held a non-finite number.
    peer.registerFallback((rpc.Parameters p) async {
      throw rpc.RpcException(
          _handlerFailed, 'this panel does not answer "${p.method}".',
          data: _substitute(p.method));
    });

    // Both completion paths, one teardown (`relay_session.dart:418-420`).
    unawaited(peer.listen().then(
          (_) => _transportEnded(gen),
          onError: (Object _) => _transportEnded(gen),
        ));

    _enter(LinkState.resyncing);

    try {
      final raw = await callWithDeadline(
        () => _peerFor(gen),
        Methods.hello,
        params: HelloParams(
          protocol: protocolVersion,
          supported: const [protocolVersion],
          client: client,
        ).toJson(),
        deadline: config.controlDeadline,
      );
      if (_disposed || gen != _generation) return;
      watchdog.sawFrame(InboundFrame.rpcResponse);

      final hello =
          HelloResult.fromJson(_asJson(sanitize(raw).value));
      _clockOffset = ClockOffset.fromHello(
        hello.serverTime,
        _now(),
        threshold: config.implausibleClockThreshold,
      );

      // Adopts the epoch and re-establishes every page. It returns only when
      // all of them are holding a snapshot, which is the definition of ready.
      await _resync.onHello(hello.epoch);
      if (_disposed || gen != _generation) return;
    } on rpc.RpcException catch (error) {
      // The gateway answered and said no. A version refusal is the one answer
      // that will not change on the next attempt, and it is taken from the
      // answer rather than from the close that follows it — Finding 2's
      // double signal is one event, and the number on the close means nothing.
      if (error.code == _versionMismatch) {
        _stop('the gateway refused this build\'s protocol version: '
            '${error.message}');
        return;
      }
      _down(gen, 'the handshake was refused: ${error.message}');
      return;
    } catch (error) {
      _down(gen, 'the link died before the snapshot landed: $error');
      return;
    }

    _enter(LinkState.ready);
  }

  /// The peer this generation owns, or null once it has been retired.
  ///
  /// A call that started before a reconnect must not be retargeted at the
  /// replacement socket — for a write that is a second actuation of the
  /// machinery, which this client never performs on its own.
  rpc.Peer? _peerFor(int gen) => gen == _generation ? _peer : null;

  /// The subscribe the resync engine calls, deadline-wrapped.
  Future<DecodedSubscribeResult> _subscribe(String sub, Set<String> keys) async {
    final raw = await callWithDeadline(
      () => _peer,
      Methods.subscribe,
      params: SubscribeParams(sub: sub, keys: keys.toList(growable: false))
          .toJson(),
      deadline: config.controlDeadline,
    );
    watchdog.sawFrame(InboundFrame.rpcResponse);
    return decodeSubscribeResult(raw);
  }

  /// An update frame: handles resolved to keys, then the sequence verdict.
  Future<void> _update(rpc.Parameters params) async {
    watchdog.sawFrame(InboundFrame.update);
    final update = UpdateParams.fromJson(_asJson(sanitize(params.asMap).value));
    final state = subscriptions[update.sub];
    if (state == null) return;

    final changes = <String, DynamicValue>{};
    for (final entry in update.changes.entries) {
      final key = state.handles[entry.key];
      if (key == null) {
        // Never filed under a guess: a value on a mimic under a label the
        // gateway never agreed to is worse than a value missing from it.
        _resync.complaints.add('update for "${update.sub}" named handle '
            '${entry.key}, which this session never announced');
        continue;
      }
      changes[key] = entry.value.toDynamicValue();
    }
    await _resync.onUpdate(update.sub, seq: update.seq, changes: changes);
  }

  /// A tick: the link is alive, and every subscription is re-judged against
  /// the gateway's own clock.
  void _tick(rpc.Parameters params) =>
      watchdog.sawTick(TickParams.fromJson(_asJson(sanitize(params.asMap).value)));

  /// The gateway announced that one page must be rebuilt.
  Future<void> _resynced(rpc.Parameters params) async {
    watchdog.sawFrame(InboundFrame.update);
    final asked = ResyncParams.fromJson(_asJson(sanitize(params.asMap).value));
    await _resync.onResync(asked.sub);
  }

  /// An upstream device changed state. Carried up, never interpreted here.
  void _status(rpc.Parameters params) {
    watchdog.sawFrame(InboundFrame.update);
    final status = StatusParams.fromJson(_asJson(sanitize(params.asMap).value));
    _onStatus?.call(status);
  }

  /// The gateway is leaving on purpose. The close follows; the loop's answer
  /// to it is the same as to any other drop, because a draining gateway is a
  /// gateway that is coming back.
  void _bye(rpc.Parameters params) {
    watchdog.sawFrame(InboundFrame.update);
    final json = _asJson(sanitize(params.asMap).value);
    _onBye?.call('${json['reason'] ?? 'the gateway said goodbye'}');
  }

  /// Wraps a handler body in the pre-substituted armor.
  Future<void> _armored(String name, FutureOr<void> Function() body) async {
    try {
      await body();
    } catch (error) {
      throw rpc.RpcException(
          _handlerFailed, 'this panel could not handle "$name": $error',
          data: _substitute(name));
    }
  }

  /// The request, replaced by the reason it is not here.
  ///
  /// Verbatim from `relay_session.dart:521-526`, including the reasoning: a
  /// request holding a non-finite number makes the error that echoes it
  /// unencodable, and an unencodable error is a hang on every error path that
  /// peer has.
  static Map<String, Object?> _substitute(String method) => {
        'method': method,
        'request': 'omitted: echoing a request that may carry a non-finite '
            'number is what makes the error itself unencodable, and an '
            'unencodable error on a path with no deadline is a hang',
      };

  /// The peer's `listen()` finished, either way. Same teardown for both.
  void _transportEnded(int gen) => _down(gen, 'the transport ended');

  /// This connection is over: retire it, re-arm, and schedule the next.
  void _down(int gen, String why) {
    if (_disposed || gen != _generation) return;
    _generation++;
    _retirePeer();
    // Re-armed so the next caller waits for the new link rather than being
    // let through to a socket that is gone. Everyone already through stays
    // through — a completed future cannot un-complete.
    barrier.rearm();
    _lastDownReason = why;
    _enter(LinkState.down);
    if (_stopped) return;
    _schedule();
  }

  /// The gateway refused this build. Retrying will not change its mind.
  ///
  /// Deliberately *not* guarded by generation: the refusal and the close that
  /// follows it are one event, and whichever of the two arrives first must be
  /// able to stop the loop — including cancelling a retry the other one had
  /// already scheduled.
  void _stop(String why) {
    if (_disposed || _stopped) return;
    _stopped = true;
    _stopReason = why;
    _generation++;
    _retry?.cancel();
    _retry = null;
    _retirePeer();
    barrier.rearm();
    _enter(LinkState.down);
  }

  void _retirePeer() {
    final peer = _peer;
    _peer = null;
    if (peer == null) return;
    // Closing the peer closes the channel's sink, which closes the socket.
    // Nothing waits on it: a close that fails is a socket that was already
    // gone, which is the ordinary shape of a teardown after a cut cable.
    unawaited(peer.close().catchError((Object _) {}));
  }

  void _schedule() {
    _retry?.cancel();
    final wait = backoff.next();
    _waits.add(wait);
    // Bounded (04-REVIEW IN-02). One entry per attempt and never trimmed is a
    // leak with a diagnostic excuse: a panel whose gateway is down all shift
    // makes an attempt every backoffCap. What the list answers — "what has the
    // schedule been doing lately" — is a question about the recent past.
    if (_waits.length > _waitHistory) _waits.removeAt(0);
    _retry = Timer(wait, () {
      _retry = null;
      unawaited(_attempt());
    });
  }

  /// Announces a transition, and performs the two things that belong to
  /// entering a state rather than to the code path that got there.
  void _enter(LinkState next) {
    if (_disposed || _state == next) return;
    _state = next;
    if (next == LinkState.ready) {
      barrier.open();
      // **Here and nowhere else.** See the library doc: a link earns its
      // forgiveness by delivering a snapshot, not by answering the phone.
      backoff.reset();
    }
    if (!_states.isClosed) _states.add(next);
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// Narrows a decoded frame to the map shape the DTOs take.
  static Map<String, Object?> _asJson(Object? raw) => raw is Map
      ? {for (final entry in raw.entries) '${entry.key}': entry.value}
      : throw FormatException('expected a JSON object, got ${raw.runtimeType}');
}

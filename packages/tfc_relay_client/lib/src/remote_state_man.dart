/// The `StateManApi` a panel holds: the same shape as `ChannelStateMan`, with
/// the four things that file deliberately omits wired around it.
///
/// `channel_state_man.dart:11-16` says outright that it was written as a
/// rehearsal for this class — "same store, same synchronous-answers-from-cache
/// shape, same `subscribe` adapter over the same node. What it is missing is
/// everything a socket forces — reconnect, resync, sequence gaps and
/// per-request deadlines". This file is that class with the missing four
/// supplied, so it is a copy where it can be (including the comments, because
/// the comments are the reasoning) and different only where a socket makes it
/// different. Those differences, in full:
///
///  1. **No connection at construction.** The shared contract suite calls
///     `StateManApi Function() make` synchronously (04-RESEARCH Finding 6), so
///     there is nothing to await in a constructor. `_peer` is therefore not a
///     field here at all: it is owned by [ConnectionSupervisor], swapped on
///     every reconnect, and read through [ConnectionSupervisor.peer] at the
///     moment of each call. That constraint is also the right production shape
///     — a panel boots with the rest of the line, and a client that threw at
///     power-on would put the plant's start-up order in the operator's hands.
///
///  2. **Every async method waits on the readiness barrier.** `read`, `listen`,
///     `keys` and `subscribe` do not: they are cache reads by design
///     (`state_man_api.dart:90-96`, "synchronous and never a round trip"), and
///     a page that blocked on the socket before it could paint would be grey at
///     exactly the moment an operator needs to see the last known value marked
///     stale.
///
///  3. **Handler registration is per connection, not per client.** In
///     `ChannelStateMan` the `registerMethod` block lives in the constructor
///     because there is one `Peer` for life. A fresh `Peer` per socket means
///     fresh registrations per socket, so that block lives in the supervisor's
///     per-connection setup and not here.
///
///  4. **Every request carries a deadline** (`deadline.dart`), and every
///     failure goes through one classifier (`failure_taxonomy.dart`). A closed
///     transport is reported by `json_rpc_2` as a `StateError`, so a call site
///     that caught only `RpcException` would never see the link die.
///
/// **One store per subscription, and why this class owns the map.** A
/// `ValueStore` holds a single sequence counter, so N subscriptions sharing one
/// store rebuild client-side the false-gap hazard the server refuses
/// server-side (04-04). The supervisor takes `subscriptions` and `storeFor` by
/// reference and never invents an entry — page lifecycle is this class's, which
/// is why the maps live here and the supervisor only re-establishes what it is
/// given.
///
/// What breaks in the plant without this file: nothing on a panel can read a
/// tag. It is the whole client surface.
library;

import 'dart:async';

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'backoff.dart';
import 'client_config.dart';
import 'connection_supervisor.dart';
import 'deadline.dart';
import 'freshness_watchdog.dart';
import 'readiness_barrier.dart';
import 'subscription_state.dart';

/// The subscription a client opens for the keys it was constructed with.
///
/// One name, because a panel shows pages and this class is handed a page's key
/// set; a second subscription is a second entry in [_subscriptions], which is
/// the shape the supervisor and the resync engine already take.
const String defaultPageSubscription = 'page';

/// A `StateManApi` whose values only ever arrive over a WebSocket.
final class RemoteStateMan {
  /// Points a client at [uri] and starts dialling. Never throws, never blocks.
  ///
  /// [keys] is the page this panel is showing. It becomes one subscription,
  /// re-established by the supervisor on every reconnect; an empty set is a
  /// legitimate client that reads and writes without watching anything.
  RemoteStateMan({
    required this.uri,
    required this.config,
    Set<String> keys = const <String>{},
    String page = defaultPageSubscription,
    Backoff? backoff,
    PeerInfo client = const PeerInfo('tfc_relay_client', '0.1.0'),
    void Function(StatusParams status)? onStatus,
    void Function(String reason)? onBye,
  }) : _page = page {
    if (keys.isNotEmpty) {
      _subscriptions[page] =
          SubscriptionState(subId: page, keys: <String>{...keys});
      for (final key in keys) {
        _subOf[key] = page;
      }
    }

    // Built here and handed over: `ConnectionSupervisor.dispose` disposes the
    // watchdog and the barrier it was given, so these must not be shared with a
    // second supervisor (04-07 handoff). This client owns exactly one.
    _supervisor = ConnectionSupervisor(
      uri: uri,
      config: config,
      backoff: backoff ??
          Backoff(base: config.backoffBase, cap: config.backoffCap),
      barrier: ReadinessBarrier(),
      watchdog: FreshnessWatchdog(
        config: config,
        onViewFreshnessChanged: (_) {},
      ),
      subscriptions: _subscriptions,
      storeFor: _storeFor,
      client: client,
      onStatus: onStatus,
      onBye: onBye,
    );

    // Attached **before** `start()`. The supervisor can reach `ready` in the
    // same event-loop turn the connect completes in, so a listener attached
    // afterwards waits for a transition that already happened — the ordering
    // trap `ws_fault_test.dart:118-121` names from the other end.
    _transitions = _supervisor.states.listen(_onLinkState);
    _supervisor.start();
  }

  /// Where the gateway is.
  final Uri uri;

  /// The deadlines, the backoff window and the staleness horizon.
  final ClientConfig config;

  /// The subscription this client's constructor keys were filed under.
  final String _page;

  /// The pages this panel is showing. Read by the supervisor; owned here.
  final Map<String, SubscriptionState> _subscriptions =
      <String, SubscriptionState>{};

  /// One cache per subscription — see the library doc on the shared-counter
  /// hazard a single store would rebuild.
  final Map<String, ValueStore> _stores = <String, ValueStore>{};

  /// key → the subscription whose store holds it.
  ///
  /// Fixed at the moment the key is first filed, and never moved: a key that
  /// changed stores would change *node identity*, and a widget holds the node
  /// it was handed.
  final Map<String, String> _subOf = <String, String>{};

  /// Closers for the streams [subscribe] handed out that are still open.
  ///
  /// The shape is `channel_state_man.dart:114-119`'s, including the
  /// self-deregistering closer: a registry that only grows is a leak, and a
  /// panel runs for a shift.
  final _closeHandedOutStreams = <Future<void> Function()>{};

  late final ConnectionSupervisor _supervisor;
  late final StreamSubscription<LinkState> _transitions;

  var _disposed = false;

  // -------------------------------------------------------------- the link

  /// Where the connection is right now, for the operator-facing indicator.
  LinkState get linkState => _supervisor.state;

  /// Every transition, in order.
  Stream<LinkState> get linkStates => _supervisor.states;

  /// Whether a call issued right now would go straight out.
  bool get isReady => _supervisor.barrier.isOpen;

  /// Why the last connection ended, in words an integrator can act on.
  String? get lastDownReason => _supervisor.lastDownReason;

  /// Set when the gateway refused this build outright and the loop gave up.
  String? get stopReason => _supervisor.stopReason;

  /// Configuration problems collected while re-establishing pages — a rejected
  /// key, a snapshot entry naming a handle nobody announced. Never thrown: a
  /// page carries ~1500 hand-edited keys and one typo must cost one tag.
  List<String> get complaints =>
      List<String>.unmodifiable(_supervisor.resync.complaints);

  /// Every timer this client owns. Never more than two, whatever else is going
  /// on — the count is the design, not an implementation detail.
  int get debugTimerCount => _supervisor.debugTimerCount;

  // ------------------------------------------------- answers from the store

  /// The node for [key] — the same instance every time.
  ValueListenable<DynamicValue> listen(String key) => _storeOf(key).node(key);

  /// The last known value for [key], or null if none is known yet.
  ///
  /// Synchronous and never a round trip, whatever the link is doing. Null means
  /// "not known yet", which is a different thing from a known-bad value.
  DynamicValue? read(String key) => _storeOf(key).peek(key);

  /// The keys a value has actually arrived for.
  ///
  /// Filtered on arrival, exactly as `channel_state_man.dart:131-142` filters:
  /// [listen] creates a node for any key asked of it, including one mistyped
  /// into a page config, and offering that back to the picker would launder a
  /// typo into a valid binding.
  List<String> get keys => [
        for (final store in _stores.values)
          for (final key in store.keys)
            if (store.peek(key) != null) key,
      ];

  /// A broadcast view of the same node, for stream-consuming code.
  ///
  /// A view and never a second source of truth. Returned synchronously so
  /// taking the stream and listening to it happen in one turn, which is what
  /// stops a widget missing the first values of its own subscription.
  Stream<DynamicValue> subscribe(String key) {
    final node = _storeOf(key).node(key);
    late final StreamController<DynamicValue> controller;
    void push() => controller.add(node.value);
    late final Future<void> Function() close;
    close = () async {
      _closeHandedOutStreams.remove(close);
      await controller.close();
    };
    controller = StreamController<DynamicValue>.broadcast(
      onListen: () {
        node.addListener(push);
        _closeHandedOutStreams.add(close);
      },
      onCancel: () {
        node.removeListener(push);
        _closeHandedOutStreams.remove(close);
      },
    );
    // Added twice on purpose — once here, once in `onListen`. A stream nobody
    // ever listened to still has to be closable at dispose.
    _closeHandedOutStreams.add(close);
    return controller.stream;
  }

  // -------------------------------------------------- answers over the wire

  /// Forces a round trip and resolves with a freshly-read value.
  Future<DynamicValue> readFresh(String key) async {
    final raw = await _request(Methods.readFresh, {'key': key});
    return _value(_asJson(raw)['value']);
  }

  /// One round trip for many keys.
  ///
  /// One request for however many keys, which is the promise the interface
  /// makes (`state_man_api.dart:104-109`) and the reason the diagnostics page
  /// does not pay N latencies for N tags.
  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    final raw = _asJson(await _request(Methods.readMany, {'keys': keys}));
    final values = raw['values'];
    if (values is! Map) return const <String, DynamicValue>{};
    return {
      for (final entry in values.entries) '${entry.key}': _value(entry.value),
    };
  }

  // ---------------------------------------------------------------- teardown

  /// Drops every listener, closes every handed-out stream, stops the
  /// reconnect loop and releases the socket. Idempotent.
  ///
  /// Handed-out streams go **before** the link, as in
  /// `channel_state_man.dart:424-436`, and the supervisor goes last because
  /// disposing it errors the readiness barrier — which is how a call still
  /// waiting for a connection gets something it can show instead of a spinner
  /// that never stops.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final close in List.of(_closeHandedOutStreams)) {
      await close();
    }
    _closeHandedOutStreams.clear();

    await _transitions.cancel();
    await _supervisor.dispose();

    for (final store in _stores.values) {
      store.dispose();
    }
  }

  // ------------------------------------------------------------- internals

  /// The store for [sub], created on first use.
  ValueStore _storeFor(String sub) =>
      _stores.putIfAbsent(sub, ValueStore.new);

  /// The store that holds [key].
  ///
  /// A key nobody has filed belongs to the page subscription, so a `listen` for
  /// a tag this client was not constructed with still returns a stable node
  /// rather than a fresh one per call.
  ValueStore _storeOf(String key) => _storeFor(_subOf[key] ?? _page);

  /// One request out and one answer back, once the link is up.
  ///
  /// The barrier wait is the whole of difference (2) in the library doc, and
  /// the disposed guards on either side of it are not defensive tidiness: a
  /// page can close while its read is parked on the barrier, and a
  /// `sendRequest` on a peer that is gone throws a `StateError` out of
  /// `json_rpc_2` which the caller would have to tell apart from a real defect.
  Future<Object?> _request(
    String method,
    Map<String, Object?> params, {
    Duration? deadline,
  }) async {
    _refuseIfDisposed(method);
    await _supervisor.barrier.ready;
    _refuseIfDisposed(method);
    return callWithDeadline(
      () => _supervisor.peer,
      method,
      params: params,
      deadline: deadline ?? config.controlDeadline,
    );
  }

  /// A [StateError] of this file's own, naming the call that arrived after the
  /// close — the precedent is `channel_state_man.dart:484-492`. There is no
  /// value to invent and no round trip left to make.
  void _refuseIfDisposed(String method) {
    if (!_disposed) return;
    throw StateError(
        'RemoteStateMan was asked for "$method" after it was disposed; the '
        'link is closed, so there is no round trip left to make and no answer '
        'that would not be invented');
  }

  /// One transition. Everything that belongs to *entering* a state rather than
  /// to the code path that got there lives here.
  void _onLinkState(LinkState state) {
    if (_disposed) return;
  }

  /// A wire value, sanitized and quality-composed by [WireValue.fromJson].
  static DynamicValue _value(Object? raw) {
    final wire = WireValue.fromJson(_asJson(raw));
    return DynamicValue(value: wire.v, quality: wire.q);
  }

  /// Narrows a decoded JSON value to the map shape the protocol decoders take.
  ///
  /// `json_rpc_2` hands back whatever `jsonDecode` produced, which is a
  /// `Map<String, dynamic>` for an object and anything at all for a peer that
  /// is lying. A `FormatException` here is the honest outcome — the decoders
  /// this feeds are documented to be tolerant of *fields*, not of being handed
  /// a list where an object belongs.
  static Map<String, Object?> _asJson(Object? raw) => raw is Map
      ? {for (final entry in raw.entries) '${entry.key}': entry.value}
      : throw FormatException('expected a JSON object, got ${raw.runtimeType}');
}

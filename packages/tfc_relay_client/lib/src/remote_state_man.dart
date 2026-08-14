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
import 'client_sub_apis.dart';
import 'connection_supervisor.dart';
import 'deadline.dart';
import 'failure_taxonomy.dart';
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
final class RemoteStateMan implements StateManApi {
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

  /// Commands whose outcome this client cannot establish.
  ///
  /// A `WriteUnknown` is the only verdict that lands here and the only one that
  /// stays: applied, rejected and never-received are all settled answers, and
  /// re-querying a settled answer is a question nobody needed asked.
  final _unresolved = <String>{};

  /// Every `writeStatus` re-query this client has issued, in order.
  ///
  /// The observable the no-re-actuation property is asserted against: an
  /// implementation that re-sent the write instead would leave this empty and
  /// [debugWritesSent] one higher.
  final _writeStatusQueries = <List<String>>[];

  var _writesSent = 0;
  var _requerying = false;

  late final ConnectionSupervisor _supervisor;
  late final StreamSubscription<LinkState> _transitions;

  var _disposed = false;

  /// Commands still in flight, for the case that has to prove the set was not
  /// empty when the re-query ran.
  List<String> get debugUnresolvedCmds => List<String>.unmodifiable(_unresolved);

  /// The cmd lists this client has re-queried, in order.
  List<List<String>> get debugWriteStatusQueries => [
        for (final query in _writeStatusQueries) List<String>.unmodifiable(query),
      ];

  /// How many `write` requests reached the wire. Never more than one per call.
  int get debugWritesSent => _writesSent;

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
  @override
  ValueListenable<DynamicValue> listen(String key) => _storeOf(key).node(key);

  /// The last known value for [key], or null if none is known yet.
  ///
  /// Synchronous and never a round trip, whatever the link is doing. Null means
  /// "not known yet", which is a different thing from a known-bad value.
  @override
  DynamicValue? read(String key) => _storeOf(key).peek(key);

  /// The keys a value has actually arrived for.
  ///
  /// Filtered on arrival, exactly as `channel_state_man.dart:131-142` filters:
  /// [listen] creates a node for any key asked of it, including one mistyped
  /// into a page config, and offering that back to the picker would launder a
  /// typo into a valid binding.
  @override
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
  @override
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
  @override
  Future<DynamicValue> readFresh(String key) async {
    final raw = await _request(Methods.readFresh, {'key': key});
    return _value(_asJson(raw)['value']);
  }

  /// One round trip for many keys.
  ///
  /// One request for however many keys, which is the promise the interface
  /// makes (`state_man_api.dart:104-109`) and the reason the diagnostics page
  /// does not pay N latencies for N tags.
  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    final raw = _asJson(await _request(Methods.readMany, {'keys': keys}));
    final values = raw['values'];
    if (values is! Map) return const <String, DynamicValue>{};
    return {
      for (final entry in values.entries) '${entry.key}': _value(entry.value),
    };
  }

  // -------------------------------------------------------- the sub-APIs

  /// Browse, timeseries, history views and preferences — all four over the same
  /// pipe, none of them holding a source of their own.
  ///
  /// Built once and kept, rather than minted per access, for one reason that
  /// only applies to the last of them (`channel_state_man.dart:443-448`):
  /// [preferences] owns the broadcast controller every local listener reads
  /// from, and a fresh instance per getter call would hand the second listener a
  /// stream nothing ever pushes to. The other three are stateless and are kept
  /// alongside it for symmetry.
  ///
  /// None of these has a gateway handler before Phase 10; until then they
  /// surface `-32601` (04-RESEARCH Finding 4), which is the honest answer and
  /// the gap 04-10 counts.
  @override
  late final BrowseApi browse = ClientBrowseApi(_dataServiceCall);

  @override
  late final TimeseriesApi timeseries = ClientTimeseriesApi(_dataServiceCall);

  @override
  late final HistoryViewApi historyViews =
      ClientHistoryViewApi(_dataServiceCall);

  @override
  late final ClientPreferencesApi preferences =
      ClientPreferencesApi(_dataServiceCall);

  /// The request the sub-APIs are handed: the same barrier, the same deadline
  /// and the same peer-at-call-time capture as every other call this client
  /// makes.
  Future<Object?> _dataServiceCall(
          String method, Map<String, Object?> params) =>
      _request(method, params);

  // ------------------------------------------------------------- the write

  /// Writes [value] to [key] and reports what became of it.
  ///
  /// **Never throws to report an outcome, and never retried.** Both halves are
  /// the property rather than an omission (`CLAUDE.md`: no queue / no retry =
  /// the write-safety property). A retry here would be invisible from the API
  /// surface — same call, same result type, slightly later — and on a plant it
  /// is a second actuation of machinery an operator commanded once. What
  /// replaces it is [Methods.writeStatus] on the next `ready`: the client asks
  /// what became of the command, it does not send the command again.
  ///
  /// The `cmd` is minted **here**, at call time, because the call is the
  /// operator action (`state_man_api.dart:121-125`). It is the only handle
  /// `writeStatus` has on this write, so it goes into [_unresolved] before the
  /// request leaves — a socket that dies between the two would otherwise lose
  /// the one identifier the outcome can ever be reconciled against.
  ///
  /// The non-finite halves are not symmetric, and the asymmetry is copied
  /// verbatim from `channel_state_man.dart:207-227`:
  ///
  ///  * a non-finite **value** is sanitized *knowingly*: null goes on the wire,
  ///    because `jsonEncode` throws on NaN and ±Infinity rather than emitting
  ///    null, so an unsanitized value does not fail one write — it fails the
  ///    frame, which a real pipe shares with every other client on it.
  ///    [Quality.badNonFinite] is attached locally once the outcome is back, so
  ///    the operator sees a fault rather than a blank box.
  ///  * a non-finite **expect** is refused outright. See the [ArgumentError].
  @override
  Future<WriteResult> write(String key, Object? value, {Object? expect}) async {
    final sanitizedValue = sanitize(value);
    final sanitizedExpect = sanitize(expect);
    if (sanitizedExpect.hadNonFinite) {
      throw ArgumentError.value(
          expect,
          'expect',
          'a write cannot carry a non-finite compare-and-set guard: nulling '
              'it is this path\'s encoding of "no guard at all", so a guarded '
              'write would silently become an unconditional one');
    }

    final cmd = newUlid();
    _unresolved.add(cmd);

    WriteResult result;
    try {
      final raw = await _request(
        Methods.write,
        {
          'cmd': cmd,
          'key': key,
          'value': sanitizedValue.value,
          if (expect != null) 'expect': sanitizedExpect.value,
        },
        deadline: config.writeDeadline,
        onSend: () => _writesSent++,
      );
      result = WriteResult.fromJson(_asJson(raw));
    } catch (error) {
      // One seam decides whether this means "we do not know" or "the server
      // said no", and it rethrows anything that is a defect in this process
      // rather than a condition of the plant (`failure_taxonomy.dart`).
      result = writeOutcomeFor(cmd, error);
    }

    // Only an established outcome settles the command. `WriteUnknown` is the
    // one verdict that does not, which is exactly what makes it re-queryable.
    if (result is! WriteUnknown) _unresolved.remove(cmd);

    if (sanitizedValue.hadNonFinite) _markNonFinite(key);
    return result;
  }

  /// Records, locally, that the value written to [key] was not a number.
  ///
  /// After the outcome rather than before it, and the ordering is load-bearing
  /// (`channel_state_man.dart:252-265`). The gateway pushes the readback as an
  /// update whose flush is scheduled while the write is still being handled, so
  /// on an ordered channel that update is delivered *before* the response this
  /// runs after. Marking first would be marking something the readback then
  /// overwrote — with a good-quality null, which renders as a healthy empty box.
  void _markNonFinite(String key) {
    if (_disposed) return;
    final store = _storeOf(key);
    final held = store.peek(key);
    store.applyBatch({
      key: DynamicValue(
        value: null,
        quality: Quality.badNonFinite,
        sourceTime: held?.sourceTime,
      ),
    });
  }

  /// Asks the gateway what became of every command still in flight.
  ///
  /// Invoked on entry to `ready` and nowhere else. This is the whole of the
  /// recovery story for a write whose link died under it: one question about N
  /// commands, and never a re-send. A gateway that has forgotten the command
  /// answers `unknown` again, which leaves it in [_unresolved] for the next
  /// `ready` to ask about — forgetting is not evidence that it never happened.
  Future<void> _requeryWriteStatus() async {
    if (_requerying) return;
    final cmds = List<String>.of(_unresolved);
    if (cmds.isEmpty) return;
    _requerying = true;
    _writeStatusQueries.add(cmds);
    try {
      final raw = _asJson(await _request(Methods.writeStatus, {'cmds': cmds}));
      final results = raw['results'];
      if (results is! List) return;
      for (final entry in results) {
        final outcome = WriteResult.fromJson(_asJson(entry));
        if (outcome is WriteUnknown) continue;
        _unresolved.remove(outcome.cmd);
      }
    } catch (_) {
      // A re-query that fails leaves the commands unresolved, which is the
      // honest state and the one the next `ready` will ask about again. What it
      // never becomes is a reason to send the write a second time.
    } finally {
      _requerying = false;
    }
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
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final close in List.of(_closeHandedOutStreams)) {
      await close();
    }
    _closeHandedOutStreams.clear();
    await preferences.dispose();

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
    void Function()? onSend,
  }) async {
    _refuseIfDisposed(method);
    await _supervisor.barrier.ready;
    _refuseIfDisposed(method);
    onSend?.call();
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
    // Entry to `ready` and nowhere else: `resyncing` means the socket answered
    // the phone, and a re-query issued then races the snapshot it is competing
    // with for the same link.
    if (state != LinkState.ready) return;
    if (_unresolved.isEmpty) return;
    unawaited(_requeryWriteStatus());
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

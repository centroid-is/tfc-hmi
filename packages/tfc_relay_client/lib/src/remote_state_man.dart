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
import 'ws_transport.dart';

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
    Future<ConnectAttempt> Function(Uri uri)? dial,
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
      // Null in production: the supervisor dials with `connect`. A harness
      // supplies one so a contract leg can be built synchronously against a
      // server whose port is only known asynchronously — see
      // `connection_supervisor.dart`'s `_dial`.
      dial: dial,
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

  /// key per unresolved command, so a re-query's answer can be adopted.
  ///
  /// A `writeStatus` result carries a `cmd` and no key, and the readback has to
  /// land on the tag it was read from. Bounded by [_unresolved]: an entry
  /// leaves the moment its command settles.
  final _keyOf = <String, String>{};

  /// Every `writeStatus` re-query this client has issued, in order.
  ///
  /// The observable the no-re-actuation property is asserted against: an
  /// implementation that re-sent the write instead would leave this empty and
  /// [debugWritesSent] one higher.
  final _writeStatusQueries = <List<String>>[];

  /// What those re-queries came *back* with, in order.
  ///
  /// The other half of the same observable, and the one 04-REVIEW CR-02 was
  /// found through: a case can assert that the re-query went out and that
  /// nothing was re-sent while the gateway is answering `not_received` — the
  /// one verdict that licenses re-actuating a machine — about every command
  /// whose fate is genuinely unknown.
  final _writeStatusAnswers = <WriteResult>[];

  /// How many entries each debug history keeps. See [_record].
  static const int _debugHistory = 64;

  final _resolved = StreamController<WriteResult>.broadcast();

  var _writesSent = 0;
  var _requerying = false;
  var _requeryWanted = false;

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

  /// The answers those re-queries came back with, in order.
  List<WriteResult> get debugWriteStatusAnswers =>
      List<WriteResult>.unmodifiable(_writeStatusAnswers);

  /// Every write whose outcome was established *after* the call that made it
  /// had already resolved — the `writeStatus` re-query's answers.
  ///
  /// Broadcast, and never a second source of truth: what an applied outcome
  /// says about the value is already in the store by the time this emits. It
  /// exists so an operator who was shown "unknown" is shown the resolution
  /// when it arrives, rather than having to remember to ask.
  Stream<WriteResult> get onWriteResolved => _resolved.stream;

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
    final answer = <String, DynamicValue>{
      if (values is Map)
        for (final entry in values.entries) '${entry.key}': _value(entry.value),
    };

    // A key the gateway refused is still a key the caller asked about, and it
    // comes back as a value that renders rather than as an absence that does
    // not. A missing map entry is indistinguishable from a key nobody
    // requested, so a diagnostics page writes a blank cell exactly where it
    // needed to write a fault — and a renamed PLC tag then survives on a page
    // for months looking like a tag that is merely quiet.
    //
    // `errorConfig` rather than a bad-comms code: nothing is broken upstream,
    // the page is asking for a tag this source does not serve, and that is a
    // sentence an engineer can act on. Whatever the gateway put in `rejected`
    // is the diagnosis; the quality is what makes it visible.
    final rejected = raw['rejected'];
    if (rejected is Map) {
      for (final entry in rejected.entries) {
        final key = '${entry.key}';
        // Never over a real reading: if the gateway somehow answered both, the
        // reading is the more specific fact.
        answer.putIfAbsent(
            key, () => DynamicValue(quality: Quality.errorConfig));
      }
    }
    return answer;
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
  Future<WriteResult> write(String key, Object? value,
      {Object? expect, String? cmd}) async {
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

    // Minted here when this client *is* the operator action, carried through
    // when it is relaying one already minted upstream of it. Either way there
    // is exactly one id for one action, which is what `writeStatus` reconciles
    // against after a reconnect.
    final id = cmd ?? newUlid();
    _unresolved.add(id);
    // The tag this id belongs to, so a re-query's readback can be adopted onto
    // it later — a `writeStatus` answer names the command and not the key.
    _keyOf[id] = key;

    // Whether any bytes were offered to a socket for this write. A `cmd` that
    // never reached one is a `cmd` no gateway can have an opinion about, and
    // re-querying it on every reconnect for the rest of the shift is how a
    // panel with a dead link grows an unresolved set until `writeStatus` is
    // refused for being over `maxKeysPerSubscribe` — taking the recovery path
    // for the *genuine* unknowns down with it.
    var dispatched = false;

    WriteResult result;
    try {
      final raw = await _request(
        Methods.write,
        {
          'cmd': id,
          'key': key,
          'value': sanitizedValue.value,
          if (expect != null) 'expect': sanitizedExpect.value,
        },
        deadline: config.writeDeadline,
        onSend: () {
          dispatched = true;
          _writesSent++;
        },
      );
      result = WriteResult.fromJson(_asJson(raw));
    } catch (error) {
      // One seam decides whether this means "we do not know" or "the server
      // said no", and it rethrows anything that is a defect in this process
      // rather than a condition of the plant (`failure_taxonomy.dart`).
      result = _writeOutcomeFor(id, error);
    }

    // Only an established outcome settles the command. `WriteUnknown` is the
    // one verdict that does not, which is exactly what makes it re-queryable —
    // unless this client watched the request fail to leave, in which case
    // there is nothing on the far side to reconcile against.
    if (result is! WriteUnknown || !dispatched) {
      _unresolved.remove(id);
      _keyOf.remove(id);
    }

    _adoptReadback(key, result);
    if (sanitizedValue.hadNonFinite) _markNonFinite(key);
    return result;
  }

  /// [writeOutcomeFor], plus the one fact the taxonomy cannot know: this
  /// client is shutting down.
  ///
  /// A page that closes while a write is parked on the barrier gets a
  /// `StateError` out of [ReadinessBarrier.dispose] or [_refuseIfDisposed], and
  /// the taxonomy rethrows an unrecognised `StateError` on purpose — a defect
  /// in this process must never be reported to an operator as a plant
  /// condition. But `write` promises never to throw to report an outcome, and
  /// a closing page handed a `StateError` instead of a `WriteResult` is that
  /// promise broken at the one moment nobody is watching the screen.
  ///
  /// [_disposed] is a fact this object owns rather than a message match, so
  /// nothing widens here the way a string predicate widens. Unknown and not
  /// never-received: what this client knows is that it stopped looking.
  WriteResult _writeOutcomeFor(String cmd, Object error) {
    if (_disposed && error is StateError) {
      return WriteUnknown(
          cmd,
          WriteReason(FailureKind.linkDown,
              message: 'the panel was shut down before this write could be '
                  'sent: ${error.message}'));
    }
    return writeOutcomeFor(cmd, error);
  }

  /// Puts an applied write's readback into the store before the write resolves.
  ///
  /// **This closes a race the caller cannot see and cannot work around.** The
  /// gateway answers the write on the RPC path and pushes the new reading on
  /// the subscription path, and the subscription path is tick-quantised and
  /// conflated — so the response routinely wins. For the caller that means
  /// `await write(...)` returns `WriteApplied(readback: 1500)` while
  /// `read(key)` still says 1200 and the value still wears the pending badge
  /// the plant stamped on it when the write went upstream. A mimic redrawn on
  /// that turn shows the operator the setpoint they typed over, still amber,
  /// after the confirmation has already arrived — and if the tick that would
  /// have corrected it is the one lost to a reconnect, it shows it until the
  /// next change on that key.
  ///
  /// The readback is not a guess: it is what the device reported holding, and
  /// `WriteResult`'s whole design is that the readback is the only confirmation
  /// there is. Adopting it is applying the confirmation, not predicting it —
  /// which is exactly why the *typed* value is never adopted, and why nothing
  /// is adopted for a rejected, unknown or never-received outcome. Those leave
  /// the last confirmed reading standing, which is the honest thing to show
  /// when nobody upstream has agreed to anything.
  ///
  /// The push that follows carries the same reading, so `applyBatch`'s equality
  /// guard makes it free: one notification for one write, not two.
  void _adoptReadback(String key, WriteResult result) {
    if (_disposed) return;
    if (result is! WriteApplied) return;
    // A clamped write reports what the device took; an unclamped one reports
    // the value back unchanged. Both are the device's word, and both clear the
    // pending badge that the write itself put on.
    _storeOf(key).applyBatch({
      key: DynamicValue(
        value: result.readback,
        quality: Quality.good,
        // `at` is epoch milliseconds on the wire; UTC here for the same reason
        // `WireValue.toDynamicValue` uses it — a local-time stamp would be
        // compared against gateway stamps that are not.
        sourceTime: DateTime.fromMillisecondsSinceEpoch(result.at, isUtc: true),
      ),
    });
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
    if (_requerying) {
      // **Wanted, not dropped** (04-REVIEW WR-01). The guard is against a
      // storm, and the flag alone turned it into a permanent skip: ready →
      // re-query sent → link drops → reconnect → this fires while the old
      // call's future has not failed yet → early return. The old call then
      // failed and cleared the flag, and nothing re-armed, so the commands
      // stayed unresolved until some later entry to ready — which on a link
      // that then behaves is never.
      _requeryWanted = true;
      return;
    }
    final cmds = List<String>.of(_unresolved);
    if (cmds.isEmpty) return;
    _requerying = true;
    _record(_writeStatusQueries, cmds);
    try {
      final raw = _asJson(await _request(Methods.writeStatus, {'cmds': cmds}));
      final results = raw['results'];
      if (results is! List) return;
      for (final entry in results) {
        final WriteResult outcome;
        try {
          outcome = WriteResult.fromJson(_asJson(entry));
        } catch (error) {
          // One entry, not the batch (04-REVIEW WR-03). Decoding inside the
          // loop was letting a malformed entry at index 0 discard the settled
          // outcomes of every other command in it, and on a 1500-key panel the
          // batch is not small. One typo costs one tag, here as everywhere.
          _supervisor.resync.complaints.add(
              'a writeStatus entry could not be read and was dropped rather '
              'than taken as an answer about some other command: $error');
          continue;
        }
        _record(_writeStatusAnswers, outcome);
        if (outcome is WriteUnknown) continue;
        _settle(outcome);
      }
    } catch (_) {
      // A re-query that fails leaves the commands unresolved, which is the
      // honest state and the one the next `ready` will ask about again. What it
      // never becomes is a reason to send the write a second time.
    } finally {
      _requerying = false;
      if (_requeryWanted && !_disposed) {
        _requeryWanted = false;
        unawaited(_requeryWriteStatus());
      }
    }
  }

  /// One command has an established answer at last.
  ///
  /// **The recovery has to end somewhere the operator can see** (04-REVIEW
  /// WR-02). Removing the id from [_unresolved] and stopping there meant that
  /// an operator who was told "unknown", walked out to look at the machine and
  /// came back was told nothing at all when the gateway finally said "applied".
  /// So the outcome goes out on [onWriteResolved], and an applied one has its
  /// readback adopted into the store exactly as the direct path adopts one —
  /// the readback is what the device reported holding, and adopting it is
  /// applying the confirmation rather than predicting it.
  void _settle(WriteResult outcome) {
    _unresolved.remove(outcome.cmd);
    final key = _keyOf.remove(outcome.cmd);
    if (key != null) _adoptReadback(key, outcome);
    if (!_resolved.isClosed) _resolved.add(outcome);
  }

  /// Appends to a debug list, keeping only the most recent [_debugHistory].
  ///
  /// 04-REVIEW IN-02: one entry per re-query, never trimmed, is a leak with a
  /// diagnostic excuse — a panel that flaps all shift accumulates them. The
  /// question these answer ("what did the recovery just do?") is about the
  /// recent past, so the bound costs nothing that was being read.
  static void _record<T>(List<T> history, T entry) {
    history.add(entry);
    if (history.length > _debugHistory) history.removeAt(0);
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
    await _resolved.close();
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
    final budget = deadline ?? config.controlDeadline;
    try {
      await _supervisor.barrier.ready.timeout(budget);
    } on TimeoutException {
      // **Never queued behind a link that is not there.** The barrier owns no
      // clock (`readiness_barrier.dart`: "the supervisor owns the clock", and
      // the supervisor's only schedules reconnects), so an unbounded wait here
      // made every deadline in `ClientConfig` a measurement of the round trip
      // alone. Two things came of that, and the second is the dangerous one: a
      // write never settled, so the operator's spinner never stopped; and when
      // the gateway came back — ten minutes later, at shift change — the
      // request went out. A button pressed at 09:00 actuating a ram at 09:10 is
      // a queue, and `CLAUDE.md` names "no queue / no retry" as *the*
      // write-safety property.
      //
      // Reported as "no link", never as a server answer: `writeOutcomeFor`
      // turns [LinkDown] into `WriteUnknown(link_down)` and reads surface it
      // through `classifyFailure`.
      throw LinkDown(method);
    }
    _refuseIfDisposed(method);
    onSend?.call();
    // The budget again rather than what is left of it. A link that arrived at
    // the last millisecond of the wait has earned the whole round-trip window;
    // a truncated one would expire against a perfectly healthy gateway and
    // report a write it never sent as unknown. So the worst case is two
    // budgets, bounded and deliberate, instead of one budget and a queue.
    return callWithDeadline(
      () => _supervisor.peer,
      method,
      params: params,
      deadline: budget,
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
  static DynamicValue _value(Object? raw) =>
      WireValue.fromJson(_asJson(raw)).toDynamicValue();

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

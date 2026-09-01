/// The gateway's `StateManApi`: one composer over the key router, the ordered
/// upstream links and one value store.
///
/// ## Why the 2,796-line `StateMan` composer does not enter the gateway
///
/// This is the decision the whole package rests on, and it is written here by
/// line so the next reader does not have to re-derive it. `ClientWrapper`,
/// `ModbusDeviceClientAdapter` and `M2400DeviceClientAdapter` *are* wrapped —
/// they carry years of plant scar tissue (a two-phase resubscribe that fixed a
/// measured monitored-item storm, a heartbeat-derived effective status with a
/// 15 s stale / 30 s grace window, the classification that tells a transient
/// `Inactivity` from a fatal `SubscriptionDeleted`) and none of that is worth
/// rewriting. The composer above them is a different matter, and four of its
/// properties are the anti-patterns `StateManApi` exists to replace:
///
///  1. **`read` throws on every failure path**
///     (`packages/tfc_dart/lib/core/state_man.dart:1876`). A read that throws
///     is a read whose caller has to invent a quality, and an invented quality
///     is how a plausible number survives the loss of the thing producing it.
///  2. **`write` throws too** (`:2042`), which collapses "I cannot tell whether
///     it happened" into "it failed" — the one distinction the whole write path
///     exists to preserve.
///  3. **`subscribe` is a `Future<Stream<…>>`** (`:2054`), the shape
///     `state_man_api.dart:80-84` names as how a widget ends up missing the
///     first values of its own subscription.
///  4. **Its values carry no quality.** `tfc_dart`'s `DynamicValue` and this
///     package's are two different classes with one name, and only one of them
///     has `quality` and `sourceTime` as fields. Everything crossing into the
///     gateway is a translation between them, and the translation is where the
///     two facts get minted rather than lost.
///
/// ## Nothing is spawned by the constructor
///
/// `StateMan._` starts two unawaited background loops per OPC UA client
/// (`:1364`, `:1398`) with a bare `Logger()` and no error seam, in a
/// constructor. That is the shape being replaced. Here construction allocates
/// and connects nothing; [start] opens the links under a bounded deadline and
/// [dispose] closes them, so a failure to reach a PLC is a value the caller
/// receives rather than an exception raised inside somebody else's `new`.
///
/// ## Explicit delegation, never `noSuchMethod`
///
/// Every member is written out. `policy_state_man.dart:80-87` gives the reason
/// and `cert_health_state_man.dart:153-158` repeats it: a forwarder silently
/// absorbs a member added to `StateManApi` in a later phase — the new member
/// works, unpoliced, and nothing says so. Here a new member is a compile error,
/// and a compile error is a decision. `freeze_test.dart` pins the spelling out
/// of `lib/` so the shortcut cannot be taken later either.
///
/// ## What this plan does not implement yet
///
/// `write`, `writeStatus` and `holdToRun` are 08-06's; `browse`, `timeseries`,
/// `historyViews` and `preferences` are 08-11's and Phase 10's. Each throws an
/// `UnimplementedError` naming the plan that owes it, and the count is a
/// declared constant in `freeze_test.dart` that must reach zero. This is
/// 07-01's `gateOutstanding` doctrine: a self-deleting list with an owner beats
/// a red suite, because a phase whose own gate is red cannot tell a new failure
/// from a known one.
library;

import 'dart:async';

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'fanin.dart';
import 'freshness_sweep.dart';
import 'ingest.dart';
import 'key_router.dart';
import 'upstream_link.dart';

/// The `StateManApi` the gateway serves every session from.
final class LocalStateMan implements StateManApi {
  LocalStateMan({
    required List<UpstreamLink> links,
    required this.router,
    this.staleAfter = const Duration(seconds: 5),
    this.linger = Duration.zero,
    this.readDeadline = const Duration(seconds: 5),
    this.connectDeadline = const Duration(seconds: 10),
    DateTime Function()? now,
  })  : links = List<UpstreamLink>.unmodifiable(links),
        _now = now ?? DateTime.now {
    // Allocation only. Nothing here opens a socket, starts a clock or spawns a
    // loop — see the library doc on why `StateMan._`'s constructor is the shape
    // being replaced.
    _sweep = FreshnessSweep(
      staleAfter: staleAfter,
      store: _store,
      lastArrival: _lastArrival,
      degrade: _degrade,
      now: _now,
    );
    _fanIn = FanIn(
      open: _openUpstream,
      onValue: _onUpstreamValue,
      onUpstreamEnded: _onUpstreamEnded,
      onUpstreamError: _onUpstreamError,
      linger: linger,
      // The listener gate. The sweep's clock runs on the transition off zero
      // watchers and stops on the return to it — with nobody watching there is
      // no timer, and the synchronous re-derivation in [read] is what makes
      // that safe rather than merely cheap (state_man.dart:966-992).
      onFirstWatcher: () => _sweep.start(),
      onLastWatcher: () => _sweep.stop(),
    );
  }

  /// The configured links, in the order the router offers keys to them.
  ///
  /// Held here as well as inside the router because the *lifecycle* is this
  /// class's: [start] connects them and [dispose] closes them, following
  /// `createM2400DeviceClients`' division of labour, whose comment says in so
  /// many words that "the caller is responsible for calling connect() and
  /// dispose() on the returned clients" (`state_man.dart:1292-1293`). The
  /// router only ever asks them to `resolve`.
  final List<UpstreamLink> links;

  /// Which link owns a key, or which named refusal it earns.
  final KeyRouter router;

  /// How long a value may go unheard-of before it must stop claiming to be
  /// current. 08-05's freshness sweep is what notices; see `freshness_sweep.dart`.
  final Duration staleAfter;

  /// How long an upstream subscription survives its last client subscriber.
  ///
  /// Zero by default and that is the correct gateway behaviour — a page close
  /// should stop costing the PLC a monitored item, which is SRV-07 and the
  /// departure from `AutoDisposingStream`'s ten-minute idle timer
  /// (`state_man.dart:2674-2676`). See `fanin.dart` for why the knob exists.
  final Duration linger;

  /// The bound on a single upstream round trip.
  ///
  /// Required at every call site by [UpstreamLink]'s signatures and defaulted
  /// here rather than there, so an omission is impossible and a deployment's
  /// choice is still one constructor argument.
  final Duration readDeadline;

  /// The bound on opening one link.
  final Duration connectDeadline;

  /// Injectable clock. The freshness verdict is arithmetic on this, so a case
  /// can move the gateway forward in time instead of sleeping.
  final DateTime Function() _now;

  /// One map, one batch entry point — the same [ValueStore] the server and
  /// client implementations use, so the k-of-n notification promise is
  /// satisfied by production code rather than by anything written here.
  final ValueStore _store = ValueStore();

  /// When each key last had a value *arrive* for it.
  ///
  /// Deliberately not the value's own `sourceTime`: an upstream may not fill
  /// it, and a source that dated freshness from a field the PLC leaves null
  /// would consider every value it has ever received to be infinitely old
  /// (`fake_state_man.dart:133-140`).
  final Map<String, DateTime> _lastArrival = <String, DateTime>{};

  /// The refcount that makes thirty panels on one key cost the PLC one
  /// monitored item, and releases it when the last of them goes (SRV-07).
  late final FanIn _fanIn;

  /// The clock that notices silence. Listener-gated; see `freshness_sweep.dart`.
  late final FreshnessSweep _sweep;

  /// Which keys have already been complained about, so a struct failing at
  /// 10 Hz costs one log line rather than the log file.
  final IngestLog _ingestLog = IngestLog();

  /// One counting handle per key, so [listen] answers the same object every
  /// time and the fan-in learns when the first listener arrives and the last
  /// one leaves.
  final Map<String, _WatchedKey> _handles = <String, _WatchedKey>{};

  bool _disposed = false;

  // ---------------------------------------------------------------- lifecycle

  /// Opens every configured link, bounded.
  ///
  /// Sequential rather than concurrent, because the order is the caller's and
  /// a plant with four PLCs is four connects, not four hundred. A link that
  /// cannot be reached does not stop the others: [UpstreamLink.connect] is
  /// bounded by [connectDeadline] and a gateway that refused to start because
  /// one PLC was in a download would take the other three off the screens too.
  Future<void> start() async {
    for (final link in links) {
      try {
        await link.connect(deadline: connectDeadline);
      } catch (error) {
        // Never a throw out of start(). The link's own state and, from 08-09,
        // PIPE.upstream.<alias>.state are where a failed connect is reported —
        // a subscribable fact rather than an exception the caller has to
        // decide the meaning of.
        _noteLinkStartFailure(link, error);
      }
    }
  }

  /// Releases the store, the links and everything held on their behalf.
  ///
  /// Idempotent: the suite disposes in `addTearDown` and a case that disposed
  /// deliberately must not be punished for it. No `.timeout` anywhere on this
  /// path — a dispose that gives up half way leaves the thing it was disposing
  /// in a state nobody owns.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _fanIn.dispose();
    _sweep.dispose();
    _store.dispose();
    for (final link in links) {
      await link.dispose();
    }
  }

  // --------------------------------------------------------------- value path

  /// The handle for [key] — the same instance every time.
  ///
  /// A **counting view** of the store's node rather than the node itself, and
  /// the reason is SRV-07 rather than taste. `listen` is documented as the
  /// primary read path — the one widgets use — so if only `subscribe`
  /// refcounted, thirty panels bound through `listen` would open one upstream
  /// subscription that nothing could ever release. There is no `unlisten` on
  /// the interface, which makes `removeListener` reaching zero the **only
  /// observable release point** on this path; the wire package agrees, which is
  /// why `ValueStoreNode.listenerCount` is public at `value_store.dart:118`
  /// ("this is the only place the truth lives").
  ///
  /// Taking the handle costs nothing. A diagnostics page that enumerates every
  /// key must not subscribe the whole plant by looking at it.
  @override
  ValueListenable<DynamicValue> listen(String key) {
    _touch(key);
    return _handles.putIfAbsent(
        key,
        () => _WatchedKey(
              node: _store.node(key),
              attach: () => _fanIn.attach(key),
              detach: () => _fanIn.detach(key),
            ));
  }

  /// A view of the same node, for stream-consuming code.
  ///
  /// A **plain Stream**, and its first event is the value the store already
  /// holds rather than the next change: a page opened on a slow-moving tank
  /// level would otherwise read blank until the level moved. The snapshot is
  /// pushed in `onListen`, so taking the stream and listening to it happen in
  /// the same turn and there is no window in which a change can be missed.
  @override
  Stream<DynamicValue> subscribe(String key) {
    _touch(key);
    final node = _store.node(key);
    late final StreamController<DynamicValue> controller;
    void push() {
      if (!controller.isClosed) controller.add(node.value);
    }

    controller = StreamController<DynamicValue>(
      onListen: () {
        node.addListener(push);
        // The refcount moves on LISTEN, not on the call to subscribe: a stream
        // nobody listened to is not a subscription and must not cost the PLC
        // anything. Single-subscription rather than broadcast so onListen and
        // onCancel are exactly one client each — a broadcast controller fires
        // onListen only for the first of its listeners, and the refcount would
        // then be wrong by however many panels shared the stream.
        _fanIn.attach(key);
        push();
      },
      onCancel: () {
        node.removeListener(push);
        _fanIn.detach(key);
      },
    );
    return controller.stream;
  }

  /// The last known value for [key], or null when nothing is known yet.
  ///
  /// Synchronous, never a round trip, and **never a throw** — reading is what a
  /// widget does during a build. Null means "not known yet", which is a
  /// different statement from a known-bad value.
  ///
  /// A key the router *refuses* is neither: the gateway has affirmatively
  /// established it cannot serve that name, so [_touch] has already put a
  /// [Quality.errorConfig] value with a **null** payload into the store and
  /// this answers it. Never a zero and never a false — on a plant floor a
  /// good-quality `0` on a mistyped speed tag is a stopped conveyor and a
  /// good-quality `false` on a mistyped permit is an interlock reading
  /// satisfied.
  @override
  DynamicValue? read(String key) {
    _touch(key);
    final cached = _store.peek(key);
    if (cached == null) return null;
    // The verdict is RE-DERIVED here, not merely reported: the sweep's clock is
    // parked whenever nobody is watching, and a read taken during a parked
    // period must still be correct. `judge` does not write to the store — a
    // read is not an event, and one that notified every listener would make a
    // diagnostics page's poll a rebuild storm.
    return _sweep.judge(key, cached);
  }

  /// Forces a round trip and answers a freshly-read value.
  ///
  /// One code path with [readMany] so there is exactly one place an upstream
  /// read is awaited, and therefore exactly one place a deadline could go
  /// missing.
  @override
  Future<DynamicValue> readFresh(String key) async =>
      (await readMany(<String>[key]))[key]!;

  /// One round trip for many keys.
  ///
  /// **Every key asked for gets an answer**, including keys nothing is known
  /// about and keys the router refuses — as a bad-quality value rather than a
  /// missing entry, so the caller renders a fault instead of a blank. One bad
  /// key never fails the batch.
  ///
  /// The reads are issued concurrently and awaited together: reading fifty keys
  /// over a link with 200 ms of latency must cost 200 ms and not ten seconds,
  /// which is the reason this method is on the interface at all
  /// (`state_man_api.dart:100-105`). Everything that came back from upstream is
  /// then applied as **one** batch — one pass over the store, k notifications.
  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    final results =
        await Future.wait(<Future<_ReadAnswer>>[for (final key in keys) _readOne(key)]);
    final answers = <String, DynamicValue>{};
    final arrived = <String, DynamicValue>{};
    final degraded = <String, DynamicValue>{};
    for (final result in results) {
      answers[result.key] = result.value;
      if (!result.fromUpstream) continue;
      // A round trip that came back `badCommFault` did not reach the plant, so
      // it is not news from upstream and must not reset the freshness clock —
      // otherwise a disconnected PLC polled once a second is a key that never
      // goes stale. It still lands in the store: the screen has to learn.
      if (_isLinkDegraded(result.value.quality)) {
        degraded[result.key] = result.value;
      } else {
        arrived[result.key] = result.value;
      }
    }
    applyUpstreamBatch(arrived);
    _degrade(degraded);
    return answers;
  }

  /// Whether [quality] is one the freshness and link machinery applied, rather
  /// than one the plant reported.
  ///
  /// `fake_state_man.dart:487-489`'s distinction and its reason: a source that
  /// reset *any* bad quality on a read would launder a genuine upstream fault —
  /// a non-finite reading, a bad string encoding — into a healthy number, which
  /// is the same lie as a stale value with better manners.
  static bool _isLinkDegraded(Quality quality) =>
      quality == Quality.badStale || quality == Quality.badCommFault;

  /// One key's round trip. The only place an upstream read is awaited.
  Future<_ReadAnswer> _readOne(String key) async {
    final route = router.route(key);
    switch (route) {
      case RefusedRoute():
        return (key: key, value: _refuse(route), fromUpstream: false);
      case PipeKeyRoute():
        // The gateway's own namespace: there is nothing upstream to ask. 08-09
        // produces these; until then the honest answer for an unproduced one is
        // uncertain-not-yet-known, because waiting does fix it.
        return (
          key: key,
          value: _store.peek(key) ?? notYetKnown,
          fromUpstream: false,
        );
      case ClaimedRoute(link: final link, ref: final ref):
        final value = await link.read(ref, deadline: readDeadline);
        return (key: key, value: value, fromUpstream: true);
    }
  }

  /// Every key this source can serve.
  ///
  /// The router's key set **union** the `PIPE.*` keys this instance has
  /// actually produced — a union and not a replacement, which is
  /// `cert_health_state_man.dart:317-320`'s rule. The health half is derived
  /// from what is in the store rather than from a roster, so 08-09 adding a
  /// producer puts its key here on the day it mints one and there is no second
  /// list to keep in step.
  ///
  /// Keys the router refused are **not** here: offering a refused name back to
  /// the page editor's key picker would launder a typo into an apparently valid
  /// binding.
  @override
  List<String> get keys => <String>{
        ...router.keys,
        for (final key in _store.keys)
          if (PipeKeys.isPipeKey(key) && _store.peek(key) != null) key,
      }.toList(growable: false);

  // ------------------------------------------------------------------- ingest

  /// Applies a batch of values that genuinely arrived from upstream.
  ///
  /// One `applyBatch`, never a loop of single sets: the sequence bookkeeping and
  /// the gap check happen once per batch, and only keys whose value actually
  /// changed notify. This is also the one seam that resets the freshness clock —
  /// see [_degrade] for the other half of that distinction.
  void applyUpstreamBatch(Map<String, DynamicValue> values) {
    if (values.isEmpty) return;
    final now = _now();
    for (final key in values.keys) {
      _lastArrival[key] = now;
    }
    _store.applyBatch(values);
  }

  /// Converts a batch of raw upstream samples and applies it.
  ///
  /// The plant-facing entry point: a link's poll cycle or a converter's output
  /// arrives here as key/raw pairs, and **one bad tag costs one tag**. See
  /// `ingest.dart` for the per-key `try`/`catch` and why it is not per batch.
  ///
  /// One [applyUpstreamBatch] for the whole cycle, so the store makes one pass
  /// and notifies k times for k changed keys — never a loop of single sets.
  IngestOutcome ingestRaw(
    Iterable<RawSample> samples, {
    Quality quality = Quality.good,
    DateTime? sourceTime,
  }) {
    final outcome = ingestSamples(samples,
        quality: quality, sourceTime: sourceTime, log: _ingestLog);
    applyUpstreamBatch(outcome.batch);
    return outcome;
  }

  /// What this instance has refused at ingest, and how often.
  IngestLog get ingestLog => _ingestLog;

  /// Applies a quality change **without** pretending a value arrived.
  ///
  /// The distinction is the whole freshness story: marking a value stale must
  /// not make it fresh again, and losing an upstream link is not news from
  /// upstream. A single seam that reset the clock on everything would produce a
  /// source that goes stale exactly once and never again
  /// (`fake_state_man.dart:390-397`).
  void _degrade(Map<String, DynamicValue> values) {
    if (values.isEmpty) return;
    _store.applyBatch(values);
  }

  // ----------------------------------------------------------- not this plan

  @override
  Future<WriteResult> write(String key, Object? value,
          {Object? expect, String? cmd}) =>
      throw UnimplementedError('08-06 owes LocalStateMan.write — the '
          'three-state outcome, the cmd the operator minted, the readback that '
          'is the only confirmation, and the no-retry seam are one subject and '
          'one plan');

  @override
  Future<List<WriteResult>> writeStatus(List<String> cmds) =>
      throw UnimplementedError('08-06 owes LocalStateMan.writeStatus — the '
          'reconnect re-query is the other half of the write path and cannot '
          'be answered before there is an outcome log to answer from');

  @override
  Future<HoldHandle> holdToRun(String key) =>
      throw UnimplementedError('08-06 owes LocalStateMan.holdToRun — a hold '
          'engage is a write with a deadman counter on top of it');

  @override
  BrowseApi get browse =>
      throw UnimplementedError('08-11 owes LocalStateMan.browse — the live '
          'address space per alias, behind UpstreamLink.supportsBrowse');

  @override
  TimeseriesApi get timeseries =>
      throw UnimplementedError('08-11 owes LocalStateMan.timeseries — Phase 10 '
          'consumes what Phase 8 collects; 08-11 sets supportsDataServices '
          'false on the contract leg until it does');

  @override
  HistoryViewApi get historyViews =>
      throw UnimplementedError('08-11 owes LocalStateMan.historyViews — as '
          'timeseries, and from the same database seam');

  @override
  PreferencesApi get preferences =>
      throw UnimplementedError('08-11 owes LocalStateMan.preferences — Phase '
          '10 owns the stored preferences, and no method here may request '
          'secret material');

  // ---------------------------------------------------------------- internals

  /// Establishes what the gateway can say about [key] before it is read.
  ///
  /// Only routes when the store holds nothing: a route is a map lookup, but a
  /// read is on the widget build path and the cheapest correct thing to do for
  /// a key that already has a value is nothing at all.
  void _touch(String key) {
    if (_store.peek(key) != null) return;
    final route = router.route(key);
    if (route is RefusedRoute) _refuse(route);
  }

  /// Records a refusal as a value, so a widget bound to a mistyped key sees a
  /// fault rather than an eternity of "not yet known".
  DynamicValue _refuse(RefusedRoute route) {
    final value = DynamicValue(value: null, quality: Quality.errorConfig);
    // Through _degrade and not applyUpstreamBatch: nothing arrived. A refusal
    // that reset the freshness clock would be a key that is never stale and
    // never true either.
    _degrade(<String, DynamicValue>{route.key: value});
    return value;
  }

  /// A link that could not be opened at [start].
  ///
  /// Nothing to publish yet — 08-09 owns `PIPE.upstream.<alias>.state` and
  /// `.last_error`, and inventing a second place to record this would be the
  /// second spelling `PipeKeys` exists to prevent. The redaction is applied
  /// here rather than there because the string must never exist unredacted
  /// outside the link (T-08-08).
  void _noteLinkStartFailure(UpstreamLink link, Object error) {
    _startFailures[link.alias] = redactUpstreamError(error.toString()) ?? '';
  }

  /// Links whose [start] connect did not succeed, by alias, redacted.
  ///
  /// Observable so a case can assert the gateway came up anyway; 08-09 turns
  /// this into `PIPE.upstream.<alias>.last_error`.
  Map<String, String> get startFailures =>
      Map<String, String>.unmodifiable(_startFailures);
  final Map<String, String> _startFailures = <String, String>{};

  /// How many repeating clocks this instance is running right now.
  ///
  /// **Zero until somebody is watching**, and that is the property rather than
  /// an implementation detail: an always-on `Timer.periodic` leaks past every
  /// widget test that builds a source without draining it, and an unobserved
  /// gateway has nobody to tell. 08-05 task 3 wires the freshness sweep behind
  /// this number.
  int get liveTimers => _sweep.running ? 1 : 0;

  /// The sweep's cadence: a quarter of [staleAfter], floored.
  Duration get sweepInterval => _sweep.interval;

  /// How many freshness passes have been made. A diagnostic, and the observable
  /// that tells a case the listener gate actually opened.
  int get freshnessSweeps => _sweep.sweeps;

  // ------------------------------------------------------- fan-in observation

  /// Clients watching [key] right now, through `listen` or `subscribe`.
  int listenerCount(String key) => _fanIn.listenerCount(key);

  /// Keys holding a live upstream subscription — the SRV-07 release assertion.
  int get openUpstreamSubscriptions => _fanIn.openUpstreamSubscriptions;

  /// Linger timers armed right now. Zero at the default [linger].
  int get liveLingerTimers => _fanIn.liveLingerTimers;

  // ---------------------------------------------------------- fan-in callbacks

  /// What the fan-in subscribes to for [key], or null when there is nothing
  /// upstream to subscribe to.
  ///
  /// The route is taken **once**, at the moment the refcount leaves zero, and
  /// the epoch-stamped [UpstreamRef] the link minted rides inside the
  /// [ClaimedRoute] for the life of that subscription. Re-resolving inside one
  /// epoch would be pointless work; re-resolving after an `epochStream` event
  /// is necessary and is 08-08's.
  Stream<DynamicValue>? _openUpstream(String key) {
    final route = router.route(key);
    switch (route) {
      case ClaimedRoute(link: final link, ref: final ref):
        return link.subscribe(ref);
      case PipeKeyRoute():
        // The gateway's own namespace. No link is ever consulted for one of
        // these — 08-09's producer owns the whole prefix.
        return null;
      case RefusedRoute():
        _refuse(route);
        return null;
    }
  }

  void _onUpstreamValue(String key, DynamicValue value) =>
      applyUpstreamBatch(<String, DynamicValue>{key: value});

  /// The upstream stream for [key] ended.
  ///
  /// **The node is not closed and the value is not forgotten.** The key is
  /// marked [Quality.badCommFault] and keeps its number: staleness and link
  /// loss are statements about whether the reading can be trusted, not claims
  /// that it never existed. The band guard is what stops this overwriting a
  /// key that is already worse news — `errorConfig` means the tag is gone and
  /// waiting will not fix it, and repainting that as a comm fault tells the
  /// operator to wait for something never coming back.
  void _onUpstreamEnded(String key) {
    final cached = _store.peek(key);
    if (cached == null) {
      _degrade(<String, DynamicValue>{
        key: DynamicValue(value: null, quality: Quality.badCommFault),
      });
      return;
    }
    if (Quality.badCommFault.band <= cached.quality.band) return;
    _degrade(<String, DynamicValue>{
      key: cached.copyWith(quality: Quality.badCommFault),
    });
  }

  /// An error on one key's upstream stream costs that key and nothing else.
  void _onUpstreamError(String key, Object error) {
    _upstreamErrors[key] = redactUpstreamError(error.toString()) ?? '';
    _onUpstreamEnded(key);
  }

  /// The last upstream error per key, already redacted (T-08-08).
  Map<String, String> get upstreamErrors =>
      Map<String, String>.unmodifiable(_upstreamErrors);
  final Map<String, String> _upstreamErrors = <String, String>{};
}

/// A counting view of one store node.
///
/// Delegates every member to the node — so `value` is the node's value and a
/// registered listener is registered *on the node*, which is where
/// `listenerCount` reads from and where a teardown assertion looks. What it
/// adds is the two transitions the node has no hook for
/// (`value_store.dart:66`): first listener in, last listener out.
final class _WatchedKey implements ValueListenable<DynamicValue> {
  _WatchedKey({
    required this.node,
    required void Function() attach,
    required void Function() detach,
  })  : _attach = attach,
        _detach = detach;

  final ValueStoreNode node;
  final void Function() _attach;
  final void Function() _detach;

  int _count = 0;

  @override
  DynamicValue get value => node.value;

  @override
  void addListener(VoidCallback listener) {
    node.addListener(listener);
    _count++;
    if (_count == 1) _attach();
  }

  @override
  void removeListener(VoidCallback listener) {
    // Measured rather than assumed: removing a listener that was never added
    // is a documented no-op on the node, and a refcount that decremented on
    // one would release an upstream subscription somebody is still watching.
    final before = node.listenerCount;
    node.removeListener(listener);
    if (node.listenerCount == before) return;
    if (_count == 0) return;
    _count--;
    if (_count == 0) _detach();
  }
}

/// One key's answer plus whether it came from the wire, so [LocalStateMan.readMany]
/// can apply exactly the ones that did as a single batch.
typedef _ReadAnswer = ({String key, DynamicValue value, bool fromUpstream});

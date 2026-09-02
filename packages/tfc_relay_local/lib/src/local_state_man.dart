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
/// ## The write path is here, and there is one of it
///
/// `write` is 08-06's and so is the single line that crosses into a plant
/// ([_crossIntoThePlant]). Three states, no throw to report an outcome, no
/// retry anywhere, and readback as the only confirmation — the badge on a
/// value says "sent", and only an upstream sample says "confirmed".
///
/// ## What this plan does not implement yet
///
/// `holdToRun` is 08-06 task 3's; `browse`, `timeseries`,
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
import 'write_translation.dart';

/// The `StateManApi` the gateway serves every session from.
final class LocalStateMan implements StateManApi {
  LocalStateMan({
    required List<UpstreamLink> links,
    required this.router,
    this.staleAfter = const Duration(seconds: 5),
    this.linger = Duration.zero,
    this.readDeadline = const Duration(seconds: 5),
    this.connectDeadline = const Duration(seconds: 10),
    this.writeDeadline = const Duration(seconds: 5),
    this.writeOutcomeTtl = const Duration(minutes: 10),
    this.maxWriteOutcomes = 4096,
    DateTime Function()? now,
  })  : links = List<UpstreamLink>.unmodifiable(links),
        _now = now ?? DateTime.now {
    _startedMs = _now().millisecondsSinceEpoch;
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
      router: router,
      onValue: _onUpstreamValue,
      onRefusedRoute: _refuse,
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

  /// The bound on one write round trip.
  ///
  /// Separate from [readDeadline] because the two failures cost different
  /// things: a read that gives up leaves a value visibly stale, and a write
  /// that gives up leaves an outcome nobody knows — which is the answer an
  /// operator has to go and check a tag over.
  final Duration writeDeadline;

  /// How long the plant-side outcome log vouches for a cmd.
  ///
  /// Past this, `writeStatus` answers `WriteUnknown(outcome_expired)` rather
  /// than `WriteNotReceived`: an outcome this source has forgotten is not an
  /// outcome that never happened, and `not_received` is the one answer that
  /// tells an operator a re-send is safe.
  final Duration writeOutcomeTtl;

  /// How many settled outcomes the log holds before the oldest is dropped.
  ///
  /// A gateway runs for months; an unbounded map of every write it has ever
  /// settled is a leak with an audit trail's name on it.
  final int maxWriteOutcomes;

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
      // Subscribed BEFORE the connect, so the link coming up is an event this
      // source saw rather than a state it later noticed. One subscription per
      // link and one handler behind it: the degradation, the health keys and
      // the announcement are three things that must happen in one order, and
      // three independent listeners on the same stream would run in whatever
      // order they happened to be registered.
      _linkStates.add(link.stateStream.listen((state) => _onLinkState(link)));
      try {
        await link.connect(deadline: connectDeadline);
      } catch (error) {
        // Never a throw out of start(). The link's own state and
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
    // BEFORE the flag, because the zero is written through the ordinary write
    // path and that path refuses a disposed source. A hold must not outlive
    // its source: a disposed gateway that left a counter frozen at its last
    // value is a machine nobody is holding that the PLC still thinks somebody
    // is, for as long as its deadman window lasts.
    await _releaseHolds(HoldEnded.disposed);
    _disposed = true;
    for (final subscription in _linkStates) {
      await subscription.cancel();
    }
    _linkStates.clear();
    await _status.close();
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

  // -------------------------------------------------------------- write path

  /// Writes [value] to [key] and reports which of the three things happened.
  ///
  /// **It never throws to report an outcome.** The two throws below are
  /// programmer errors, and they are the same two the reference implementation
  /// keeps (`fake_state_man.dart:645-670`): writing through a disposed source,
  /// and re-using a command id. A throw that meant "the write failed" would
  /// collapse "the PLC may have applied this" into "this definitely did not
  /// happen", which is the anti-pattern `WriteResult` exists to make
  /// unrepresentable.
  ///
  /// Three refusals are established **before** the plant is touched, and each
  /// is a `WriteRejected` rather than a `WriteUnknown` for the same reason:
  /// nothing was sent, so there is nothing to be unsure about.
  ///
  ///  * a key the router will not route (including a `PIPE.` name — the
  ///    gateway's own namespace is produced, never written into by a client);
  ///  * an `expect` that does not match the last known value;
  ///  * a value the wire cannot represent (a cycle, or a depth past 64).
  ///
  /// The **idempotency window** — same cmd plus same key/value answered from
  /// the log, Stripe's semantic — is deliberately not here. It attaches at one
  /// named line in `value_handlers.write`, one layer up, because it is a
  /// property of the *wire*: two frames carrying one operator action. This
  /// source stays strict, and the gateway maps the throw below to
  /// `WriteUnknown(gateway_lost_track)`.
  @override
  Future<WriteResult> write(String key, Object? value,
      {Object? expect, String? cmd}) async {
    if (_disposed) {
      throw StateError('write($key) on a disposed source: the store and the '
          'upstream links are both gone, so no outcome reported here could be '
          'true. This is a lifecycle bug in the caller, not a write outcome.');
    }
    final id = cmd ?? newUlid(nowMs: _now().millisecondsSinceEpoch);
    if (!_mintedCmds.add(id)) {
      throw ArgumentError.value(
          id,
          'cmd',
          'this source has already seen the command id "$id". One id is one '
              'operator action: a second write under it would be a second '
              'actuation reported under the first one\'s outcome, which is '
              'the failure the id exists to make impossible');
    }
    final outcome =
        await _settle(key: key, value: value, expect: expect, cmd: id);
    if (outcome is WriteApplied) {
      // Staged only on applied, and only here: a write that was refused or
      // lost has nothing in flight to badge.
      _markWritePending(key);
    }
    _recordOutcome(outcome);
    return outcome;
  }

  /// Everything one write does between the id and the answer.
  Future<WriteResult> _settle({
    required String key,
    required Object? value,
    required Object? expect,
    required String cmd,
  }) async {
    final at = _now().millisecondsSinceEpoch;
    final route = router.route(key);
    switch (route) {
      case RefusedRoute():
        return WriteRejected(
            cmd, WriteReason('unroutable_key', message: route.message),
            at: at);
      case PipeKeyRoute():
        return WriteRejected(
            cmd,
            WriteReason('unroutable_key',
                message: 'the key "$key" is in the gateway\'s own namespace, '
                    'which is produced here and never written into from a '
                    'session',
                status: 'Bad_NotWritable'),
            at: at);
      case ClaimedRoute(link: final link, ref: final ref):
        // Compare-and-set, as far as this side can honestly offer it: the
        // comparison is against the last value the gateway heard, which is a
        // guard and not an atomic CAS — a protocol that can do better should
        // do it in its adapter. Refusing on a mismatch is the point; an
        // `expect` that was silently ignored would be worse than none at all,
        // because the caller believes it is guarded.
        if (expect != null) {
          final cached = _store.peek(key);
          if (cached == null || !jsonEquals(cached.value, expect)) {
            return WriteRejected(
                cmd,
                WriteReason('expect_mismatch',
                    message: 'the value this gateway last heard for "$key" is '
                        'not the one the caller compared against, so the '
                        'write was not sent'),
                at: at);
          }
        }
        final DynamicValue payload;
        try {
          payload = DynamicValue(value: value);
        } catch (error) {
          // `sanitize` throws on a cycle or a depth past 64 (08-RESEARCH §H).
          // A throw here would read to the operator as "the write failed for a
          // reason nobody knows"; this is definitively no effect.
          return WriteRejected(
              cmd,
              WriteReason('unrepresentable_value',
                  message: redactUpstreamError(error.toString())),
              at: at);
        }
        return _crossIntoThePlant(link: link, ref: ref, value: payload, cmd: cmd);
    }
  }

  /// **The one place in this package that asks a plant to move something.**
  ///
  /// Every write funnels through here — the operator's, a hold engage, every
  /// hold tick, the release — so there is exactly one line to read to know
  /// what the gateway does to a PLC, and exactly one place a deadline could go
  /// missing. `freeze_test.dart`'s freeze 4 pins the count at one and freeze 3
  /// pins that it is bounded; anyone adding a second site trips a named pin
  /// rather than a code review (T-08-22, `no_retry_test.dart:182-293`'s shape).
  ///
  /// There is no retry here and there is nowhere to put one: this method makes
  /// one call and returns what came back. A lost answer is `WriteUnknown` and
  /// what happens next is an operator's decision, never this code's.
  Future<WriteResult> _crossIntoThePlant({
    required UpstreamLink link,
    required UpstreamRef ref,
    required DynamicValue value,
    required String cmd,
  }) async {
    try {
      return await link.write(ref, value, cmd: cmd, deadline: writeDeadline);
    } catch (error) {
      // `UpstreamLink.write` is contracted never to throw, so this is a bug in
      // an adapter rather than news about a plant — and the honest report of a
      // bug on the write path is still "nobody knows", because the request may
      // already have been on the wire when it happened. STATE.md's mapping.
      return WriteUnknown(
          cmd,
          WriteReason('gateway_lost_track',
              message: redactUpstreamError(error.toString())));
    }
  }

  /// Re-asks what became of [cmds], positionally.
  ///
  /// The four-piece positive-evidence rule, mirrored from
  /// `fake_state_man.dart:715-740` rather than loosened, with two answers the
  /// reference has no need for because a fake lives for one test and a gateway
  /// runs for months: [writeOutcomeTtl] expiry and cap eviction. Both answer
  /// **unknown**, never `not_received`.
  ///
  /// ### This log answers about the PLANT, and the server's answers about the WIRE
  ///
  /// `tfc_relay_server`'s `WriteOutcomeLog` is one per `RelayServer` and
  /// survives session churn; it knows whether a *frame* arrived. This one
  /// knows whether a *plant* was asked. They are deliberately not merged: a
  /// gateway restart resets this one and not that one, and pretending
  /// otherwise would let a `writeStatus` claim knowledge of a write that never
  /// reached a PLC.
  @override
  Future<List<WriteResult>> writeStatus(List<String> cmds) async {
    _pruneWriteOutcomes();
    return alignWriteStatusAnswers(
      cmds,
      <WriteResult>[for (final cmd in cmds) _statusOf(cmd)],
    );
  }

  WriteResult _statusOf(String cmd) {
    final held = _outcomes[cmd];
    if (held != null) return held.result;

    final mintedAt = _ulidMs(cmd);
    if (mintedAt == null) {
      return WriteUnknown(
          cmd,
          const WriteReason('unrecognized_cmd',
              message: 'this is not an id this source could have issued an '
                  'outcome for, so nothing about it can be ruled out'));
    }
    final nowMs = _now().millisecondsSinceEpoch;
    if (mintedAt < _startedMs || mintedAt > nowMs) {
      return WriteUnknown(
          cmd,
          const WriteReason('outcome_unwitnessed',
              message: 'this command was minted outside the window this '
                  'source can vouch for with its own clock — before it '
                  'started recording, or ahead of it. Read the value back '
                  'before acting'));
    }
    if (nowMs - mintedAt > writeOutcomeTtl.inMilliseconds) {
      return WriteUnknown(
          cmd,
          const WriteReason('outcome_expired',
              message: 'this command is older than the window this gateway '
                  'keeps outcomes for. Read the value back before acting'));
    }
    if (mintedAt <= _forgottenBeforeMs) {
      // The log was full and dropped its oldest entries. A command from that
      // era WAS received and may well have moved the machine, so the one
      // answer it must never get is `not_received` — the log has to remember
      // that it forgot. Conservative at the edges by construction: a command
      // minted in the same millisecond as an evicted one is answered unknown
      // too, which costs a readback and saves an unasked-for actuation.
      return WriteUnknown(
          cmd,
          const WriteReason('outcome_forgotten',
              message: 'this gateway settled and then dropped outcomes from '
                  'around this command\'s time, so it cannot say this one was '
                  'never received. Read the value back before acting'));
    }
    return WriteNotReceived(cmd);
  }

  /// Settled outcomes, oldest first — a `LinkedHashMap` by insertion, which is
  /// what makes "drop the oldest" one line rather than a sort.
  final Map<String, _LoggedOutcome> _outcomes = <String, _LoggedOutcome>{};

  /// Every id this source has seen, so a re-use is caught while the first
  /// write is still in flight — not only after it settles.
  final Set<String> _mintedCmds = <String>{};

  /// The instant this source started recording. Evidence, not decoration: a
  /// command minted before it is one this source could never have heard about.
  late final int _startedMs;

  /// The mint-time of the newest outcome the cap has evicted. See [_statusOf].
  int _forgottenBeforeMs = 0;

  /// How many settled outcomes the log is holding.
  int get writeOutcomeCount => _outcomes.length;

  /// Keys carrying the in-flight badge right now.
  ///
  /// Derived from the store rather than kept alongside it, so it cannot drift:
  /// the badge is on the value or it is not, and the freshness sweep taking it
  /// off is not something this class has to be told about.
  Set<String> get writePendingKeys => <String>{
        for (final key in _store.keys)
          if (_store.peek(key)?.quality == Quality.goodWritePending) key,
      };

  void _recordOutcome(WriteResult result) {
    _pruneWriteOutcomes();
    _outcomes[result.cmd] =
        (result: result, at: _now().millisecondsSinceEpoch);
    while (_outcomes.length > maxWriteOutcomes) {
      final oldest = _outcomes.keys.first;
      _forgottenBeforeMs =
          [_forgottenBeforeMs, _ulidMs(oldest) ?? 0].reduce((a, b) => a > b ? a : b);
      _outcomes.remove(oldest);
    }
  }

  /// Drops outcomes past [writeOutcomeTtl].
  ///
  /// It does **not** move [_forgottenBeforeMs]: an expiry is answerable on the
  /// command's own age (`outcome_expired`), so there is no need for a
  /// watermark that would then swallow younger commands as well.
  void _pruneWriteOutcomes() {
    if (_outcomes.isEmpty) return;
    final cutoff = _now().millisecondsSinceEpoch - writeOutcomeTtl.inMilliseconds;
    _outcomes.removeWhere((_, entry) => entry.at < cutoff);
  }

  /// Puts the in-flight badge on [key]'s current value.
  ///
  /// The band guard and its reason are `fake_state_man.dart:936-938`'s:
  /// `goodWritePending` is a **good**-band code, so stamping it onto a stale or
  /// comm-faulted value would make a write a way of making a dead tag look
  /// alive. Applied through [_degrade] and never through [applyUpstreamBatch],
  /// because a write starting is not news from upstream — resetting the
  /// freshness clock here would let a page keep itself looking current by
  /// writing to itself.
  ///
  /// Nothing takes the badge off deliberately. The next upstream sample
  /// overwrites it (readback is the only confirmation) and, if none comes, the
  /// freshness sweep overtakes it with `badStale` — which is the operator-
  /// visible difference between "sent" and "confirmed".
  void _markWritePending(String key) {
    final cached = _store.peek(key);
    if (cached == null) return;
    if (cached.quality.band > Quality.goodWritePending.band) return;
    _degrade(<String, DynamicValue>{
      key: cached.copyWith(quality: Quality.goodWritePending),
    });
  }

  /// Crockford base32, the alphabet `newUlid` encodes with.
  static const String _ulidAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// The millisecond a ULID was minted at, or null when [cmd] is not one.
  ///
  /// A deliberate copy of `fake_state_man.dart:744-756`, which is itself a
  /// copy of `value_handlers.dart:479-488`, and the reason is the same in both
  /// places: the evidence rule has to be identical across the three
  /// implementations, and sharing twelve lines of decode would cost the
  /// independence that makes the contract suite worth running.
  static int? _ulidMs(String cmd) {
    if (cmd.length != 26) return null;
    var ms = 0;
    for (var i = 0; i < 10; i++) {
      final digit = _ulidAlphabet.indexOf(cmd[i]);
      if (digit < 0) return null;
      ms = (ms << 5) | digit;
    }
    return ms;
  }

  /// Engages a hold-to-run deadman on [key] and hands back the live hold.
  ///
  /// **The deadman is an ordinary tag written through the ordinary path.** The
  /// engage is [write] and so is the release, which is what makes a hold
  /// interlockable like any other command and what puts its outcome in the
  /// same log `writeStatus` answers from. There is exactly one key and it is
  /// the one passed in.
  ///
  /// [HoldHandle] is constructed, never subclassed, and no member is added to
  /// `StateManApi` — the surface is pinned at 49 (`api_surface_test.dart:
  /// 213-224`) and the two-callback design exists precisely so one class
  /// serves the fake, the harness, the gateway and the client. `tick()` is not
  /// on the interface and must never be put there: a method there is something
  /// any connected client may invoke against any key, and a bare `tick(key, n)`
  /// is a write primitive with no engage in front of it.
  ///
  /// The counter is minted **here** and a tick's value never comes from a
  /// caller (`value_handlers.dart:628-654` discards the wire's `n` for the same
  /// reason): the liveness an operator's finger is supposed to provide must not
  /// be something a peer can assert.
  @override
  Future<HoldHandle> holdToRun(String key) async {
    final engagement = await write(key, 1);
    final hold = HoldHandle(
      key: key,
      engagement: engagement,
      onTick: (counter) => _feedDeadman(key, counter),
      onRelease: (counter) => write(key, counter),
    );
    if (hold.isHeld) {
      _liveHolds.add(hold);
      // The handle completes `onReleased` exactly once, however the hold ends,
      // so this is the one place the set is pruned.
      unawaited(hold.onReleased.then((_) => _liveHolds.remove(hold)));
    }
    return hold;
  }

  /// Every hold this source is currently feeding, so [dispose] can end them.
  final Set<HoldHandle> _liveHolds = <HoldHandle>{};

  /// One tick: the gateway's counter, onto the plant, with nobody waiting.
  ///
  /// Fire-and-forget by design — safety comes from the counter *stopping*, so
  /// giving a tick an outcome would invite somebody to await it, and awaiting
  /// liveness is how a stalled socket becomes a queue
  /// (`hold_handle.dart:127-133`). A lost tick costs nothing a re-tick 100 ms
  /// later does not fix, so it neither ends the hold nor throws.
  ///
  /// **Ticks are deliberately not recorded in the outcome log.** The engage and
  /// the release are commands somebody may ask `writeStatus` about; a tick is
  /// liveness. At 10 Hz a two-minute hold is 1,200 of them, and recording them
  /// would evict the operator's real outcomes out of a bounded log inside
  /// seconds — which is the log answering "I forgot" about the writes that
  /// mattered so that it could remember the ones that did not.
  void _feedDeadman(String key, int counter) {
    if (_disposed) return;
    final route = router.route(key);
    // Not a ClaimedRoute means the engage cannot have applied, so there is no
    // live hold to feed. Checked rather than asserted: a route can stop being
    // claimed under a hold (a disabled alias, a keymapping reload), and the
    // right answer to that is to stop feeding, not to throw into a timer.
    if (route is! ClaimedRoute) return;
    final sent = _crossIntoThePlant(
      link: route.link,
      ref: route.ref,
      value: DynamicValue(value: counter),
      cmd: newUlid(nowMs: _now().millisecondsSinceEpoch),
    );
    // `unawaited` attaches NO error handler (project memory), and an
    // unhandled error out of a tick would take down the isolate the whole
    // gateway runs on. `state_man.dart:2369` is the shape, discipline
    // included.
    unawaited(sent.catchError((Object error) => WriteUnknown(
        'tick',
        WriteReason('gateway_lost_track',
            message: redactUpstreamError(error.toString())))));
  }

  /// Ends every live hold, writing the zero, before anything is torn down.
  ///
  /// Awaited, and safely: every upstream write is bounded by its required
  /// deadline (`upstream_link.dart`), so there is nothing here that can hang
  /// and therefore no `.timeout(` on this path — a dispose that gave up half
  /// way would leave the thing it was disposing in a state nobody owns.
  Future<void> _releaseHolds(HoldEnded reason) async {
    if (_liveHolds.isEmpty) return;
    final holds = List<HoldHandle>.of(_liveHolds);
    _liveHolds.clear();
    for (final hold in holds) {
      // `release` is idempotent, so a disconnect racing an operator's finger
      // cannot put two zeros on the wire. The outcome is informational: the
      // machine stopped when the counter stopped.
      await hold.release(reason: reason).then((_) {}, onError: (Object _) {});
    }
  }

  // ----------------------------------------------------------- not this plan

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

  // ------------------------------------------- SRV-08: degrade, then announce

  /// One subscription per configured link, opened by [start].
  final List<StreamSubscription<UpstreamLinkState>> _linkStates =
      <StreamSubscription<UpstreamLinkState>>[];

  /// Link-state announcements, **one per link event and never one per key**.
  ///
  /// 08-12 wires this to the session's `status` notification path. It carries
  /// [StatusParams] **objects** and not maps, which is 03-REVIEW WR-06 not
  /// repeated: this channel once sent a hand-built map, a conforming client
  /// routed it through `StatusParams.fromJson`, and `json['alias'] as String`
  /// threw on null — on the notification path, where nothing catches.
  Stream<StatusParams> get statusStream => _status.stream;
  final StreamController<StatusParams> _status =
      StreamController<StatusParams>.broadcast();

  /// How many link-state announcements this source has made.
  ///
  /// The observable `checkUpstreamLossAnnouncesOnce` is written against, and
  /// the number the per-key-announcement sabotage moves to twenty.
  int get statusNotifications => _statusNotifications;
  int _statusNotifications = 0;

  /// One link changed state. **Degrade, then announce.**
  ///
  /// The order is the property, not the implementation. A panel that learns the
  /// link is down and *then* reads a key which has not yet degraded sees a good
  /// value under a dead link — precisely the stale-but-plausible failure
  /// PROJECT.md names as the reason this project exists. So every value that
  /// must change has changed before anything is told that anything changed.
  ///
  /// The health keys sit between the two for the same reason: they are how a
  /// panel *learns*, so they must not be ahead of the values they describe.
  void _onLinkState(UpstreamLink link) {
    switch (link.state) {
      case UpstreamLinkState.connected:
        applyLinkRestored(link.alias);
      case UpstreamLinkState.disconnected:
      case UpstreamLinkState.unhealthy:
      case UpstreamLinkState.reprogrammed:
        applyLinkLoss(link.alias);
      case UpstreamLinkState.connecting:
        // Deliberately no value change. "A reconnect is in progress" is news
        // about the link and not evidence about any number: the values are
        // already carrying whatever verdict the loss that preceded it left
        // them, and re-degrading them would restamp nothing and notify
        // everybody.
        break;
    }
    // The `PIPE.upstream.<alias>.*` producer goes here, between the two, in
    // 08-09 task 2.
    announceLinkState(link);
  }

  /// Degrades every key [alias] serves, in **one** [ValueStore.applyBatch].
  ///
  /// One batch, not one per key: the store's promise is that a batch costs one
  /// pass and k notifications, and a link loss is the largest batch this source
  /// will ever apply — at this plant, fifteen hundred keys.
  ///
  /// Three rules, and each of them is a way of getting SRV-08 wrong:
  ///
  ///  * **Filtered by alias.** Without it, losing one PLC greys out the other
  ///    three, and a mimic with half its boxes greyed reads as a plant fault
  ///    the plant does not have.
  ///  * **Health keys are skipped**, by prefix (HLTH-02). A light that goes out
  ///    when the thing it monitors fails is not an indicator, and
  ///    `PIPE.upstream.$alias.state` has to stay readable *while* its link is
  ///    down — that is the moment it exists for.
  ///  * **The band guard stages nothing for a key already worse.**
  ///    `errorConfig` means the tag is gone and waiting will not fix it;
  ///    `badCommFault` means the link is down and waiting might. Repainting the
  ///    first as the second tells an operator to wait for something that is
  ///    never coming back — and it wakes every listener on that key to do it.
  ///
  /// It **does not announce**. Kept separate for `fake_state_man.dart:598-605`'s
  /// stated reason: so a variant can fan the announcement out per key without
  /// touching the degradation, which is the sabotage that proves the
  /// announce-once arm bites.
  void applyLinkLoss(String alias) {
    final batch = <String, DynamicValue>{};
    for (final key in _store.keys) {
      if (PipeKeys.isPipeKey(key)) continue;
      if (aliasOfKey(key) != alias) continue;
      final cached = _store.peek(key);
      if (cached == null) continue;
      if (Quality.badCommFault.band <= cached.quality.band) continue;
      batch[key] = cached.copyWith(quality: Quality.badCommFault);
    }
    _degrade(batch);
  }

  /// The snapshot after [alias] comes back: link-degraded keys read
  /// [Quality.uncertainLastKnown], **not** good.
  ///
  /// The link being back is not evidence about the number. Each value becomes
  /// good again only when it has been re-read, and a snapshot that came back
  /// good would make a reconnection a way of laundering an hour-old reading
  /// into a current one — the same lie as a stale value with better manners.
  ///
  /// Recovery is a snapshot and never a delta replay: every key that has a
  /// value comes back at once rather than waiting until it next happens to
  /// change, or a slow-moving tank level stays greyed for an hour after the
  /// link healed.
  void applyLinkRestored(String alias) {
    final batch = <String, DynamicValue>{};
    for (final key in _store.keys) {
      if (PipeKeys.isPipeKey(key)) continue;
      if (aliasOfKey(key) != alias) continue;
      final cached = _store.peek(key);
      if (cached == null) continue;
      if (!_isLinkDegraded(cached.quality)) continue;
      batch[key] = cached.copyWith(quality: Quality.uncertainLastKnown);
    }
    _degrade(batch);
  }

  /// Announces [link]'s current state — **once**, however many keys it cost.
  ///
  /// Sparkplug sends one NDEATH for a whole node for the same reason: at
  /// fifteen hundred keys, one event per key is fifteen hundred events for one
  /// event, arriving in the instant the client is already re-rendering every
  /// box on the page they are all about. That is a denial of service against
  /// the operator's own screen, delivered by their own gateway at the worst
  /// possible moment.
  ///
  /// The error is [UpstreamLink.lastError], which is contracted to be redacted
  /// **at the link**. It is deliberately not redacted a second time here: one
  /// redactor used by every adapter is the property worth keeping, and a
  /// belt-and-braces pass at this call site would hide an adapter that forgot.
  void announceLinkState(UpstreamLink link) {
    _statusNotifications++;
    if (_status.isClosed) return;
    _status.add(StatusParams(
      alias: link.alias,
      state: link.state.wireName,
      error: link.lastError,
    ));
  }

  /// Which link serves [key], or null for a health key, a refusal, or a name
  /// no configured link claimed.
  ///
  /// **Cached, and invalidated on a keymapping reload.** A mass degradation
  /// routes every key in the store, and routing is not free — the OPC UA
  /// adapter builds a `NodeId` on every `resolve`. But the cache cannot be
  /// permanent either: a reload re-points keys at different servers, and a
  /// stale attribution would degrade the wrong PLC's keys, which is the
  /// isolation failure this method exists to prevent wearing a disguise.
  /// `KeyRouter.applyKeyMappings` mints a fresh `KeyMappingsIngestResult` on
  /// every call, so its identity is the reload signal with nothing to keep in
  /// step.
  String? aliasOfKey(String key) {
    final ingest = router.lastIngest;
    if (!identical(ingest, _aliasCacheGeneration)) {
      _aliasCache.clear();
      _aliasCacheGeneration = ingest;
    }
    if (_aliasCache.containsKey(key)) return _aliasCache[key];
    final route = router.route(key);
    final alias = route is ClaimedRoute ? route.link.alias : null;
    _aliasCache[key] = alias;
    return alias;
  }

  final Map<String, String?> _aliasCache = <String, String?>{};
  Object? _aliasCacheGeneration;
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

/// One settled write outcome plus the instant this gateway settled it.
///
/// The settle instant is what the TTL prunes on; the command's own mint time
/// (decoded out of the ULID) is what the evidence rule reasons about. They are
/// different facts and conflating them would let a command minted on a panel
/// with a fast clock buy itself a longer window.
typedef _LoggedOutcome = ({WriteResult result, int at});

/// One key's answer plus whether it came from the wire, so [LocalStateMan.readMany]
/// can apply exactly the ones that did as a single batch.
typedef _ReadAnswer = ({String key, DynamicValue value, bool fromUpstream});

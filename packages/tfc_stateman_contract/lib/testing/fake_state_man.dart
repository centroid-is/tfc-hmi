/// The reference implementation the contract suite is developed against.
///
/// It is not a mock. It is a real, in-memory `StateManApi` backed by the same
/// [ValueStore] the server and client implementations use, with a control
/// surface ([StateManHarness]) standing in for the plant. Two jobs follow from
/// that: it proves a case is satisfiable before any production code exists, and
/// it is the honest baseline the deliberately damaged variants in
/// `broken_subscribe.dart` are measured against.
///
/// Backing it with the real store is the point. A fake with its own hand-rolled
/// notification logic would let the suite pass against something no production
/// implementation resembles; here the k-of-n rebuild property is satisfied by
/// the same code that will satisfy it on the gateway.
///
/// It lives under `lib/testing/` rather than `lib/src/` because the server and
/// client packages import it — a Phase 3 test that needs a state source with a
/// known value in it should not have to build one.
///
/// It runs a real freshness watchdog on the wall clock rather than on an
/// injected one. That costs the freshness cases a real `staleAfter` of runtime
/// each, and it is worth it: a sweep that only advances when a test advances a
/// fake clock is precisely the machinery that then fails to run in the plant,
/// and this fake exists to prove a case is satisfiable by something a real
/// implementation resembles.
///
/// The five reserved `PIPE.` health keys are served through the ordinary value
/// path (design §4.7, HLTH-01) — there is no health method here because there
/// is none on the wire — and are excluded from the freshness sweep (HLTH-02).
///
/// Members outside this plan's slice throw [UnimplementedError] naming the plan
/// that fills them. That is deliberate: an area nobody has contracted yet must
/// fail loudly if something starts depending on it, rather than return a
/// plausible empty answer.
library;

import 'dart:async';

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../src/harness.dart';

/// An in-memory state source with a lever for everything the plant would do.
class FakeStateMan implements StateManApi, StateManHarness {
  FakeStateMan({this.staleAfter = const Duration(milliseconds: 300)}) {
    _seedHealthKeys();
    _watchdog = Timer.periodic(_sweepInterval, (_) => sweepFreshness());
  }

  /// How long a value may go unheard-of before it must stop claiming to be
  /// current.
  ///
  /// 300 ms by default: long enough that the subscribe and store cases, which
  /// finish in single-digit milliseconds, never trip it, short enough that a
  /// freshness case waiting the deadline out on the wall clock stays cheap.
  /// The freshness driver passes a shorter one still.
  @override
  final Duration staleAfter;

  /// The reserved namespace the pipe reports on itself through (design §4.7,
  /// HLTH-01). There is no health method on the wire; these are ordinary
  /// subscribable keys, served through the same store and the same qualities
  /// as a temperature.
  static const healthPrefix = 'PIPE.';

  /// The five health keys, seeded at construction so a client can read them
  /// before anything has happened — a health indicator that reads "unknown"
  /// until the first fault is no indicator at all.
  static const healthKeys = [
    '${healthPrefix}connected',
    '${healthPrefix}rtt_ms',
    '${healthPrefix}data_age_ms',
    '${healthPrefix}reconnects',
    '${healthPrefix}epoch',
  ];

  /// One map, one batch entry point — the same store the real implementations
  /// use, so the notification-count promises are satisfied by production code
  /// rather than by test scaffolding.
  final _store = ValueStore();

  /// Keys retired by [dropKey]. Held separately from the store because the
  /// store has no concept of a tag that is gone: it would happily accept the
  /// next value for it.
  final _retiredKeys = <String>{};

  /// Closers for the streams [subscribe] has handed out, so [dispose] can shut
  /// down a consumer that never cancelled. Closers rather than the controllers
  /// themselves: nothing here needs to hold a controller once it is wired up.
  final _closeHandedOutStreams = <Future<void> Function()>[];

  /// When each key last had a value *arrive* for it.
  ///
  /// Deliberately not the value's own `sourceTime`: the harness leaves that
  /// null unless a case sets one, and a source that dated freshness from a
  /// field the upstream may not fill would consider every value it has ever
  /// received to be infinitely old.
  final _lastArrival = <String, DateTime>{};

  /// The freshness watchdog. Wall clock, not an injected one — a sweep that
  /// only runs when a test advances a fake clock is exactly the machinery that
  /// then fails to run in the plant.
  late final Timer _watchdog;

  /// Whether the upstream device link is up. Health keys are served regardless;
  /// plant keys are not.
  var _connected = true;

  var _roundTrips = 0;
  var _statusNotifications = 0;

  var _disposed = false;

  /// How often the watchdog re-evaluates ages.
  ///
  /// A quarter of the deadline, so a value is reported stale within 125% of it
  /// rather than within 200% — the contract cases allow three times the
  /// deadline, and the margin between those two numbers is what keeps them
  /// green on a loaded machine. Floored at 5 ms so an implausibly short
  /// deadline cannot turn the sweep into a busy loop.
  Duration get _sweepInterval {
    final quarter = staleAfter ~/ 4;
    return quarter < const Duration(milliseconds: 5)
        ? const Duration(milliseconds: 5)
        : quarter;
  }

  /// Health keys are excluded from the freshness sweep (HLTH-02).
  static bool isHealthKey(String key) => key.startsWith(healthPrefix);

  // ------------------------------------------------------------- value path

  /// The store's node for [key] — the same instance every time, so a widget
  /// keeps the handle it was given and a second `listen` costs nothing.
  @override
  ValueListenable<DynamicValue> listen(String key) => _store.node(key);

  /// A broadcast view of the same node, for stream-consuming code.
  ///
  /// A view, never a second source of truth: the controller carries whatever
  /// the node currently holds, pushed by a listener attached on first
  /// subscription and removed when the last subscriber cancels. That is also
  /// why nothing is replayed on listen — the snapshot lives in the store, where
  /// [read] and `listen(key).value` reach it synchronously, and this stream
  /// carries changes from the moment it is taken. Because the stream is
  /// returned synchronously (not behind a `Future`), taking it and listening to
  /// it happen in the same turn, so there is no window in which a change can be
  /// missed.
  @override
  Stream<DynamicValue> subscribe(String key) {
    final node = _store.node(key);
    late final StreamController<DynamicValue> controller;
    void push() => controller.add(node.value);
    controller = StreamController<DynamicValue>.broadcast(
      onListen: () => node.addListener(push),
      onCancel: () => node.removeListener(push),
    );
    _closeHandedOutStreams.add(controller.close);
    return controller.stream;
  }

  /// The cached value, or null when nothing has arrived for [key] yet — the
  /// "not known" / "known to be bad" distinction the interface requires.
  @override
  DynamicValue? read(String key) => _store.peek(key);

  /// The keys this source can actually serve.
  ///
  /// Filtered on a value having arrived, rather than returning every node the
  /// store holds: `listen` creates a node for any key asked of it, including a
  /// tag mistyped into a page config, and offering that key back to the page
  /// editor's picker would launder a typo into an apparently valid binding.
  @override
  List<String> get keys => [
        for (final key in _store.keys)
          if (_store.peek(key) != null) key,
      ];

  /// Drops every listener and closes every stream handed out. Idempotent: a
  /// second call is harmless, because the suite disposes in `addTearDown` and a
  /// case that disposes deliberately must not be punished for it.
  ///
  /// Cancelling the watchdog is the part that matters most here: a timer that
  /// outlives its source keeps the whole test isolate alive and keeps sweeping
  /// a store nobody is watching, so a leak in one case surfaces as an
  /// inexplicable notification in the next one.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _watchdog.cancel();
    _store.dispose();
    for (final close in _closeHandedOutStreams) {
      await close();
    }
    _closeHandedOutStreams.clear();
  }

  // --------------------------------------------------------- control surface

  /// Delivers one value, as one upstream update.
  ///
  /// [sourceTime] stays null unless given: stamping a receive time here would
  /// make two identical readings unequal and silently defeat the store's
  /// unchanged-value guard. `NotifiesOnUnchanged` in `broken_subscribe.dart`
  /// is that mistake, made on purpose.
  @override
  void setValue(String key, Object? value,
          {Quality quality = Quality.good, DateTime? sourceTime}) =>
      applyChanges({
        key: DynamicValue(value: value, quality: quality, sourceTime: sourceTime)
      });

  /// Delivers many keys as exactly one batch — one pass over the store, one
  /// sequence evaluation, k notifications. Simulates a subscription push
  /// carrying everything that moved since the last one.
  @override
  void setValues(Map<String, Object?> values) => applyChanges({
        for (final entry in values.entries)
          entry.key: DynamicValue(value: entry.value),
      });

  /// Re-delivers the current value under a different quality.
  ///
  /// Simulates what the freshness watchdog and the write path do to a value
  /// without the number itself changing: going stale, losing the upstream link,
  /// or carrying a pending write. Corresponds to Phase 2's `latency` and
  /// `blackhole` proxy modes, whichever produced the degradation.
  @override
  void setQuality(String key, Quality quality) => applyChanges({
        key: (_store.peek(key) ?? notYetKnown).copyWith(quality: quality),
      });

  /// The tag is gone upstream: [key] reads as a configuration error and never
  /// updates again.
  ///
  /// Simulates a PLC tag renamed or deleted under a page that still binds it.
  /// Retiring the key *after* the error value is applied is deliberate — the
  /// operator must be told once that the tag is gone, and told nothing after
  /// that.
  @override
  void dropKey(String key) {
    applyChanges({
      key: DynamicValue(value: null, quality: Quality.errorConfig),
    });
    _retiredKeys.add(key);
  }

  /// The single seam every lever applies through.
  ///
  /// Exists so a sabotage variant can break exactly one thing by overriding one
  /// method — a variant that had to reimplement each lever would drift from the
  /// honest fake in ways nobody intended, and "the sabotage is surgical" would
  /// stop being true.
  ///
  /// Everything routed here counts as a value *arriving*, so it resets the
  /// freshness clock. Degradations do not go through it — see [_degrade].
  void applyChanges(Map<String, DynamicValue> changes) =>
      _apply(changes, arrived: true);

  /// Applies a quality change without pretending a value arrived.
  ///
  /// The distinction is the whole freshness story: marking a value stale must
  /// not make it fresh again, and losing the upstream link is not news from
  /// upstream. A single seam that reset the clock on everything would produce
  /// a source that goes stale exactly once and never again.
  void _degrade(Map<String, DynamicValue> changes) =>
      _apply(changes, arrived: false);

  void _apply(Map<String, DynamicValue> changes, {required bool arrived}) {
    final live = <String, DynamicValue>{
      for (final entry in changes.entries)
        if (!_retiredKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (live.isEmpty) return;
    if (arrived) {
      final now = DateTime.now();
      for (final key in live.keys) {
        _lastArrival[key] = now;
      }
    }
    _store.applyBatch(live);
  }

  // ------------------------------------------------------------------- reads

  /// Answers from the cache after forcing one round trip upstream.
  ///
  /// The round trip is the point: this is the call a diagnostics page and a
  /// readback check use precisely when the cache is the thing under suspicion.
  @override
  Future<DynamicValue> readFresh(String key) async {
    _roundTrips++;
    return _answerFromUpstream([key])[key]!;
  }

  /// One round trip for however many keys are asked for.
  ///
  /// [_roundTrips] is incremented once, before any key is looked at, because
  /// that is the promise: reading fifty keys over a link with 200 ms of
  /// latency costs 200 ms, not ten seconds.
  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    _roundTrips++;
    return _answerFromUpstream(keys);
  }

  @override
  int get roundTrips => _roundTrips;

  @override
  int get statusNotifications => _statusNotifications;

  /// What one round trip comes back with, and what it does to the cache.
  ///
  /// An answer for **every** key asked about, including keys nothing is known
  /// about — as a bad-quality value rather than a missing entry, so the caller
  /// renders a fault instead of a blank. Keys the round trip genuinely reached
  /// are also applied to the store, which is what makes a forced read reset
  /// the freshness clock and clear a staleness the watchdog had applied.
  Map<String, DynamicValue> _answerFromUpstream(Iterable<String> keys) {
    final answers = <String, DynamicValue>{};
    final reached = <String, DynamicValue>{};
    for (final key in keys) {
      final cached = _store.peek(key);
      if (cached == null) {
        // Nothing is known and nothing can be: notYetKnown carries
        // errorConfig, which renders as a fault rather than as a good null.
        answers[key] = notYetKnown;
        continue;
      }
      if (_retiredKeys.contains(key) || !_reachable(key)) {
        // The tag is gone, or the link is down. Either way the answer is the
        // degraded value already in the cache — inventing a good one here is
        // the `LiesAboutQuality` sabotage.
        answers[key] = cached;
        continue;
      }
      final answer = _isLinkDegraded(cached.quality)
          ? cached.copyWith(quality: Quality.good)
          : cached;
      answers[key] = answer;
      reached[key] = answer;
    }
    if (reached.isNotEmpty) applyChanges(reached);
    return answers;
  }

  /// Whether a round trip for [key] can get an answer at all.
  bool _reachable(String key) => _connected || isHealthKey(key);

  /// Whether [quality] is one the freshness and link machinery applied.
  ///
  /// Only these two clear on a successful round trip. A source that reset
  /// *any* bad quality to good on a read would launder a genuine upstream
  /// fault — a non-finite reading, a bad string encoding — into a healthy
  /// number, which is the same lie as a stale value with better manners.
  static bool _isLinkDegraded(Quality quality) =>
      quality == Quality.badStale || quality == Quality.badCommFault;

  // -------------------------------------------------------------- freshness

  /// Re-evaluates every key's age and degrades the ones past [staleAfter].
  ///
  /// Overridable because it is the single behavior `ServesStaleReads` removes:
  /// a source whose sweep never runs delivers a page that looks exactly like a
  /// healthy one and has not been true for an hour.
  ///
  /// Two rules the loop encodes. Health keys are skipped (HLTH-02): they change
  /// only when the pipe's state changes, so on a healthy pipe they are
  /// *always* older than the deadline, and staling them would grey out the one
  /// indicator that says whether to believe the rest. And a key is only
  /// degraded if `badStale` is genuinely worse than what it already carries —
  /// band comparison, not [Quality.worst], because worst-wins resets to `good`
  /// within a band and would erase a write-pending badge an operator is
  /// watching.
  void sweepFreshness() {
    final now = DateTime.now();
    final stale = <String, DynamicValue>{};
    for (final key in _store.keys) {
      if (isHealthKey(key)) continue;
      final cached = _store.peek(key);
      if (cached == null) continue;
      final arrived = _lastArrival[key];
      if (arrived == null || now.difference(arrived) < staleAfter) continue;
      if (Quality.badStale.band <= cached.quality.band) continue;
      stale[key] = cached.copyWith(quality: Quality.badStale);
    }
    if (stale.isEmpty) return;
    _degrade(stale);
  }

  // ------------------------------------------------------------- link levers

  /// The upstream device link is down (Phase 2's `flap(down)`).
  ///
  /// Idempotent: a second call while already down changes nothing and announces
  /// nothing, because it is not a second event.
  @override
  void disconnectUpstream() {
    if (!_connected) return;
    _connected = false;
    applyLinkLoss();
    announceLinkState();
  }

  /// The upstream link is back, with a snapshot (Phase 2's `flap(up)`).
  ///
  /// Recovery is a snapshot and never a delta replay, so every key that has a
  /// value comes back at once rather than waiting until it next happens to
  /// change — otherwise a slow-moving tank level would stay greyed for an hour
  /// after the link healed.
  @override
  void reconnectUpstream() {
    if (_connected) return;
    _connected = true;
    applyLinkRestored();
    announceLinkState();
  }

  /// One pass over the store: every plant key degrades, the health keys record
  /// what happened, all in a single batch.
  ///
  /// One batch, not one per key — the store's promise is that a batch costs
  /// one pass and k notifications, and a link loss is the largest batch this
  /// source will ever apply.
  void applyLinkLoss() {
    final batch = <String, DynamicValue>{};
    for (final key in _store.keys) {
      if (isHealthKey(key)) continue;
      final cached = _store.peek(key);
      if (cached == null) continue;
      if (Quality.badCommFault.band <= cached.quality.band) continue;
      batch[key] = cached.copyWith(quality: Quality.badCommFault);
    }
    batch['${healthPrefix}connected'] = DynamicValue(value: false);
    _degrade(batch);
  }

  /// The snapshot that follows a reconnect: link-degraded keys come back good,
  /// the health counters record the reconnection.
  void applyLinkRestored() {
    final batch = <String, DynamicValue>{};
    for (final key in _store.keys) {
      if (isHealthKey(key)) continue;
      final cached = _store.peek(key);
      if (cached == null || !_isLinkDegraded(cached.quality)) continue;
      batch[key] = cached.copyWith(quality: Quality.good);
    }
    batch['${healthPrefix}connected'] = DynamicValue(value: true);
    batch['${healthPrefix}reconnects'] =
        DynamicValue(value: _healthCount('${healthPrefix}reconnects') + 1);
    // The epoch changes on every reconnect so a client can tell "the same
    // session, still running" from "a new session that may have missed
    // updates" — the distinction that decides between resuming and resyncing.
    batch['${healthPrefix}epoch'] =
        DynamicValue(value: _healthCount('${healthPrefix}epoch') + 1);
    applyChanges(batch);
  }

  /// Announces that the link's state changed — once, however many keys it cost.
  ///
  /// Kept separate from [applyLinkLoss] so a variant can fan it out per key
  /// without touching the degradation itself, which is exactly what
  /// `AnnouncesPerKey` does. Sparkplug sends one NDEATH for a whole node for
  /// the same reason: at 1500 keys, one event per key is 1500 events arriving
  /// in the instant the client is trying to redraw the page they are about.
  void announceLinkState() => _statusNotifications++;

  /// Seeds the five reserved health keys so they are readable before anything
  /// happens. A health indicator that reads "unknown" until the first fault
  /// tells an operator nothing at the moment they most need telling.
  ///
  /// `data_age_ms` and `rtt_ms` are seeded and left alone: a fake that
  /// refreshed them on a timer would notify every listener on every sweep and
  /// quietly wreck the notification-count promises the rest of the suite
  /// makes. A real gateway updates them on a slow cadence, which is a
  /// behaviour Phase 3 owns and no contract case here depends on.
  void _seedHealthKeys() => applyChanges({
        '${healthPrefix}connected': DynamicValue(value: true),
        '${healthPrefix}rtt_ms': DynamicValue(value: 0),
        '${healthPrefix}data_age_ms': DynamicValue(value: 0),
        '${healthPrefix}reconnects': DynamicValue(value: 0),
        '${healthPrefix}epoch': DynamicValue(value: 1),
      });

  int _healthCount(String key) => _store.peek(key)?.asInt ?? 0;

  // ----------------------------------------------------- other slices' areas

  @override
  Future<WriteResult> write(String key, Object? value, {Object? expect}) =>
      throw UnimplementedError('writes: plan 01-08');

  @override
  BrowseApi get browse => throw UnimplementedError('data services: plan 01-09');

  @override
  TimeseriesApi get timeseries =>
      throw UnimplementedError('data services: plan 01-09');

  @override
  HistoryViewApi get historyViews =>
      throw UnimplementedError('data services: plan 01-09');

  @override
  PreferencesApi get preferences =>
      throw UnimplementedError('data services: plan 01-09');
}

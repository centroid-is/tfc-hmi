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
  FakeStateMan({this.staleAfter = const Duration(milliseconds: 300)});

  /// How long a value may go unheard-of before it must stop claiming to be
  /// current.
  ///
  /// 300 ms by default: long enough that the subscribe and store cases, which
  /// finish in single-digit milliseconds, never trip it, short enough that a
  /// freshness case waiting the deadline out on the wall clock stays cheap.
  /// The freshness driver passes a shorter one still.
  @override
  final Duration staleAfter;

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

  var _disposed = false;

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
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
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
  void applyChanges(Map<String, DynamicValue> changes) {
    final live = <String, DynamicValue>{
      for (final entry in changes.entries)
        if (!_retiredKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (live.isEmpty) return;
    _store.applyBatch(live);
  }

  // ----------------------------------------------------- other slices' areas

  @override
  Future<DynamicValue> readFresh(String key) =>
      throw UnimplementedError('freshness and reads: plan 01-07 task 2');

  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) =>
      throw UnimplementedError('freshness and reads: plan 01-07 task 2');

  @override
  int get roundTrips =>
      throw UnimplementedError('freshness and reads: plan 01-07 task 2');

  @override
  int get statusNotifications =>
      throw UnimplementedError('freshness and reads: plan 01-07 task 2');

  @override
  void disconnectUpstream() =>
      throw UnimplementedError('freshness and reads: plan 01-07 task 2');

  @override
  void reconnectUpstream() =>
      throw UnimplementedError('freshness and reads: plan 01-07 task 2');

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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/state_man.dart';
import '../../../providers/timeseries.dart';
import 'timeseries_cache.dart';

export '../../../providers/timeseries.dart'
    show
        kTimeseriesResyncInterval,
        kTimeseriesResyncWindow,
        kTimeseriesNotifyGrace;

/// Mixin on [ConsumerState] that gives timeseries readouts a live, reconciled
/// cache per key — shared with every other readout showing the same key.
///
/// The plumbing — LISTEN/NOTIFY subscription, history fetch, cache, and the
/// periodic sweep that reconciles the cache with the database and re-opens a
/// stream that has ended, errored, or gone quiet — lives in
/// [TimeseriesKeyTracker], one per key however many readouts are looking at
/// it (see `timeseriesTrackerProvider`). The figure on the mimic and the same
/// figure in an open side pane read the same cache and cannot disagree.
///
/// This mixin is the widget-side adapter: it holds the trackers alive, routes
/// their change notifications into [tsUpdateDisplay], forwards TickerMode
/// visibility so sweeping pauses when nobody is watching a key, and keeps the
/// per-widget concerns — the interval variable and the display-expiry timer —
/// where they belong.
///
/// Subclasses implement 5 abstract members and call 3 lifecycle hooks.
mixin TimeseriesNotifyMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  // ── Abstract members ────────────────────────────────────────────────

  /// The timeseries keys to track (e.g. `[widget.config.key]` or
  /// `[widget.config.key1, widget.config.key2]`).
  List<String> get tsKeys;

  /// Optional variable name from an OptionVariable widget that controls the
  /// active counting interval. Return null if not used.
  String? get tsIntervalVariable;

  /// Maximum window in minutes across all presets + active interval.
  /// Used for pruning old timestamps and initial historical fetch.
  int get tsMaxWindowMinutes;

  /// Called when the interval variable changes value.
  /// The widget should store the new value and call [tsUpdateDisplay].
  void tsOnIntervalChanged(int minutes);

  /// Called when the display should be refreshed.
  /// Typically reads [tsCache.countSince] and calls [setState].
  void tsUpdateDisplay();

  /// Historical: the shared tracker always caches values alongside
  /// timestamps, so readouts that count and readouts that sum share a
  /// tracker when they share a key. Kept so subclasses that declared it
  /// still compile; it changes nothing.
  bool get tsCacheValues => false;

  // ── Provided state ──────────────────────────────────────────────────

  /// Read-only view over the shared per-key caches. Reads answer from the
  /// tracker of the key asked about; the write surface is inert here because
  /// the caches belong to the trackers and their other subscribers.
  late final TimeseriesCache tsCache = _SharedTrackerCache(this);

  final Map<String, TimeseriesKeyTracker> _tsTrackers = {};
  final Map<String, TimeseriesTrackerHandle> _tsHandles = {};
  final List<ProviderSubscription<TimeseriesKeyTracker>> _tsKeepAlive = [];

  StreamSubscription<Map<String, String>>? _tsSubsSub;
  Timer? _tsExpiryTimer;
  bool _tsVisible = true;
  bool _tsDisposed = false;

  bool get _tsAlive => !_tsDisposed && mounted;

  // ── Lifecycle hooks (call from widget) ──────────────────────────────

  /// Call from [initState] after setting initial interval.
  void tsInit() {
    _tsWatchIntervalVariable();
    for (final key in tsKeys) {
      // listenManual is what keeps the autoDispose tracker alive for this
      // widget's lifetime; it is closed with the element (and in tsDispose).
      _tsKeepAlive
          .add(ref.listenManual(timeseriesTrackerProvider(key), (_, __) {}));
      final tracker = ref.read(timeseriesTrackerProvider(key));
      _tsTrackers[key] = tracker;
      _tsHandles[key] = tracker.attach(windowMinutes: tsMaxWindowMinutes);
      tracker.addListener(_tsOnTrackerChanged);
    }
    // A tracker that already has data — this readout is the pane opening on
    // a key the page has been showing all along — will not notify again for
    // rows it already holds; paint what is there once this frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tsAlive && _tsVisible) tsUpdateDisplay();
    });
  }

  /// Call from [didChangeDependencies].
  void tsDidChangeDependencies() {
    final ticking = TickerMode.of(context);
    if (ticking && !_tsVisible) {
      _tsVisible = true;
      for (final handle in _tsHandles.values) {
        handle.visible = true;
      }
      // The trackers sweep the hidden stretch themselves if nobody else was
      // watching; the display just needs to catch up with their caches.
      tsUpdateDisplay();
    } else if (!ticking && _tsVisible) {
      _tsVisible = false;
      for (final handle in _tsHandles.values) {
        handle.visible = false;
      }
    }
  }

  /// Call from [dispose].
  void tsDispose() {
    _tsDisposed = true;
    _tsSubsSub?.cancel();
    _tsExpiryTimer?.cancel();
    for (final tracker in _tsTrackers.values) {
      tracker.removeListener(_tsOnTrackerChanged);
    }
    for (final handle in _tsHandles.values) {
      handle.detach();
    }
    for (final sub in _tsKeepAlive) {
      sub.close();
    }
    _tsTrackers.clear();
    _tsHandles.clear();
    _tsKeepAlive.clear();
  }

  // ── Internal ────────────────────────────────────────────────────────

  void _tsOnTrackerChanged() {
    if (_tsAlive && _tsVisible) tsUpdateDisplay();
  }

  void _tsWatchIntervalVariable() {
    final varName = tsIntervalVariable;
    if (varName == null) return;

    ref.read(stateManProvider.future).then((sm) {
      if (!_tsAlive) return;
      final cur = sm.getSubstitution(varName);
      if (cur != null) {
        final v = int.tryParse(cur);
        if (v != null && v > 0) {
          tsOnIntervalChanged(v);
        }
      }
      _tsSubsSub = sm.substitutionsChanged.listen((subs) {
        final v = int.tryParse(subs[varName] ?? '');
        if (v != null && v > 0 && _tsAlive) {
          tsOnIntervalChanged(v);
        }
      });
    });
  }

  /// Schedule a display update for exactly when the oldest in-window event
  /// expires from the counting window. Call from [tsUpdateDisplay].
  void tsScheduleExpiry(int intervalMinutes) {
    _tsExpiryTimer?.cancel();
    final since = DateTime.now().subtract(Duration(minutes: intervalMinutes));
    final oldest = tsCache.oldestAfter(tsKeys, since);
    if (oldest == null) return;
    final delay = oldest
        .add(Duration(minutes: intervalMinutes))
        .difference(DateTime.now());
    if (delay.isNegative) return;
    _tsExpiryTimer = Timer(delay, () {
      if (!_tsAlive || !_tsVisible) return;
      tsUpdateDisplay();
    });
  }
}

/// [TimeseriesCache]-shaped view over a mixin's trackers, so readouts keep
/// calling `tsCache.countSince(key, …)` unchanged.
///
/// Reads forward to the tracker holding that key. Writes are forwarded too —
/// they land in the shared cache, which is what a writer would mean — except
/// the destructive ones: `clear`/`clearKey` are no-ops (the cache has other
/// subscribers), and `prune` never cuts below a tracker's own window, which
/// may be wider than this widget's because someone else asked for more.
class _SharedTrackerCache implements TimeseriesCache {
  _SharedTrackerCache(this._owner);

  final TimeseriesNotifyMixin _owner;

  TimeseriesCache? _cacheFor(String key) => _owner._tsTrackers[key]?.cache;

  @override
  void init(List<String> keys) {}

  @override
  bool addTimestamp(String key, DateTime time) =>
      _cacheFor(key)?.addTimestamp(key, time) ?? false;

  @override
  int addAll(String key, Iterable<DateTime> times) =>
      _cacheFor(key)?.addAll(key, times) ?? 0;

  @override
  bool addEntry(String key, DateTime time, dynamic value) =>
      _cacheFor(key)?.addEntry(key, time, value) ?? false;

  @override
  int addEntries(String key, List<(DateTime, dynamic)> entries) =>
      _cacheFor(key)?.addEntries(key, entries) ?? 0;

  @override
  bool contains(String key, DateTime time) =>
      _cacheFor(key)?.contains(key, time) ?? false;

  @override
  (DateTime, dynamic)? latestValue(String key) =>
      _cacheFor(key)?.latestValue(key);

  @override
  List<(DateTime, dynamic)> valuesSince(String key, DateTime since) =>
      _cacheFor(key)?.valuesSince(key, since) ?? const [];

  @override
  double sumSince(String key, DateTime since) =>
      _cacheFor(key)?.sumSince(key, since) ?? 0.0;

  @override
  int countSince(String key, DateTime since) =>
      _cacheFor(key)?.countSince(key, since) ?? 0;

  @override
  void prune(int maxWindowMinutes) {
    for (final tracker in _owner._tsTrackers.values) {
      final floor = tracker.windowMinutes;
      tracker.cache
          .prune(maxWindowMinutes > floor ? maxWindowMinutes : floor);
    }
  }

  @override
  void clear() {}

  @override
  void clearKey(String key) {}

  @override
  DateTime? oldestAfter(List<String> keys, DateTime since) {
    DateTime? oldest;
    for (final key in keys) {
      final t = _cacheFor(key)?.oldestAfter([key], since);
      if (t != null && (oldest == null || t.isBefore(oldest))) {
        oldest = t;
      }
    }
    return oldest;
  }

  @override
  Set<DateTime> timestamps(String key) =>
      _cacheFor(key)?.timestamps(key) ?? const {};
}

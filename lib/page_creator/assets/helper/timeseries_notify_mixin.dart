import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart' as drift_db;

import '../../../providers/database.dart';
import '../../../providers/state_man.dart';
import 'timeseries_cache.dart';

/// Mixin on [ConsumerState] that replaces timer-based polling with
/// PostgreSQL LISTEN/NOTIFY for timeseries counting widgets.
///
/// Owns a [TimeseriesCache] and manages:
///   - LISTEN/NOTIFY subscriptions per key
///   - TickerMode visibility (pause/resume refresh timer)
///   - Interval variable watching via StateMan substitutions
///   - Periodic refresh timer (30s) for cache pruning + display update
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

  /// Override to `true` to also cache values alongside timestamps.
  /// When true, historical fetches and NOTIFY events store values via
  /// [TimeseriesCache.addEntries] / [TimeseriesCache.addEntry].
  bool get tsCacheValues => false;

  // ── Provided state ──────────────────────────────────────────────────

  final TimeseriesCache tsCache = TimeseriesCache();

  Database? _tsDb;
  bool _tsVisible = true;
  bool _tsDisposed = false;
  Timer? _tsRefreshTimer;
  StreamSubscription<Map<String, String>>? _tsSubsSub;
  final List<StreamSubscription<String>> _tsNotifySubs = [];
  final Set<String> _tsNotifyAlive = {};
  Timer? _tsExpiryTimer;

  bool get _tsAlive => !_tsDisposed && mounted;

  // ── Lifecycle hooks (call from widget) ──────────────────────────────

  /// Call from [initState] after setting initial interval.
  void tsInit() {
    tsCache.init(tsKeys);
    _tsWatchIntervalVariable();
    _tsInitData();
  }

  /// Call from [didChangeDependencies].
  void tsDidChangeDependencies() {
    final ticking = TickerMode.of(context);
    if (ticking && !_tsVisible) {
      _tsVisible = true;
      _tsStartRefreshTimer();
      tsUpdateDisplay();
    } else if (!ticking && _tsVisible) {
      _tsVisible = false;
      _tsRefreshTimer?.cancel();
      _tsRefreshTimer = null;
    }
  }

  /// Call from [dispose].
  void tsDispose() {
    _tsDisposed = true;
    _tsSubsSub?.cancel();
    _tsRefreshTimer?.cancel();
    _tsExpiryTimer?.cancel();
    for (final sub in _tsNotifySubs) {
      sub.cancel();
    }
    _tsNotifySubs.clear();
    tsCache.clear();
  }

  // ── Internal ────────────────────────────────────────────────────────

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

  Future<void> _tsInitData() async {
    _tsDb = await ref.read(databaseProvider.future);
    if (_tsDb == null || !_tsAlive) return;

    // Historical fetch
    final since =
        DateTime.now().subtract(Duration(minutes: tsMaxWindowMinutes));
    final sm = await ref.read(stateManProvider.future);
    if (!_tsAlive) return;

    for (final key in tsKeys) {
      try {
        final tableName = sm.resolveKey(key);
        final rows = await _tsDb!
            .queryTimeseriesData(tableName, since, orderBy: 'time ASC');
        if (!_tsAlive) return;
        if (tsCacheValues) {
          tsCache.addEntries(key, rows.map((r) => (r.time, r.value)).toList());
        } else {
          tsCache.addAll(key, rows.map((r) => r.time));
        }
      } catch (_) {
        // Table may not exist yet — that's fine
      }
    }

    if (!_tsAlive) return;
    tsUpdateDisplay();
    _tsInitNotify(sm);
    _tsStartRefreshTimer();
  }

  Future<void> _tsInitNotify(dynamic sm) async {
    if (_tsDb == null || !_tsAlive) return;

    for (final key in tsKeys) {
      try {
        final tableName = sm.resolveKey(key);
        final channelName =
            await _tsDb!.db.enableNotificationChannel(tableName);
        final sub =
            _tsDb!.db.listenToChannel(channelName).listen((payload) {
          if (!_tsAlive) return;
          final notification = drift_db.NotificationData.fromJson(payload);
          if (notification.action == drift_db.NotificationAction.insert) {
            if (notification.data.containsKey('time')) {
              final time = DateTime.parse(notification.data['time']);
              if (tsCacheValues) {
                tsCache.addEntry(key, time, notification.data['value']);
              } else {
                tsCache.addTimestamp(key, time);
              }
              _tsNotifyAlive.add(key);
              tsCache.prune(tsMaxWindowMinutes);
              if (_tsVisible) tsUpdateDisplay();
            }
          }
        });
        _tsNotifySubs.add(sub);
        _tsNotifyAlive.add(key);
      } catch (_) {
        // Channel setup can fail if table doesn't exist yet
      }
    }
  }

  void _tsStartRefreshTimer() {
    _tsRefreshTimer?.cancel();
    _tsRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_tsAlive || !_tsVisible) return;
      await _tsRefetchStale();
    });
  }

  /// Re-fetch from DB only for keys where NOTIFY setup failed.
  Future<void> _tsRefetchStale() async {
    if (_tsDb == null || !_tsAlive) return;
    final staleKeys =
        tsKeys.where((key) => !_tsNotifyAlive.contains(key)).toList();
    if (staleKeys.isEmpty) return;

    final since =
        DateTime.now().subtract(Duration(minutes: tsMaxWindowMinutes));
    final sm = await ref.read(stateManProvider.future);
    if (!_tsAlive) return;

    for (final key in staleKeys) {
      try {
        final tableName = sm.resolveKey(key);
        final rows = await _tsDb!
            .queryTimeseriesData(tableName, since, orderBy: 'time ASC');
        if (!_tsAlive) return;
        tsCache.clearKey(key);
        if (tsCacheValues) {
          tsCache.addEntries(key, rows.map((r) => (r.time, r.value)).toList());
        } else {
          tsCache.addAll(key, rows.map((r) => r.time));
        }
      } catch (_) {}
    }
    if (_tsAlive && _tsVisible) tsUpdateDisplay();
  }

  /// Schedule a display update for exactly when the oldest in-window event
  /// expires from the counting window. Call from [tsUpdateDisplay].
  void tsScheduleExpiry(int intervalMinutes) {
    _tsExpiryTimer?.cancel();
    final since =
        DateTime.now().subtract(Duration(minutes: intervalMinutes));
    final oldest = tsCache.oldestAfter(tsKeys, since);
    if (oldest == null) return;
    final delay = oldest
        .add(Duration(minutes: intervalMinutes))
        .difference(DateTime.now());
    if (delay.isNegative) return;
    _tsExpiryTimer = Timer(delay, () {
      if (!_tsAlive || !_tsVisible) return;
      tsCache.prune(tsMaxWindowMinutes);
      tsUpdateDisplay();
    });
  }
}

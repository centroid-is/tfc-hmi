import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart' as drift_db;
import 'package:tfc_dart/core/state_man.dart';

import '../../../providers/database.dart';
import '../../../providers/state_man.dart';
import 'database_recovery.dart';
import 'timeseries_cache.dart';

/// How often every timeseries readout reconciles its cache with the database.
///
/// This is the ceiling on how stale a readout can be when its NOTIFY stream
/// has stopped delivering — for whatever reason, detected or not.
const kTimeseriesResyncInterval = Duration(seconds: 30);

/// How far back each reconciling sweep looks.
///
/// Wider than [kTimeseriesResyncInterval] so consecutive sweeps overlap and a
/// row cannot fall between two of them, and wider than the collector's batch
/// lag so a row is never both too old for the slice and not yet inserted.
const kTimeseriesResyncWindow = Duration(minutes: 2);

/// A row older than this that a sweep finds in the database but not in the
/// cache is taken as proof that NOTIFY is no longer delivering for that key.
///
/// Younger rows are not: the collector batches its inserts, so a row's `time`
/// can lag its insert by seconds, and the sweep's query can return a row
/// whose notification is still on the wire. Sixty seconds is comfortably
/// beyond both.
const kTimeseriesNotifyGrace = Duration(seconds: 60);

/// Mixin on [ConsumerState] that replaces timer-based polling with
/// PostgreSQL LISTEN/NOTIFY for timeseries counting widgets.
///
/// Owns a [TimeseriesCache] and manages:
///   - LISTEN/NOTIFY subscriptions per key
///   - TickerMode visibility (pause/resume the reconciling timer)
///   - Interval variable watching via StateMan substitutions
///   - A periodic sweep ([kTimeseriesResyncInterval]) that reconciles the
///     cache with the database, re-fetches and re-subscribes any key whose
///     channel has ended, and prunes what has aged out
///
/// The sweep is what makes the figure trustworthy. NOTIFY is the fast path,
/// but it is a stream that can stop without saying so — the connection
/// carrying it dies, or the trigger feeding it is dropped by a table
/// recreate — and a readout that trusted it alone sat on its last count for
/// the rest of the shift, looking perfectly healthy, while the same readout
/// freshly mounted in a side pane showed the right number. The two must never
/// disagree by more than the sweep interval.
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

  static final Logger _tsLog = Logger();

  Database? _tsDb;
  bool _tsVisible = true;
  bool _tsDisposed = false;
  Timer? _tsRefreshTimer;
  StreamSubscription<Map<String, String>>? _tsSubsSub;

  /// The live NOTIFY subscription per key. A key with no entry here is
  /// polled by the sweep until it can be subscribed again.
  final Map<String, StreamSubscription<String>> _tsNotifySubs = {};

  /// Keys whose NOTIFY stream is believed to be delivering.
  final Set<String> _tsNotifyAlive = {};
  Timer? _tsExpiryTimer;

  /// A sweep in flight; the timer does not start another on top of it.
  bool _tsSweeping = false;

  /// When the widget stopped ticking, so the sweep on resume can cover the
  /// whole stretch it was not looking.
  DateTime? _tsHiddenSince;

  /// Bumped by every (re)initialisation, so one overtaken by a newer one
  /// stops at its next await instead of subscribing on top of it.
  int _tsGeneration = 0;

  bool get _tsAlive => !_tsDisposed && mounted;

  // ── Lifecycle hooks (call from widget) ──────────────────────────────

  /// Call from [initState] after setting initial interval.
  void tsInit() {
    tsCache.init(tsKeys);
    _tsWatchIntervalVariable();
    // The database is often not up yet — on a plant-wide power cut Flutter is
    // drawing while Postgres is still replaying WAL. Without this the readout
    // takes the null and stays blank until the station is restarted.
    reinitOnDatabaseAvailable(
      ref,
      currentDatabase: () => _tsDb,
      onDatabaseAvailable: _tsRestartData,
    );
    _tsStart();
  }

  Future<void> _tsStart() async {
    final db = await ref.read(databaseProvider.future);
    if (db == null || !_tsAlive) return;
    // When the database is up from the start, the recovery hook above fires
    // the moment the provider resolves — before this continuation gets its
    // turn — and has already initialised on this very instance. Doing it
    // again here subscribed every readout twice at startup, each time
    // dropping and recreating the table's trigger.
    if (identical(db, _tsDb)) return;
    await _tsInitData(db);
  }

  /// Call from [didChangeDependencies].
  void tsDidChangeDependencies() {
    final ticking = TickerMode.of(context);
    if (ticking && !_tsVisible) {
      _tsVisible = true;
      final hiddenFor = _tsHiddenSince == null
          ? Duration.zero
          : DateTime.now().difference(_tsHiddenSince!);
      _tsHiddenSince = null;
      _tsStartRefreshTimer();
      tsUpdateDisplay();
      // Back in front of the operator: reconcile now rather than at the next
      // tick, over a window that covers everything the sweep did not look at
      // while the page was hidden. NOTIFY kept the cache current in the
      // meantime if it was delivering; this is for when it was not.
      unawaited(_tsSweep(window: hiddenFor + kTimeseriesResyncWindow));
    } else if (!ticking && _tsVisible) {
      _tsVisible = false;
      _tsHiddenSince = DateTime.now();
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
    for (final sub in _tsNotifySubs.values) {
      sub.cancel();
    }
    _tsNotifySubs.clear();
    _tsNotifyAlive.clear();
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

  /// Drop what the previous (failed or superseded) connection left behind and
  /// fetch again. Only reached when a *different* Database instance turns up,
  /// so it cannot loop on a database that stays down.
  void _tsRestartData(Database db) {
    if (!_tsAlive || identical(db, _tsDb)) return;
    for (final sub in _tsNotifySubs.values) {
      sub.cancel();
    }
    _tsNotifySubs.clear();
    _tsNotifyAlive.clear();
    _tsRefreshTimer?.cancel();
    _tsRefreshTimer = null;
    _tsInitData(db);
  }

  Future<void> _tsInitData(Database db) async {
    final generation = ++_tsGeneration;
    _tsDb = db;
    bool superseded() => !_tsAlive || generation != _tsGeneration;

    final sm = await ref.read(stateManProvider.future);
    if (superseded()) return;

    // Subscribe first, then fetch: a row landing between the two is then in
    // the fetch, or notified, or both — and both is fine, the cache is a set.
    // The other order leaves a gap the size of the fetch.
    for (final key in tsKeys) {
      await _tsSubscribe(sm, key);
      if (superseded()) return;
    }
    final since =
        DateTime.now().subtract(Duration(minutes: tsMaxWindowMinutes));
    for (final key in tsKeys) {
      await _tsMerge(sm, key, since);
      if (superseded()) return;
    }

    tsUpdateDisplay();
    _tsStartRefreshTimer();
  }

  /// Opens the NOTIFY stream for [key], replacing any it already has.
  ///
  /// The stream ending or erroring — the connection under it died, and
  /// `AppDatabase` ends every channel stream when it notices — drops the key
  /// from [_tsNotifyAlive]; the next sweep fetches what was missed and calls
  /// this again. Failure to open at all (the table does not exist yet) is the
  /// same: the sweep keeps trying.
  Future<void> _tsSubscribe(StateMan sm, String key) async {
    final db = _tsDb;
    if (db == null || !_tsAlive) return;
    // Not awaited: there is nothing to wait for, and a cancel's future is
    // completed in the root zone, which under a fake-async test never gets
    // its turn — the whole sweep would stall behind it.
    _tsNotifySubs.remove(key)?.cancel();
    _tsNotifyAlive.remove(key);
    try {
      final tableName = sm.resolveKey(key);
      final channelName = await db.db.enableNotificationChannel(tableName);
      if (!_tsAlive || !identical(db, _tsDb)) return;
      late final StreamSubscription<String> sub;
      sub = db.db.listenToChannel(channelName).listen(
        (payload) {
          if (!_tsAlive) return;
          final notification = drift_db.NotificationData.fromJson(payload);
          if (notification.action != drift_db.NotificationAction.insert) {
            return;
          }
          if (!notification.data.containsKey('time')) return;
          final time = DateTime.parse(notification.data['time']);
          if (tsCacheValues) {
            tsCache.addEntry(key, time, notification.data['value']);
          } else {
            tsCache.addTimestamp(key, time);
          }
          tsCache.prune(tsMaxWindowMinutes);
          if (_tsVisible) tsUpdateDisplay();
        },
        onError: (Object error) => _tsChannelLost(key, sub, 'errored: $error'),
        onDone: () => _tsChannelLost(key, sub, 'ended'),
      );
      _tsNotifySubs[key] = sub;
      _tsNotifyAlive.add(key);
    } catch (e) {
      // Table may not exist yet, or the database is unreachable. The sweep
      // polls this key and retries the subscription every tick.
      _tsLog.d('NOTIFY subscription for "$key" not available yet: $e');
    }
  }

  /// The NOTIFY stream for [key] stopped. From here until the next sweep
  /// re-subscribes it, the key is polled.
  void _tsChannelLost(String key, StreamSubscription<String> sub, String how) {
    // A stream superseded by a fresh subscription may still report its end;
    // that is not news about the current one.
    if (!identical(_tsNotifySubs[key], sub)) return;
    _tsNotifySubs.remove(key);
    _tsNotifyAlive.remove(key);
    sub.cancel();
    if (!_tsAlive) return;
    _tsLog.w('NOTIFY stream for "$key" $how; '
        'polling until it can be re-subscribed');
  }

  void _tsStartRefreshTimer() {
    _tsRefreshTimer?.cancel();
    _tsRefreshTimer = Timer.periodic(kTimeseriesResyncInterval, (_) {
      if (!_tsAlive || !_tsVisible) return;
      unawaited(_tsSweep());
    });
  }

  /// Reconciles the cache with the database.
  ///
  /// A key whose NOTIFY stream is gone gets the full window fetched again and
  /// the stream re-opened. A key whose stream looks fine gets the last
  /// [window] merged in — cheap, an index range on a few dozen rows — which
  /// both corrects the count and tests the stream: rows older than
  /// [kTimeseriesNotifyGrace] that only the database knew about mean it has
  /// quietly stopped delivering, and it is re-opened on the spot. The trigger
  /// gets recreated by that, which is the cure for the one way a stream goes
  /// quiet with its connection intact — a table recreate dropping the
  /// trigger.
  Future<void> _tsSweep({Duration window = kTimeseriesResyncWindow}) async {
    if (_tsDb == null || !_tsAlive || _tsSweeping) return;
    _tsSweeping = true;
    try {
      final sm = await ref.read(stateManProvider.future);
      if (!_tsAlive) return;
      final maxWindow = Duration(minutes: tsMaxWindowMinutes);
      final slice = window < maxWindow ? window : maxWindow;
      var changed = false;
      for (final key in tsKeys) {
        if (_tsNotifyAlive.contains(key)) {
          final now = DateTime.now();
          final missed = await _tsMerge(sm, key, now.subtract(slice),
              missedBefore: now.subtract(kTimeseriesNotifyGrace));
          if (!_tsAlive) return;
          if (missed == null) continue;
          if (missed.added > 0) changed = true;
          if (missed.silent > 0) {
            _tsLog.w('NOTIFY stream for "$key" has gone quiet: '
                '${missed.silent} row(s) older than '
                '${kTimeseriesNotifyGrace.inSeconds}s arrived without a '
                'notification; re-subscribing');
            await _tsSubscribe(sm, key);
          }
        } else {
          await _tsSubscribe(sm, key);
          if (!_tsAlive) return;
          final missed = await _tsMerge(
              sm, key, DateTime.now().subtract(maxWindow));
          if ((missed?.added ?? 0) > 0) changed = true;
        }
        if (!_tsAlive) return;
      }
      tsCache.prune(tsMaxWindowMinutes);
      if (changed && _tsVisible) tsUpdateDisplay();
    } finally {
      _tsSweeping = false;
    }
  }

  /// Fetches [key]'s rows since [since] and merges them into the cache.
  ///
  /// Returns how many were new, and how many of those were already older
  /// than [missedBefore] — rows NOTIFY should have delivered long ago. Null
  /// when the query failed (the table may not exist yet), which is not the
  /// same as nothing new.
  Future<({int added, int silent})?> _tsMerge(
      StateMan sm, String key, DateTime since,
      {DateTime? missedBefore}) async {
    final db = _tsDb;
    if (db == null) return null;
    try {
      final tableName = sm.resolveKey(key);
      final rows =
          await db.queryTimeseriesData(tableName, since, orderBy: 'time ASC');
      if (!_tsAlive || !identical(db, _tsDb)) return null;
      var silent = 0;
      if (missedBefore != null) {
        for (final row in rows) {
          if (row.time.isBefore(missedBefore) &&
              !tsCache.contains(key, row.time)) {
            silent++;
          }
        }
      }
      final added = tsCacheValues
          ? tsCache.addEntries(key, [for (final r in rows) (r.time, r.value)])
          : tsCache.addAll(key, rows.map((r) => r.time));
      return (added: added, silent: silent);
    } catch (e) {
      _tsLog.d('History for "$key" not available: $e');
      return null;
    }
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

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:logger/logger.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import 'database.dart';

/// Watches a fixed set of `flutter_preferences` rows for changes made by
/// *other* processes.
///
/// [Preferences.onPreferencesChanged] only fires for writes made through the
/// local [Preferences] instance, so a headless process (the backend) never
/// hears about edits an HMI station saves. This class closes that gap without
/// hammering the database:
///
/// - Primary signal: Postgres LISTEN/NOTIFY via a keyed trigger
///   ([AppDatabase.enableKeyedNotificationChannel]) on the shared
///   notification connection — an idle-cost of zero queries.
/// - Every signal (and a slow safety-net poll) is answered with one tiny
///   query that hashes the watched rows *server-side*
///   (`md5(value)`), so the multi-hundred-kB `key_mappings` JSON is never
///   shipped over the wire just to discover nothing changed.
/// - Change events are emitted only when a digest actually differs, so an HMI
///   re-saving an identical config is a no-op.
///
/// The poll also covers the failure modes NOTIFY cannot: notifications missed
/// while the connection was down, and a trigger that could not be installed
/// at all. When the notification stream dies it is re-listened with backoff,
/// and every successful (re-)listen is followed by an immediate digest check
/// so nothing that happened in between is lost.
class PreferencesWatcher {
  PreferencesWatcher({
    required Set<String> keys,
    required Future<Map<String, String>> Function(Set<String> keys)
        fetchDigests,
    Stream<String> Function()? listenForChanges,
    this.pollInterval = const Duration(minutes: 5),
    this.notifyDebounce = const Duration(milliseconds: 300),
    this.relistenBackoff = const Duration(seconds: 5),
  })  : keys = Set.unmodifiable(keys),
        _fetchDigests = fetchDigests,
        _listenForChanges = listenForChanges;

  /// Watch [keys] in the `flutter_preferences` table behind [db].
  factory PreferencesWatcher.forDatabase(
    Database db, {
    required Set<String> keys,
    Duration pollInterval = const Duration(minutes: 5),
  }) {
    return PreferencesWatcher(
      keys: keys,
      pollInterval: pollInterval,
      fetchDigests: (keys) async {
        final ordered = keys.toList();
        final placeholders =
            List.generate(ordered.length, (i) => '\$${i + 1}').join(', ');
        final rows = await db.db.customSelect(
          'SELECT key, md5(coalesce(value, \'\')) AS digest FROM flutter_preferences '
          'WHERE key IN ($placeholders)',
          variables: [for (final k in ordered) Variable.withString(k)],
        ).get();
        return {
          for (final row in rows)
            row.read<String>('key'): row.read<String>('digest'),
        };
      },
      listenForChanges: () {
        StreamSubscription<String>? sub;
        late StreamController<String> controller;
        controller = StreamController<String>(
          onListen: () async {
            try {
              final channel = await db.db.enableKeyedNotificationChannel(
                  'flutter_preferences', 'key');
              sub = db.db.listenToChannel(channel).listen(
                (payload) {
                  final key = _keyFromPayload(payload);
                  if (key != null) controller.add(key);
                },
                onError: controller.addError,
                onDone: controller.close,
              );
            } catch (e, s) {
              controller.addError(e, s);
              await controller.close();
            }
          },
          onCancel: () => sub?.cancel(),
        );
        return controller.stream;
      },
    );
  }

  final Set<String> keys;
  final Duration pollInterval;
  final Duration notifyDebounce;
  final Duration relistenBackoff;

  final Future<Map<String, String>> Function(Set<String> keys) _fetchDigests;
  final Stream<String> Function()? _listenForChanges;

  static final Logger _logger = Logger();

  final _changes = StreamController<String>.broadcast();
  Map<String, String>? _baseline;
  Timer? _pollTimer;
  Timer? _debounceTimer;
  Timer? _relistenTimer;
  StreamSubscription<String>? _notifySub;
  Future<void>? _refreshInFlight;
  bool _closed = false;

  /// Preference keys whose stored value actually changed. Broadcast.
  Stream<String> get changes => _changes.stream;

  /// Payload shape comes from [AppDatabase.enableKeyedNotificationChannel]:
  /// `{"action": "UPDATE", "key": "key_mappings"}`.
  static String? _keyFromPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded['key'] as String?;
    } catch (_) {
      // Not ours / malformed — the poll still covers the change.
    }
    return null;
  }

  /// Takes the digest baseline, starts the notification listener and the
  /// safety-net poll. A baseline fetch failure is tolerated: the first
  /// *successful* refresh becomes the baseline instead (and emits nothing),
  /// so a database hiccup at startup cannot fabricate change events.
  Future<void> start() async {
    await _refresh();
    _pollTimer = Timer.periodic(pollInterval, (_) => _refresh());
    _listen();
  }

  void _listen() {
    final listenForChanges = _listenForChanges;
    if (listenForChanges == null || _closed) return;
    try {
      _notifySub = listenForChanges().listen(
        (key) {
          if (!keys.contains(key)) return;
          _debounceTimer?.cancel();
          _debounceTimer = Timer(notifyDebounce, _refresh);
        },
        onError: (Object e) {
          _logger.w('Preferences notify stream error, will re-listen: $e');
          _scheduleRelisten();
        },
        onDone: _scheduleRelisten,
      );
    } catch (e) {
      _logger.w('Preferences notify listen failed, will re-listen: $e');
      _scheduleRelisten();
    }
  }

  void _scheduleRelisten() {
    if (_closed) return;
    _notifySub?.cancel();
    _notifySub = null;
    _relistenTimer?.cancel();
    _relistenTimer = Timer(relistenBackoff, () {
      _listen();
      // Catch anything that changed while we were deaf.
      _refresh();
    });
  }

  /// Fetches the digests and emits every watched key whose digest differs
  /// from the baseline. Concurrent calls (poll firing during a notify-driven
  /// refresh) share one fetch.
  @visibleForTesting
  Future<void> refreshNow() => _refresh();

  Future<void> _refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _doRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  Future<void> _doRefresh() async {
    final Map<String, String> digests;
    try {
      digests = await _fetchDigests(keys);
    } catch (e) {
      // Outage: the next notify or poll retries. Never emit on failure.
      _logger.w('Preferences digest fetch failed: $e');
      return;
    }
    if (_closed) return;
    final baseline = _baseline;
    _baseline = digests;
    if (baseline == null) return;
    for (final key in keys) {
      if (baseline[key] != digests[key]) {
        _changes.add(key);
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    _pollTimer?.cancel();
    _debounceTimer?.cancel();
    _relistenTimer?.cancel();
    await _notifySub?.cancel();
    await _changes.close();
  }
}

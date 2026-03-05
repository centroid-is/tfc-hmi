/// Pure Dart cache for timeseries timestamps.
///
/// Manages `Map<String, Set<DateTime>>` with add/prune/count operations.
/// No Flutter dependencies — fully unit-testable.
class TimeseriesCache {
  final Map<String, Set<DateTime>> _caches = {};

  /// Create empty sets for the given keys.
  void init(List<String> keys) {
    for (final key in keys) {
      _caches.putIfAbsent(key, () => {});
    }
  }

  /// Add a single timestamp to [key]. Auto-creates key if missing.
  void addTimestamp(String key, DateTime time) {
    (_caches[key] ??= {}).add(time);
  }

  /// Bulk-load timestamps for [key]. Auto-creates key if missing.
  void addAll(String key, Iterable<DateTime> times) {
    (_caches[key] ??= {}).addAll(times);
  }

  /// Count timestamps strictly after [since] (exclusive boundary).
  int countSince(String key, DateTime since) {
    final set = _caches[key];
    if (set == null) return 0;
    return set.where((t) => t.isAfter(since)).length;
  }

  /// Remove timestamps older than [maxWindowMinutes] from all keys.
  void prune(int maxWindowMinutes) {
    final cutoff =
        DateTime.now().subtract(Duration(minutes: maxWindowMinutes));
    for (final set in _caches.values) {
      set.removeWhere((t) => t.isBefore(cutoff));
    }
  }

  /// Remove all data from all keys.
  void clear() {
    for (final set in _caches.values) {
      set.clear();
    }
  }

  /// Remove all data for a single key.
  void clearKey(String key) {
    _caches[key]?.clear();
  }

  /// Returns the oldest timestamp strictly after [since] across [keys],
  /// or null if none exist. Used to schedule the next expiry timer.
  DateTime? oldestAfter(List<String> keys, DateTime since) {
    DateTime? oldest;
    for (final key in keys) {
      for (final t in _caches[key] ?? const <DateTime>{}) {
        if (t.isAfter(since) && (oldest == null || t.isBefore(oldest))) {
          oldest = t;
        }
      }
    }
    return oldest;
  }

  /// Direct read access (unmodifiable view).
  Set<DateTime> timestamps(String key) =>
      _caches[key] ?? const {};
}

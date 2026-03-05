/// Pure Dart cache for timeseries timestamps and optional values.
///
/// Manages `Map<String, Set<DateTime>>` with add/prune/count operations.
/// Optionally stores `Map<String, Map<DateTime, dynamic>>` for value caching.
/// No Flutter dependencies — fully unit-testable.
class TimeseriesCache {
  final Map<String, Set<DateTime>> _caches = {};
  final Map<String, Map<DateTime, dynamic>> _values = {};

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

  /// Add a single timestamped value to [key]. Auto-creates key if missing.
  void addEntry(String key, DateTime time, dynamic value) {
    (_caches[key] ??= {}).add(time);
    (_values[key] ??= {})[time] = value;
  }

  /// Bulk-load timestamped values for [key]. Auto-creates key if missing.
  /// [entries] is a list of `(DateTime, dynamic)` records.
  void addEntries(String key, List<(DateTime, dynamic)> entries) {
    final timestamps = (_caches[key] ??= {});
    final values = (_values[key] ??= {});
    for (final (time, value) in entries) {
      timestamps.add(time);
      values[time] = value;
    }
  }

  /// Returns the most recent `(DateTime, value)` for [key], or null.
  (DateTime, dynamic)? latestValue(String key) {
    final values = _values[key];
    if (values == null || values.isEmpty) return null;
    DateTime? latest;
    for (final t in values.keys) {
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    return (latest!, values[latest]!);
  }

  /// Returns all `(DateTime, value)` entries strictly after [since], sorted by time.
  List<(DateTime, dynamic)> valuesSince(String key, DateTime since) {
    final values = _values[key];
    if (values == null || values.isEmpty) return const [];
    final result = <(DateTime, dynamic)>[];
    for (final entry in values.entries) {
      if (entry.key.isAfter(since)) {
        result.add((entry.key, entry.value));
      }
    }
    result.sort((a, b) => a.$1.compareTo(b.$1));
    return result;
  }

  /// Sum numeric values strictly after [since] (exclusive boundary).
  /// Non-numeric values are skipped.
  double sumSince(String key, DateTime since) {
    final values = _values[key];
    if (values == null || values.isEmpty) return 0.0;
    double sum = 0.0;
    for (final entry in values.entries) {
      if (entry.key.isAfter(since)) {
        final v = entry.value;
        if (v is num) {
          sum += v.toDouble();
        } else {
          final parsed = double.tryParse(v.toString());
          if (parsed != null) sum += parsed;
        }
      }
    }
    return sum;
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
    for (final values in _values.values) {
      values.removeWhere((t, _) => t.isBefore(cutoff));
    }
  }

  /// Remove all data from all keys.
  void clear() {
    for (final set in _caches.values) {
      set.clear();
    }
    for (final values in _values.values) {
      values.clear();
    }
  }

  /// Remove all data for a single key.
  void clearKey(String key) {
    _caches[key]?.clear();
    _values[key]?.clear();
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

/// In-memory key-value cache with per-entry TTL expiration.
///
/// Entries are lazily evicted on access (no background timer).
/// Thread-safe within a single Dart isolate (async but not multi-threaded).
///
/// Supports nullable values: use [has] to distinguish "not cached" from
/// "cached null". The [getOrCompute] method correctly handles null values
/// by checking entry existence rather than value nullability.
class TtlCache<K, V> {
  /// Creates a [TtlCache] with the given [defaultTtl] and optional
  /// [maxEntries] limit (default 500).
  TtlCache({required this.defaultTtl, this.maxEntries = 500});

  /// Default time-to-live for cached entries.
  final Duration defaultTtl;

  /// Maximum number of entries before eviction occurs.
  final int maxEntries;

  final _store = <K, _CacheEntry<V>>{};

  /// Get a cached value, or null if missing or expired.
  ///
  /// For nullable value types, use [has] to distinguish "not cached" from
  /// "cached null".
  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    return entry.value;
  }

  /// Whether the cache contains a non-expired entry for [key].
  ///
  /// Returns true even if the cached value is null.
  bool has(K key) {
    final entry = _store[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _store.remove(key);
      return false;
    }
    return true;
  }

  /// Get a cached value, or compute and cache it if missing/expired.
  ///
  /// Correctly handles null values: null is a valid cached result.
  /// Uses entry existence (not value nullability) to detect cache hits.
  Future<V> getOrCompute(K key, Future<V> Function() compute,
      {Duration? ttl}) async {
    final entry = _store[key];
    if (entry != null && !entry.isExpired) {
      return entry.value;
    }
    _store.remove(key); // Clean up expired entry
    final value = await compute();
    set(key, value, ttl: ttl);
    return value;
  }

  /// Store a value with optional custom [ttl].
  void set(K key, V value, {Duration? ttl}) {
    if (_store.length >= maxEntries) {
      _evictOldest();
    }
    _store[key] = _CacheEntry(value, ttl ?? defaultTtl);
  }

  /// Remove a specific entry.
  void invalidate(K key) => _store.remove(key);

  /// Clear all entries.
  void clear() => _store.clear();

  /// Number of entries (including possibly expired ones).
  int get length => _store.length;

  void _evictOldest() {
    // Remove expired entries first
    _store.removeWhere((_, entry) => entry.isExpired);
    // If still over capacity, remove oldest by insertion order
    while (_store.length >= maxEntries) {
      _store.remove(_store.keys.first);
    }
  }
}

class _CacheEntry<V> {
  _CacheEntry(this.value, Duration ttl) : _expiresAt = DateTime.now().add(ttl);

  final V value;
  final DateTime _expiresAt;

  bool get isExpired => DateTime.now().isAfter(_expiresAt);
}

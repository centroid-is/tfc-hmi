import 'package:drift/drift.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase;

/// A single time bucket within aggregated trend data.
///
/// Contains the min/avg/max values and sample count for one time window
/// of a collected key's data.
class TrendBucket {
  TrendBucket({
    required this.bucket,
    required this.minVal,
    required this.avgVal,
    required this.maxVal,
    required this.sampleCount,
  });

  /// The start timestamp of this bucket.
  final DateTime bucket;

  /// Minimum value within this bucket.
  final double minVal;

  /// Average value within this bucket.
  final double avgVal;

  /// Maximum value within this bucket.
  final double maxVal;

  /// Number of raw samples aggregated into this bucket.
  final int sampleCount;

  /// Format this bucket as a single human-readable text line.
  String toText() {
    return '${bucket.toUtc().toIso8601String()}  '
        'min=$minVal  avg=$avgVal  max=$maxVal  samples=$sampleCount';
  }
}

/// The result of a trend query, containing aggregated buckets or an error.
class TrendResult {
  TrendResult({
    required this.key,
    required this.buckets,
    required this.bucketInterval,
    this.error,
  });

  /// The logical key that was queried.
  final String key;

  /// Aggregated time buckets, empty if no data or error.
  final List<TrendBucket> buckets;

  /// The bucket interval used for aggregation (e.g., "36000 milliseconds").
  final String bucketInterval;

  /// Error message if the query failed, null on success.
  final String? error;

  /// Format the result as human-readable text for LLM consumption.
  ///
  /// Returns either the error message, a no-data message, or a header line
  /// followed by one text line per bucket.
  String toText() {
    if (error != null) return error!;
    if (buckets.isEmpty) {
      return 'No data available for key "$key" in the requested time range.';
    }

    final buffer = StringBuffer();
    buffer.writeln(
        'Trend data for "$key" (${buckets.length} buckets, interval: $bucketInterval):');
    buffer.writeln();
    for (final b in buckets) {
      buffer.writeln(b.toText());
    }
    return buffer.toString().trimRight();
  }
}

/// Service for querying time-bucketed trend data from dynamically-created
/// PostgreSQL/TimescaleDB tables.
///
/// Timeseries data lives in tables named after the logical key (e.g., a table
/// named `"pump3.speed"` with columns `time TIMESTAMPTZ` and `value`). These
/// tables are NOT in the Drift schema -- they are created at runtime by the
/// collector. This service queries them using raw SQL via `customSelect()`.
///
/// The [isPostgres] flag controls which SQL dialect is used:
/// - `true` (default): Uses `information_schema.tables` and TimescaleDB
///   `time_bucket()` for aggregation.
/// - `false`: Uses `sqlite_master` for table existence checks and simple
///   `GROUP BY` for aggregation (for testing with in-memory SQLite).
class TrendService {
  /// Creates a [TrendService] backed by [db].
  ///
  /// Set [isPostgres] to `false` for SQLite-based testing.
  TrendService(this._db, {this.isPostgres = true});

  final McpDatabase _db;

  /// Whether to use PostgreSQL/TimescaleDB SQL dialect.
  final bool isPostgres;

  /// Cache of table existence checks to avoid repeated
  /// `information_schema.tables` queries for the same table name.
  /// Keyed by table name, value is whether the table exists.
  final Map<String, bool> _tableExistsCache = {};

  /// Maximum number of buckets returned per query to stay within LLM
  /// token budget (~100 buckets * ~80 chars = ~8000 chars = ~2000 tokens).
  static const int maxBuckets = 100;

  /// Calculate the bucket interval in milliseconds for a given time range.
  ///
  /// Ensures the result produces at most [maxBuckets] buckets.
  static int calculateBucketIntervalMs(DateTime from, DateTime to) {
    final rangeMs = to.difference(from).inMilliseconds;
    return (rangeMs / maxBuckets).ceil();
  }

  /// Check whether a table with [tableName] exists in the database.
  ///
  /// Results are cached per [tableName] within this service instance to avoid
  /// repeated `information_schema.tables` queries when multiple trend keys
  /// reference the same table (or are checked in quick succession).
  ///
  /// Uses `information_schema.tables` for PostgreSQL or `sqlite_master`
  /// for SQLite.
  Future<bool> tableExists(String tableName) async {
    // Return cached result if available
    final cached = _tableExistsCache[tableName];
    if (cached != null) return cached;

    final bool exists;
    if (isPostgres) {
      final result = await _db.customSelect(
        r'''
        SELECT EXISTS (
          SELECT 1 FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = $1
        ) AS "exists"
        ''',
        variables: [Variable.withString(tableName)],
      ).getSingle();
      exists = result.read<bool>('exists');
    } else {
      // SQLite: query sqlite_master
      final result = await _db.customSelect(
        "SELECT COUNT(*) AS cnt FROM sqlite_master "
        "WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(tableName)],
      ).getSingle();
      exists = result.read<int>('cnt') > 0;
    }

    _tableExistsCache[tableName] = exists;
    return exists;
  }

  /// Clear the table-existence cache.
  ///
  /// Useful in tests or if tables may be created at runtime after initial
  /// checks. Only clears the cache for the specified [tableName], or all
  /// entries if [tableName] is null.
  void clearTableExistsCache([String? tableName]) {
    if (tableName != null) {
      _tableExistsCache.remove(tableName);
    } else {
      _tableExistsCache.clear();
    }
  }

  /// Query time-bucketed trend data for a collected [key].
  ///
  /// Returns aggregated min/avg/max values in at most [maxBuckets] time
  /// windows. If the table does not exist, returns a [TrendResult] with
  /// an error message (not an exception).
  ///
  /// The [from] and [to] parameters define the mandatory time range.
  Future<TrendResult> queryTrend({
    required String key,
    required DateTime from,
    required DateTime to,
  }) async {
    // Check table existence first
    final exists = await tableExists(key);
    if (!exists) {
      return TrendResult(
        key: key,
        buckets: [],
        bucketInterval: '',
        error: 'No trend data table found for key "$key". '
            'This key may not have collection enabled.',
      );
    }

    // Calculate bucket interval
    final bucketMs = calculateBucketIntervalMs(from, to);
    final bucketInterval = '$bucketMs milliseconds';

    // Quote table name for SQL (keys contain dots)
    final quotedTable = key.replaceAll('"', '""');

    try {
      final List<QueryRow> rows;
      if (isPostgres) {
        rows = await _db.customSelect(
          r'''
          SELECT
            time_bucket($1::interval, time) AS bucket,
            min(value) AS min_val,
            avg(value) AS avg_val,
            max(value) AS max_val,
            count(*) AS sample_count
          FROM "'''
              '$quotedTable'
              r'''"
          WHERE time >= $2::timestamptz AND time <= $3::timestamptz
          GROUP BY bucket
          ORDER BY bucket
          ''',
          variables: [
            Variable.withString(bucketInterval),
            Variable.withString(from.toUtc().toIso8601String()),
            Variable.withString(to.toUtc().toIso8601String()),
          ],
        ).get();
      } else {
        // SQLite fallback: simple query without time_bucket
        // Returns raw rows; for SQLite testing we just read all matching rows
        // and bucket them in Dart.
        rows = await _db.customSelect(
          'SELECT time, value FROM "$quotedTable" '
          'WHERE time >= ? AND time <= ? '
          'ORDER BY time',
          variables: [
            Variable.withString(from.toUtc().toIso8601String()),
            Variable.withString(to.toUtc().toIso8601String()),
          ],
        ).get();

        if (rows.isEmpty) {
          return TrendResult(
            key: key,
            buckets: [],
            bucketInterval: bucketInterval,
          );
        }

        // Bucket the rows in Dart for SQLite
        return _bucketInDart(
          key: key,
          rows: rows,
          from: from,
          bucketMs: bucketMs,
          bucketInterval: bucketInterval,
        );
      }

      if (rows.isEmpty) {
        return TrendResult(
          key: key,
          buckets: [],
          bucketInterval: bucketInterval,
        );
      }

      // Map PostgreSQL result rows to TrendBucket objects
      final buckets = rows.map((row) {
        return TrendBucket(
          bucket: DateTime.parse(row.read<String>('bucket')),
          minVal: (row.read<double>('min_val')),
          avgVal: (row.read<double>('avg_val')),
          maxVal: (row.read<double>('max_val')),
          sampleCount: row.read<int>('sample_count'),
        );
      }).toList();

      return TrendResult(
        key: key,
        buckets: buckets,
        bucketInterval: bucketInterval,
      );
    } on Exception catch (e) {
      return TrendResult(
        key: key,
        buckets: [],
        bucketInterval: bucketInterval,
        error: 'Error querying trend data for "$key": $e',
      );
    }
  }

  /// Bucket raw SQLite rows in Dart (no time_bucket function available).
  TrendResult _bucketInDart({
    required String key,
    required List<QueryRow> rows,
    required DateTime from,
    required int bucketMs,
    required String bucketInterval,
  }) {
    final bucketMap = <int, List<double>>{};

    for (final row in rows) {
      final time = DateTime.parse(row.read<String>('time'));
      final value = row.read<double>('value');
      final bucketIndex = time.difference(from).inMilliseconds ~/ bucketMs;
      bucketMap.putIfAbsent(bucketIndex, () => []).add(value);
    }

    final sortedKeys = bucketMap.keys.toList()..sort();
    final buckets = sortedKeys.map((idx) {
      final values = bucketMap[idx]!;
      final minVal = values.reduce((a, b) => a < b ? a : b);
      final maxVal = values.reduce((a, b) => a > b ? a : b);
      final avgVal = values.reduce((a, b) => a + b) / values.length;
      final bucketTime = from.add(Duration(milliseconds: idx * bucketMs));
      return TrendBucket(
        bucket: bucketTime,
        minVal: minVal,
        avgVal: avgVal,
        maxVal: maxVal,
        sampleCount: values.length,
      );
    }).toList();

    return TrendResult(
      key: key,
      buckets: buckets,
      bucketInterval: bucketInterval,
    );
  }
}

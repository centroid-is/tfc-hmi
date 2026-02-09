import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:postgres/postgres.dart' as pg;
import 'package:postgres/postgres.dart' show Endpoint, SslMode;
import 'package:json_annotation/json_annotation.dart' as json;
export 'package:postgres/postgres.dart' show Sql;
import 'package:logger/logger.dart';

import 'secure_storage/secure_storage.dart';
import 'database_drift.dart';
import '../converter/duration_converter.dart';

part 'database.g.dart';

// todo skoða
// https://github.com/osaxma/postgresql-dart-replication-example/blob/main/example/listen_v3.dart

extension IntervalToDuration on pg.Interval {
  Duration toDuration() {
    // TODO: THIS IS BAD
    // Convert months to approximate days (30 days per month)
    final monthDays = months * 30;
    final totalDays = days + monthDays;

    return Duration(
      days: totalDays,
      microseconds: microseconds,
    );
  }
}

class EndpointConverter
    implements json.JsonConverter<pg.Endpoint, Map<String, dynamic>> {
  const EndpointConverter();

  @override
  pg.Endpoint fromJson(Map<String, dynamic> json) {
    return pg.Endpoint(
      host: json['host'] as String,
      port: json['port'] as int,
      database: json['database'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
      isUnixSocket: json['isUnixSocket'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson(pg.Endpoint endpoint) => {
        'host': endpoint.host,
        'port': endpoint.port,
        'database': endpoint.database,
        'username': endpoint.username,
        'password': endpoint.password,
        'isUnixSocket': endpoint.isUnixSocket,
      };
}

class SslModeConverter implements json.JsonConverter<pg.SslMode, String> {
  const SslModeConverter();

  @override
  pg.SslMode fromJson(String json) {
    return pg.SslMode.values.firstWhere(
      (mode) => mode.name == json,
      orElse: () => pg.SslMode.disable,
    );
  }

  @override
  String toJson(pg.SslMode mode) => mode.name;
}

@json.JsonSerializable()
class DatabaseConfig {
  @EndpointConverter()
  pg.Endpoint? postgres;
  @SslModeConverter()
  pg.SslMode? sslMode;
  bool debug = false;

  DatabaseConfig({this.postgres, this.sslMode, this.debug = false});

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) =>
      _$DatabaseConfigFromJson(json);

  Map<String, dynamic> toJson() => _$DatabaseConfigToJson(this);

  static const _configLocation = 'database_config';

  static Future<DatabaseConfig> fromEnv() async {
    if (Platform.environment['CENTROID_PGHOST'] == null) {
      throw Exception("Please provide environment variable CENTROID_PGHOST");
    }
    final host = Platform.environment['CENTROID_PGHOST']!;
    final port =
        int.tryParse(Platform.environment['CENTROID_PGPORT'] ?? '') ?? 5432;
    final database = Platform.environment['CENTROID_PGDATABASE'] ?? 'hmi';
    final username = Platform.environment['CENTROID_PGUSER'];
    final password = Platform.environment['CENTROID_PGPASSWORD'];
    final sslModeStr = Platform.environment['CENTROID_PGSSLMODE'];
    final debug = Platform.environment['CENTROID_DB_DEBUG'] == 'true';

    final sslMode = sslModeStr != null
        ? pg.SslMode.values.firstWhere(
            (mode) => mode.name == sslModeStr,
            orElse: () => pg.SslMode.disable,
          )
        : pg.SslMode.disable;

    return DatabaseConfig(
      postgres: pg.Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
      sslMode: sslMode,
      debug: debug,
    );
  }

  static Future<DatabaseConfig> fromPrefs() async {
    final prefs = SecureStorage.getInstance();
    var configJson = await prefs.read(key: _configLocation);
    DatabaseConfig config;
    if (configJson == null) {
      // If not found, create default config
      config = DatabaseConfig(
          postgres: null); // Or provide a default Endpoint if needed
      configJson = jsonEncode(config.toJson());
      await prefs.write(key: _configLocation, value: configJson);
    } else {
      config = DatabaseConfig.fromJson(jsonDecode(configJson));
    }
    return config;
  }

  Future<void> toPrefs() async {
    final prefs = SecureStorage.getInstance();
    final configJson = jsonEncode(toJson());
    await prefs.write(key: _configLocation, value: configJson);
  }

  @override
  String toString() {
    return "DatabaseConfig(${jsonEncode(toJson())})";
  }
}

class DatabaseException implements Exception {
  DatabaseException(this.message);

  final String message;
}

// https://docs.tigerdata.com/api/latest/data-retention/add_retention_policy/
@json.JsonSerializable(explicitToJson: true)
class RetentionPolicy {
  @DurationMinutesConverter()
  @json.JsonKey(name: 'drop_after_min')
  final Duration
      dropAfter; // Chunks fully older than this interval when the policy is run are dropped
  @DurationMinutesConverter()
  @json.JsonKey(name: 'schedule_interval_min')
  final Duration?
      scheduleInterval; // The interval between the finish time of the last execution and the next start. Defaults to NULL.

  const RetentionPolicy({required this.dropAfter, this.scheduleInterval});

  factory RetentionPolicy.fromJson(Map<String, dynamic> json) =>
      _$RetentionPolicyFromJson(json);

  Map<String, dynamic> toJson() => _$RetentionPolicyToJson(this);

  @override
  bool operator ==(Object other) {
    if (other is RetentionPolicy) {
      return dropAfter == other.dropAfter &&
          scheduleInterval == other.scheduleInterval;
    }
    return false;
  }

  @override
  int get hashCode => dropAfter.hashCode ^ scheduleInterval.hashCode;

  @override
  String toString() =>
      'RetentionPolicy(dropAfter: $dropAfter, scheduleInterval: $scheduleInterval)';
}

class _PendingWrite {
  final DateTime time;
  final dynamic value;

  _PendingWrite(this.time, this.value);

  Map<String, dynamic> toMap() {
    if (value is Map<String, dynamic>) {
      return {"time": time.toIso8601String(), ...value};
    } else {
      return {'time': time.toIso8601String(), 'value': value};
    }
  }
}

class Database {
  Database(this.db) {
    _startBatchFlushTimer();
    _initConnectionHealth();
  }

  /// Lightweight check if the database is reachable.
  /// Opens and immediately closes a single connection. Throws on failure.
  static Future<void> probe(DatabaseConfig config) async {
    final conn = await pg.Connection.open(
      config.postgres!,
      settings: pg.ConnectionSettings(
        sslMode: config.sslMode ?? pg.SslMode.disable,
      ),
    ).timeout(const Duration(seconds: 5));
    await conn.close();
  }

  /// Probe the database, create an [AppDatabase], and open the connection.
  /// Retries every [retryDelay] until the database is reachable.
  /// Set [useIsolate] to false when already running inside an isolate.
  static Future<Database> connectWithRetry(
    DatabaseConfig config, {
    Duration retryDelay = const Duration(seconds: 2),
    bool useIsolate = true,
  }) async {
    while (true) {
      try {
        await probe(config);
        final appDb = useIsolate
            ? await AppDatabase.spawn(config)
            : await AppDatabase.create(config);
        final db = Database(appDb);
        await db.db.open();
        logger.i('Database connected');
        return db;
      } catch (e) {
        logger.w('Database not reachable, retrying in ${retryDelay.inSeconds}s: $e');
        await Future.delayed(retryDelay);
      }
    }
  }

  AppDatabase db;
  Map<String, RetentionPolicy> retentionPolicies = {};
  static final Logger logger = Logger();
  final Map<String, Completer<void>> _tableCreationLocks = {};
  bool _lastConnectionState = false;
  final _connectionStateController = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _healthSub;

  void _initConnectionHealth() {
    _healthSub = db.connectionHealth?.listen((state) {
      _lastConnectionState = state;
      _connectionStateController.add(state);
    });
  }

  /// Multi-subscription stream of connection health.
  /// Each new listener immediately receives the last known state,
  /// then gets live updates. Safe for multiple StreamBuilders.
  late final Stream<bool> connectionState = Stream.multi((controller) {
    controller.add(_lastConnectionState);
    final sub = _connectionStateController.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });

  /// Retry a database operation with exponential backoff
  Future<T> _withRetry<T>(Future<T> Function() operation,
      {int maxRetries = 5,
      Duration initialDelay = const Duration(seconds: 1)}) async {
    var delay = initialDelay;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt == maxRetries - 1) rethrow;
        logger.w(
            'Database operation failed (attempt ${attempt + 1}/$maxRetries): $e');
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
    throw StateError('Unreachable');
  }

  // Batch write buffering
  final Map<String, List<_PendingWrite>> _writeBuffer = {};
  Timer? _flushTimer;
  bool _flushInProgress = false;
  static const _batchFlushInterval = Duration(milliseconds: 500);
  static const _maxBatchSize = 50;

  // Retry queue for failed writes (survives extended DB outages)
  final Map<String, List<_PendingWrite>> _retryQueue = {};
  bool _retryInProgress = false;
  static const _maxRetryQueueSize = 100; // per table

  Future<void> open() async {
    try {
      await db.open();
    } catch (e) {
      throw DatabaseException('Failed to open database: $e');
    }
  }

  Future<void> registerRetentionPolicy(
      String tableName, RetentionPolicy retention) async {
    retentionPolicies[tableName] = retention;
    // We will actually create the table when the first data point is inserted,
    // because we need to know the type of the value column beforehand
    try {
      if (await db.tableExists(tableName)) {
        final currentRetention = await db.getRetentionPolicy(tableName);
        if (currentRetention != retention) {
          await db.updateRetentionPolicy(tableName, retention);
        }
      }
    } catch (e) {
      logger.w('Could not check/update retention policy for $tableName (DB may be down): $e');
      // Will be applied when table is created during first insert
    }
  }

  // Track tables that need creation (when DB was down during first insert)
  final Set<String> _pendingTableCreation = {};

  /// Insert a time-series data point (buffered for batch writes)
  Future<void> insertTimeseriesData(
      String tableName, DateTime time, dynamic value) async {
    if (tableName.isEmpty) {
      throw ArgumentError('Table name cannot be empty');
    }

    // Try to ensure table exists, but don't fail if DB is unavailable
    if (!_writeBuffer.containsKey(tableName) && !_pendingTableCreation.contains(tableName)) {
      try {
        if (!await db.tableExists(tableName)) {
          await _tryToCreateTimeseriesTable(tableName, value);
        }
      } catch (e) {
        logger.w('Could not verify table $tableName exists (DB may be down), will retry: $e');
        _pendingTableCreation.add(tableName);
      }
    }

    // Always add to buffer, even if DB is down
    final buffer = _writeBuffer.putIfAbsent(tableName, () => []);
    buffer.add(_PendingWrite(time, value));

    // Enforce max queue size across writeBuffer + retryQueue (drop oldest)
    final retryQueue = _retryQueue[tableName] ?? [];
    final totalPending = buffer.length + retryQueue.length;
    if (totalPending > _maxRetryQueueSize) {
      // Drop from retryQueue first (oldest), then from buffer
      if (retryQueue.isNotEmpty) {
        final dropped = retryQueue.removeAt(0);
        logger.w('Queue overflow for $tableName, dropping oldest from ${dropped.time}');
      } else if (buffer.length > 1) {
        final dropped = buffer.removeAt(0);
        logger.w('Queue overflow for $tableName, dropping oldest from ${dropped.time}');
      }
    }

    // Flush immediately if batch size reached
    if (_writeBuffer[tableName]!.length >= _maxBatchSize) {
      final writes = _writeBuffer[tableName]!;
      _writeBuffer[tableName] = [];

      _writeCount++;
      _totalWriteTime.start();

      try {
        await _ensureTableAndInsert(tableName, writes);
      } catch (e) {
        _totalWriteTime.stop();
        logger.w('Batch flush failed for $tableName, queuing ${writes.length} items for retry: $e');
        _queueForRetry(tableName, writes);
        return;
      }

      _totalWriteTime.stop();
    }
  }

  /// Ensure table exists and insert rows
  Future<void> _ensureTableAndInsert(String tableName, List<_PendingWrite> writes) async {
    // Create table if it was pending
    if (_pendingTableCreation.contains(tableName)) {
      if (!await db.tableExists(tableName)) {
        await _tryToCreateTimeseriesTable(tableName, writes.first.value);
      }
      _pendingTableCreation.remove(tableName);
    }
    final rows = writes.map((w) => w.toMap()).toList();
    await _withRetry(() => db.tableInsertBatch(tableName, rows));
  }

  /// Get performance statistics
  Map<String, dynamic> getStats() {
    final uptime = _totalWriteTime.elapsed.inMilliseconds > 0
        ? _totalWriteTime.elapsed.inSeconds
        : 1;
    return {
      'total_writes': _writeCount,
      'writes_per_sec': _writeCount / uptime,
      'total_waits': _waitCount,
      'avg_wait_ms':
          _waitCount > 0 ? _totalWaitTime.elapsedMilliseconds / _waitCount : 0,
      'total_write_time_ms': _totalWriteTime.elapsedMilliseconds,
      'avg_write_ms': _writeCount > 0
          ? _totalWriteTime.elapsedMilliseconds / _writeCount
          : 0,
    };
  }

  /// Reset performance statistics
  void resetStats() {
    _writeCount = 0;
    _waitCount = 0;
    _totalWaitTime.reset();
    _totalWriteTime.reset();
  }

  /// Start the periodic batch flush timer
  void _startBatchFlushTimer() {
    _flushTimer = Timer.periodic(_batchFlushInterval, (_) async {
      await _flushAllBatches();
    });
  }

  /// Flush all pending writes to the database
  Future<void> _flushAllBatches() async {
    if (_writeBuffer.isEmpty) return;

    if (_flushInProgress) {
      final pendingCount = _writeBuffer.values.fold<int>(0, (sum, list) => sum + list.length);
      logger.w('Flush already in progress, $pendingCount items waiting - not keeping up with data rate');
      return;
    }

    _flushInProgress = true;

    // Snapshot the current buffer and clear it
    final batchesToFlush = Map<String, List<_PendingWrite>>.from(_writeBuffer);
    _writeBuffer.clear();

    // Flush each table's batch
    try {
      for (final entry in batchesToFlush.entries) {
        final tableName = entry.key;
        final writes = entry.value;
        if (writes.isEmpty) continue;

        try {
          _writeCount++;
          _totalWriteTime.start();

          await _ensureTableAndInsert(tableName, writes);

          _totalWriteTime.stop();
        } catch (e) {
          _totalWriteTime.stop();
          logger.w('Batch flush failed for $tableName, queuing ${writes.length} items for retry: $e');
          _queueForRetry(tableName, writes);
        }
      }
    } finally {
      _flushInProgress = false;
    }
  }

  /// Flush all pending writes immediately (useful for tests)
  Future<void> flush() => _flushAllBatches();

  /// Queue failed writes for later retry (drops oldest if queue full)
  void _queueForRetry(String tableName, List<_PendingWrite> writes) {
    final queue = _retryQueue.putIfAbsent(tableName, () => []);
    for (final write in writes) {
      if (queue.length >= _maxRetryQueueSize) {
        final dropped = queue.removeAt(0);
        logger.w('Retry queue full for $tableName, dropping oldest from ${dropped.time}');
      }
      queue.add(write);
    }
    _scheduleRetryFlush();
  }

  /// Schedule periodic retry of queued writes
  void _scheduleRetryFlush() {
    if (_retryInProgress || _retryQueue.isEmpty) return;
    _retryInProgress = true;

    Future.delayed(const Duration(seconds: 5), () async {
      // Snapshot and clear
      final batch = Map<String, List<_PendingWrite>>.from(_retryQueue);
      _retryQueue.clear();

      for (final entry in batch.entries) {
        final tableName = entry.key;
        final writes = entry.value;
        if (writes.isEmpty) continue;

        try {
          await _ensureTableAndInsert(tableName, writes);
          logger.i('Retry flush succeeded for $tableName: ${writes.length} items');
        } catch (e) {
          // Still failing — re-queue (drops oldest if full)
          logger.w('Retry flush failed for $tableName, re-queuing ${writes.length} items');
          final queue = _retryQueue.putIfAbsent(tableName, () => []);
          for (final write in writes) {
            if (queue.length >= _maxRetryQueueSize) {
              queue.removeAt(0);
            }
            queue.add(write);
          }
        }
      }

      _retryInProgress = false;

      // Schedule another flush if items remain
      if (_retryQueue.isNotEmpty) {
        final total = _retryQueue.values.fold<int>(0, (sum, list) => sum + list.length);
        logger.w('Retry queue: $total items still pending');
        _scheduleRetryFlush();
      }
    });
  }

  /// Dispose resources - flushes pending data before shutdown
  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _healthSub?.cancel();
    await _connectionStateController.close();
    // Attempt to flush any remaining data
    try {
      await _flushAllBatches();
    } catch (e) {
      logger.w('Failed to flush remaining data on dispose: $e');
    }
  }

  // Performance instrumentation
  int _writeCount = 0;
  int _waitCount = 0;
  final Stopwatch _totalWaitTime = Stopwatch();
  final Stopwatch _totalWriteTime = Stopwatch();
  Future<Map<String, List<TimeseriesData<dynamic>>>>
      queryTimeseriesDataMultiple(List<String> tableNames, DateTime to,
          {String? orderBy = 'time ASC', DateTime? from}) async {
    Map<String, List<String>> tapleMap = {};
    for (final tableName in tableNames) {
      tapleMap[tableName] = ['value', 'time'];
    }
    final where = from != null
        ? r'time >= $1::timestamptz AND time <= $2::timestamptz'
        : r'time >= $1::timestamptz';
    final whereArgs = from != null
        ? [from.toUtc().toIso8601String(), to.toUtc().toIso8601String()]
        : [to.toUtc().toIso8601String()];
    final rows = await db.tableQueryMultiple(tapleMap,
        where: where, whereArgs: whereArgs, orderBy: orderBy);
    final map = Map<String, List<TimeseriesData<dynamic>>>();
    for (final row in rows) {
      final time = row.data['time'];
      if (time == null) continue;
      final d = row.data;
      final nonNullTuples =
          d.entries.where((e) => e.value != null && e.key != 'time').toList();
      for (final tuple in nonNullTuples) {
        if (!map.containsKey(tuple.key)) {
          map[tuple.key] = [];
        }
        map[tuple.key]!.add(TimeseriesData(tuple.value, time));
      }
    }
    return map;
  }

  /// Query time-series data with performance analysis
  Future<List<TimeseriesData<dynamic>>> queryTimeseriesData(
      String tableName, DateTime to,
      {String? orderBy = 'time ASC', DateTime? from}) async {
    // final totalStart = DateTime.now();
    // print('🔍 queryTimeseriesData: Starting query for table $tableName');
    // print('📅 queryTimeseriesData: Querying since $since');

    // // Analyze table performance first
    // await db.analyzeTablePerformance(tableName);

    late final List<QueryRow> result;

    // final queryStart = DateTime.now();
    if (from != null) {
      final startTime = from.isBefore(to) ? from : to;
      final endTime = from.isBefore(to) ? to : from;
      // If from is provided, we need to query from that time
      // We need to query from the time of the first data point in the table
      // Use ISO8601 strings for PostgreSQL timestamptz compatibility
      result = await db.tableQuery(tableName,
          where: r'time >= $1::timestamptz AND time <= $2::timestamptz',
          whereArgs: [startTime.toUtc().toIso8601String(), endTime.toUtc().toIso8601String()],
          orderBy: orderBy);
    } else {
      // Use ISO8601 string for PostgreSQL timestamptz compatibility
      result = await db.tableQuery(tableName,
          where: r'time >= $1::timestamptz', whereArgs: [to.toUtc().toIso8601String()], orderBy: orderBy);
    }

    // final queryDuration = DateTime.now().difference(queryStart);
    // print(
    //     '⏱️  queryTimeseriesData: Database query took ${queryDuration.inMilliseconds}ms, returned ${result.length} rows');

    // final processStart = DateTime.now();
    if (result.isEmpty) {
      print('📊 queryTimeseriesData: No results found');
      return [];
    }

    if (result.first.data.containsKey('time')) {
      final processed = result.map((row) {
        // Read time as raw value - PostgreSQL returns DateTime directly
        final rawTime = row.data['time'];
        final DateTime time;
        if (rawTime is DateTime) {
          time = rawTime;
        } else if (rawTime is String) {
          time = DateTime.parse(rawTime);
        } else {
          throw DatabaseException('Unexpected time format: ${rawTime.runtimeType}');
        }
        if (row.data.length == 2 && row.data.containsKey('value')) {
          return TimeseriesData(row.data['value'], time);
        }
        row.data.remove('time');
        return TimeseriesData(row.data, time);
      }).toList();

      // final processDuration = DateTime.now().difference(processStart);
      // final totalDuration = DateTime.now().difference(totalStart);
      // print(
      //     '⏱️  queryTimeseriesData: Data processing took ${processDuration.inMilliseconds}ms');
      // print(
      //     '⏱️  queryTimeseriesData: Total operation took ${totalDuration.inMilliseconds}ms');
      return processed;
    }

    throw DatabaseException('Time column not found in table $tableName');
  }

  /// Query time-series data with server-side downsampling using TimescaleDB time_bucket().
  ///
  /// For each bucket, returns 3 points: min value, max value, and last value,
  /// preserving spikes and step changes while reducing density.
  ///
  /// The bucket interval is auto-calculated from the time range and [maxPoints]:
  ///   bucketInterval = (to - from) / (maxPoints / 3)
  ///
  /// Supports scalar numeric columns (DOUBLE PRECISION, INTEGER) and
  /// numeric array columns (DOUBLE PRECISION[]). For unsupported column types
  /// (boolean, text, jsonb), falls back to the raw query.
  Future<List<TimeseriesData<dynamic>>> queryTimeseriesDataDownsampled(
      String tableName, DateTime from, DateTime to,
      {int maxPoints = 1000}) async {
    final startTime = from.isBefore(to) ? from : to;
    final endTime = from.isBefore(to) ? to : from;
    final rangeMs = endTime.difference(startTime).inMilliseconds;

    // If the range is tiny, just return raw data
    if (rangeMs <= 0) {
      return queryTimeseriesData(tableName, endTime, from: startTime);
    }

    // Each bucket produces 3 points (min, max, last), so we need maxPoints/3 buckets
    final numBuckets = (maxPoints / 3).floor();
    if (numBuckets <= 0) {
      return queryTimeseriesData(tableName, endTime, from: startTime);
    }

    final bucketMs = (rangeMs / numBuckets).ceil();
    final intervalStr = '$bucketMs milliseconds';
    final quotedTable = tableName.replaceAll('"', '""');

    // Detect column type to choose the right SQL
    final typeResult = await db.customSelect(
      r'''
      SELECT data_type, udt_name
      FROM information_schema.columns
      WHERE table_name = $1 AND column_name = 'value'
      ''',
      variables: [Variable.withString(tableName)],
    ).get();

    if (typeResult.isEmpty) {
      return queryTimeseriesData(tableName, endTime, from: startTime);
    }

    final dataType = typeResult.first.data['data_type'] as String;
    final udtName = typeResult.first.data['udt_name'] as String;
    final isArray = dataType == 'ARRAY' || udtName.startsWith('_');

    // Only support numeric types
    const scalarNumericTypes = {'double precision', 'integer', 'bigint', 'real', 'smallint', 'numeric'};
    const arrayNumericUdts = {'_float8', '_float4', '_int4', '_int8', '_int2', '_numeric'};
    if (!scalarNumericTypes.contains(dataType) && !arrayNumericUdts.contains(udtName)) {
      return queryTimeseriesData(tableName, endTime, from: startTime);
    }

    final String sql;
    if (isArray) {
      // Unnest array elements, aggregate per-index, re-assemble arrays
      sql = r'''
        WITH elements AS (
          SELECT
            time,
            val,
            idx
          FROM "''' + quotedTable + r'''"
          CROSS JOIN LATERAL unnest(value) WITH ORDINALITY AS t(val, idx)
          WHERE time >= $2::timestamptz AND time <= $3::timestamptz
        ),
        agg AS (
          SELECT
            time_bucket($1::interval, time) AS bucket,
            idx,
            min(val)                                   AS min_val,
            max(val)                                   AS max_val,
            (array_agg(val ORDER BY time DESC))[1]     AS last_val
          FROM elements
          GROUP BY bucket, idx
        )
        SELECT bucket AS time, array_agg(min_val ORDER BY idx) AS value FROM agg GROUP BY bucket
        UNION ALL
        SELECT bucket + $1::interval * 0.5, array_agg(max_val ORDER BY idx) FROM agg GROUP BY bucket
        UNION ALL
        SELECT bucket + $1::interval, array_agg(last_val ORDER BY idx) FROM agg GROUP BY bucket
        ORDER BY 1
      ''';
    } else {
      sql = r'''
        WITH agg AS (
          SELECT
            time_bucket($1::interval, time) AS bucket,
            min(value)                                   AS min_val,
            max(value)                                   AS max_val,
            (array_agg(value ORDER BY time DESC))[1]     AS last_val
          FROM "''' + quotedTable + r'''"
          WHERE time >= $2::timestamptz AND time <= $3::timestamptz
          GROUP BY bucket
        )
        SELECT bucket              AS time, min_val  AS value FROM agg
        UNION ALL
        SELECT bucket + $1::interval * 0.5,  max_val  AS value FROM agg
        UNION ALL
        SELECT bucket + $1::interval,         last_val AS value FROM agg
        ORDER BY 1
      ''';
    }

    final result = await db.customSelect(sql, variables: [
      Variable.withString(intervalStr),
      Variable.withString(startTime.toUtc().toIso8601String()),
      Variable.withString(endTime.toUtc().toIso8601String()),
    ]).get();

    if (result.isEmpty) {
      return [];
    }

    return result.map((row) {
      final rawTime = row.data['time'];
      final DateTime time;
      if (rawTime is DateTime) {
        time = rawTime;
      } else if (rawTime is String) {
        time = DateTime.parse(rawTime);
      } else {
        throw DatabaseException(
            'Unexpected time format: ${rawTime.runtimeType}');
      }
      return TimeseriesData(row.data['value'], time);
    }).toList();
  }

  /// columns: {tableName: columnName}
  Future<void> createView(String viewName, Map<String, String> columns) async {
    if (columns.isEmpty) {
      throw DatabaseException('createView("$viewName"): columns map is empty');
    }

    // Quote identifiers safely
    String q(String ident) => '"${ident.replaceAll('"', '""')}"';

    final qView = q(viewName);
    final tables = columns.keys.toList();

    // Build alias map t0, t1, ...
    final aliasFor = <String, String>{};
    for (var i = 0; i < tables.length; i++) {
      aliasFor[tables[i]] = 't$i';
    }

    // CTE: all distinct timestamps across all tables
    final allTimes =
        tables.map((t) => 'SELECT time FROM ${q(t)}').join('\nUNION\n');

    // SELECT list: time + requested columns, aliased as table_col
    final selectCols = <String>['at.time AS "time"'];
    for (final t in tables) {
      final alias = aliasFor[t]!;
      final col = columns[t]!;
      final outAlias = '${t}_${col}';
      selectCols.add('$alias.${q(col)} AS ${q(outAlias)}');
    }

    // LEFT JOIN each table to the all_times spine
    final joins = tables.map((t) {
      final alias = aliasFor[t]!;
      return 'LEFT JOIN ${q(t)} $alias ON $alias.time = at.time';
    }).join('\n');

    final isPg = db.postgres; // PgDatabase vs. Native (sqlite)
    final createKeyword = isPg ? 'MATERIALIZED VIEW' : 'VIEW';
    final dropStmt = isPg
        ? 'DROP MATERIALIZED VIEW IF EXISTS $qView CASCADE;'
        : 'DROP VIEW IF EXISTS $qView CASCADE;';

    final createSql = '''
CREATE $createKeyword $qView AS
WITH all_times AS (
  $allTimes
)
SELECT
  ${selectCols.join(',\n  ')}
FROM all_times at
$joins
ORDER BY at.time;
''';

    // Execute (separate statements for compatibility)
    await db.customStatement(dropStmt);
    await db.customStatement(createSql);

    // Postgres-only: add a UNIQUE index on time to allow REFRESH CONCURRENTLY
    if (isPg) {
      final idxName = ('${viewName}_time_uidx'
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9_]+'), '_'))
          .replaceAll(RegExp(r'_+'), '_');
      await db.customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS $idxName ON $qView ("time");');
    }
  }

  /// Count time-series data points in regular time intervals
  /// Returns a map of counts for each interval, from oldest to newest {bucketStart: count, ...}
  /// [interval] is the duration of each bucket
  /// [howMany] is the number of buckets to count
  /// [since] is the end time for the buckets (defaults to now)
  Future<Map<DateTime, int>> countTimeseriesDataMultiple(
      String tableName, Duration interval, int howMany,
      {DateTime? since}) async {
    if (howMany <= 0) {
      return {};
    }

    final endTime = since ?? DateTime.now();
    final bucketStarts = <DateTime>[];
    final bucketEnds = <DateTime>[];

    // Generate time buckets from oldest to newest
    for (int i = howMany - 1; i >= 0; i--) {
      final bucketStart = endTime.subtract(interval * (i + 1));
      final bucketEnd = endTime.subtract(interval * i);
      bucketStarts.add(bucketStart);
      bucketEnds.add(bucketEnd);
    }

    // Build a UNION query for the specific number of intervals
    final unionQueries = <String>[];
    for (int i = 0; i < howMany; i++) {
      final startTime = bucketStarts[i].toIso8601String();
      final endTime = bucketEnds[i].toIso8601String();
      unionQueries.add('''
          SELECT COUNT(*) as count FROM "$tableName"
          WHERE time >= '$startTime' AND time < '$endTime'
        ''');
    }
    final sql = unionQueries.join(' UNION ALL ');

    final result = await db.customSelect(sql).get();

    // Extract counts from result rows
    final counts = <DateTime, int>{};
    for (int i = 0; i < result.length; i++) {
      counts[bucketStarts[i]] = result[i].read<int>('count');
    }
    return counts;
  }

  Future<void> _createTimeseriesTable(
      String tableName, RetentionPolicy retention, dynamic value) async {
    if (value is Map<String, dynamic>) {
      // Create table with columns for each key in the complex object
      await _createComplexTimeseriesTable(tableName, retention, value);
    } else {
      String valueType = _getPostgresType(value);
      await db
          .createTable(tableName, {'value': valueType, 'time': 'TIMESTAMPTZ'});
      await db.updateRetentionPolicy(tableName, retention);
    }
  }

  /// Create table for complex objects with separate columns for each key
  Future<void> _createComplexTimeseriesTable(String tableName,
      RetentionPolicy retention, Map<String, dynamic> value) async {
    Map<String, String> columns = {};

    for (final entry in value.entries) {
      final columnName = entry.key;
      final columnValue = entry.value;
      final columnType = _getPostgresType(columnValue);
      columns[columnName] = columnType;
    }

    await db.createTable(tableName, {'time': 'TIMESTAMPTZ', ...columns});
    await db.updateRetentionPolicy(tableName, retention);
  }

  /// Get PostgreSQL type for a value
  String _getPostgresType(dynamic value) {
    if (value is List) {
      // Infer array type from first element, default to TEXT[]
      if (value.isEmpty) {
        // todo this is error prone, I think we should just skip it, and create it by altering the table afterwards when there is a value
        return 'TEXT[]';
      }
      final first = value.first;
      switch (first) {
        case int():
          return 'INTEGER[]';
        case double():
          return 'DOUBLE PRECISION[]';
        case bool():
          return 'BOOLEAN[]';
        case String():
          return 'TEXT[]';
        case Duration():
          return 'INTERVAL[]';
        case DateTime():
          return 'TIMESTAMPTZ[]';
        default:
          return 'JSONB[]'; // fallback for complex/nested objects
      }
    }
    switch (value) {
      case int():
        return 'INTEGER';
      case double():
        return 'DOUBLE PRECISION';
      case bool():
        return 'BOOLEAN';
      case String():
        return 'TEXT';
      case null:
        return 'TEXT'; // Allow NULL values, TODO: I DONT LIKE THIS
      case Duration():
        return 'INTERVAL';
      case DateTime():
        return 'TIMESTAMPTZ';
      default:
        return 'JSONB'; // For complex nested objects
    }
  }

  /// Returns true if the table was created successfully, false if it already exists or policy is missing
  Future<bool> _tryToCreateTimeseriesTable(
      String tableName, dynamic value) async {
    // Check again after waiting - table might have been created
    // if (await db.tableExists(tableName)) {
    //   return true;
    // }

    if (!retentionPolicies.containsKey(tableName)) {
      stderr.writeln(
          'Table $tableName does not exist, and no retention policy is set');
      return false;
    }

    // Acquire lock for this table
    final completer = Completer<void>();
    logger.t("Lock Creating table $tableName");

    _tableCreationLocks[tableName] = completer;

    try {
      logger.t("Creating table $tableName");
      await _createTimeseriesTable(
          tableName, retentionPolicies[tableName]!, value);
    } finally {
      // Release lock
      _tableCreationLocks.remove(tableName);
      completer.complete();
    }
    return true;
  }

  Future<void> close() async {
    await db.close();
  }
}

class TimeseriesData<T> {
  final T value;
  final DateTime time;

  @override
  String toString() {
    return 'TimeseriesData(value: $value, time: $time)';
  }

  TimeseriesData(this.value, this.time);
}

/// Web stub for database.dart and database_drift.dart
/// On web, no local database is used — config comes from static files.

class RetentionPolicy {
  final Duration dropAfter;
  final Duration? scheduleInterval;

  const RetentionPolicy({required this.dropAfter, this.scheduleInterval});

  factory RetentionPolicy.fromJson(Map<String, dynamic> json) =>
      const RetentionPolicy(dropAfter: Duration(days: 365));

  Map<String, dynamic> toJson() => {
        'drop_after_minutes': dropAfter.inMinutes,
        if (scheduleInterval != null)
          'schedule_interval_minutes': scheduleInterval!.inMinutes,
      };
}

class DatabaseConfig {
  dynamic postgres;
  dynamic sslMode;
  bool debug;
  Duration connectTimeout;
  Duration queryTimeout;

  DatabaseConfig({
    this.postgres,
    this.sslMode,
    this.debug = false,
    this.connectTimeout = const Duration(seconds: 5),
    this.queryTimeout = const Duration(seconds: 30),
  });

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) =>
      DatabaseConfig();

  Map<String, dynamic> toJson() => {};

  static Future<DatabaseConfig> fromEnv() async =>
      throw UnsupportedError('Database not available on web');

  static Future<DatabaseConfig> fromPrefs() async => DatabaseConfig();

  Future<void> toPrefs() async {}

  @override
  String toString() => 'DatabaseConfig(web stub)';
}

class Database {
  final dynamic db;
  Database(this.db, {Duration healthTimeout = const Duration(seconds: 30)});

  static Future<void> probe(DatabaseConfig config) async =>
      throw UnsupportedError('Database.probe not available on web');

  static Future<Database> connectWithRetry(
    DatabaseConfig config, {
    Duration retryDelay = const Duration(seconds: 2),
    bool useIsolate = true,
  }) async =>
      throw UnsupportedError('Database.connectWithRetry not available on web');

  Future<List<TimeseriesData<dynamic>>> queryTimeseriesData(
    String tableName,
    DateTime to, {
    String? orderBy,
    DateTime? from,
  }) async =>
      [];

  Future<void> dispose() async {}

  Future<List<TimeseriesData<dynamic>>> queryTimeseriesDataDownsampled(
    String tableName,
    DateTime from,
    DateTime to, {
    int maxPoints = 1000,
  }) async =>
      [];

  Future<void> close() async {}
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

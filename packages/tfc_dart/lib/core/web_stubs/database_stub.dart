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
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  DatabaseConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  static Future<DatabaseConfig> fromEnv() async =>
      throw UnsupportedError('Database not available on web');

  static Future<DatabaseConfig?> fromPrefs(dynamic prefs) async => null;
}

class Database {
  final dynamic db;
  Database._() : db = null;

  static Future<Database?> connectWithRetry({
    required DatabaseConfig config,
    int maxRetries = 3,
  }) async =>
      null;

  Future<void> close() async {}
}

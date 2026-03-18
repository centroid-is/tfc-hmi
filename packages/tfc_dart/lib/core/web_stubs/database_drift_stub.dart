/// Web stub for database_drift.dart
/// On web, no drift database is used — types exist for compilation only.

import 'database_stub.dart' show Database, DatabaseConfig;

class AppDatabase {
  AppDatabase._();

  static Future<AppDatabase?> connect({
    required Database? database,
  }) async =>
      null;

  static Future<AppDatabase> spawn(DatabaseConfig config,
      {dynamic sqliteFolder}) async {
    throw UnsupportedError('AppDatabase.spawn not available on web');
  }

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

enum NotificationAction {
  insert,
  update,
  delete,
}

class NotificationData {
  final NotificationAction action;
  final Map<String, dynamic> data;

  NotificationData({required this.action, required this.data});

  factory NotificationData.fromJson(String json) =>
      NotificationData(action: NotificationAction.insert, data: {});
}

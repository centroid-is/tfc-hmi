/// Web stub for database_drift.dart
/// On web, no drift database is used.

import 'database_stub.dart';

enum NotificationAction { insert, update, delete }

class NotificationData {
  final String table;
  final NotificationAction action;
  final Map<String, dynamic>? data;

  NotificationData({required this.table, required this.action, this.data});

  factory NotificationData.fromJson(dynamic json) => NotificationData(
        table: '',
        action: NotificationAction.insert,
      );
}

class AppDatabase {
  AppDatabase._();

  static Future<AppDatabase> spawn(DatabaseConfig config) async =>
      throw UnsupportedError('AppDatabase not available on web');

  Future<void> close() async {}
  Future<void> open() async {}
}

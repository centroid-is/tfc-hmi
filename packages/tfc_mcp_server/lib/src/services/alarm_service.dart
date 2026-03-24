import 'package:drift/drift.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase;

import '../interfaces/alarm_reader.dart';
import 'sql_dialect.dart';

/// Service for querying alarm configuration and history.
///
/// Provides three levels of progressive discovery:
/// - Level 1: [listActiveAlarms] -- currently active alarms (overview)
/// - Level 2: [getAlarmDetail] -- full config for a specific alarm
/// - Level 3: [queryHistory] -- historical alarm records with filtering
///
/// Accepts [McpDatabase] (not ServerDatabase) so it works with both
/// AppDatabase (Flutter in-process) and ServerDatabase (standalone binary).
/// Shared tables (alarm_history) are queried via raw SQL since AppDatabase
/// and ServerDatabase define different row classes for the same physical tables.
///
/// SQL queries use [adaptSql] to translate `?` placeholders to `$N` when
/// running against PostgreSQL, since drift's `customSelect` passes raw SQL
/// verbatim to the database engine without placeholder translation.
class AlarmService {
  /// Creates an [AlarmService] with an [AlarmReader] for config data
  /// and a [McpDatabase] for history queries.
  AlarmService({
    required AlarmReader alarmReader,
    required McpDatabase db,
  })  : _alarmReader = alarmReader,
        _db = db,
        _isPostgres = isPostgresDb(db);

  final AlarmReader _alarmReader;
  final McpDatabase _db;

  /// Whether the database uses PostgreSQL dialect.
  final bool _isPostgres;

  /// Adapts SQL with `?` placeholders to `$N` for PostgreSQL.
  String _sql(String query) => adaptSql(query, isPostgres: _isPostgres);

  /// Returns currently active alarms from the history table.
  ///
  /// Active alarms are those where `active=true` AND `deactivatedAt IS NULL`.
  /// Results are ordered by `createdAt` descending (most recent first)
  /// and capped by [limit].
  ///
  /// Uses raw SQL via [customSelect] because alarm_history is a shared table
  /// with different row classes in AppDatabase vs ServerDatabase.
  Future<List<Map<String, dynamic>>> listActiveAlarms({int limit = 50}) async {
    final rows = await _db.customSelect(
      _sql('SELECT alarm_level, alarm_title, alarm_description, created_at '
          'FROM alarm_history '
          'WHERE active = ? AND deactivated_at IS NULL '
          'ORDER BY created_at DESC LIMIT ?'),
      variables: [Variable.withBool(true), Variable.withInt(limit)],
    ).get();

    return rows.map((row) {
      return {
        'alarmLevel': row.read<String>('alarm_level'),
        'alarmTitle': row.read<String>('alarm_title'),
        'alarmDescription': row.read<String>('alarm_description'),
        'createdAt': row.read<String>('created_at'),
      };
    }).toList();
  }

  /// Returns the alarm configuration for [uid], or null if not found.
  ///
  /// Looks up the config from [AlarmReader.alarmConfigs] (in-memory).
  Map<String, dynamic>? getAlarmDetail(String uid) {
    for (final config in _alarmReader.alarmConfigs) {
      if (config['uid'] == uid) {
        return config;
      }
    }
    return null;
  }

  /// Returns all alarm configurations from the in-memory reader.
  ///
  /// Used by [AlarmContextService] to build a UID-to-config map once,
  /// avoiding per-row [getAlarmDetail] calls in the sibling detection loop.
  List<Map<String, dynamic>> getAllAlarmConfigs() {
    return _alarmReader.alarmConfigs;
  }

  /// Queries alarm history with optional filters.
  ///
  /// - [after]: only records with `createdAt >= after`
  /// - [before]: only records with `createdAt <= before`
  /// - [alarmUid]: only records matching this alarm UID
  /// - [limit]: maximum number of records (default 100, max 500)
  ///
  /// Results are ordered by `createdAt` descending (most recent first).
  ///
  /// Uses raw SQL via [customSelect] because alarm_history is a shared table
  /// with different row classes in AppDatabase vs ServerDatabase.
  Future<List<Map<String, dynamic>>> queryHistory({
    DateTime? after,
    DateTime? before,
    String? alarmUid,
    int limit = 100,
  }) async {
    final conditions = <String>[];
    final variables = <Variable>[];

    if (after != null) {
      conditions.add('created_at >= ?');
      variables.add(Variable.withString(after.toIso8601String()));
    }
    if (before != null) {
      conditions.add('created_at <= ?');
      variables.add(Variable.withString(before.toIso8601String()));
    }
    if (alarmUid != null) {
      conditions.add('alarm_uid = ?');
      variables.add(Variable.withString(alarmUid));
    }

    final whereClause =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final sql = 'SELECT alarm_uid, alarm_level, alarm_title, '
        'alarm_description, active, expression, created_at, '
        'deactivated_at, acknowledged_at '
        'FROM alarm_history $whereClause '
        'ORDER BY created_at DESC LIMIT ?';

    final rows = await _db.customSelect(
      _sql(sql),
      variables: [...variables, Variable.withInt(limit.clamp(1, 500))],
    ).get();

    return rows.map((row) {
      final deactivatedAt = row.readNullable<String>('deactivated_at');
      final acknowledgedAt = row.readNullable<String>('acknowledged_at');
      final expression = row.readNullable<String>('expression');

      return {
        'alarmUid': row.read<String>('alarm_uid'),
        'alarmLevel': row.read<String>('alarm_level'),
        'alarmTitle': row.read<String>('alarm_title'),
        'alarmDescription': row.read<String>('alarm_description'),
        'active': row.read<bool>('active'),
        'createdAt': row.read<String>('created_at'),
        if (expression != null) 'expression': expression,
        if (deactivatedAt != null) 'deactivatedAt': deactivatedAt,
        if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt,
      };
    }).toList();
  }
}

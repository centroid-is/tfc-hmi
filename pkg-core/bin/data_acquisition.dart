import 'dart:io';
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:tfc_core/core/preferences.dart';

import 'package:tfc_core/core/state_man.dart';
import 'package:tfc_core/core/collector.dart';
import 'package:tfc_core/core/database.dart';
import 'package:tfc_core/core/database_drift.dart';

class _TraceFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true; // Allow all log levels including trace
  }
}

/// Main data acquisition class that manages OPC UA client and Postgres client.
class DataAcquisition {
  late final StateMan _stateMan;
  late final Database _db;
  late final Collector _collector;
  Timer? _statsTimer;
  final _logger = Logger(
    filter: _TraceFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
  );

  DataAcquisition({
    required StateManConfig config,
    required DatabaseConfig dbConfig,
    bool enableStatsLogging = true,
  }) {
    _logger.t("constructor");
    () async {
      _logger.t("create stateman");
      _db = Database(await AppDatabase.create(dbConfig));
      final prefs = await Preferences.create(db: _db);
      final keym = await KeyMappings.fromPrefs(prefs);
      _stateMan = await StateMan.create(
          config: config, keyMappings: keym, useIsolate: false);
      _logger.t("create database");
      _logger.t("create collector");
      // todo db reconnect logic
      _collector = Collector(
          config: CollectorConfig(collect: true),
          stateMan: _stateMan,
          database: _db);

      if (enableStatsLogging) {
        _startStatsLogging();
      }
    }();
  }

  void _startStatsLogging() {
    _statsTimer = Timer.periodic(Duration(seconds: 5), (_) {
      final collectorStats = _collector.getStats();
      final dbStats = _db.getStats();
      _logger.i('=== Performance Stats ===');
      _logger.i(
          'Collector: ${collectorStats['events_per_sec'].toStringAsFixed(1)} events/s, '
          '${collectorStats['inserts_per_sec'].toStringAsFixed(1)} inserts/s, '
          '${collectorStats['active_subscriptions']} subscriptions, '
          'JSON: ${collectorStats['avg_json_conversion_us']}us/call, '
          'Insert: ${collectorStats['avg_insert_ms']}ms/call');
      _logger.i(
          'Database: ${dbStats['writes_per_sec'].toStringAsFixed(1)} writes/s, '
          '${dbStats['total_waits']} waits, '
          'avg wait: ${dbStats['avg_wait_ms'].toStringAsFixed(2)}ms, '
          'avg write: ${dbStats['avg_write_ms'].toStringAsFixed(2)}ms');
    });
  }

  /// Get performance statistics
  Map<String, dynamic> getStats() {
    return {
      'collector': _collector.getStats(),
      'database': _db.getStats(),
    };
  }

  void dispose() {
    _statsTimer?.cancel();
  }
}

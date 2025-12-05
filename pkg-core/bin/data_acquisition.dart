import 'dart:io';
import 'package:logger/logger.dart';

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
    required KeyMappings mappings,
    required DatabaseConfig dbConfig,
  }) {
    _logger.t("constructor");
    () async {
      _logger.t("create stateman");
      _stateMan = await StateMan.create(
          config: config, keyMappings: mappings, useIsolate: false);
      _logger.t("create database");
      _db = Database(await AppDatabase.create(dbConfig));
      _logger.t("create collector");
      // todo db reconnect logic
      _collector = Collector(
          config: CollectorConfig(collect: true),
          stateMan: _stateMan,
          database: _db);
    }();
  }
}

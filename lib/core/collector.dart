import 'dart:async';

import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import 'dynamic_value_converter.dart';
import 'state_man.dart';
import 'database.dart';

part 'collector.g.dart';

class DurationMicrosecondsConverter implements JsonConverter<Duration?, int?> {
  const DurationMicrosecondsConverter();

  @override
  Duration? fromJson(int? json) {
    if (json == null) return null;
    return Duration(microseconds: json);
  }

  @override
  int? toJson(Duration? duration) {
    if (duration == null) return null;
    return duration.inMicroseconds;
  }
}

class DurationMinutesConverter implements JsonConverter<Duration?, int?> {
  const DurationMinutesConverter();

  @override
  Duration? fromJson(int? json) {
    if (json == null) return null;
    return Duration(minutes: json);
  }

  @override
  int? toJson(Duration? duration) {
    if (duration == null) return null;
    return duration.inMinutes;
  }
}

@JsonSerializable()
class CollectEntry {
  String key;
  String? name;
  @JsonKey(name: 'retention_min')
  @DurationMinutesConverter()
  Duration retention = const Duration(days: 365);
  @DurationMicrosecondsConverter()
  @JsonKey(name: 'sample_interval_us')
  Duration? sampleInterval; // microseconds

  CollectEntry({required this.key, this.name, this.sampleInterval}) {
    name ??= key;
  }
  @override
  Map<String, dynamic> toJson() => _$CollectEntryToJson(this);
  static CollectEntry fromJson(Map<String, dynamic> json) =>
      _$CollectEntryFromJson(json);
}

@JsonSerializable()
class CollectTable {
  String name;
  @JsonKey(name: 'retention_min')
  @DurationMinutesConverter()
  Duration retention = const Duration(days: 365);
  List<CollectEntry> entries;

  CollectTable({required this.name, required this.entries});
  Map<String, dynamic> toJson() => _$CollectTableToJson(this);
  static CollectTable fromJson(Map<String, dynamic> json) =>
      _$CollectTableFromJson(json);
}

@JsonSerializable()
class CollectorConfig {
  List<CollectTable> tables;

  CollectorConfig({required this.tables});

  Map<String, dynamic> toJson() => _$CollectorConfigToJson(this);
  static CollectorConfig fromJson(Map<String, dynamic> json) =>
      _$CollectorConfigFromJson(json);
}

class Collector {
  final CollectorConfig config;
  final StateMan stateMan;
  final Database database;
  final Map<String, StreamSubscription<DynamicValue>> subscriptions = {};
  final Logger logger = Logger();

  Collector({
    required this.config,
    required this.stateMan,
    required this.database,
  }) {
    final keyMappings = stateMan.keyMappings;
    for (var value in keyMappings.nodes.values) {
      if (value.collect != null) {
        collect(value.collect!);
      }
    }
  }

  /// Initiate a collection of data from a node.
  /// Returns when the collection is started.
  Future<void> collect(CollectEntry entry) async {
    // Ensure the table exists with the correct schema
    final table = CollectTable(name: entry.key, entries: [entry]);
    await _ensureTableExists(table);

    final subscription = await stateMan.subscribe(entry.key);
    subscriptions[entry.key] = subscription.listen(
      (value) async {
        // Insert into TimescaleDB
        await database.insertTimeseriesData(
          table.name,
          DateTime.now().toUtc(),
          const DynamicValueConverter().toJson(value, slim: true),
        );
      },
      onError: (error, stackTrace) {
        logger.e('Error collecting data for key ${entry.key}',
            error: error, stackTrace: stackTrace);
      },
      onDone: () {
        logger.i('Collection for key ${entry.key} done');
      },
    );
  }

  /// Ensure a table exists with the correct schema for all its entries
  Future<void> _ensureTableExists(CollectTable table) async {
    final tableExists = await database.tableExists(table.name);

    if (!tableExists) {
      await database.createTimeseriesTable(table.name, table.retention);
    }
  }

  /// Returns a Stream of the collected data.
  Stream<List<CollectedSample>> collectStream(String key,
      {Duration howLongBack = const Duration(days: 1)}) async* {
    // Find which table this key belongs to
    final table = config.tables.firstWhere(
      (t) => t.entries.any((e) => e.key == key),
      orElse: () => throw Exception('No table for key $key'),
    );

    final since = DateTime.now().toUtc().subtract(howLongBack);
    final result = await database.queryTimeseriesData(table.name, since);

    yield result.map((row) {
      final value = row[1]; // JSONB value
      return CollectedSample(value, row[0] as DateTime);
    }).toList();
  }

  /// Stop a collection.
  void stopCollect(String key) {
    subscriptions[key]?.cancel();
    subscriptions.remove(key);
  }
}

class CollectedSample {
  final dynamic value;
  final DateTime time;

  @override
  String toString() {
    return 'CollectedSample(value: $value, time: $time)';
  }

  CollectedSample(this.value, this.time);
}

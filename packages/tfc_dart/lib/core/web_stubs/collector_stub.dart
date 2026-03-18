/// Web stub for collector.dart
/// On web, collection is not performed — types exist for compilation only.

import 'database_stub.dart' show Database, RetentionPolicy, TimeseriesData;
import 'boolean_expression_stub.dart' show ExpressionConfig;

class CollectEntry {
  String key;
  String? name;
  RetentionPolicy retention;
  Duration? sampleInterval;
  ExpressionConfig? sampleExpression;

  CollectEntry({
    required this.key,
    this.name,
    this.sampleInterval,
    this.sampleExpression,
    this.retention = const RetentionPolicy(
        dropAfter: Duration(days: 365), scheduleInterval: null),
  }) {
    name ??= key;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        if (name != null) 'name': name,
        'retention': retention.toJson(),
        if (sampleInterval != null)
          'sample_interval_us': sampleInterval!.inMicroseconds,
        if (sampleExpression != null)
          'sample_expression': sampleExpression!.toJson(),
      };

  static CollectEntry fromJson(Map<String, dynamic> json) => CollectEntry(
        key: json['key'] as String,
        name: json['name'] as String?,
        sampleInterval: json['sample_interval_us'] != null
            ? Duration(microseconds: json['sample_interval_us'] as int)
            : null,
        retention: json['retention'] != null
            ? RetentionPolicy.fromJson(json['retention'] as Map<String, dynamic>)
            : const RetentionPolicy(dropAfter: Duration(days: 365)),
        sampleExpression: json['sample_expression'] != null
            ? ExpressionConfig.fromJson(
                json['sample_expression'] as Map<String, dynamic>)
            : null,
      );
}

class CollectorConfig {
  bool collect;
  CollectorConfig({this.collect = false});

  Map<String, dynamic> toJson() => {'collect': collect};
  static CollectorConfig fromJson(Map<String, dynamic> json) =>
      CollectorConfig(collect: json['collect'] as bool? ?? false);

  CollectorConfig copyWith({bool? collect}) =>
      CollectorConfig(collect: collect ?? this.collect);
}

class Collector {
  final CollectorConfig config;
  final dynamic stateMan;
  final Database database;

  static const configLocation = 'collector_config';

  Collector({
    required this.config,
    required this.stateMan,
    required this.database,
  });

  Stream<List<TimeseriesData<dynamic>>> collectStream(String key,
      {Duration since = const Duration(days: 1)}) {
    throw UnsupportedError('Collector not available on web');
  }

  Future<void> collectEntry(CollectEntry entry) async {}

  void stopCollect(CollectEntry entry) {}

  void close() {}

  Map<String, dynamic> getStats() => {};
  void resetStats() {}
}

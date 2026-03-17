/// Web stub for collector.dart
/// On web, collection is not performed.

import 'database_stub.dart' show RetentionPolicy;
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
}

class Collector {
  Collector._();
}

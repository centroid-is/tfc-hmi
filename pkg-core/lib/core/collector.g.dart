// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collector.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CollectEntry _$CollectEntryFromJson(Map<String, dynamic> json) => CollectEntry(
      key: json['key'] as String,
      name: json['name'] as String?,
      sampleInterval: const DurationMicrosecondsConverter()
          .fromJson((json['sample_interval_us'] as num?)?.toInt()),
      sampleExpression: json['sample_expression'] == null
          ? null
          : ExpressionConfig.fromJson(
              json['sample_expression'] as Map<String, dynamic>),
      retention: json['retention'] == null
          ? const RetentionPolicy(
              dropAfter: Duration(days: 365), scheduleInterval: null)
          : RetentionPolicy.fromJson(json['retention'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CollectEntryToJson(CollectEntry instance) =>
    <String, dynamic>{
      'key': instance.key,
      'name': instance.name,
      'retention': instance.retention.toJson(),
      'sample_interval_us':
          const DurationMicrosecondsConverter().toJson(instance.sampleInterval),
      'sample_expression': instance.sampleExpression?.toJson(),
    };

CollectorConfig _$CollectorConfigFromJson(Map<String, dynamic> json) =>
    CollectorConfig(
      collect: json['collect'] as bool? ?? false,
    );

Map<String, dynamic> _$CollectorConfigToJson(CollectorConfig instance) =>
    <String, dynamic>{
      'collect': instance.collect,
    };

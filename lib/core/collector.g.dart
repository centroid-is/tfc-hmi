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
      retention: json['retention_min'] == null
          ? const RetentionPolicy(
              dropAfter: Duration(days: 365), scheduleInterval: null)
          : RetentionPolicy.fromJson(
              json['retention_min'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CollectEntryToJson(CollectEntry instance) =>
    <String, dynamic>{
      'key': instance.key,
      'name': instance.name,
      'retention_min': instance.retention,
      'sample_interval_us':
          const DurationMicrosecondsConverter().toJson(instance.sampleInterval),
    };

CollectTable _$CollectTableFromJson(Map<String, dynamic> json) => CollectTable(
      name: json['name'] as String,
      entries: (json['entries'] as List<dynamic>)
          .map((e) => CollectEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      retention: json['retention_min'] == null
          ? const RetentionPolicy(
              dropAfter: Duration(days: 365), scheduleInterval: null)
          : RetentionPolicy.fromJson(
              json['retention_min'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CollectTableToJson(CollectTable instance) =>
    <String, dynamic>{
      'name': instance.name,
      'retention_min': instance.retention,
      'entries': instance.entries,
    };

CollectorConfig _$CollectorConfigFromJson(Map<String, dynamic> json) =>
    CollectorConfig(
      tables: (json['tables'] as List<dynamic>)
          .map((e) => CollectTable.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$CollectorConfigToJson(CollectorConfig instance) =>
    <String, dynamic>{
      'tables': instance.tables,
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collector.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CollectEntry _$CollectEntryFromJson(Map<String, dynamic> json) => CollectEntry(
      key: json['key'] as String,
      sampleInterval: const DurationMicrosecondsConverter()
          .fromJson((json['sample_interval_us'] as num?)?.toInt()),
    )..retention =
        Duration(microseconds: (json['retention_min'] as num).toInt());

Map<String, dynamic> _$CollectEntryToJson(CollectEntry instance) =>
    <String, dynamic>{
      'key': instance.key,
      'retention_min': instance.retention.inMicroseconds,
      'sample_interval_us':
          const DurationMicrosecondsConverter().toJson(instance.sampleInterval),
    };

CollectTable _$CollectTableFromJson(Map<String, dynamic> json) => CollectTable(
      name: json['name'] as String,
      entries: (json['entries'] as List<dynamic>)
          .map((e) => CollectEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    )..retention =
        Duration(microseconds: (json['retention_min'] as num).toInt());

Map<String, dynamic> _$CollectTableToJson(CollectTable instance) =>
    <String, dynamic>{
      'name': instance.name,
      'retention_min': instance.retention.inMicroseconds,
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

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DatabaseConfig _$DatabaseConfigFromJson(Map<String, dynamic> json) =>
    DatabaseConfig(
      postgres: _$JsonConverterFromJson<Map<String, dynamic>, Endpoint>(
          json['postgres'], const EndpointConverter().fromJson),
      sslMode: _$JsonConverterFromJson<String, SslMode>(
          json['sslMode'], const SslModeConverter().fromJson),
      debug: json['debug'] as bool? ?? false,
    );

Map<String, dynamic> _$DatabaseConfigToJson(DatabaseConfig instance) =>
    <String, dynamic>{
      'postgres': _$JsonConverterToJson<Map<String, dynamic>, Endpoint>(
          instance.postgres, const EndpointConverter().toJson),
      'sslMode': _$JsonConverterToJson<String, SslMode>(
          instance.sslMode, const SslModeConverter().toJson),
      'debug': instance.debug,
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);

RetentionPolicy _$RetentionPolicyFromJson(Map<String, dynamic> json) =>
    RetentionPolicy(
      dropAfter:
          Duration(microseconds: (json['drop_after_min'] as num).toInt()),
      scheduleInterval: const DurationMinutesConverter()
          .fromJson((json['schedule_interval_min'] as num?)?.toInt()),
    );

Map<String, dynamic> _$RetentionPolicyToJson(RetentionPolicy instance) =>
    <String, dynamic>{
      'drop_after_min': instance.dropAfter.inMicroseconds,
      'schedule_interval_min':
          const DurationMinutesConverter().toJson(instance.scheduleInterval),
    };

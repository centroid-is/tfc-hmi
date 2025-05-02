// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preferences.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PreferencesConfig _$PreferencesConfigFromJson(Map<String, dynamic> json) =>
    PreferencesConfig(
      postgres: _$JsonConverterFromJson<Map<String, dynamic>, Endpoint>(
          json['postgres'], const EndpointConverter().fromJson),
    );

Map<String, dynamic> _$PreferencesConfigToJson(PreferencesConfig instance) =>
    <String, dynamic>{
      'postgres': _$JsonConverterToJson<Map<String, dynamic>, Endpoint>(
          instance.postgres, const EndpointConverter().toJson),
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

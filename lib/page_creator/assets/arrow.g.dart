// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'arrow.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ArrowConfig _$ArrowConfigFromJson(Map<String, dynamic> json) => ArrowConfig(
      key: json['key'] as String,
      label: json['label'] as String,
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>);

Map<String, dynamic> _$ArrowConfigToJson(ArrowConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'key': instance.key,
      'label': instance.label,
    };

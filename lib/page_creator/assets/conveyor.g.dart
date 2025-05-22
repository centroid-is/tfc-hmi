// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conveyor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConveyorColorPaletteConfig _$ConveyorColorPaletteConfigFromJson(
        Map<String, dynamic> json) =>
    ConveyorColorPaletteConfig()
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>);

Map<String, dynamic> _$ConveyorColorPaletteConfigToJson(
        ConveyorColorPaletteConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
    };

ConveyorConfig _$ConveyorConfigFromJson(Map<String, dynamic> json) =>
    ConveyorConfig(
      key: json['key'] as String,
      batchesKey: json['batchesKey'] as String?,
      simulateBatches: json['simulateBatches'] as bool?,
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>);

Map<String, dynamic> _$ConveyorConfigToJson(ConveyorConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'key': instance.key,
      'batchesKey': instance.batchesKey,
      'simulateBatches': instance.simulateBatches,
    };

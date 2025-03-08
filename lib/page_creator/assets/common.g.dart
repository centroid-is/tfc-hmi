// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'common.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ColorConverter _$ColorConverterFromJson(Map<String, dynamic> json) =>
    ColorConverter();

Map<String, dynamic> _$ColorConverterToJson(ColorConverter instance) =>
    <String, dynamic>{};

SizeConverter _$SizeConverterFromJson(Map<String, dynamic> json) =>
    SizeConverter();

Map<String, dynamic> _$SizeConverterToJson(SizeConverter instance) =>
    <String, dynamic>{};

Coordinates _$CoordinatesFromJson(Map<String, dynamic> json) => Coordinates(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      angle: (json['angle'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$CoordinatesToJson(Coordinates instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'angle': instance.angle,
    };

Map<String, dynamic> _$BaseAssetToJson(BaseAsset instance) => <String, dynamic>{
      'assetName': instance.assetName,
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'common.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ColorConverter _$ColorConverterFromJson(Map<String, dynamic> json) =>
    ColorConverter();

Map<String, dynamic> _$ColorConverterToJson(ColorConverter instance) =>
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

RelativeSize _$RelativeSizeFromJson(Map<String, dynamic> json) => RelativeSize(
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );

Map<String, dynamic> _$RelativeSizeToJson(RelativeSize instance) =>
    <String, dynamic>{
      'width': instance.width,
      'height': instance.height,
    };

Map<String, dynamic> _$BaseAssetToJson(BaseAsset instance) => <String, dynamic>{
      'assetName': instance.assetName,
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

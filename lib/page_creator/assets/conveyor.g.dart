// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conveyor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConveyorColorPaletteConfig _$ConveyorColorPaletteConfigFromJson(
        Map<String, dynamic> json) =>
    ConveyorColorPaletteConfig()
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..preview = json['preview'] as bool?;

Map<String, dynamic> _$ConveyorColorPaletteConfigToJson(
        ConveyorColorPaletteConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'preview': instance.preview,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

ConveyorConfig _$ConveyorConfigFromJson(Map<String, dynamic> json) =>
    ConveyorConfig(
      key: json['key'] as String?,
      batchesKey: json['batchesKey'] as String?,
      frequencyKey: json['frequencyKey'] as String?,
      tripKey: json['tripKey'] as String?,
      simulateBatches: json['simulateBatches'] as bool?,
      bidirectional: json['bidirectional'] as bool?,
      reverseDirection: json['reverseDirection'] as bool?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$ConveyorConfigToJson(ConveyorConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'key': instance.key,
      'batchesKey': instance.batchesKey,
      'frequencyKey': instance.frequencyKey,
      'tripKey': instance.tripKey,
      'simulateBatches': instance.simulateBatches,
      'bidirectional': instance.bidirectional,
      'reverseDirection': instance.reverseDirection,
    };

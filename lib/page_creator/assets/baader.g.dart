// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baader.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Baader221Config _$Baader221ConfigFromJson(Map<String, dynamic> json) =>
    Baader221Config(
      color: const ColorConverter()
          .fromJson(json['color'] as Map<String, dynamic>),
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2.0,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$Baader221ConfigToJson(Baader221Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'color': const ColorConverter().toJson(instance.color),
      'stroke_width': instance.strokeWidth,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

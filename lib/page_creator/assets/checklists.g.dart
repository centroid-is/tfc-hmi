// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklists.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChecklistsConfig _$ChecklistsConfigFromJson(Map<String, dynamic> json) =>
    ChecklistsConfig(
      line1: (json['line1'] as List<dynamic>)
          .map((e) => LEDConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      line2: (json['line2'] as List<dynamic>)
          .map((e) => LEDConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      line3: (json['line3'] as List<dynamic>)
          .map((e) => LEDConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$ChecklistsConfigToJson(ChecklistsConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'line1': instance.line1,
      'line2': instance.line2,
      'line3': instance.line3,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

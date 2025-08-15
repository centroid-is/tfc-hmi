// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schneider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SchneiderATV320Config _$SchneiderATV320ConfigFromJson(
        Map<String, dynamic> json) =>
    SchneiderATV320Config(
      label: json['label'] as String?,
      hmisKey: json['hmisKey'] as String?,
      freqKey: json['freqKey'] as String?,
      configKey: json['configKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$SchneiderATV320ConfigToJson(
        SchneiderATV320Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'label': instance.label,
      'hmisKey': instance.hmisKey,
      'freqKey': instance.freqKey,
      'configKey': instance.configKey,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

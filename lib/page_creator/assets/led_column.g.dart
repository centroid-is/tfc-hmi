// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'led_column.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LEDColumnConfig _$LEDColumnConfigFromJson(Map<String, dynamic> json) =>
    LEDColumnConfig(
      leds: (json['leds'] as List<dynamic>)
          .map((e) => LEDConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..spacing = (json['spacing'] as num?)?.toDouble();

Map<String, dynamic> _$LEDColumnConfigToJson(LEDColumnConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'leds': instance.leds,
      'spacing': instance.spacing,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

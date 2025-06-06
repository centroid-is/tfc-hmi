// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'led.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LEDConfig _$LEDConfigFromJson(Map<String, dynamic> json) => LEDConfig(
      key: json['key'] as String,
      onColor: const ColorConverter()
          .fromJson(json['on_color'] as Map<String, dynamic>),
      offColor: const ColorConverter()
          .fromJson(json['off_color'] as Map<String, dynamic>),
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..ledType = $enumDecode(_$LEDTypeEnumMap, json['led_type']);

Map<String, dynamic> _$LEDConfigToJson(LEDConfig instance) => <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'key': instance.key,
      'on_color': const ColorConverter().toJson(instance.onColor),
      'off_color': const ColorConverter().toJson(instance.offColor),
      'led_type': _$LEDTypeEnumMap[instance.ledType]!,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

const _$LEDTypeEnumMap = {
  LEDType.circle: 'circle',
  LEDType.square: 'square',
};

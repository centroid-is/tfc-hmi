// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'led.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LEDConfig _$LEDConfigFromJson(Map<String, dynamic> json) => LEDConfig(
      key: json['key'] as String,
      onColor: const ColorConverter()
          .fromJson(json['on_color'] as Map<String, double>),
      offColor: const ColorConverter()
          .fromJson(json['off_color'] as Map<String, double>),
      textPos: $enumDecode(_$TextPosEnumMap, json['text_pos']),
      coordinates:
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>),
      size: const SizeConverter().fromJson(json['size'] as Map<String, double>),
    );

Map<String, dynamic> _$LEDConfigToJson(LEDConfig instance) => <String, dynamic>{
      'key': instance.key,
      'on_color': const ColorConverter().toJson(instance.onColor),
      'off_color': const ColorConverter().toJson(instance.offColor),
      'text_pos': _$TextPosEnumMap[instance.textPos]!,
      'coordinates': instance.coordinates,
      'size': const SizeConverter().toJson(instance.size),
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
};

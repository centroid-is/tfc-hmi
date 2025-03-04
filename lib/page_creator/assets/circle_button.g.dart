// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'circle_button.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CircleButtonConfig _$CircleButtonConfigFromJson(Map<String, dynamic> json) =>
    CircleButtonConfig(
      key: json['key'] as String,
      outwardColor: const ColorConverter()
          .fromJson(json['outward_color'] as Map<String, double>),
      inwardColor: const ColorConverter()
          .fromJson(json['inward_color'] as Map<String, double>),
      textPos: $enumDecode(_$TextPosEnumMap, json['text_pos']),
      coordinates:
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>),
      size: const SizeConverter().fromJson(json['size'] as Map<String, double>),
    );

Map<String, dynamic> _$CircleButtonConfigToJson(CircleButtonConfig instance) =>
    <String, dynamic>{
      'key': instance.key,
      'outward_color': const ColorConverter().toJson(instance.outwardColor),
      'inward_color': const ColorConverter().toJson(instance.inwardColor),
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

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'icon.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IconConfig _$IconConfigFromJson(Map<String, dynamic> json) => IconConfig(
      iconData: const IconDataConverter().fromJson(json['iconData'] as String),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..color = const OptionalColorConverter()
          .fromJson(json['color'] as Map<String, dynamic>?);

Map<String, dynamic> _$IconConfigToJson(IconConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'iconData': const IconDataConverter().toJson(instance.iconData),
      'color': const OptionalColorConverter().toJson(instance.color),
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

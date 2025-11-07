// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'aircab.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AirCabConfig _$AirCabConfigFromJson(Map<String, dynamic> json) => AirCabConfig(
      label: json['label'] as String,
      pressureKey: json['pressureKey'] as String,
      softStartKey: json['softStartKey'] as String,
      buttonKey: json['buttonKey'] as String,
      buttonFeedbackKey: json['buttonFeedbackKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$AirCabConfigToJson(AirCabConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'label': instance.label,
      'pressureKey': instance.pressureKey,
      'softStartKey': instance.softStartKey,
      'buttonKey': instance.buttonKey,
      'buttonFeedbackKey': instance.buttonFeedbackKey,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

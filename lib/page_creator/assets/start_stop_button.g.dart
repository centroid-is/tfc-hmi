// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_stop_button.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StartStopPillButtonConfig _$StartStopPillButtonConfigFromJson(
        Map<String, dynamic> json) =>
    StartStopPillButtonConfig(
      runKey: json['runKey'] as String,
      stopKey: json['stopKey'] as String,
      runningKey: json['runningKey'] as String,
      stoppedKey: json['stoppedKey'] as String,
      cleanKey: json['cleanKey'] as String?,
      cleaningKey: json['cleaningKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$StartStopPillButtonConfigToJson(
        StartStopPillButtonConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'runKey': instance.runKey,
      'stopKey': instance.stopKey,
      'cleanKey': instance.cleanKey,
      'runningKey': instance.runningKey,
      'stoppedKey': instance.stoppedKey,
      'cleaningKey': instance.cleaningKey,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

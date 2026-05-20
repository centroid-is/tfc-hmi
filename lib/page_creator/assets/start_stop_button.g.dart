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
      manualModeKey: json['manual_mode_key'] as String?,
      manualModePolarity: $enumDecodeNullable(
              _$ManualModePolarityEnumMap, json['manual_mode_polarity'],
              unknownValue: ManualModePolarity.manualWhenTrue) ??
          ManualModePolarity.manualWhenTrue,
      inactiveColor: StartStopPillButtonConfig._inactiveColorFromJson(
          json['inactive_color'] as Map<String, dynamic>?),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$StartStopPillButtonConfigToJson(
        StartStopPillButtonConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'runKey': instance.runKey,
      'stopKey': instance.stopKey,
      'cleanKey': instance.cleanKey,
      'runningKey': instance.runningKey,
      'stoppedKey': instance.stoppedKey,
      'cleaningKey': instance.cleaningKey,
      'manual_mode_key': instance.manualModeKey,
      'manual_mode_polarity':
          _$ManualModePolarityEnumMap[instance.manualModePolarity]!,
      'inactive_color': StartStopPillButtonConfig._inactiveColorToJson(
          instance.inactiveColor),
    };

const _$ManualModePolarityEnumMap = {
  ManualModePolarity.manualWhenTrue: 'manualWhenTrue',
  ManualModePolarity.manualWhenFalse: 'manualWhenFalse',
};

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

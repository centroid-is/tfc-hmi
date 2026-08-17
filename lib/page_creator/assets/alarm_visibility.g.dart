// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alarm_visibility.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AlarmVisibilityConfig _$AlarmVisibilityConfigFromJson(
        Map<String, dynamic> json) =>
    AlarmVisibilityConfig(
      alarmUids: (json['alarm_uids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      showWhenInactive: json['show_when_inactive'] as bool? ?? false,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$AlarmVisibilityConfigToJson(
        AlarmVisibilityConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'alarm_uids': instance.alarmUids,
      'show_when_inactive': instance.showWhenInactive,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

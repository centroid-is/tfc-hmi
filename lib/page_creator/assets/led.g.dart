// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'led.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LEDConfig _$LEDConfigFromJson(Map<String, dynamic> json) => LEDConfig(
      key: json['key'] as String,
      onColor: json['on_color'] == null
          ? AssetColor.green
          : const AssetColorConverter()
              .fromJson(json['on_color'] as Map<String, dynamic>),
      offColor: json['off_color'] == null
          ? AssetColor.grey
          : const AssetColorConverter()
              .fromJson(json['off_color'] as Map<String, dynamic>),
    )
      ..variant = json['asset_name'] as String
      ..id = json['id'] as String?
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?
      ..ledType = $enumDecode(_$LEDTypeEnumMap, json['led_type']);

Map<String, dynamic> _$LEDConfigToJson(LEDConfig instance) => <String, dynamic>{
      'asset_name': instance.variant,
      if (instance.id case final value?) 'id': value,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'key': instance.key,
      'on_color': const AssetColorConverter().toJson(instance.onColor),
      'off_color': const AssetColorConverter().toJson(instance.offColor),
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

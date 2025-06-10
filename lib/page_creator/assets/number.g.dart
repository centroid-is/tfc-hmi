// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'number.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NumberConfig _$NumberConfigFromJson(Map<String, dynamic> json) => NumberConfig(
      key: json['key'] as String,
      showDecimalPoint: json['showDecimalPoint'] as bool? ?? true,
      decimalPlaces: (json['decimalPlaces'] as num?)?.toInt() ?? 2,
      units: json['units'] as String?,
      textColor: json['textColor'] == null
          ? Colors.black
          : const ColorConverter()
              .fromJson(json['textColor'] as Map<String, dynamic>),
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$NumberConfigToJson(NumberConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'key': instance.key,
      'showDecimalPoint': instance.showDecimalPoint,
      'decimalPlaces': instance.decimalPlaces,
      'units': instance.units,
      'textColor': const ColorConverter().toJson(instance.textColor),
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

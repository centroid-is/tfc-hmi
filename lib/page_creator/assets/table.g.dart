// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'table.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TableAssetConfig _$TableAssetConfigFromJson(Map<String, dynamic> json) =>
    TableAssetConfig(
      entryKey: json['entryKey'] as String,
      entryCount: (json['entryCount'] as num?)?.toInt() ?? 10,
      headerText: json['headerText'] as String?,
      showTimestamps: json['showTimestamps'] as bool? ?? true,
      textColor: const OptionalColorConverter()
          .fromJson(json['text_color'] as Map<String, dynamic>?),
      backgroundColor: const OptionalColorConverter()
          .fromJson(json['background_color'] as Map<String, dynamic>?),
      borderColor: const OptionalColorConverter()
          .fromJson(json['border_color'] as Map<String, dynamic>?),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$TableAssetConfigToJson(TableAssetConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'entryKey': instance.entryKey,
      'entryCount': instance.entryCount,
      'headerText': instance.headerText,
      'showTimestamps': instance.showTimestamps,
      'text_color': const OptionalColorConverter().toJson(instance.textColor),
      'background_color':
          const OptionalColorConverter().toJson(instance.backgroundColor),
      'border_color':
          const OptionalColorConverter().toJson(instance.borderColor),
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

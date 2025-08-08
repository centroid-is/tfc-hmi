// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ratio_number.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RatioNumberConfig _$RatioNumberConfigFromJson(Map<String, dynamic> json) =>
    RatioNumberConfig(
      key1: json['key1'] as String,
      key2: json['key2'] as String,
      key1Label: json['key1_label'] as String? ?? '',
      key2Label: json['key2_label'] as String? ?? '',
      textColor: json['text_color'] == null
          ? Colors.black
          : const ColorConverter()
              .fromJson(json['text_color'] as Map<String, dynamic>),
      sinceMinutes: json['since_minutes'] == null
          ? const Duration(minutes: 10)
          : Duration(microseconds: (json['since_minutes'] as num).toInt()),
      howMany: (json['how_many'] as num?)?.toInt() ?? 10,
      pollInterval: json['poll_interval'] == null
          ? const Duration(seconds: 1)
          : Duration(microseconds: (json['poll_interval'] as num).toInt()),
      graphHeader: json['graph_header'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$RatioNumberConfigToJson(RatioNumberConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'key1': instance.key1,
      'key2': instance.key2,
      'key1_label': instance.key1Label,
      'key2_label': instance.key2Label,
      'text_color': const ColorConverter().toJson(instance.textColor),
      'since_minutes': instance.sinceMinutes.inMicroseconds,
      'how_many': instance.howMany,
      'poll_interval': instance.pollInterval.inMicroseconds,
      'graph_header': instance.graphHeader,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

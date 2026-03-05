// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bpm.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BpmConfig _$BpmConfigFromJson(Map<String, dynamic> json) => BpmConfig(
      key: json['key'] as String,
      textColor: json['text_color'] == null
          ? Colors.black
          : const ColorConverter()
              .fromJson(json['text_color'] as Map<String, dynamic>),
      pollInterval: json['poll_interval'] == null
          ? const Duration(seconds: 15)
          : Duration(microseconds: (json['poll_interval'] as num).toInt()),
      defaultInterval: (json['default_interval'] as num?)?.toInt() ?? 1,
      howMany: (json['how_many'] as num?)?.toInt() ?? 20,
      graphHeader: json['graph_header'] as String?,
      intervalPresets: (json['interval_presets'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [1, 5, 10, 30, 60],
      showBph: json['show_bph'] as bool? ?? false,
      unit: json['unit'] as String? ?? 'bpm',
      intervalVariable: json['interval_variable'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$BpmConfigToJson(BpmConfig instance) => <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'key': instance.key,
      'text_color': const ColorConverter().toJson(instance.textColor),
      'poll_interval': instance.pollInterval.inMicroseconds,
      'default_interval': instance.defaultInterval,
      'how_many': instance.howMany,
      'graph_header': instance.graphHeader,
      'interval_presets': instance.intervalPresets,
      'show_bph': instance.showBph,
      'unit': instance.unit,
      'interval_variable': instance.intervalVariable,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

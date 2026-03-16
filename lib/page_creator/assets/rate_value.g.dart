// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rate_value.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RateValueConfig _$RateValueConfigFromJson(Map<String, dynamic> json) =>
    RateValueConfig(
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
      showPerHour: json['show_per_hour'] as bool? ?? false,
      unit: json['unit'] as String? ?? 'kg/min',
      intervalVariable: json['interval_variable'] as String?,
      decimalPlaces: (json['decimal_places'] as num?)?.toInt() ?? 1,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$RateValueConfigToJson(RateValueConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'key': instance.key,
      'text_color': const ColorConverter().toJson(instance.textColor),
      'poll_interval': instance.pollInterval.inMicroseconds,
      'default_interval': instance.defaultInterval,
      'how_many': instance.howMany,
      'graph_header': instance.graphHeader,
      'interval_presets': instance.intervalPresets,
      'show_per_hour': instance.showPerHour,
      'unit': instance.unit,
      'interval_variable': instance.intervalVariable,
      'decimal_places': instance.decimalPlaces,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

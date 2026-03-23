// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inference_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InferenceLogConfig _$InferenceLogConfigFromJson(Map<String, dynamic> json) =>
    InferenceLogConfig(
      key: json['key'] as String,
      controlKey: json['control_key'] as String?,
      maxEntries: (json['max_entries'] as num?)?.toInt() ?? 30,
      showThumbnail: json['show_thumbnail'] as bool? ?? true,
      showConfidenceBar: json['show_confidence_bar'] as bool? ?? true,
      showLatency: json['show_latency'] as bool? ?? true,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$InferenceLogConfigToJson(InferenceLogConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'key': instance.key,
      'control_key': instance.controlKey,
      'max_entries': instance.maxEntries,
      'show_thumbnail': instance.showThumbnail,
      'show_confidence_bar': instance.showConfidenceBar,
      'show_latency': instance.showLatency,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

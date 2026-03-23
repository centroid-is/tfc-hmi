// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_feed.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImageFeedConfig _$ImageFeedConfigFromJson(Map<String, dynamic> json) =>
    ImageFeedConfig(
      key: json['key'] as String,
      controlKey: json['control_key'] as String?,
      maxImages: (json['max_images'] as num?)?.toInt() ?? 9,
      gridColumns: (json['grid_columns'] as num?)?.toInt() ?? 3,
      showConfidence: json['show_confidence'] as bool? ?? true,
      showLabel: json['show_label'] as bool? ?? true,
      showNewBadge: json['show_new_badge'] as bool? ?? true,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$ImageFeedConfigToJson(ImageFeedConfig instance) =>
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
      'max_images': instance.maxImages,
      'grid_columns': instance.gridColumns,
      'show_confidence': instance.showConfidence,
      'show_label': instance.showLabel,
      'show_new_badge': instance.showNewBadge,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'circle_button.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FeedbackConfig _$FeedbackConfigFromJson(Map<String, dynamic> json) =>
    FeedbackConfig()
      ..key = json['key'] as String
      ..color = const ColorConverter()
          .fromJson(json['color'] as Map<String, dynamic>);

Map<String, dynamic> _$FeedbackConfigToJson(FeedbackConfig instance) =>
    <String, dynamic>{
      'key': instance.key,
      'color': const ColorConverter().toJson(instance.color),
    };

CircleButtonConfig _$CircleButtonConfigFromJson(Map<String, dynamic> json) =>
    CircleButtonConfig(
      key: json['key'] as String,
      outwardColor: const ColorConverter()
          .fromJson(json['outward_color'] as Map<String, dynamic>),
      inwardColor: const ColorConverter()
          .fromJson(json['inward_color'] as Map<String, dynamic>),
      textPos: $enumDecode(_$TextPosEnumMap, json['text_pos']),
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..feedback = json['feedback'] == null
          ? null
          : FeedbackConfig.fromJson(json['feedback'] as Map<String, dynamic>)
      ..text = json['text'] as String?;

Map<String, dynamic> _$CircleButtonConfigToJson(CircleButtonConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'key': instance.key,
      'feedback': instance.feedback,
      'text': instance.text,
      'outward_color': const ColorConverter().toJson(instance.outwardColor),
      'inward_color': const ColorConverter().toJson(instance.inwardColor),
      'text_pos': _$TextPosEnumMap[instance.textPos]!,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
};

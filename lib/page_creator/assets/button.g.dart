// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'button.dart';

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

ButtonConfig _$ButtonConfigFromJson(Map<String, dynamic> json) => ButtonConfig(
      key: json['key'] as String,
      outwardColor: const ColorConverter()
          .fromJson(json['outward_color'] as Map<String, dynamic>),
      inwardColor: const ColorConverter()
          .fromJson(json['inward_color'] as Map<String, dynamic>),
      buttonType: $enumDecode(_$ButtonTypeEnumMap, json['button_type']),
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..feedback = json['feedback'] == null
          ? null
          : FeedbackConfig.fromJson(json['feedback'] as Map<String, dynamic>);

Map<String, dynamic> _$ButtonConfigToJson(ButtonConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'key': instance.key,
      'feedback': instance.feedback,
      'outward_color': const ColorConverter().toJson(instance.outwardColor),
      'inward_color': const ColorConverter().toJson(instance.inwardColor),
      'button_type': _$ButtonTypeEnumMap[instance.buttonType]!,
    };

const _$ButtonTypeEnumMap = {
  ButtonType.circle: 'circle',
  ButtonType.square: 'square',
};

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

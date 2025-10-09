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
      icon: json['icon'] == null
          ? null
          : IconConfig.fromJson(json['icon'] as Map<String, dynamic>),
      feedback: json['feedback'] == null
          ? null
          : FeedbackConfig.fromJson(json['feedback'] as Map<String, dynamic>),
      isToggle: json['is_toggle'] as bool? ?? false,
      serverWritesLow: json['server_writes_low'] as bool? ?? false,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$ButtonConfigToJson(ButtonConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'key': instance.key,
      'feedback': instance.feedback,
      'icon': instance.icon,
      'outward_color': const ColorConverter().toJson(instance.outwardColor),
      'inward_color': const ColorConverter().toJson(instance.inwardColor),
      'button_type': _$ButtonTypeEnumMap[instance.buttonType]!,
      'is_toggle': instance.isToggle,
      'server_writes_low': instance.serverWritesLow,
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

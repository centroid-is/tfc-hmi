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
      outwardColor: json['outward_color'] == null
          ? AssetColor.primary
          : const AssetColorConverter()
              .fromJson(json['outward_color'] as Map<String, dynamic>),
      inwardColor: json['inward_color'] == null
          ? AssetColor.secondary
          : const AssetColorConverter()
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
      disabledKey: json['disabled_key'] as String?,
      disabledPolarity: $enumDecodeNullable(
              _$DisabledPolarityEnumMap, json['disabled_polarity'],
              unknownValue: DisabledPolarity.disableWhenTrue) ??
          DisabledPolarity.disableWhenTrue,
      disabledColor: ButtonConfig._disabledColorFromJson(
          json['disabled_color'] as Map<String, dynamic>?),
      textColor: const OptionalColorConverter()
          .fromJson(json['text_color'] as Map<String, dynamic>?),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$ButtonConfigToJson(ButtonConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'key': instance.key,
      'feedback': instance.feedback?.toJson(),
      'icon': instance.icon?.toJson(),
      'outward_color':
          const AssetColorConverter().toJson(instance.outwardColor),
      'inward_color': const AssetColorConverter().toJson(instance.inwardColor),
      'button_type': _$ButtonTypeEnumMap[instance.buttonType]!,
      'is_toggle': instance.isToggle,
      'server_writes_low': instance.serverWritesLow,
      'disabled_key': instance.disabledKey,
      'disabled_polarity':
          _$DisabledPolarityEnumMap[instance.disabledPolarity]!,
      'disabled_color':
          ButtonConfig._disabledColorToJson(instance.disabledColor),
      'text_color': const OptionalColorConverter().toJson(instance.textColor),
    };

const _$ButtonTypeEnumMap = {
  ButtonType.circle: 'circle',
  ButtonType.square: 'square',
};

const _$DisabledPolarityEnumMap = {
  DisabledPolarity.disableWhenTrue: 'disableWhenTrue',
  DisabledPolarity.disableWhenFalse: 'disableWhenFalse',
};

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

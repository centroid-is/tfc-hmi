// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'option_variable.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OptionItem _$OptionItemFromJson(Map<String, dynamic> json) => OptionItem(
      value: json['value'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
    );

Map<String, dynamic> _$OptionItemToJson(OptionItem instance) =>
    <String, dynamic>{
      'value': instance.value,
      'label': instance.label,
      'description': instance.description,
    };

OptionVariableConfig _$OptionVariableConfigFromJson(
        Map<String, dynamic> json) =>
    OptionVariableConfig(
      variableName: json['variableName'] as String,
      options: (json['options'] as List<dynamic>)
          .map((e) => OptionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      selectedValue: json['selectedValue'] as String?,
      defaultValue: json['defaultValue'] as String?,
      showSearch: json['showSearch'] as bool? ?? true,
      customLabel: json['customLabel'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$OptionVariableConfigToJson(
        OptionVariableConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'variableName': instance.variableName,
      'options': instance.options,
      'selectedValue': instance.selectedValue,
      'defaultValue': instance.defaultValue,
      'showSearch': instance.showSearch,
      'customLabel': instance.customLabel,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

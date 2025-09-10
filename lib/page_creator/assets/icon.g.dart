// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'icon.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConditionalIconState _$ConditionalIconStateFromJson(
        Map<String, dynamic> json) =>
    ConditionalIconState(
      expression:
          ExpressionConfig.fromJson(json['expression'] as Map<String, dynamic>),
      iconData: _$JsonConverterFromJson<String, IconData>(
          json['iconData'], const IconDataConverter().fromJson),
      color: const OptionalColorConverter()
          .fromJson(json['color'] as Map<String, dynamic>?),
    );

Map<String, dynamic> _$ConditionalIconStateToJson(
        ConditionalIconState instance) =>
    <String, dynamic>{
      'expression': instance.expression.toJson(),
      'iconData': _$JsonConverterToJson<String, IconData>(
          instance.iconData, const IconDataConverter().toJson),
      'color': const OptionalColorConverter().toJson(instance.color),
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);

IconConfig _$IconConfigFromJson(Map<String, dynamic> json) => IconConfig(
      iconData: const IconDataConverter().fromJson(json['iconData'] as String),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..color = const OptionalColorConverter()
          .fromJson(json['color'] as Map<String, dynamic>?)
      ..conditionalStates = (json['conditional_states'] as List<dynamic>?)
          ?.map((e) => ConditionalIconState.fromJson(e as Map<String, dynamic>))
          .toList();

Map<String, dynamic> _$IconConfigToJson(IconConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'iconData': const IconDataConverter().toJson(instance.iconData),
      'color': const OptionalColorConverter().toJson(instance.color),
      'conditional_states':
          instance.conditionalStates?.map((e) => e.toJson()).toList(),
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'elevator.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ElevatorChildEntry _$ElevatorChildEntryFromJson(Map<String, dynamic> json) =>
    ElevatorChildEntry(
      id: json['id'] as String?,
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0.5,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0.0,
      child: _childFromJson(json['child'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ElevatorChildEntryToJson(ElevatorChildEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'offsetX': instance.offsetX,
      'offsetY': instance.offsetY,
      'child': _childToJson(instance.child),
    };

ElevatorConfig _$ElevatorConfigFromJson(Map<String, dynamic> json) =>
    ElevatorConfig(
      positionKey: json['positionKey'] as String? ?? '',
      tweenDurationMs: (json['tweenDurationMs'] as num?)?.toInt() ?? 250,
      simulate: json['simulate'] as bool?,
      children: _childrenFromJson(json['children'] as List?),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$ElevatorConfigToJson(ElevatorConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'positionKey': instance.positionKey,
      'tweenDurationMs': instance.tweenDurationMs,
      'children': _childrenToJson(instance.children),
      if (instance.simulate case final value?) 'simulate': value,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

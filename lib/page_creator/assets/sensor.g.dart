// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sensor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SensorConfig _$SensorConfigFromJson(Map<String, dynamic> json) => SensorConfig(
      kind: $enumDecodeNullable(_$SensorKindEnumMap, json['kind'],
              unknownValue: SensorKind.redLight) ??
          SensorKind.redLight,
      detectionKey: json['detectionKey'] as String? ?? '',
      invertActivePolarity: json['invertActivePolarity'] as bool? ?? false,
      risingEdgeDelayKey: json['risingEdgeDelayKey'] as String? ?? '',
      fallingEdgeDelayKey: json['fallingEdgeDelayKey'] as String? ?? '',
      activeColor: _$JsonConverterFromJson<Map<String, dynamic>, AssetColor>(
          json['activeColor'], const AssetColorConverter().fromJson),
      inactiveColor: _$JsonConverterFromJson<Map<String, dynamic>, AssetColor>(
          json['inactiveColor'], const AssetColorConverter().fromJson),
      tag: json['tag'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?
      ..text = json['text'] as String?;

Map<String, dynamic> _$SensorConfigToJson(SensorConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'kind': _$SensorKindEnumMap[instance.kind]!,
      'detectionKey': instance.detectionKey,
      'invertActivePolarity': instance.invertActivePolarity,
      'risingEdgeDelayKey': instance.risingEdgeDelayKey,
      'fallingEdgeDelayKey': instance.fallingEdgeDelayKey,
      'activeColor': const AssetColorConverter().toJson(instance.activeColor),
      'inactiveColor':
          const AssetColorConverter().toJson(instance.inactiveColor),
      'tag': instance.tag,
      'text': instance.text,
    };

const _$SensorKindEnumMap = {
  SensorKind.redLight: 'redLight',
  SensorKind.opticField: 'opticField',
  SensorKind.inductiveField: 'inductiveField',
};

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'third_party.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThirdPartyChildEntry _$ThirdPartyChildEntryFromJson(
        Map<String, dynamic> json) =>
    ThirdPartyChildEntry(
      id: json['id'] as String?,
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0.5,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0.5,
      keepUpright: json['keepUpright'] as bool? ?? false,
      child: _childFromJson(json['child'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ThirdPartyChildEntryToJson(
        ThirdPartyChildEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'offsetX': instance.offsetX,
      'offsetY': instance.offsetY,
      'keepUpright': instance.keepUpright,
      'child': _childToJson(instance.child),
    };

ThirdPartyEquipmentConfig _$ThirdPartyEquipmentConfigFromJson(
        Map<String, dynamic> json) =>
    ThirdPartyEquipmentConfig(
      kind: $enumDecodeNullable(_$ThirdPartyEquipmentKindEnumMap, json['kind'],
              unknownValue: ThirdPartyEquipmentKind.multivac) ??
          ThirdPartyEquipmentKind.multivac,
      runKey: json['runKey'] as String? ?? '',
      invertRunPolarity: json['invertRunPolarity'] as bool? ?? false,
      runningColor: _$JsonConverterFromJson<Map<String, dynamic>, Color>(
          json['runningColor'], const ColorConverter().fromJson),
      stoppedColor: _$JsonConverterFromJson<Map<String, dynamic>, Color>(
          json['stoppedColor'], const ColorConverter().fromJson),
      outlineColor: _$JsonConverterFromJson<Map<String, dynamic>, Color>(
          json['outlineColor'], const ColorConverter().fromJson),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      tag: json['tag'] as String?,
      notes: json['notes'] as String?,
      strapMachines: (json['strapMachines'] as num?)?.toInt() ?? 3,
      childTextAngle: (json['childTextAngle'] as num?)?.toDouble() ?? 0.0,
      acceptWindowMinutes: (json['acceptWindowMinutes'] as num?)?.toInt() ?? 30,
      children: _childrenFromJson(json['children'] as List?),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?
      ..text = json['text'] as String?;

Map<String, dynamic> _$ThirdPartyEquipmentConfigToJson(
        ThirdPartyEquipmentConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'kind': _$ThirdPartyEquipmentKindEnumMap[instance.kind]!,
      'runKey': instance.runKey,
      'invertRunPolarity': instance.invertRunPolarity,
      'runningColor': const ColorConverter().toJson(instance.runningColor),
      'stoppedColor': const ColorConverter().toJson(instance.stoppedColor),
      'outlineColor': const ColorConverter().toJson(instance.outlineColor),
      'strokeWidth': instance.strokeWidth,
      'tag': instance.tag,
      'notes': instance.notes,
      'strapMachines': instance.strapMachines,
      'children': _childrenToJson(instance.children),
      'childTextAngle': instance.childTextAngle,
      'acceptWindowMinutes': instance.acceptWindowMinutes,
      'text': instance.text,
    };

const _$ThirdPartyEquipmentKindEnumMap = {
  ThirdPartyEquipmentKind.multivac: 'multivac',
  ThirdPartyEquipmentKind.speedBatcher: 'speedBatcher',
  ThirdPartyEquipmentKind.boxErector: 'boxErector',
  ThirdPartyEquipmentKind.strappingLine: 'strappingLine',
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

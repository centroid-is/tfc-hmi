// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conveyor_fb.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConveyorFbConfig _$ConveyorFbConfigFromJson(Map<String, dynamic> json) =>
    ConveyorFbConfig(
      fbInstanceName: json['fbInstanceName'] as String?,
      parentWordKey: json['parentWordKey'] as String?,
      schema: $enumDecodeNullable(_$ConveyorSchemaEnumMap, json['schema']),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$ConveyorFbConfigToJson(ConveyorFbConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'fbInstanceName': instance.fbInstanceName,
      'parentWordKey': instance.parentWordKey,
      'schema': _$ConveyorSchemaEnumMap[instance.schema],
    };

const _$ConveyorSchemaEnumMap = {
  ConveyorSchema.beckhoff: 'beckhoff',
  ConveyorSchema.schneider: 'schneider',
};

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

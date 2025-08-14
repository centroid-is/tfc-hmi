// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'beckhoff.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BeckhoffCX5010Config _$BeckhoffCX5010ConfigFromJson(
        Map<String, dynamic> json) =>
    BeckhoffCX5010Config()
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..subdevices =
          const AssetListConverter().fromJson(json['subdevices'] as List);

Map<String, dynamic> _$BeckhoffCX5010ConfigToJson(
        BeckhoffCX5010Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'subdevices': const AssetListConverter().toJson(instance.subdevices),
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

BeckhoffEL1008Config _$BeckhoffEL1008ConfigFromJson(
        Map<String, dynamic> json) =>
    BeckhoffEL1008Config(
      nameOrId: json['nameOrId'] as String,
      descriptionsKey: json['descriptionsKey'] as String?,
      rawStateKey: json['rawStateKey'] as String?,
      processedStateKey: json['processedStateKey'] as String?,
      forceValuesKey: json['forceValuesKey'] as String?,
      onFiltersKey: json['onFiltersKey'] as String?,
      offFiltersKey: json['offFiltersKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$BeckhoffEL1008ConfigToJson(
        BeckhoffEL1008Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'nameOrId': instance.nameOrId,
      'descriptionsKey': instance.descriptionsKey,
      'rawStateKey': instance.rawStateKey,
      'processedStateKey': instance.processedStateKey,
      'forceValuesKey': instance.forceValuesKey,
      'onFiltersKey': instance.onFiltersKey,
      'offFiltersKey': instance.offFiltersKey,
    };

BeckhoffEL2008Config _$BeckhoffEL2008ConfigFromJson(
        Map<String, dynamic> json) =>
    BeckhoffEL2008Config(
      nameOrId: json['nameOrId'] as String,
      descriptionsKey: json['descriptionsKey'] as String?,
      rawStateKey: json['rawStateKey'] as String?,
      forceValuesKey: json['forceValuesKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$BeckhoffEL2008ConfigToJson(
        BeckhoffEL2008Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'nameOrId': instance.nameOrId,
      'descriptionsKey': instance.descriptionsKey,
      'rawStateKey': instance.rawStateKey,
      'forceValuesKey': instance.forceValuesKey,
    };

BeckhoffEL9222Config _$BeckhoffEL9222ConfigFromJson(
        Map<String, dynamic> json) =>
    BeckhoffEL9222Config(
      nameOrId: json['nameOrId'] as String,
      descriptionsKey: json['descriptionsKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$BeckhoffEL9222ConfigToJson(
        BeckhoffEL9222Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'nameOrId': instance.nameOrId,
      'descriptionsKey': instance.descriptionsKey,
    };

BeckhoffEL9187Config _$BeckhoffEL9187ConfigFromJson(
        Map<String, dynamic> json) =>
    BeckhoffEL9187Config()
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$BeckhoffEL9187ConfigToJson(
        BeckhoffEL9187Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
    };

BeckhoffEL9186Config _$BeckhoffEL9186ConfigFromJson(
        Map<String, dynamic> json) =>
    BeckhoffEL9186Config()
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$BeckhoffEL9186ConfigToJson(
        BeckhoffEL9186Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
    };

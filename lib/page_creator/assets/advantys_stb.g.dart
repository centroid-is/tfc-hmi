// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'advantys_stb.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

STBDDI3725Config _$STBDDI3725ConfigFromJson(Map<String, dynamic> json) =>
    STBDDI3725Config(
      nameOrId: json['nameOrId'] as String? ?? '1',
      rawStateKey: json['rawStateKey'] as String?,
      forceValuesKey: json['forceValuesKey'] as String?,
      onFiltersKey: json['onFiltersKey'] as String?,
      offFiltersKey: json['offFiltersKey'] as String?,
      descriptionsKey: json['descriptionsKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$STBDDI3725ConfigToJson(STBDDI3725Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'nameOrId': instance.nameOrId,
      'rawStateKey': instance.rawStateKey,
      'forceValuesKey': instance.forceValuesKey,
      'onFiltersKey': instance.onFiltersKey,
      'offFiltersKey': instance.offFiltersKey,
      'descriptionsKey': instance.descriptionsKey,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

STBDDO3705Config _$STBDDO3705ConfigFromJson(Map<String, dynamic> json) =>
    STBDDO3705Config(
      nameOrId: json['nameOrId'] as String? ?? '1',
      rawStateKey: json['rawStateKey'] as String?,
      forceValuesKey: json['forceValuesKey'] as String?,
      descriptionsKey: json['descriptionsKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$STBDDO3705ConfigToJson(STBDDO3705Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'nameOrId': instance.nameOrId,
      'rawStateKey': instance.rawStateKey,
      'forceValuesKey': instance.forceValuesKey,
      'descriptionsKey': instance.descriptionsKey,
    };

STBNIP2311Config _$STBNIP2311ConfigFromJson(Map<String, dynamic> json) =>
    STBNIP2311Config(
      nameOrId: json['nameOrId'] as String? ?? '1',
      subdevices: _$JsonConverterFromJson<List<dynamic>, List<Asset>>(
          json['subdevices'], const AssetListConverter().fromJson),
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$STBNIP2311ConfigToJson(STBNIP2311Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'nameOrId': instance.nameOrId,
      'subdevices': const AssetListConverter().toJson(instance.subdevices),
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

STBPDT3100Config _$STBPDT3100ConfigFromJson(Map<String, dynamic> json) =>
    STBPDT3100Config(
      nameOrId: json['nameOrId'] as String? ?? '1',
      inputOkKey: json['inputOkKey'] as String?,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$STBPDT3100ConfigToJson(STBPDT3100Config instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'nameOrId': instance.nameOrId,
      'inputOkKey': instance.inputOkKey,
    };

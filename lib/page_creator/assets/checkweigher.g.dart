// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkweigher.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckweigherConfig _$CheckweigherConfigFromJson(Map<String, dynamic> json) =>
    CheckweigherConfig(
      currentWeightKey: json['currentWeightKey'] as String,
      acceptKey: json['acceptKey'] as String?,
      rejectKey: json['rejectKey'] as String?,
      tareKey: json['tareKey'] as String?,
      zeroKey: json['zeroKey'] as String?,
      calibrateKey: json['calibrateKey'] as String?,
      targetWeightKey: json['targetWeightKey'] as String?,
      upperLimitKey: json['upperLimitKey'] as String?,
      lowerLimitKey: json['lowerLimitKey'] as String?,
      sampleSize: (json['sampleSize'] as num?)?.toInt() ?? 100,
      decimalPlaces: (json['decimalPlaces'] as num?)?.toInt() ?? 2,
      textColor: json['textColor'] == null
          ? Colors.black
          : const ColorConverter()
              .fromJson(json['textColor'] as Map<String, dynamic>),
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$CheckweigherConfigToJson(CheckweigherConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'currentWeightKey': instance.currentWeightKey,
      'acceptKey': instance.acceptKey,
      'rejectKey': instance.rejectKey,
      'tareKey': instance.tareKey,
      'zeroKey': instance.zeroKey,
      'calibrateKey': instance.calibrateKey,
      'targetWeightKey': instance.targetWeightKey,
      'upperLimitKey': instance.upperLimitKey,
      'lowerLimitKey': instance.lowerLimitKey,
      'sampleSize': instance.sampleSize,
      'decimalPlaces': instance.decimalPlaces,
      'textColor': const ColorConverter().toJson(instance.textColor),
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

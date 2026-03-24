// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drawing_viewer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DrawingViewerConfig _$DrawingViewerConfigFromJson(Map<String, dynamic> json) =>
    DrawingViewerConfig(
      drawingName: json['drawingName'] as String,
      filePath: json['filePath'] as String,
      startPage: (json['startPage'] as num?)?.toInt() ?? 1,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$DrawingViewerConfigToJson(
        DrawingViewerConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'drawingName': instance.drawingName,
      'filePath': instance.filePath,
      'startPage': instance.startPage,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drawn_box.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DrawnBoxConfig _$DrawnBoxConfigFromJson(Map<String, dynamic> json) =>
    DrawnBoxConfig(
      color: json['color'] == null
          ? Colors.black
          : const ColorConverter()
              .fromJson(json['color'] as Map<String, dynamic>),
      lineWidth: (json['lineWidth'] as num?)?.toDouble() ?? 2.0,
      isDashed: json['isDashed'] as bool? ?? false,
      showTop: json['showTop'] as bool? ?? true,
      showRight: json['showRight'] as bool? ?? true,
      showBottom: json['showBottom'] as bool? ?? true,
      showLeft: json['showLeft'] as bool? ?? true,
      dashLength: (json['dashLength'] as num?)?.toDouble() ?? 5.0,
      dashSpacing: (json['dashSpacing'] as num?)?.toDouble() ?? 5.0,
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$DrawnBoxConfigToJson(DrawnBoxConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates,
      'size': instance.size,
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'color': const ColorConverter().toJson(instance.color),
      'lineWidth': instance.lineWidth,
      'isDashed': instance.isDashed,
      'showTop': instance.showTop,
      'showRight': instance.showRight,
      'showBottom': instance.showBottom,
      'showLeft': instance.showLeft,
      'dashLength': instance.dashLength,
      'dashSpacing': instance.dashSpacing,
    };

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

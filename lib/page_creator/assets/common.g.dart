// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'common.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Coordinates _$CoordinatesFromJson(Map<String, dynamic> json) => Coordinates(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      angle: (json['angle'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$CoordinatesToJson(Coordinates instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'angle': instance.angle,
    };

RelativeSize _$RelativeSizeFromJson(Map<String, dynamic> json) => RelativeSize(
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );

Map<String, dynamic> _$RelativeSizeToJson(RelativeSize instance) =>
    <String, dynamic>{
      'width': instance.width,
      'height': instance.height,
    };

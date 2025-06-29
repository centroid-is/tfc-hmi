// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'graph.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GraphDataConfig _$GraphDataConfigFromJson(Map<String, dynamic> json) =>
    GraphDataConfig(
      label: json['label'] as String,
      mainAxis: json['mainAxis'] as bool? ?? true,
    );

Map<String, dynamic> _$GraphDataConfigToJson(GraphDataConfig instance) =>
    <String, dynamic>{
      'label': instance.label,
      'mainAxis': instance.mainAxis,
    };

GraphAxisConfig _$GraphAxisConfigFromJson(Map<String, dynamic> json) =>
    GraphAxisConfig(
      unit: json['unit'] as String,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      step: (json['step'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$GraphAxisConfigToJson(GraphAxisConfig instance) =>
    <String, dynamic>{
      'unit': instance.unit,
      'min': instance.min,
      'max': instance.max,
      'step': instance.step,
    };

GraphConfig _$GraphConfigFromJson(Map<String, dynamic> json) => GraphConfig(
      type: $enumDecode(_$GraphTypeEnumMap, json['type']),
      xAxis: GraphAxisConfig.fromJson(json['xAxis'] as Map<String, dynamic>),
      yAxis: GraphAxisConfig.fromJson(json['yAxis'] as Map<String, dynamic>),
      yAxis2: json['yAxis2'] == null
          ? null
          : GraphAxisConfig.fromJson(json['yAxis2'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GraphConfigToJson(GraphConfig instance) =>
    <String, dynamic>{
      'type': _$GraphTypeEnumMap[instance.type]!,
      'xAxis': instance.xAxis.toJson(),
      'yAxis': instance.yAxis.toJson(),
      'yAxis2': instance.yAxis2?.toJson(),
    };

const _$GraphTypeEnumMap = {
  GraphType.line: 'line',
  GraphType.bar: 'bar',
  GraphType.scatter: 'scatter',
  GraphType.timeseries: 'timeseries',
};

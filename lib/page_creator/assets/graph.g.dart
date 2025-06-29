// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'graph.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GraphSeriesConfig _$GraphSeriesConfigFromJson(Map<String, dynamic> json) =>
    GraphSeriesConfig(
      key: json['key'] as String,
      label: json['label'] as String,
    );

Map<String, dynamic> _$GraphSeriesConfigToJson(GraphSeriesConfig instance) =>
    <String, dynamic>{
      'key': instance.key,
      'label': instance.label,
    };

GraphAssetConfig _$GraphAssetConfigFromJson(Map<String, dynamic> json) =>
    GraphAssetConfig(
      graphType: $enumDecodeNullable(_$GraphTypeEnumMap, json['graph_type']) ??
          GraphType.line,
      primarySeries: (json['primary_series'] as List<dynamic>?)
          ?.map((e) => GraphSeriesConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      secondarySeries: (json['secondary_series'] as List<dynamic>?)
          ?.map((e) => GraphSeriesConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      xAxis: json['x_axis'] == null
          ? null
          : GraphAxisConfig.fromJson(json['x_axis'] as Map<String, dynamic>),
      yAxis: json['y_axis'] == null
          ? null
          : GraphAxisConfig.fromJson(json['y_axis'] as Map<String, dynamic>),
      yAxis2: json['y_axis2'] == null
          ? null
          : GraphAxisConfig.fromJson(json['y_axis2'] as Map<String, dynamic>),
      timeWindowMinutes: json['time_window_min'] == null
          ? const Duration(minutes: 10)
          : Duration(microseconds: (json['time_window_min'] as num).toInt()),
    )
      ..variant = json['asset_name'] as String
      ..pageName = json['page_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$GraphAssetConfigToJson(GraphAssetConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'page_name': instance.pageName,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'graph_type': _$GraphTypeEnumMap[instance.graphType]!,
      'primary_series': instance.primarySeries.map((e) => e.toJson()).toList(),
      'secondary_series':
          instance.secondarySeries.map((e) => e.toJson()).toList(),
      'x_axis': instance.xAxis.toJson(),
      'y_axis': instance.yAxis.toJson(),
      'y_axis2': instance.yAxis2?.toJson(),
      'time_window_min': instance.timeWindowMinutes.inMicroseconds,
    };

const _$GraphTypeEnumMap = {
  GraphType.line: 'line',
  GraphType.bar: 'bar',
  GraphType.scatter: 'scatter',
  GraphType.timeseries: 'timeseries',
};

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

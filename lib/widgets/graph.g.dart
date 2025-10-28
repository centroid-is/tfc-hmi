// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'graph.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GraphDataConfig _$GraphDataConfigFromJson(Map<String, dynamic> json) =>
    GraphDataConfig(
      label: json['label'] as String,
      mainAxis: json['mainAxis'] as bool? ?? true,
      color: const OptionalColorConverter()
          .fromJson(json['color'] as Map<String, dynamic>?),
    );

Map<String, dynamic> _$GraphDataConfigToJson(GraphDataConfig instance) =>
    <String, dynamic>{
      'label': instance.label,
      'mainAxis': instance.mainAxis,
      'color': const OptionalColorConverter().toJson(instance.color),
    };

GraphAxisConfig _$GraphAxisConfigFromJson(Map<String, dynamic> json) =>
    GraphAxisConfig(
      title: json['title'] as String?,
      unit: json['unit'] as String,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      boolean: json['boolean'] as bool? ?? false,
    );

Map<String, dynamic> _$GraphAxisConfigToJson(GraphAxisConfig instance) =>
    <String, dynamic>{
      'title': instance.title,
      'unit': instance.unit,
      'min': instance.min,
      'max': instance.max,
      'boolean': instance.boolean,
    };

GraphConfig _$GraphConfigFromJson(Map<String, dynamic> json) => GraphConfig(
      type: $enumDecode(_$GraphTypeEnumMap, json['type']),
      xAxis: GraphAxisConfig.fromJson(json['xAxis'] as Map<String, dynamic>),
      yAxis: GraphAxisConfig.fromJson(json['yAxis'] as Map<String, dynamic>),
      yAxis2: json['yAxis2'] == null
          ? null
          : GraphAxisConfig.fromJson(json['yAxis2'] as Map<String, dynamic>),
      xSpan: json['xSpan'] == null
          ? null
          : Duration(microseconds: (json['xSpan'] as num).toInt()),
      pan: json['pan'] as bool? ?? true,
      width: (json['width'] as num?)?.toDouble() ?? 2,
      zoom: json['zoom'] as bool? ?? true,
    );

Map<String, dynamic> _$GraphConfigToJson(GraphConfig instance) =>
    <String, dynamic>{
      'type': _$GraphTypeEnumMap[instance.type]!,
      'xAxis': instance.xAxis.toJson(),
      'yAxis': instance.yAxis.toJson(),
      'yAxis2': instance.yAxis2?.toJson(),
      'xSpan': instance.xSpan?.inMicroseconds,
      'pan': instance.pan,
      'zoom': instance.zoom,
      'width': instance.width,
    };

const _$GraphTypeEnumMap = {
  GraphType.line: 'line',
  GraphType.bar: 'bar',
  GraphType.scatter: 'scatter',
  GraphType.pie: 'pie',
  GraphType.timeseries: 'timeseries',
  GraphType.barTimeseries: 'barTimeseries',
};

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$chartThemeNotifierHash() =>
    r'62b1352e93f1aea589eefdb712f37d30c6895607';

/// -------------------- Chart theme (Riverpod) --------------------
///
/// Copied from [ChartThemeNotifier].
@ProviderFor(ChartThemeNotifier)
final chartThemeNotifierProvider =
    AutoDisposeNotifierProvider<ChartThemeNotifier, cs.ChartTheme>.internal(
  ChartThemeNotifier.new,
  name: r'chartThemeNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$chartThemeNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ChartThemeNotifier = AutoDisposeNotifier<cs.ChartTheme>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

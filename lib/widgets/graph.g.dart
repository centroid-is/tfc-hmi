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
      xSpan: json['xSpan'] == null
          ? null
          : Duration(microseconds: (json['xSpan'] as num).toInt()),
    );

Map<String, dynamic> _$GraphConfigToJson(GraphConfig instance) =>
    <String, dynamic>{
      'type': _$GraphTypeEnumMap[instance.type]!,
      'xAxis': instance.xAxis.toJson(),
      'yAxis': instance.yAxis.toJson(),
      'yAxis2': instance.yAxis2?.toJson(),
      'xSpan': instance.xSpan?.inMicroseconds,
    };

const _$GraphTypeEnumMap = {
  GraphType.line: 'line',
  GraphType.timeseries: 'timeseries',
  GraphType.barTimeseries: 'barTimeseries',
};

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$chartThemeNotifierHash() =>
    r'84be81c1b75854160d298b8b54d2e3a2d807bf23';

/// Chart theme provider that integrates with the app's theme system
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

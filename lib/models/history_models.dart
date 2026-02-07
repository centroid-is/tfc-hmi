import 'package:flutter/material.dart';

// TODO REMOVE
class GraphDataConfig {
  final String label;

  /// true => primary Y axis (left); false => secondary Y axis (right)
  final bool mainAxis;
  final Color? color;

  const GraphDataConfig({
    required this.label,
    this.mainAxis = true,
    this.color,
  });
}

class GraphKeyConfig {
  final String key;
  final String alias;
  final bool useSecondYAxis;
  final int graphIndex; // 0-4 for up to 5 graphs

  GraphKeyConfig({
    required this.key,
    required this.alias,
    this.useSecondYAxis = false,
    this.graphIndex = 0,
  });

  GraphKeyConfig copyWith({
    String? key,
    String? alias,
    bool? useSecondYAxis,
    int? graphIndex,
  }) {
    return GraphKeyConfig(
      key: key ?? this.key,
      alias: alias ?? this.alias,
      useSecondYAxis: useSecondYAxis ?? this.useSecondYAxis,
      graphIndex: graphIndex ?? this.graphIndex,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GraphKeyConfig &&
        other.key == key &&
        other.alias == alias &&
        other.useSecondYAxis == useSecondYAxis &&
        other.graphIndex == graphIndex;
  }

  @override
  int get hashCode => Object.hash(key, alias, useSecondYAxis, graphIndex);
}

class GraphDisplayConfig {
  final int index;
  final String name;
  final String yAxisUnit;
  final String yAxis2Unit;

  GraphDisplayConfig({
    required this.index,
    this.name = '',
    this.yAxisUnit = '',
    this.yAxis2Unit = '',
  });

  String get displayName =>
      name.isNotEmpty ? name : 'Graph ${index + 1}';

  GraphDisplayConfig copyWith({
    int? index,
    String? name,
    String? yAxisUnit,
    String? yAxis2Unit,
  }) {
    return GraphDisplayConfig(
      index: index ?? this.index,
      name: name ?? this.name,
      yAxisUnit: yAxisUnit ?? this.yAxisUnit,
      yAxis2Unit: yAxis2Unit ?? this.yAxis2Unit,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GraphDisplayConfig &&
        other.index == index &&
        other.name == name &&
        other.yAxisUnit == yAxisUnit &&
        other.yAxis2Unit == yAxis2Unit;
  }

  @override
  int get hashCode => Object.hash(index, name, yAxisUnit, yAxis2Unit);
}

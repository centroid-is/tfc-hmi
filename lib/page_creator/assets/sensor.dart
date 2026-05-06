import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/converter/color_converter.dart';

import 'common.dart';

part 'sensor.g.dart';

/// The kind of sensor — drives painter dispatch and glyph appearance.
@JsonEnum()
enum SensorKind {
  redLight,
  opticField,
  inductiveField,
}

/// Configuration for a sensor asset.
///
/// Pure data model — JSON-serialisable, no widget/painter wiring. The widget,
/// painter, registry registration, and config dialog are introduced in
/// Plans 02–05 of the same phase.
@JsonSerializable(explicitToJson: true)
class SensorConfig extends BaseAsset {
  @override
  String get displayName => 'Sensor';

  @override
  String get category => 'Visualization';

  /// Sensor kind — determines which painter renders the glyph.
  @JsonKey(unknownEnumValue: SensorKind.redLight)
  SensorKind kind;

  /// State key emitting the raw detection bool.
  String detectionKey;

  /// When true, the visual `isActive` is the inverse of the raw bool.
  bool invertActivePolarity;

  /// State key carrying the rising-edge delay (ms). Display-only.
  String risingEdgeDelayKey;

  /// State key carrying the falling-edge delay (ms). Display-only.
  String fallingEdgeDelayKey;

  /// Per-instance active colour. Default `Colors.green` matches `led.dart`.
  @ColorConverter()
  Color activeColor;

  /// Per-instance inactive colour. Default `Colors.grey.shade400`.
  @ColorConverter()
  Color inactiveColor;

  /// Optional human-readable label (e.g. `"PE-101A"`).
  String? tag;

  SensorConfig({
    this.kind = SensorKind.redLight,
    this.detectionKey = '',
    this.invertActivePolarity = false,
    this.risingEdgeDelayKey = '',
    this.fallingEdgeDelayKey = '',
    Color? activeColor,
    Color? inactiveColor,
    this.tag,
  })  : activeColor = activeColor ?? Colors.green,
        inactiveColor = inactiveColor ?? Colors.grey.shade400;

  /// Preview factory with reasonable defaults for the asset palette.
  SensorConfig.preview() : this();

  factory SensorConfig.fromJson(Map<String, dynamic> json) =>
      _$SensorConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$SensorConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError('Sensor widget — Plan 03');
  }

  @override
  Widget configure(BuildContext context) {
    throw UnimplementedError('Sensor config dialog — Plan 05');
  }
}

/// Apply polarity inversion to a raw detection bool.
///
/// Implementation in Task 4 (TDD).
bool sensorIsActive({
  required bool rawBool,
  required bool invertActivePolarity,
}) {
  throw UnimplementedError('sensorIsActive — Task 4');
}

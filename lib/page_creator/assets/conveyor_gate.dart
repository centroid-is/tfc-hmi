import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:tfc/page_creator/assets/common.dart';

part 'conveyor_gate.g.dart';

/// Color helpers for JSON serialization of Color objects.
int _colorToJson(Color c) => c.value;
Color _colorFromJson(int v) => Color(v);

/// The type of gate mechanism.
@JsonEnum()
enum GateVariant {
  pneumatic,
  slider,
  pusher,
}

/// Which side the gate flap hinges from.
@JsonEnum()
enum GateSide {
  left,
  right,
}

/// Configuration for a conveyor gate asset.
///
/// Extends [BaseAsset] with fields specific to the pneumatic diverter gate:
/// variant type, hinge side, OPC UA state key, opening angle, animation timing,
/// and configurable open/closed colors.
@JsonSerializable(explicitToJson: true)
class ConveyorGateConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor Gate';

  @override
  String get category => 'Visualization';

  @JsonKey(unknownEnumValue: GateVariant.pneumatic)
  GateVariant gateVariant;

  @JsonKey(unknownEnumValue: GateSide.left)
  GateSide side;

  String stateKey;

  double openAngleDegrees;

  int openTimeMs;

  int? closeTimeMs;

  @JsonKey(fromJson: _colorFromJson, toJson: _colorToJson)
  Color openColor;

  @JsonKey(fromJson: _colorFromJson, toJson: _colorToJson)
  Color closedColor;

  ConveyorGateConfig({
    this.gateVariant = GateVariant.pneumatic,
    this.side = GateSide.left,
    this.stateKey = '',
    this.openAngleDegrees = 45.0,
    this.openTimeMs = 800,
    this.closeTimeMs,
    this.openColor = Colors.green,
    this.closedColor = Colors.white,
  });

  /// Preview factory with reasonable defaults for the asset palette.
  ConveyorGateConfig.preview()
      : gateVariant = GateVariant.pneumatic,
        side = GateSide.left,
        stateKey = '',
        openAngleDegrees = 45.0,
        openTimeMs = 800,
        closeTimeMs = null,
        openColor = Colors.green,
        closedColor = Colors.white;

  factory ConveyorGateConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorGateConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ConveyorGateConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    // Stub -- full widget implementation in Plan 03
    return Container(
      color: Colors.grey.shade300,
      child: const Center(child: Text('Gate')),
    );
  }

  @override
  Widget configure(BuildContext context) {
    // Stub -- full config dialog in Plan 02
    return const SizedBox.shrink();
  }
}

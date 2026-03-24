// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conveyor_gate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChildGateEntry _$ChildGateEntryFromJson(Map<String, dynamic> json) =>
    ChildGateEntry(
      position: (json['position'] as num?)?.toDouble() ?? 0.5,
      side: $enumDecodeNullable(_$GateSideEnumMap, json['side'],
              unknownValue: GateSide.left) ??
          GateSide.left,
      gate: _gateFromJson(json['gate'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ChildGateEntryToJson(ChildGateEntry instance) =>
    <String, dynamic>{
      'position': instance.position,
      'side': _$GateSideEnumMap[instance.side]!,
      'gate': _gateToJson(instance.gate),
    };

const _$GateSideEnumMap = {
  GateSide.left: 'left',
  GateSide.right: 'right',
};

ConveyorGateConfig _$ConveyorGateConfigFromJson(Map<String, dynamic> json) =>
    ConveyorGateConfig(
      gateVariant: $enumDecodeNullable(
              _$GateVariantEnumMap, json['gateVariant'],
              unknownValue: GateVariant.pneumatic) ??
          GateVariant.pneumatic,
      side: $enumDecodeNullable(_$GateSideEnumMap, json['side'],
              unknownValue: GateSide.left) ??
          GateSide.left,
      stateKey: json['stateKey'] as String? ?? '',
      openAngleDegrees: (json['openAngleDegrees'] as num?)?.toDouble() ?? 45.0,
      openTimeMs: (json['openTimeMs'] as num?)?.toInt() ?? 800,
      closeTimeMs: (json['closeTimeMs'] as num?)?.toInt(),
      openColor: json['openColor'] == null
          ? Colors.green
          : _colorFromJson((json['openColor'] as num).toInt()),
      closedColor: json['closedColor'] == null
          ? Colors.white
          : _colorFromJson((json['closedColor'] as num).toInt()),
      sliderActiveOut: json['sliderActiveOut'] as bool? ?? true,
      sliderLidAngleDegrees:
          (json['sliderLidAngleDegrees'] as num?)?.toDouble() ?? 0.0,
      sliderLidLength: (json['sliderLidLength'] as num?)?.toDouble() ?? 0.55,
      sliderActuationLength:
          (json['sliderActuationLength'] as num?)?.toDouble() ?? 1.0,
      forceOpenKey: json['forceOpenKey'] as String? ?? '',
      forceOpenFeedbackKey: json['forceOpenFeedbackKey'] as String? ?? '',
      forceCloseKey: json['forceCloseKey'] as String? ?? '',
      forceCloseFeedbackKey: json['forceCloseFeedbackKey'] as String? ?? '',
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos']);

Map<String, dynamic> _$ConveyorGateConfigToJson(ConveyorGateConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'gateVariant': _$GateVariantEnumMap[instance.gateVariant]!,
      'side': _$GateSideEnumMap[instance.side]!,
      'stateKey': instance.stateKey,
      'openAngleDegrees': instance.openAngleDegrees,
      'openTimeMs': instance.openTimeMs,
      'closeTimeMs': instance.closeTimeMs,
      'openColor': _colorToJson(instance.openColor),
      'closedColor': _colorToJson(instance.closedColor),
      'sliderActiveOut': instance.sliderActiveOut,
      'sliderLidAngleDegrees': instance.sliderLidAngleDegrees,
      'sliderLidLength': instance.sliderLidLength,
      'sliderActuationLength': instance.sliderActuationLength,
      'forceOpenKey': instance.forceOpenKey,
      'forceOpenFeedbackKey': instance.forceOpenFeedbackKey,
      'forceCloseKey': instance.forceCloseKey,
      'forceCloseFeedbackKey': instance.forceCloseFeedbackKey,
    };

const _$GateVariantEnumMap = {
  GateVariant.pneumatic: 'pneumatic',
  GateVariant.slider: 'slider',
  GateVariant.pusher: 'pusher',
};

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

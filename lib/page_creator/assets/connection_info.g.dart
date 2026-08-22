// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConnectionInfoConfig _$ConnectionInfoConfigFromJson(
        Map<String, dynamic> json) =>
    ConnectionInfoConfig(
      serverAlias: json['serverAlias'] as String? ?? '',
      protocol: $enumDecodeNullable(
              _$ConnectionProtocolEnumMap, json['protocol'],
              unknownValue: ConnectionProtocol.modbus) ??
          ConnectionProtocol.modbus,
    )
      ..variant = json['asset_name'] as String
      ..coordinates =
          Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>)
      ..size = RelativeSize.fromJson(json['size'] as Map<String, dynamic>)
      ..text = json['text'] as String?
      ..textPos = $enumDecodeNullable(_$TextPosEnumMap, json['textPos'])
      ..techDocId = (json['techDocId'] as num?)?.toInt()
      ..plcAssetKey = json['plcAssetKey'] as String?;

Map<String, dynamic> _$ConnectionInfoConfigToJson(
        ConnectionInfoConfig instance) =>
    <String, dynamic>{
      'asset_name': instance.variant,
      'coordinates': instance.coordinates.toJson(),
      'size': instance.size.toJson(),
      'text': instance.text,
      'textPos': _$TextPosEnumMap[instance.textPos],
      'techDocId': instance.techDocId,
      'plcAssetKey': instance.plcAssetKey,
      'serverAlias': instance.serverAlias,
      'protocol': _$ConnectionProtocolEnumMap[instance.protocol]!,
    };

const _$ConnectionProtocolEnumMap = {
  ConnectionProtocol.modbus: 'modbus',
  ConnectionProtocol.opcua: 'opcua',
};

const _$TextPosEnumMap = {
  TextPos.above: 'above',
  TextPos.below: 'below',
  TextPos.left: 'left',
  TextPos.right: 'right',
  TextPos.inside: 'inside',
};

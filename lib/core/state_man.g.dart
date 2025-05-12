// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state_man.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OpcUAConfig _$OpcUAConfigFromJson(Map<String, dynamic> json) => OpcUAConfig()
  ..endpoint = json['endpoint'] as String
  ..username = json['username'] as String?
  ..password = json['password'] as String?;

Map<String, dynamic> _$OpcUAConfigToJson(OpcUAConfig instance) =>
    <String, dynamic>{
      'endpoint': instance.endpoint,
      'username': instance.username,
      'password': instance.password,
    };

StateManConfig _$StateManConfigFromJson(Map<String, dynamic> json) =>
    StateManConfig(
      opcua: OpcUAConfig.fromJson(json['opcua'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$StateManConfigToJson(StateManConfig instance) =>
    <String, dynamic>{
      'opcua': instance.opcua,
    };

NodeIdConfig _$NodeIdConfigFromJson(Map<String, dynamic> json) => NodeIdConfig(
      namespace: (json['namespace'] as num).toInt(),
      identifier: json['identifier'] as String,
    );

Map<String, dynamic> _$NodeIdConfigToJson(NodeIdConfig instance) =>
    <String, dynamic>{
      'namespace': instance.namespace,
      'identifier': instance.identifier,
    };

KeyMappingEntry _$KeyMappingEntryFromJson(Map<String, dynamic> json) =>
    KeyMappingEntry(
      nodeId: json['nodeId'] == null
          ? null
          : NodeIdConfig.fromJson(json['nodeId'] as Map<String, dynamic>),
      collectSize: (json['collectSize'] as num?)?.toInt(),
    )..io = json['io'] as bool?;

Map<String, dynamic> _$KeyMappingEntryToJson(KeyMappingEntry instance) =>
    <String, dynamic>{
      'nodeId': instance.nodeId,
      'collectSize': instance.collectSize,
      'io': instance.io,
    };

KeyMappings _$KeyMappingsFromJson(Map<String, dynamic> json) => KeyMappings(
      nodes: (json['nodes'] as Map<String, dynamic>).map(
        (k, e) =>
            MapEntry(k, KeyMappingEntry.fromJson(e as Map<String, dynamic>)),
      ),
    );

Map<String, dynamic> _$KeyMappingsToJson(KeyMappings instance) =>
    <String, dynamic>{
      'nodes': instance.nodes,
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state_man.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OpcUAConfig _$OpcUAConfigFromJson(Map<String, dynamic> json) => OpcUAConfig()
  ..endpoint = json['endpoint'] as String
  ..username = json['username'] as String?
  ..password = json['password'] as String?
  ..sslCert = const Base64Converter().fromJson(json['ssl_cert'] as String?)
  ..sslKey = const Base64Converter().fromJson(json['ssl_key'] as String?)
  ..serverAlias = json['server_alias'] as String?;

Map<String, dynamic> _$OpcUAConfigToJson(OpcUAConfig instance) =>
    <String, dynamic>{
      'endpoint': instance.endpoint,
      'username': instance.username,
      'password': instance.password,
      'ssl_cert': const Base64Converter().toJson(instance.sslCert),
      'ssl_key': const Base64Converter().toJson(instance.sslKey),
      'server_alias': instance.serverAlias,
    };

StateManConfig _$StateManConfigFromJson(Map<String, dynamic> json) =>
    StateManConfig(
      opcua: (json['opcua'] as List<dynamic>)
          .map((e) => OpcUAConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$StateManConfigToJson(StateManConfig instance) =>
    <String, dynamic>{
      'opcua': instance.opcua.map((e) => e.toJson()).toList(),
    };

OpcUANodeConfig _$OpcUANodeConfigFromJson(Map<String, dynamic> json) =>
    OpcUANodeConfig(
      namespace: (json['namespace'] as num).toInt(),
      identifier: json['identifier'] as String,
    )
      ..arrayIndex = (json['array_index'] as num?)?.toInt()
      ..serverAlias = json['server_alias'] as String?;

Map<String, dynamic> _$OpcUANodeConfigToJson(OpcUANodeConfig instance) =>
    <String, dynamic>{
      'namespace': instance.namespace,
      'identifier': instance.identifier,
      'array_index': instance.arrayIndex,
      'server_alias': instance.serverAlias,
    };

KeyMappingEntry _$KeyMappingEntryFromJson(Map<String, dynamic> json) =>
    KeyMappingEntry(
      opcuaNode: json['opcua_node'] == null
          ? null
          : OpcUANodeConfig.fromJson(
              json['opcua_node'] as Map<String, dynamic>),
      collect: json['collect'] == null
          ? null
          : CollectEntry.fromJson(json['collect'] as Map<String, dynamic>),
    )..io = json['io'] as bool?;

Map<String, dynamic> _$KeyMappingEntryToJson(KeyMappingEntry instance) =>
    <String, dynamic>{
      'opcua_node': instance.opcuaNode,
      'io': instance.io,
      'collect': instance.collect,
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

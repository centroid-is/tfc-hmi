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

ModbusPollGroup _$ModbusPollGroupFromJson(Map<String, dynamic> json) =>
    ModbusPollGroup(
      name: json['name'] as String,
      pollIntervalMs: (json['poll_interval_ms'] as num).toInt(),
    );

Map<String, dynamic> _$ModbusPollGroupToJson(ModbusPollGroup instance) =>
    <String, dynamic>{
      'name': instance.name,
      'poll_interval_ms': instance.pollIntervalMs,
    };

ModbusConfig _$ModbusConfigFromJson(Map<String, dynamic> json) => ModbusConfig(
      host: json['host'] as String? ?? 'localhost',
      port: (json['port'] as num?)?.toInt() ?? 502,
      unitId: (json['unit_id'] as num?)?.toInt() ?? 1,
      pollGroups: (json['poll_groups'] as List<dynamic>?)
          ?.map((e) => ModbusPollGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
      serverAlias: json['server_alias'] as String?,
    );

Map<String, dynamic> _$ModbusConfigToJson(ModbusConfig instance) =>
    <String, dynamic>{
      'host': instance.host,
      'port': instance.port,
      'unit_id': instance.unitId,
      'poll_groups': instance.pollGroups.map((e) => e.toJson()).toList(),
      'server_alias': instance.serverAlias,
    };

ModbusNodeConfig _$ModbusNodeConfigFromJson(Map<String, dynamic> json) =>
    ModbusNodeConfig(
      registerType:
          $enumDecode(_$ModbusRegisterTypeEnumMap, json['register_type']),
      address: (json['address'] as num).toInt(),
      dataType: $enumDecode(_$ModbusDataTypeEnumMap, json['data_type']),
      serverAlias: json['server_alias'] as String?,
      pollGroup: json['poll_group'] as String?,
    );

Map<String, dynamic> _$ModbusNodeConfigToJson(ModbusNodeConfig instance) =>
    <String, dynamic>{
      'register_type': _$ModbusRegisterTypeEnumMap[instance.registerType]!,
      'address': instance.address,
      'data_type': _$ModbusDataTypeEnumMap[instance.dataType]!,
      'server_alias': instance.serverAlias,
      'poll_group': instance.pollGroup,
    };

const _$ModbusRegisterTypeEnumMap = {
  ModbusRegisterType.coil: 'coil',
  ModbusRegisterType.discreteInput: 'discreteInput',
  ModbusRegisterType.holdingRegister: 'holdingRegister',
  ModbusRegisterType.inputRegister: 'inputRegister',
};

const _$ModbusDataTypeEnumMap = {
  ModbusDataType.bit: 'bit',
  ModbusDataType.int16: 'int16',
  ModbusDataType.uint16: 'uint16',
  ModbusDataType.int32: 'int32',
  ModbusDataType.uint32: 'uint32',
  ModbusDataType.float32: 'float32',
  ModbusDataType.int64: 'int64',
  ModbusDataType.uint64: 'uint64',
  ModbusDataType.float64: 'float64',
};

StateManConfig _$StateManConfigFromJson(Map<String, dynamic> json) =>
    StateManConfig(
      opcua: (json['opcua'] as List<dynamic>)
          .map((e) => OpcUAConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      modbus: (json['modbus'] as List<dynamic>?)
              ?.map((e) => ModbusConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$StateManConfigToJson(StateManConfig instance) =>
    <String, dynamic>{
      'opcua': instance.opcua.map((e) => e.toJson()).toList(),
      'modbus': instance.modbus.map((e) => e.toJson()).toList(),
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
      modbusNode: json['modbus_node'] == null
          ? null
          : ModbusNodeConfig.fromJson(
              json['modbus_node'] as Map<String, dynamic>),
      collect: json['collect'] == null
          ? null
          : CollectEntry.fromJson(json['collect'] as Map<String, dynamic>),
    )..io = json['io'] as bool?;

Map<String, dynamic> _$KeyMappingEntryToJson(KeyMappingEntry instance) =>
    <String, dynamic>{
      'opcua_node': instance.opcuaNode?.toJson(),
      'modbus_node': instance.modbusNode?.toJson(),
      'io': instance.io,
      'collect': instance.collect?.toJson(),
    };

KeyMappings _$KeyMappingsFromJson(Map<String, dynamic> json) => KeyMappings(
      nodes: (json['nodes'] as Map<String, dynamic>).map(
        (k, e) =>
            MapEntry(k, KeyMappingEntry.fromJson(e as Map<String, dynamic>)),
      ),
    );

Map<String, dynamic> _$KeyMappingsToJson(KeyMappings instance) =>
    <String, dynamic>{
      'nodes': instance.nodes.map((k, e) => MapEntry(k, e.toJson())),
    };

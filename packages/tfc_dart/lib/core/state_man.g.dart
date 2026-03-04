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

M2400Config _$M2400ConfigFromJson(Map<String, dynamic> json) => M2400Config(
      type: json['type'] as String? ?? 'm2400',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 52211,
    )..serverAlias = json['server_alias'] as String?;

Map<String, dynamic> _$M2400ConfigToJson(M2400Config instance) =>
    <String, dynamic>{
      'type': instance.type,
      'host': instance.host,
      'port': instance.port,
      'server_alias': instance.serverAlias,
    };

M2400NodeConfig _$M2400NodeConfigFromJson(Map<String, dynamic> json) =>
    M2400NodeConfig(
      recordType: $enumDecode(_$M2400RecordTypeEnumMap, json['record_type']),
      field: $enumDecodeNullable(_$M2400FieldEnumMap, json['field']),
      serverAlias: json['server_alias'] as String?,
      statusFilter: (json['status_filter'] as num?)?.toInt(),
    );

Map<String, dynamic> _$M2400NodeConfigToJson(M2400NodeConfig instance) =>
    <String, dynamic>{
      'record_type': _$M2400RecordTypeEnumMap[instance.recordType]!,
      'field': _$M2400FieldEnumMap[instance.field],
      'server_alias': instance.serverAlias,
      'status_filter': instance.statusFilter,
    };

const _$M2400RecordTypeEnumMap = {
  M2400RecordType.recWgt: 'recWgt',
  M2400RecordType.recIntro: 'recIntro',
  M2400RecordType.recStat: 'recStat',
  M2400RecordType.recLua: 'recLua',
  M2400RecordType.recBatch: 'recBatch',
  M2400RecordType.unknown: 'unknown',
};

const _$M2400FieldEnumMap = {
  M2400Field.weight: 'weight',
  M2400Field.unit: 'unit',
  M2400Field.siWeight: 'siWeight',
  M2400Field.output: 'output',
  M2400Field.material: 'material',
  M2400Field.wQuality: 'wQuality',
  M2400Field.wCount: 'wCount',
  M2400Field.length: 'length',
  M2400Field.batchId: 'batchId',
  M2400Field.status: 'status',
  M2400Field.pieces: 'pieces',
  M2400Field.msgId: 'msgId',
  M2400Field.regCmd: 'regCmd',
  M2400Field.key: 'key',
  M2400Field.devId: 'devId',
  M2400Field.devType: 'devType',
  M2400Field.devProg: 'devProg',
  M2400Field.exId: 'exId',
  M2400Field.position: 'position',
  M2400Field.errText: 'errText',
  M2400Field.buttonId: 'buttonId',
  M2400Field.idFamily: 'idFamily',
  M2400Field.tare: 'tare',
  M2400Field.barcode: 'barcode',
  M2400Field.saddles: 'saddles',
  M2400Field.nominal: 'nominal',
  M2400Field.target: 'target',
  M2400Field.fGiveaway: 'fGiveaway',
  M2400Field.vGiveaway: 'vGiveaway',
  M2400Field.tareType: 'tareType',
  M2400Field.serialNumber: 'serialNumber',
  M2400Field.stdDevA: 'stdDevA',
  M2400Field.resultCode: 'resultCode',
  M2400Field.date: 'date',
  M2400Field.time: 'time',
  M2400Field.timeMs: 'timeMs',
  M2400Field.scaleRange: 'scaleRange',
  M2400Field.weighingStatus: 'weighingStatus',
  M2400Field.programId: 'programId',
  M2400Field.programName: 'programName',
  M2400Field.minWeight: 'minWeight',
  M2400Field.maxWeight: 'maxWeight',
  M2400Field.alibi: 'alibi',
  M2400Field.division: 'division',
  M2400Field.recordId: 'recordId',
  M2400Field.rejectReason: 'rejectReason',
  M2400Field.originLabel: 'originLabel',
  M2400Field.tareDevice: 'tareDevice',
  M2400Field.tareAlibi: 'tareAlibi',
  M2400Field.packId: 'packId',
  M2400Field.checksum: 'checksum',
  M2400Field.alibiText: 'alibiText',
};

StateManConfig _$StateManConfigFromJson(Map<String, dynamic> json) =>
    StateManConfig(
      opcua: (json['opcua'] as List<dynamic>)
          .map((e) => OpcUAConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      jbtm: (json['jbtm'] as List<dynamic>?)
              ?.map((e) => M2400Config.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$StateManConfigToJson(StateManConfig instance) =>
    <String, dynamic>{
      'opcua': instance.opcua.map((e) => e.toJson()).toList(),
      'jbtm': instance.jbtm.map((e) => e.toJson()).toList(),
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
      m2400Node: json['m2400_node'] == null
          ? null
          : M2400NodeConfig.fromJson(
              json['m2400_node'] as Map<String, dynamic>),
      collect: json['collect'] == null
          ? null
          : CollectEntry.fromJson(json['collect'] as Map<String, dynamic>),
    )..io = json['io'] as bool?;

Map<String, dynamic> _$KeyMappingEntryToJson(KeyMappingEntry instance) =>
    <String, dynamic>{
      'opcua_node': instance.opcuaNode?.toJson(),
      'm2400_node': instance.m2400Node?.toJson(),
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

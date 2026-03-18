import 'dart:async';
import 'dart:io'
    if (dart.library.js_interop) 'web_stubs/io_stub.dart';
import 'dart:typed_data';
import 'dart:convert';

import 'package:meta/meta.dart'; // Add this import at the top
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'dynamic_value.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'package:jbtm/src/m2400.dart'
    if (dart.library.js_interop) 'web_stubs/jbtm_m2400_stub.dart'
    show M2400RecordType;
import 'package:jbtm/src/m2400_fields.dart'
    if (dart.library.js_interop) 'web_stubs/jbtm_m2400_fields_stub.dart'
    show M2400Field;

import 'package:modbus_client/modbus_client.dart'
    if (dart.library.js_interop) 'web_stubs/modbus_client_stub.dart'
    show ModbusElementType, ModbusEndianness;

import 'collector.dart'
    if (dart.library.js_interop) 'web_stubs/collector_stub.dart';
import 'modbus_client_wrapper.dart'
    if (dart.library.js_interop) 'web_stubs/modbus_client_wrapper_stub.dart'
    show ModbusDataType;
import 'm2400_device_client.dart'
    if (dart.library.js_interop) 'web_stubs/m2400_device_client_stub.dart'
    show M2400DeviceClientAdapter;
import 'modbus_device_client.dart'
    if (dart.library.js_interop) 'web_stubs/modbus_device_client_stub.dart'
    show ModbusDeviceClientAdapter;
import 'opcua_device_client.dart'
    if (dart.library.js_interop) 'web_stubs/opcua_device_client_stub.dart'
    show ClientWrapper, OpcUaDeviceClientAdapter;
import 'preferences.dart'
    if (dart.library.js_interop) 'web_stubs/preferences_stub.dart';

part 'state_man.g.dart';

/// Statistics tracker for runIterate timing
class RunIterateStats {
  final String clientName;
  final Logger _logger = Logger();

  DateTime? _lastCallTime;
  int _callCount = 0;

  // Time between calls (gaps)
  Duration _maxGap = Duration.zero;
  Duration _totalGap = Duration.zero;

  // Execution time
  Duration _maxExecTime = Duration.zero;
  Duration _totalExecTime = Duration.zero;

  // Report interval
  final int _reportInterval = 1000; // Report every N calls

  RunIterateStats(this.clientName);

  void recordCall(Duration execTime) {
    final now = DateTime.now();

    if (_lastCallTime != null) {
      final gap = now.difference(_lastCallTime!);
      _totalGap += gap;
      if (gap > _maxGap) {
        _maxGap = gap;
      }
    }

    _totalExecTime += execTime;
    if (execTime > _maxExecTime) {
      _maxExecTime = execTime;
    }

    _callCount++;
    _lastCallTime = now;

    // Log periodically
    if (_callCount % _reportInterval == 0) {
      _logStats();
    }
  }

  void _logStats() {
    if (_callCount == 0) return;

    final avgGapMs = _callCount > 1
        ? (_totalGap.inMicroseconds / (_callCount - 1) / 1000)
            .toStringAsFixed(2)
        : 'N/A';
    final avgExecMs =
        (_totalExecTime.inMicroseconds / _callCount / 1000).toStringAsFixed(2);

    _logger.i('[$clientName] runIterate stats after $_callCount calls: '
        'gap(avg: ${avgGapMs}ms, max: ${_maxGap.inMilliseconds}ms) '
        'exec(avg: ${avgExecMs}ms, max: ${_maxExecTime.inMilliseconds}ms)');
  }

  void logFinal() {
    _logStats();
  }
}

class Base64Converter implements JsonConverter<Uint8List?, String?> {
  const Base64Converter();

  @override
  Uint8List? fromJson(String? json) {
    if (json == null) return null;
    return base64Decode(json);
  }

  @override
  String? toJson(Uint8List? certificateContents) {
    if (certificateContents == null) return null;
    return base64Encode(certificateContents);
  }
}

@JsonSerializable(explicitToJson: true)
class OpcUAConfig {
  String endpoint = "opc.tcp://localhost:4840";
  String? username;
  String? password;
  @Base64Converter()
  @JsonKey(name: 'ssl_cert')
  Uint8List? sslCert;
  @Base64Converter()
  @JsonKey(name: 'ssl_key')
  Uint8List? sslKey;
  @JsonKey(name: 'server_alias')
  String? serverAlias;

  OpcUAConfig();

  @override
  String toString() {
    return 'OpcUAConfig(endpoint: $endpoint, username: $username, password: $password, sslCert: $sslCert, sslKey: $sslKey)';
  }

  factory OpcUAConfig.fromJson(Map<String, dynamic> json) =>
      _$OpcUAConfigFromJson(json);
  Map<String, dynamic> toJson() => _$OpcUAConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class M2400Config {
  @JsonKey(defaultValue: 'm2400')
  String type;
  String host;
  int port;
  @JsonKey(name: 'server_alias')
  String? serverAlias;

  M2400Config({this.type = 'm2400', this.host = '', this.port = 52211});

  factory M2400Config.fromJson(Map<String, dynamic> json) =>
      _$M2400ConfigFromJson(json);
  Map<String, dynamic> toJson() => _$M2400ConfigToJson(this);

  @override
  String toString() =>
      'M2400Config(type: $type, host: $host, port: $port, alias: $serverAlias)';
}

@JsonSerializable(explicitToJson: true)
class M2400NodeConfig {
  @JsonKey(name: 'record_type')
  M2400RecordType recordType;
  M2400Field? field;
  @JsonKey(name: 'server_alias')
  String? serverAlias;

  /// Optional WeigherStatus code filter (BATCH only).
  /// When set, only BATCH records whose status field matches this code are emitted.
  @JsonKey(name: 'status_filter')
  int? statusFilter;

  M2400NodeConfig({
    required this.recordType,
    this.field,
    this.serverAlias,
    this.statusFilter,
  });

  factory M2400NodeConfig.fromJson(Map<String, dynamic> json) =>
      _$M2400NodeConfigFromJson(json);
  Map<String, dynamic> toJson() => _$M2400NodeConfigToJson(this);

  @override
  String toString() =>
      'M2400NodeConfig(recordType: $recordType, field: $field, alias: $serverAlias, statusFilter: $statusFilter)';
}

// =============================================================================
// Modbus configuration classes (Phase 8)
// =============================================================================

/// Modbus register type for JSON serialization.
///
/// Maps to [ModbusElementType] at runtime via [toModbusElementType] and
/// [fromModbusElementType]. Kept as a separate enum so json_serializable
/// generates camelCase string serialization without depending on the
/// modbus_client package in the serialization layer.
enum ModbusRegisterType {
  coil,
  discreteInput,
  holdingRegister,
  inputRegister;

  /// Converts to the modbus_client library's [ModbusElementType].
  ModbusElementType toModbusElementType() {
    switch (this) {
      case ModbusRegisterType.coil:
        return ModbusElementType.coil;
      case ModbusRegisterType.discreteInput:
        return ModbusElementType.discreteInput;
      case ModbusRegisterType.holdingRegister:
        return ModbusElementType.holdingRegister;
      case ModbusRegisterType.inputRegister:
        return ModbusElementType.inputRegister;
    }
  }

  /// Creates from the modbus_client library's [ModbusElementType].
  static ModbusRegisterType fromModbusElementType(ModbusElementType type) {
    switch (type) {
      case ModbusElementType.coil:
        return ModbusRegisterType.coil;
      case ModbusElementType.discreteInput:
        return ModbusRegisterType.discreteInput;
      case ModbusElementType.holdingRegister:
        return ModbusRegisterType.holdingRegister;
      case ModbusElementType.inputRegister:
        return ModbusRegisterType.inputRegister;
      default:
        throw ArgumentError('Unsupported ModbusElementType: $type');
    }
  }
}

/// Configuration for a named Modbus poll group.
///
/// Poll groups allow registers to be read at different intervals (e.g. fast
/// control loop vs slow diagnostics).
@JsonSerializable(explicitToJson: true)
class ModbusPollGroupConfig {
  String name;
  @JsonKey(name: 'interval_ms')
  int intervalMs;

  ModbusPollGroupConfig({required this.name, this.intervalMs = 1000});

  /// Convenience getter for use with Timer/Duration APIs.
  Duration get interval => Duration(milliseconds: intervalMs);

  factory ModbusPollGroupConfig.fromJson(Map<String, dynamic> json) =>
      _$ModbusPollGroupConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ModbusPollGroupConfigToJson(this);

  @override
  String toString() => 'ModbusPollGroupConfig(name: $name, intervalMs: $intervalMs)';
}

/// Top-level configuration for a single Modbus TCP server connection.
///
/// Parallels [M2400Config] and [OpcUAConfig] in the config hierarchy.
@JsonSerializable(explicitToJson: true)
class ModbusConfig {
  String host;
  int port;
  @JsonKey(name: 'unit_id')
  int unitId;
  @JsonKey(name: 'server_alias')
  String? serverAlias;
  @JsonKey(name: 'poll_groups', defaultValue: [])
  List<ModbusPollGroupConfig> pollGroups;
  @JsonKey(name: 'umas_enabled', defaultValue: false)
  bool umasEnabled;
  @JsonKey(defaultValue: ModbusEndianness.ABCD)
  ModbusEndianness endianness;
  @JsonKey(name: 'address_base', defaultValue: 0)
  int addressBase;

  ModbusConfig({
    this.host = '',
    this.port = 502,
    int unitId = 1,
    this.serverAlias,
    this.pollGroups = const [],
    this.umasEnabled = false,
    this.endianness = ModbusEndianness.ABCD,
    this.addressBase = 0,
  }) : unitId = unitId.clamp(0, 255);

  factory ModbusConfig.fromJson(Map<String, dynamic> json) =>
      _$ModbusConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ModbusConfigToJson(this);

  @override
  String toString() =>
      'ModbusConfig(host: $host, port: $port, unitId: $unitId, alias: $serverAlias, pollGroups: $pollGroups)';
}

/// Per-key configuration that describes which Modbus register a key maps to.
///
/// Parallels [M2400NodeConfig] and [OpcUANodeConfig] in the keymappings.
@JsonSerializable(explicitToJson: true)
class ModbusNodeConfig {
  @JsonKey(name: 'server_alias')
  String? serverAlias;
  @JsonKey(name: 'register_type')
  ModbusRegisterType registerType;
  int address;
  @JsonKey(name: 'data_type')
  ModbusDataType dataType;
  @JsonKey(name: 'poll_group')
  String pollGroup;

  ModbusNodeConfig({
    this.serverAlias,
    required this.registerType,
    required int address,
    this.dataType = ModbusDataType.uint16,
    this.pollGroup = 'default',
  }) : address = address.clamp(0, 65535);

  factory ModbusNodeConfig.fromJson(Map<String, dynamic> json) =>
      _$ModbusNodeConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ModbusNodeConfigToJson(this);

  @override
  String toString() =>
      'ModbusNodeConfig(alias: $serverAlias, registerType: $registerType, address: $address, dataType: $dataType, pollGroup: $pollGroup)';
}

// =============================================================================
// MQTT configuration classes
// =============================================================================

/// Payload interpretation strategy for MQTT messages.
enum MqttPayloadType { json, raw, string }

/// Top-level configuration for a single MQTT broker connection.
///
/// Parallels [OpcUAConfig], [M2400Config], and [ModbusConfig] in the config
/// hierarchy.
@JsonSerializable(explicitToJson: true)
class MqttConfig {
  String host;
  int port;
  @JsonKey(name: 'server_alias')
  String? serverAlias;
  @JsonKey(name: 'use_tls')
  bool useTls;
  @JsonKey(name: 'use_web_socket')
  bool useWebSocket;
  @JsonKey(name: 'ws_path')
  String wsPath;
  String? username;
  String? password;
  @JsonKey(name: 'client_id')
  String? clientId;
  @JsonKey(name: 'keep_alive_period')
  int keepAlivePeriod;

  MqttConfig({
    this.host = '',
    this.port = 1883,
    this.serverAlias,
    this.useTls = false,
    this.useWebSocket = false,
    this.wsPath = '/mqtt',
    this.username,
    this.password,
    this.clientId,
    this.keepAlivePeriod = 60,
  });

  factory MqttConfig.fromJson(Map<String, dynamic> json) =>
      _$MqttConfigFromJson(json);
  Map<String, dynamic> toJson() => _$MqttConfigToJson(this);

  @override
  String toString() =>
      'MqttConfig(host: $host, port: $port, alias: $serverAlias, useTls: $useTls, useWebSocket: $useWebSocket)';
}

/// Per-key configuration that describes which MQTT topic a key maps to.
///
/// Parallels [OpcUANodeConfig], [M2400NodeConfig], and [ModbusNodeConfig] in
/// the keymappings.
@JsonSerializable(explicitToJson: true)
class MqttNodeConfig {
  String topic;
  @JsonKey(defaultValue: 0)
  int qos;
  @JsonKey(name: 'server_alias')
  String? serverAlias;
  @JsonKey(name: 'payload_type', defaultValue: MqttPayloadType.json)
  MqttPayloadType payloadType;

  MqttNodeConfig({
    required this.topic,
    this.qos = 0,
    this.serverAlias,
    this.payloadType = MqttPayloadType.json,
  });

  factory MqttNodeConfig.fromJson(Map<String, dynamic> json) =>
      _$MqttNodeConfigFromJson(json);
  Map<String, dynamic> toJson() => _$MqttNodeConfigToJson(this);

  @override
  String toString() =>
      'MqttNodeConfig(topic: $topic, qos: $qos, alias: $serverAlias, payloadType: $payloadType)';
}

@JsonSerializable(explicitToJson: true)
class StateManConfig {
  List<OpcUAConfig> opcua;
  @JsonKey(defaultValue: [])
  List<M2400Config> jbtm;
  @JsonKey(defaultValue: [])
  List<ModbusConfig> modbus;
  @JsonKey(defaultValue: [])
  List<MqttConfig> mqtt;

  StateManConfig({required this.opcua, this.jbtm = const [], this.modbus = const [], this.mqtt = const []});

  StateManConfig copy() => StateManConfig.fromJson(toJson());

  @override
  String toString() {
    return 'StateManConfig(opcua: ${opcua.toString()}, jbtm: ${jbtm.toString()}, modbus: ${modbus.toString()}, mqtt: ${mqtt.toString()})';
  }

  static StateManConfig fromString(String jsonString) {
    return StateManConfig.fromJson(jsonDecode(jsonString));
  }

  static Future<StateManConfig> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Config file not found: $path');
    }
    final contents = await file.readAsString();
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(contents) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw Exception('Invalid JSON in config file: $path - ${e.message}');
    }
    return StateManConfig.fromJson(json);
  }

  static Future<StateManConfig> fromPrefs(Preferences prefs) async {
    var configJson = await prefs.getString(configKey, secret: true);
    if (configJson == null) {
      configJson = jsonEncode(StateManConfig(opcua: [OpcUAConfig()]).toJson());
      await prefs.setString(configKey, configJson,
          secret: true, saveToDb: false);
    }
    return StateManConfig.fromJson(jsonDecode(configJson));
  }

  Future<void> toPrefs(Preferences prefs) async {
    final configJson = jsonEncode(toJson());
    await prefs.setString(configKey, configJson, secret: true, saveToDb: false);
  }

  factory StateManConfig.fromJson(Map<String, dynamic> json) =>
      _$StateManConfigFromJson(json);
  Map<String, dynamic> toJson() => _$StateManConfigToJson(this);

  static const String configKey = 'state_man_config';
}

@JsonSerializable(explicitToJson: true)
class OpcUANodeConfig {
  int namespace;
  String identifier;
  // I only want to support one dimension arrays, I dont think it is relevant to support multi-dimensional arrays
  @JsonKey(name: 'array_index')
  int? arrayIndex;
  @JsonKey(name: 'server_alias')
  String? serverAlias;

  OpcUANodeConfig({required this.namespace, required this.identifier});

  (NodeId, int?) toNodeId() {
    if (int.tryParse(identifier) != null) {
      return (NodeId.fromNumeric(namespace, int.parse(identifier)), arrayIndex);
    }
    return (NodeId.fromString(namespace, identifier), arrayIndex);
  }

  factory OpcUANodeConfig.fromJson(Map<String, dynamic> json) =>
      _$OpcUANodeConfigFromJson(json);
  Map<String, dynamic> toJson() => _$OpcUANodeConfigToJson(this);

  @override
  String toString() {
    return 'OpcUANodeConfig(namespace: $namespace, identifier: $identifier)';
  }
}

@JsonSerializable(explicitToJson: true)
class KeyMappingEntry {
  @JsonKey(name: 'opcua_node')
  OpcUANodeConfig? opcuaNode;
  @JsonKey(name: 'm2400_node')
  M2400NodeConfig? m2400Node;
  @JsonKey(name: 'modbus_node')
  ModbusNodeConfig? modbusNode;
  @JsonKey(name: 'mqtt_node')
  MqttNodeConfig? mqttNode;
  bool? io; // if true, the key is an IO unit
  CollectEntry? collect;

  /// Optional bit mask for extracting bits from integer values.
  /// When set, reads extract (value & bitMask) >>> bitShift.
  /// Single-bit mask produces bool; multi-bit produces int.
  @JsonKey(name: 'bit_mask')
  int? bitMask;

  /// Bit shift applied after masking (position of lowest set bit in mask).
  @JsonKey(name: 'bit_shift')
  int? bitShift;

  String? get server =>
      opcuaNode?.serverAlias ?? m2400Node?.serverAlias ?? modbusNode?.serverAlias ?? mqttNode?.serverAlias;

  KeyMappingEntry({this.opcuaNode, this.m2400Node, this.modbusNode, this.mqttNode, this.collect, this.bitMask, this.bitShift});

  KeyMappingEntry copyWith({
    OpcUANodeConfig? opcuaNode,
    M2400NodeConfig? m2400Node,
    ModbusNodeConfig? modbusNode,
    MqttNodeConfig? mqttNode,
    CollectEntry? collect,
    int? bitMask,
    int? bitShift,
    bool clearBitMask = false,
  }) {
    return KeyMappingEntry(
      opcuaNode: opcuaNode ?? this.opcuaNode,
      m2400Node: m2400Node ?? this.m2400Node,
      modbusNode: modbusNode ?? this.modbusNode,
      mqttNode: mqttNode ?? this.mqttNode,
      collect: collect ?? this.collect,
      bitMask: clearBitMask ? null : (bitMask ?? this.bitMask),
      bitShift: clearBitMask ? null : (bitShift ?? this.bitShift),
    )..io = io;
  }

  factory KeyMappingEntry.fromJson(Map<String, dynamic> json) =>
      _$KeyMappingEntryFromJson(json);
  Map<String, dynamic> toJson() => _$KeyMappingEntryToJson(this);

  @override
  String toString() {
    return 'KeyMappingEntry(opcuaNode: ${opcuaNode?.toString()}, m2400Node: ${m2400Node?.toString()}, modbusNode: ${modbusNode?.toString()}, mqttNode: ${mqttNode?.toString()}, collect: $collect, io: $io)';
  }
}

@JsonSerializable(explicitToJson: true)
class KeyMappings {
  Map<String, KeyMappingEntry> nodes;

  KeyMappings({required this.nodes});

  (NodeId, int?)? lookupNodeId(String key) {
    return nodes[key]?.opcuaNode?.toNodeId();
  }

  String? lookupServerAlias(String key) {
    final entry = nodes[key];
    return entry?.opcuaNode?.serverAlias ??
        entry?.m2400Node?.serverAlias ??
        entry?.modbusNode?.serverAlias ??
        entry?.mqttNode?.serverAlias;
  }

  String? lookupKey(NodeId nodeId) {
    return nodes.entries.firstWhereOrNull((entry) {
      final result = entry.value.opcuaNode?.toNodeId();
      if (result == null) return false;
      final (entryNodeId, _) = result;
      return entryNodeId == nodeId;
    })?.key;
  }

  Iterable<String> get keys => nodes.keys;

  /// Filter key mappings to only include entries for a specific server alias.
  KeyMappings filterByServer(String? serverAlias) {
    final filtered = Map.fromEntries(
      nodes.entries.where((e) => e.value.server == serverAlias),
    );
    return KeyMappings(nodes: filtered);
  }

  static Future<KeyMappings> fromPrefs(PreferencesApi prefs,
      {bool createDefault = true}) async {
    var keyMappingsJson = await prefs.getString('key_mappings');
    if (keyMappingsJson == null) {
      if (!createDefault) {
        throw Exception(
            'key_mappings not found in preferences and createDefault is false');
      }
      final defaultKeyMappings = KeyMappings(nodes: {
        "exampleKey": KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 42, identifier: "identifier"))
      });
      keyMappingsJson = jsonEncode(defaultKeyMappings.toJson());
      await prefs.setString('key_mappings', keyMappingsJson);
    }
    return KeyMappings.fromJson(jsonDecode(keyMappingsJson));
  }

  static KeyMappings fromString(String jsonString) {
    return KeyMappings.fromJson(jsonDecode(jsonString));
  }

  static Future<KeyMappings> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Key mappings file not found: $path');
    }
    final contents = await file.readAsString();
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(contents) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw Exception(
          'Invalid JSON in key mappings file: $path - ${e.message}');
    }
    return KeyMappings.fromJson(json);
  }

  factory KeyMappings.fromJson(Map<String, dynamic> json) =>
      _$KeyMappingsFromJson(json);
  Map<String, dynamic> toJson() => _$KeyMappingsToJson(this);
}

class StateManException implements Exception {
  final String message;
  StateManException(this.message);
  @override
  String toString() => 'StateManException: $message';
}

class SingleWorker {
  List<Completer<bool>> waiters = [];

  Future<bool> doTheWork() async {
    waiters.add(Completer<bool>());
    if (waiters.length == 1) {
      waiters.last.complete(true);
    }

    return waiters.last.future;
  }

  void complete() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete(false);
      }
    }
    waiters.clear();
  }
}

enum ConnectionStatus { connected, connecting, disconnected }

// ClientWrapper has been moved to opcua_device_client.dart

/// Protocol-agnostic device client interface.
///
/// Abstracts the subscribe/status pattern shared by different device protocols
/// (OPC UA via [ClientWrapper], M2400 via M2400ClientWrapper, etc.).
///
/// Implementations define [subscribableKeys] and [canSubscribe] to declare
/// which keys they handle. [StateMan.subscribe] checks device clients first,
/// falling through to OPC UA if no device client claims the key.
abstract class DeviceClient {
  /// The set of top-level keys this device client can handle.
  Set<String> get subscribableKeys;

  /// Whether this client can handle a subscribe request for [key].
  ///
  /// Should return true for both top-level keys (e.g., 'BATCH') and
  /// dot-notation keys (e.g., 'BATCH.weight') if the root is subscribable.
  bool canSubscribe(String key);

  /// Subscribe to a DynamicValue stream by key.
  Stream<DynamicValue> subscribe(String key);

  /// Read the last known value for [key], or null if unavailable.
  DynamicValue? read(String key);

  /// Current connection status (synchronous).
  ConnectionStatus get connectionStatus;

  /// Stream of connection status changes.
  Stream<ConnectionStatus> get connectionStream;

  /// Start connecting to the device.
  void connect();

  /// Write a value to the device by key.
  Future<void> write(String key, DynamicValue value);

  /// Dispose resources.
  void dispose();
}

class StateMan {
  final logger = Logger();
  final StateManConfig config;
  KeyMappings keyMappings;

  /// Apply bit mask extraction to a raw [DynamicValue].
  ///
  /// Returns the original value unchanged if [bitMask] is null.
  /// Single-bit mask returns bool; multi-bit returns int.
  /// Non-numeric values pass through unchanged.
  static DynamicValue applyBitMask(DynamicValue value, int? bitMask, int? bitShift) {
    if (bitMask == null) return value;
    final raw = value.value;
    if (raw is! num) return value;
    final intValue = raw.toInt();
    final masked = (intValue & bitMask) >>> (bitShift ?? 0);
    // Single-bit: power of two check (exactly one bit set)
    final isSingle = bitMask != 0 && (bitMask & (bitMask - 1)) == 0;
    if (isSingle) {
      return DynamicValue(value: masked != 0, typeId: NodeId.boolean);
    }
    return DynamicValue(value: masked, typeId: value.typeId);
  }

  final List<DeviceClient> deviceClients;
  final Map<String, AutoDisposingStream<DynamicValue>> _subscriptions = {};
  final Map<String, String> _substitutions = {};
  final _subsMap$ = BehaviorSubject<Map<String, String>>.seeded(const {});
  String alias;

  /// Backward-compatible accessor for OPC UA [ClientWrapper] instances.
  ///
  /// Extracts wrappers from the first [OpcUaDeviceClientAdapter] found in
  /// [deviceClients]. Returns an empty list when no OPC UA adapter is present
  /// (e.g. on web or MQTT-only configs).
  List<ClientWrapper> get clients {
    for (final dc in deviceClients) {
      if (dc is OpcUaDeviceClientAdapter) return dc.clients;
    }
    return const [];
  }

  /// Constructor — all protocol access routes through [deviceClients].
  StateMan._({
    required this.config,
    required this.keyMappings,
    required this.alias,
    this.deviceClients = const [],
  });

  /// Create a StateMan with the given device clients.
  ///
  /// The caller is responsible for creating and passing in all device clients
  /// (OPC UA, M2400, Modbus, MQTT). This factory connects them all.
  static Future<StateMan> create({
    required StateManConfig config,
    required KeyMappings keyMappings,
    String alias = '',
    List<DeviceClient> deviceClients = const [],
  }) async {
    final stateMan = StateMan._(
        config: config,
        keyMappings: keyMappings,
        alias: alias,
        deviceClients: deviceClients);

    // Connect device clients
    for (final dc in deviceClients) {
      dc.connect();
    }

    return stateMan;
  }

  void setSubstitution(String key, String value) {
    if (_substitutions[key] == value) return;
    _substitutions[key] = value;
    logger.d('Substitution set: $key = $value');
    _subsMap$.add(Map.unmodifiable(_substitutions));
  }

  Stream<Map<String, String>> get substitutionsChanged => _subsMap$.stream;

  /// Returns an unmodifiable view of the current variable substitutions.
  Map<String, String> get substitutions => Map.unmodifiable(_substitutions);

  String? getSubstitution(String key) {
    return _substitutions[key];
  }

  String resolveKey(String key) {
    if (!key.contains('\$')) return key;

    String resolvedKey = key;
    for (final entry in _substitutions.entries) {
      final variablePattern = '\$${entry.key}';
      if (resolvedKey.contains(variablePattern)) {
        resolvedKey = resolvedKey.replaceAll(variablePattern, entry.value);
      }
    }

    if (resolvedKey != key) {
      logger.d('Resolved key: $key -> $resolvedKey');
    }

    if (resolvedKey.contains('\$')) {
      logger.e('Resolved key still contains \$: $resolvedKey');
    }

    return resolvedKey;
  }

  /// Translate a user-facing key to M2400 subscribe info via key mappings.
  ///
  /// Returns resolved subscribe key, device client, optional status filter,
  /// and optional field name for post-filter extraction. Null if not M2400.
  ({
    String subscribeKey,
    DeviceClient dc,
    int? statusFilter,
    String? fieldName
  })? _resolveM2400Key(String key) {
    final entry = keyMappings.nodes[key];
    if (entry?.m2400Node == null) return null;
    final node = entry!.m2400Node!;

    String? recordKey;
    switch (node.recordType) {
      case M2400RecordType.recBatch:
        recordKey = 'BATCH';
        break;
      case M2400RecordType.recStat:
        recordKey = 'STAT';
        break;
      case M2400RecordType.recIntro:
        recordKey = 'INTRO';
        break;
      case M2400RecordType.recLua:
        recordKey = 'LUA';
        break;
      default:
        return null;
    }

    // When statusFilter is set, subscribe to the full record so we can
    // check the status field before extracting the target field.
    final hasFilter = node.statusFilter != null;
    final fieldName = node.field?.name;
    final subscribeKey =
        (!hasFilter && fieldName != null) ? '$recordKey.$fieldName' : recordKey;

    final alias = node.serverAlias;
    for (final dc in deviceClients) {
      if (dc is M2400DeviceClientAdapter && dc.serverAlias == alias) {
        return (
          subscribeKey: subscribeKey,
          dc: dc,
          statusFilter: node.statusFilter,
          fieldName: hasFilter ? fieldName : null,
        );
      }
    }
    return null;
  }

  /// Find the Modbus [DeviceClient] that owns [key], or null if not a Modbus key.
  DeviceClient? _resolveModbusDeviceClient(String key) {
    final entry = keyMappings.nodes[key];
    if (entry?.modbusNode == null) return null;
    final alias = entry!.modbusNode!.serverAlias;
    for (final dc in deviceClients) {
      if (dc is ModbusDeviceClientAdapter && dc.serverAlias == alias) {
        if (dc.canSubscribe(key)) return dc;
      }
    }
    return null;
  }

  /// Find a [DeviceClient] (e.g. MQTT) that can handle [key], excluding
  /// M2400 and Modbus adapters which are resolved by their own methods.
  /// Returns null if no device client claims the key or if keyMappings has
  /// no mqttNode for this key.
  /// Read a single key from any device client.
  Future<DynamicValue> read(String key) async {
    key = resolveKey(key);

    // Check M2400 key mappings first
    final m2400 = _resolveM2400Key(key);
    if (m2400 != null) {
      var value = m2400.dc.read(m2400.subscribeKey);
      if (value == null) {
        throw StateManException(
            'No cached value for key: "$key" — not found yet');
      }
      if (m2400.statusFilter != null) {
        if (value['status'].asInt != m2400.statusFilter) {
          throw StateManException(
              'No cached value for key: "$key" — status not found yet');
        }
      }
      if (m2400.fieldName != null) {
        value = value[m2400.fieldName!];
      }
      return value;
    }

    // Check Modbus key
    final modbusDc = _resolveModbusDeviceClient(key);
    if (modbusDc != null) {
      final value = modbusDc.read(key);
      if (value == null) {
        throw StateManException('No cached value for key: "$key" -- not polled yet');
      }
      return value;
    }

    // Route to any other device client that can handle this key
    for (final dc in deviceClients) {
      if (dc is M2400DeviceClientAdapter) continue;
      if (dc is ModbusDeviceClientAdapter) continue;
      if (dc.canSubscribe(key)) {
        final value = dc.read(key);
        if (value == null) {
          throw StateManException('No cached value for key: "$key" -- not received yet');
        }
        return value;
      }
    }

    throw StateManException('No device client found for key: "$key"');
  }

  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    final results = <String, DynamicValue>{};

    for (final keyToResolve in keys) {
      try {
        final value = await read(keyToResolve);
        results[resolveKey(keyToResolve)] = value;
      } catch (_) {
        // Skip keys that can't be read
      }
    }

    return results;
  }

  /// Write a value to a device by key.
  Future<void> write(String key, DynamicValue value) async {
    key = resolveKey(key);

    for (final dc in deviceClients) {
      if (dc.canSubscribe(key)) {
        await dc.write(key, value);
        return;
      }
    }

    throw StateManException('No device client found for write key: "$key"');
  }

  /// Subscribe to data changes on a specific key.
  ///
  /// Routes to the appropriate [DeviceClient] based on key mappings.
  Future<Stream<DynamicValue>> subscribe(String key) async {
    key = resolveKey(key);

    // Check M2400 key mappings first (special handling for status filter)
    final m2400 = _resolveM2400Key(key);
    if (m2400 != null) {
      Stream<DynamicValue> stream = m2400.dc.subscribe(m2400.subscribeKey);
      if (m2400.statusFilter != null) {
        stream = stream.where((dv) => dv['status'].asInt == m2400.statusFilter);
      }
      if (m2400.fieldName != null) {
        stream = stream.map((dv) => dv[m2400.fieldName!]);
      }
      return stream;
    }

    // Check Modbus key
    final modbusDc = _resolveModbusDeviceClient(key);
    if (modbusDc != null) {
      return modbusDc.subscribe(key);
    }

    // Route to any device client that can handle this key
    for (final dc in deviceClients) {
      if (dc is M2400DeviceClientAdapter) continue;
      if (dc is ModbusDeviceClientAdapter) continue;
      if (dc.canSubscribe(key)) {
        return dc.subscribe(key);
      }
    }

    // Check if we have an internal subscription (e.g. from addSubscription)
    if (_subscriptions.containsKey(key)) {
      return _subscriptions[key]!.stream;
    }

    // No device client found — return error stream instead of crashing
    return Stream.error(
        StateManException('No device client found for key: "$key"'));
  }

  void updateKeyMappings(KeyMappings newKeyMappings) {
    keyMappings = newKeyMappings;
  }

  List<String> get keys => keyMappings.keys.toList();

  /// Close all connections and dispose resources.
  Future<void> close() async {
    logger.d('Closing connection');

    for (final dc in deviceClients) {
      dc.dispose();
    }

    // Clean up subscriptions
    for (final entry in _subscriptions.values) {
      entry.cancelRawSub();
      entry.closeSubject();
    }
    _subscriptions.clear();

    _subsMap$.close();
  }

  @visibleForTesting
  void addSubscription({
    required String key,
    required Stream<DynamicValue> subscription,
    required DynamicValue? firstValue,
  }) {
    _subscriptions[key] = AutoDisposingStream(key, (key) {
      _subscriptions.remove(key);
      logger.d('Unsubscribed from $key');
    });
    _subscriptions[key]!.subscribe(subscription, firstValue);
  }
}

class AutoDisposingStream<T> {
  final String key;
  final ReplaySubject<T> _subject;
  final Logger _logger = Logger();
  int _listenerCount = 0;
  Timer? _idleTimer;
  StreamSubscription<T>? _rawSub;
  final Function(String key) _onDispose;
  T? _lastValue;
  final Duration idleTimeout;
  AutoDisposingStream(this.key, this._onDispose,
      {this.idleTimeout = const Duration(minutes: 10)})
      : _subject = ReplaySubject<T>(maxSize: 1) {
    // Count UI listeners for idle shutdown:
    _subject
      ..onListen = _handleListen
      ..onCancel = _handleCancel;
  }

  Stream<T> get stream => _subject.stream;

  /// Last value received from the raw stream.
  T? get lastValue => _lastValue;

  /// The raw upstream subscription (for cancellation/replacement).
  StreamSubscription<T>? get rawSub => _rawSub;
  set rawSub(StreamSubscription<T>? value) => _rawSub = value;

  /// Cancel the raw subscription if active.
  void cancelRawSub() {
    _rawSub?.cancel();
    _rawSub = null;
  }

  /// Close the replay subject.
  void closeSubject() => _subject.close();

  void subscribe(Stream<T> raw, T? firstValue) {
    _logger.d('[$key] subscribe() called: '
        'subjectClosed=${_subject.isClosed}, '
        'listeners=$_listenerCount, '
        'hadRawSub=${_rawSub != null}, '
        'hasFirstValue=${firstValue != null}');
    _rawSub?.cancel();
    // wire raw → subject
    _rawSub = raw.listen(
      (value) {
        if (_subject.isClosed) {
          _logger.e(
              '[$key] RAW STREAM emitted value but subject is CLOSED — data lost!');
          return;
        }
        _lastValue = value;
        _subject.add(value);
      },
      onError: (error, stackTrace) {
        _logger.e('[$key] raw stream error: $error');
        if (!_subject.isClosed) {
          _subject.addError(error, stackTrace);
        }
      },
      onDone: () {
        _logger.w('[$key] raw stream DONE — '
            'subject will close! listeners=$_listenerCount, '
            'subjectClosed=${_subject.isClosed}');
        _subject.close();
      },
    );
    _lastValue = firstValue;
    if (firstValue != null) {
      if (_subject.isClosed) {
        _logger.e('[$key] subject is CLOSED, cannot add firstValue!');
      } else {
        _subject.add(firstValue);
        _logger.d('[$key] firstValue pushed to subject');
      }
    }
  }

  void _handleListen() {
    _listenerCount++;
    _idleTimer?.cancel();
    _logger.d('[$key] listener added (count=$_listenerCount)');
  }

  void _handleCancel() {
    _listenerCount--;
    _logger.d('[$key] listener removed (count=$_listenerCount)');
    if (_listenerCount == 0) {
      _logger.w(
          '[$key] no listeners left, starting ${idleTimeout.inSeconds}s idle timer');
      _idleTimer = Timer(idleTimeout, () {
        _logger.w('[$key] idle timer fired — disposing');
        _rawSub?.cancel(); // tear down the OPC-UA monitoredItem
        _onDispose(key); // remove from StateMan._subscriptions
        _subject.close(); // close the replay buffer
      });
    }
  }

  void resendLastValue() {
    if (_lastValue != null) {
      _subject.add(_lastValue!);
    }
  }
}

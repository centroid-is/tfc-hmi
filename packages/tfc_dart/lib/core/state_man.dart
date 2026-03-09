import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:meta/meta.dart'; // Add this import at the top
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'package:jbtm/src/m2400.dart' show M2400RecordType;
import 'package:jbtm/src/m2400_fields.dart' show M2400Field;
import 'package:jbtm/src/m2400_client_wrapper.dart' show M2400ClientWrapper;
import 'package:jbtm/src/msocket.dart' as jbtm show ConnectionStatus;

import 'package:modbus_client/modbus_client.dart' show ModbusElementType;

import 'collector.dart';
import 'modbus_client_wrapper.dart' show ModbusDataType;
import 'modbus_device_client.dart' show ModbusDeviceClientAdapter;
import 'preferences.dart';

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
  String toString() => 'M2400Config(type: $type, host: $host, port: $port, alias: $serverAlias)';
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

  ModbusConfig({
    this.host = '',
    this.port = 502,
    int unitId = 1,
    this.serverAlias,
    this.pollGroups = const [],
    this.umasEnabled = false,
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

@JsonSerializable(explicitToJson: true)
class StateManConfig {
  List<OpcUAConfig> opcua;
  @JsonKey(defaultValue: [])
  List<M2400Config> jbtm;
  @JsonKey(defaultValue: [])
  List<ModbusConfig> modbus;

  StateManConfig({required this.opcua, this.jbtm = const [], this.modbus = const []});

  StateManConfig copy() => StateManConfig.fromJson(toJson());

  @override
  String toString() {
    return 'StateManConfig(opcua: ${opcua.toString()}, jbtm: ${jbtm.toString()}, modbus: ${modbus.toString()})';
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
  bool? io; // if true, the key is an IO unit
  CollectEntry? collect;

  String? get server =>
      opcuaNode?.serverAlias ?? m2400Node?.serverAlias ?? modbusNode?.serverAlias;

  KeyMappingEntry({this.opcuaNode, this.m2400Node, this.modbusNode, this.collect});

  factory KeyMappingEntry.fromJson(Map<String, dynamic> json) =>
      _$KeyMappingEntryFromJson(json);
  Map<String, dynamic> toJson() => _$KeyMappingEntryToJson(this);

  @override
  String toString() {
    return 'KeyMappingEntry(opcuaNode: ${opcuaNode?.toString()}, m2400Node: ${m2400Node?.toString()}, modbusNode: ${modbusNode?.toString()}, collect: $collect, io: $io)';
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
        entry?.modbusNode?.serverAlias;
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

class ClientWrapper {
  final ClientApi client;
  final OpcUAConfig config;
  int? subscriptionId;
  final SingleWorker worker = SingleWorker();
  StreamSubscription? _heartbeatSub;
  int _heartbeatGeneration = 0;
  DateTime? _lastHeartbeatTick;
  bool _inactive = false;
  bool sessionLost = false;
  bool resendOnRecovery;
  final Set<AutoDisposingStream> streams = {};
  final Logger _logger = Logger();

  /// Check if the subscription is dead and needs to be recreated.
  /// Only SubscriptionDeleted (server killed it) and SecureChannelClosed
  /// (connection lost) are fatal — Inactivity is transient and recovers
  /// on its own when the connection stabilises.
  /// Handles both direct type checks AND string representations — the
  /// isolate handler converts errors to strings via error.toString().
  static bool isSubscriptionDead(Object error) {
    if (error is SubscriptionDeleted || error is SecureChannelClosed) {
      return true;
    }
    if (error is String) {
      return error.contains('SubscriptionDeleted') ||
          error.contains('SecureChannelClosed');
    }
    return false;
  }

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final StreamController<ConnectionStatus> _connectionController =
      StreamController<ConnectionStatus>.broadcast();

  ClientWrapper(this.client, this.config, {this.resendOnRecovery = true});

  /// Current connection status (synchronous, always up-to-date).
  ConnectionStatus get connectionStatus => _connectionStatus;

  /// Stream of connection status changes. Subscribe anytime — read
  /// [connectionStatus] for the current value.
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;

  void updateConnectionStatus(ClientState state) {
    final next = _mapState(state);
    if (next == _connectionStatus) return;
    _connectionStatus = next;
    _connectionController.add(next);
  }

  static ConnectionStatus _mapState(ClientState state) {
    if (state.sessionState == SessionState.UA_SESSIONSTATE_ACTIVATED) {
      return ConnectionStatus.connected;
    }
    if (state.channelState == SecureChannelState.UA_SECURECHANNELSTATE_OPEN) {
      return ConnectionStatus.connecting;
    }
    return ConnectionStatus.disconnected;
  }

  void startHeartbeat(int subId) {
    _heartbeatSub?.cancel();
    final serverTimeNode = NodeId.fromNumeric(0, 2258);
    // Generation counter: isolate stream cancel() is async and stale
    // callbacks can fire after stopHeartbeat(). Each callback checks
    // its captured generation against the current one.
    final gen = ++_heartbeatGeneration;
    _logger.i('[${config.endpoint}] Starting heartbeat on sub=$subId');
    _heartbeatSub = client.monitoredItems(
      {serverTimeNode: [AttributeId.UA_ATTRIBUTEID_VALUE]},
      subId,
    ).listen(
      (_) {
        if (gen != _heartbeatGeneration) return;
        _lastHeartbeatTick = DateTime.now();
        if (_inactive) {
          _logger.i('[${config.endpoint}] Heartbeat recovered (sub=$subId)');
          _handleRecovery();
        }
        if (_connectionStatus == ConnectionStatus.disconnected) {
          updateConnectionStatus(ClientState(
            channelState: SecureChannelState.UA_SECURECHANNELSTATE_OPEN,
            sessionState: SessionState.UA_SESSIONSTATE_ACTIVATED,
            recoveryStatus: 0,
          ));
        }
      },
      onError: (error) {
        if (gen != _heartbeatGeneration) return;
        final now = DateTime.now();
        final sinceTick = _lastHeartbeatTick != null
            ? now.difference(_lastHeartbeatTick!).inMilliseconds
            : -1;
        _logger.w('[${config.endpoint}] Heartbeat error (sub=$subId, '
            '${now.toUtc().toIso8601String()}, ${sinceTick}ms since last tick): $error');
        if (error is Inactivity || error.toString().contains('Inactivity')) {
          _inactive = true;
          return;
        }
        if (isSubscriptionDead(error)) {
          _logger.e('[${config.endpoint}] Heartbeat lost (sub=$subId): $error');
          sessionLost = true;
          stopHeartbeat();
        }
      },
    );
  }

  void stopHeartbeat() {
    _heartbeatSub?.cancel();
    _heartbeatSub = null;
  }

  void _handleRecovery() {
    _inactive = false;
    if (resendOnRecovery) {
      for (final s in streams) {
        s.resendLastValue();
      }
    }
  }

  /// Mark session as lost — called by stateStream as fallback when
  /// heartbeat didn't catch it (e.g. session drops before heartbeat started).
  void markSessionLost() => sessionLost = true;

  /// Simulate inactivity for testing.
  @visibleForTesting
  void simulateInactivity() => _inactive = true;

  /// Simulate a fatal heartbeat error (SubscriptionDeleted/SecureChannelClosed).
  @visibleForTesting
  void simulateFatalHeartbeatError() {
    sessionLost = true;
    stopHeartbeat();
  }

  /// Simulate heartbeat tick for testing (triggers recovery if inactive).
  @visibleForTesting
  void simulateHeartbeatTick() {
    if (_inactive) {
      _handleRecovery();
    }
  }

  void dispose() {
    stopHeartbeat();
    _connectionController.close();
  }
}

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

/// Adapter that wraps [M2400ClientWrapper] from the jbtm package as a
/// [DeviceClient] for use in [StateMan].
///
/// Maps jbtm's [jbtm.ConnectionStatus] to state_man's [ConnectionStatus] and
/// delegates subscribe/connect/dispose to the underlying wrapper.
class M2400DeviceClientAdapter implements DeviceClient {
  /// The underlying M2400ClientWrapper from jbtm.
  final M2400ClientWrapper wrapper;

  /// The server alias for this device (from M2400Config).
  final String? serverAlias;

  static const _validKeys = {'BATCH', 'STAT', 'INTRO', 'LUA'};

  M2400DeviceClientAdapter(this.wrapper, {this.serverAlias});

  @override
  Set<String> get subscribableKeys => _validKeys;

  @override
  bool canSubscribe(String key) => _validKeys.contains(key.split('.').first);

  @override
  Stream<DynamicValue> subscribe(String key) => wrapper.subscribe(key);

  @override
  DynamicValue? read(String key) => wrapper.lastValue(key);

  @override
  ConnectionStatus get connectionStatus =>
      _mapStatus(wrapper.status);

  @override
  Stream<ConnectionStatus> get connectionStream =>
      wrapper.statusStream.map(_mapStatus);

  @override
  Future<void> write(String key, DynamicValue value) {
    throw UnsupportedError('M2400 does not support writes');
  }

  @override
  void connect() => wrapper.connect();

  @override
  void dispose() => wrapper.dispose();

  /// Map jbtm's ConnectionStatus to state_man's ConnectionStatus.
  static ConnectionStatus _mapStatus(jbtm.ConnectionStatus s) {
    switch (s) {
      case jbtm.ConnectionStatus.connected:
        return ConnectionStatus.connected;
      case jbtm.ConnectionStatus.connecting:
        return ConnectionStatus.connecting;
      case jbtm.ConnectionStatus.disconnected:
        return ConnectionStatus.disconnected;
    }
  }
}

/// Create [DeviceClient] instances for each [M2400Config] in the list.
///
/// Each M2400Config produces one [M2400DeviceClientAdapter] wrapping an
/// [M2400ClientWrapper]. The caller is responsible for calling [connect()]
/// and [dispose()] on the returned clients.
List<DeviceClient> createM2400DeviceClients(List<M2400Config> configs) {
  return configs.map((config) {
    final wrapper = M2400ClientWrapper(config.host, config.port);
    return M2400DeviceClientAdapter(wrapper, serverAlias: config.serverAlias);
  }).toList();
}

class StateMan {
  final logger = Logger();
  final StateManConfig config;
  KeyMappings keyMappings;
  final List<ClientWrapper> clients;
  final List<DeviceClient> deviceClients;
  final Map<String, AutoDisposingStream<DynamicValue>> _subscriptions = {};
  bool _shouldRun = true;
  final Map<String, String> _substitutions = {};
  final _subsMap$ = BehaviorSubject<Map<String, String>>.seeded(const {});
  String alias;

  /// Constructor requires the server endpoint.
  StateMan._({
    required this.config,
    required this.keyMappings,
    required this.clients,
    required this.alias,
    this.deviceClients = const [],
  }) {
    for (final wrapper in clients) {
      if (wrapper.client is Client) {
        // spawn a background task to keep the client active
        () async {
          final clientref = wrapper.client as Client;
          final stats =
              RunIterateStats("${wrapper.config.endpoint} \"$alias\"");
          while (_shouldRun) {
            clientref.connect(wrapper.config.endpoint).onError(
                (e, stacktrace) => logger
                    .e('Failed to connect to ${wrapper.config.endpoint}: $e'));
            while (_shouldRun) {
              final startTime = DateTime.now();
              final continueRunning =
                  clientref.runIterate(const Duration(milliseconds: 10));
              final execTime = DateTime.now().difference(startTime);
              stats.recordCall(execTime);
              if (!continueRunning) break;
              await Future.delayed(const Duration(milliseconds: 10));
            }
            stats.logFinal();
            logger.e('Disconnecting client');
            clientref.disconnect();
            await Future.delayed(const Duration(milliseconds: 1000));
          }
          logger.e('StateMan background run iterate task exited');
        }();
      }
      if (wrapper.client is ClientIsolate) {
        final clientref = wrapper.client as ClientIsolate;
        () async {
          while (_shouldRun) {
            try {
              clientref.connect(wrapper.config.endpoint).onError(
                  (e, stacktrace) => logger.e(
                      'Failed to connect to ${wrapper.config.endpoint}: $e'));
              await clientref.runIterate();
            } catch (error) {
              logger.e("run iterate error: $error");
              try {
                // try to disconnect
                await clientref.disconnect();
              } catch (_) {}
              // Throttle if often occuring error
              await Future.delayed(const Duration(seconds: 1));
            }
          }
        }();
      }

      SecureChannelState? lastChannelState;
      DateTime? channelOpenedAt;
      final channelLifetimeSec = 60; // 1 minute as configured

      wrapper.client.stateStream.listen((value) {
        wrapper.updateConnectionStatus(value);
        final now = DateTime.now();

        // Log SecureChannel state transitions with timestamps
        if (value.channelState != lastChannelState) {
          final timeSinceOpen = channelOpenedAt != null
              ? now.difference(channelOpenedAt!).inSeconds
              : 0;
          logger.i(
              '[$alias ${wrapper.config.endpoint}] SecureChannel state: ${lastChannelState?.name} -> ${value.channelState.name} '
              '(session: ${value.sessionState.name}, recovery: ${value.recoveryStatus}) '
              '[uptime: ${timeSinceOpen}s]');

          if (value.channelState ==
              SecureChannelState.UA_SECURECHANNELSTATE_OPEN) {
            channelOpenedAt = now;
            logger.i(
                '[$alias ${wrapper.config.endpoint}] Channel opened at $now, renewal expected at ~${channelLifetimeSec * 0.75}s');
          }

          lastChannelState = value.channelState;
        }

        if (value.channelState ==
            SecureChannelState.UA_SECURECHANNELSTATE_CLOSED) {
          final timeSinceOpen = channelOpenedAt != null
              ? now.difference(channelOpenedAt!).inSeconds
              : 0;
          logger.e(
              '[$alias ${wrapper.config.endpoint}] Channel closed after ${timeSinceOpen}s (expected lifetime: ${channelLifetimeSec}s, '
              'renewal window: ${channelLifetimeSec * 0.75}s-${channelLifetimeSec}s)');
          channelOpenedAt = null;
        }
        // Fallback: treat as session loss if wrapper had a subscription
        // (heartbeat may have already set sessionLost via fatal error)
        if (value.sessionState ==
                SessionState.UA_SESSIONSTATE_CREATE_REQUESTED &&
            wrapper.subscriptionId != null) {
          logger.e('[$alias ${wrapper.config.endpoint}] Session lost!');
          wrapper.markSessionLost();
        }
        if (value.sessionState == SessionState.UA_SESSIONSTATE_ACTIVATED) {
          if (wrapper.sessionLost) {
            logger.e(
                '[$alias ${wrapper.config.endpoint}] Session lost, resubscribing (old sub=${wrapper.subscriptionId})');
            wrapper.sessionLost = false;
            wrapper.subscriptionId = null;
            wrapper.stopHeartbeat();
            // Only resubscribe keys belonging to this wrapper
            final lostAlias = wrapper.config.serverAlias;
            final keysToResub = _subscriptions.values
                .where((e) => keyMappings.lookupServerAlias(e.key) == lostAlias)
                .map((e) => e.key)
                .toList();
            logger.i(
                '[$alias ${wrapper.config.endpoint}] Resubscribing ${keysToResub.length} keys');

            // Phase 1: Cancel ALL old raw subscriptions before creating
            // any new ones. This queues all DeleteMonitoredItemsRequests
            // in the native layer synchronously. By doing all cancels
            // first, we prevent cross-key monId collision: after session
            // loss the server assigns fresh monIds (1, 2, 3…) that may
            // collide with OLD monIds captured in other keys' cancel
            // closures, so a stale delete for key A could destroy key B's
            // newly created item if creates and deletes are interleaved.
            for (final key in keysToResub) {
              final ads = _subscriptions[key];
              logger.d('[$alias] resub $key: exists=${ads != null}, '
                  'hasRawSub=${ads?._rawSub != null}');
              if (ads != null && ads._rawSub != null) {
                final oldSub = ads._rawSub;
                ads._rawSub = null;
                oldSub!.cancel(); // fire-and-forget; queues delete via FFI
              }
            }

            // Phase 2: Now create new monitored items. All deletes are
            // already queued and will be sent before any creates because
            // runIterate hasn't had a chance to run yet (no await above).
            for (final key in keysToResub) {
              _monitor(key, resub: true);
            }
          }
        }
      }).onError((e, s) {
        logger.e('[$alias] Failed to listen to state stream: $e, $s');
      });
    }

  }



  static Future<StateMan> create({
    required StateManConfig config,
    required KeyMappings keyMappings,
    bool useIsolate = true,
    String alias = '',
    List<DeviceClient> deviceClients = const [],
    bool resendOnRecovery = true,
  }) async {
    // Example directory: /Users/jonb/Library/Containers/is.centroid.sildarvinnsla.skammtalina/Data/Documents/certs
    List<ClientWrapper> clients = [];
    for (final opcuaConfig in config.opcua) {
      Uint8List? cert;
      Uint8List? key;
      MessageSecurityMode securityMode =
          MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE;
      if (opcuaConfig.sslCert != null && opcuaConfig.sslKey != null) {
        cert = opcuaConfig.sslCert!;
        key = opcuaConfig.sslKey!;
        securityMode =
            MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT;
      }
      String? username;
      String? password;
      if (opcuaConfig.username != null && opcuaConfig.password != null) {
        username = opcuaConfig.username;
        password = opcuaConfig.password;
      }
      clients.add(ClientWrapper(useIsolate
              ? await ClientIsolate.create(
                  username: username,
                  password: password,
                  certificate: cert,
                  privateKey: key,
                  securityMode: securityMode,
                  logLevel: LogLevel.UA_LOGLEVEL_INFO,
                  secureChannelLifeTime: Duration(
                      minutes:
                          1), // TODO can I reproduce the problem more often
                )
              : Client(
                  username: username,
                  password: password,
                  certificate: cert,
                  privateKey: key,
                  securityMode: securityMode,
                  logLevel: LogLevel.UA_LOGLEVEL_INFO,
                  secureChannelLifeTime: Duration(
                      minutes:
                          1), // TODO can I reproduce the problem more often
                ),
          opcuaConfig,
          resendOnRecovery: resendOnRecovery,
      ));
    }
    final stateMan = StateMan._(
        config: config,
        keyMappings: keyMappings,
        clients: clients,
        alias: alias,
        deviceClients: deviceClients);

    // Connect device clients
    for (final dc in deviceClients) {
      dc.connect();
    }

    return stateMan;
  }

  ClientWrapper _getClientWrapper(String key) {
    // This throws if the key is not found
    // Be mindful that null == null is true
    return clients.firstWhere((wrapper) =>
        wrapper.config.serverAlias == keyMappings.lookupServerAlias(key));
  }

  void setSubstitution(String key, String value) {
    if (_substitutions[key] == value) return;
    _substitutions[key] = value;
    logger.d('Substitution set: $key = $value');
    _subsMap$.add(Map.unmodifiable(_substitutions));
  }

  Stream<Map<String, String>> get substitutionsChanged => _subsMap$.stream;

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
  ({String subscribeKey, DeviceClient dc, int? statusFilter, String? fieldName})?
      _resolveM2400Key(String key) {
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
    final subscribeKey = (!hasFilter && fieldName != null)
        ? '$recordKey.$fieldName'
        : recordKey;

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

  /// Example: read("myKey")
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

    // Fall through to OPC UA
    try {
      final client = _getClientWrapper(key).client;
      final nodeId = _lookupNodeId(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      final (id, idx) = nodeId;
      await client.awaitConnect();
      final value = await client.read(id);
      if (idx != null) {
        return value[idx];
      }
      return value;
    } catch (e) {
      throw StateManException('Failed to read key: \"$key\": $e');
    }
  }

  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    final results = <String, DynamicValue>{};

    // Separate DeviceClient keys from OPC UA keys
    final opcuaKeys = <String>[];
    for (final keyToResolve in keys) {
      final key = resolveKey(keyToResolve);

      // Check Modbus
      final modbusDc = _resolveModbusDeviceClient(key);
      if (modbusDc != null) {
        final value = modbusDc.read(key);
        if (value != null) results[key] = value;
        continue;
      }

      // Check M2400
      final m2400 = _resolveM2400Key(key);
      if (m2400 != null) {
        final value = m2400.dc.read(m2400.subscribeKey);
        if (value != null) {
          var result = value;
          if (m2400.fieldName != null) result = result[m2400.fieldName!];
          results[key] = result;
        }
        continue;
      }

      opcuaKeys.add(key);
    }

    // Process remaining OPC UA keys
    final parameters = <ClientApi, Map<NodeId, List<AttributeId>>>{};

    for (final key in opcuaKeys) {
      final client = _getClientWrapper(key).client;
      final nodeId = _lookupNodeId(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      final (id, idx) = nodeId;
      parameters[client] = {
        id: [
          AttributeId.UA_ATTRIBUTEID_DESCRIPTION,
          AttributeId.UA_ATTRIBUTEID_DISPLAYNAME,
          AttributeId.UA_ATTRIBUTEID_DATATYPE,
          AttributeId.UA_ATTRIBUTEID_VALUE,
        ]
      };
    }

    for (final pair in parameters.entries) {
      final client = pair.key;
      final parameters = pair.value;
      await client.awaitConnect();
      final res = await client.readAttribute(parameters);
      results.addAll(res.map((nodeId, value) {
        final key = keyMappings.lookupKey(nodeId);
        if (key == null) {
          throw StateManException("Key: \"$key\" not found");
        }
        // todo refactor this to not be so ugly
        final foo = _lookupNodeId(key);
        if (foo == null) {
          throw StateManException("Weird error:Key: \"$key\" not found");
        }
        final (_, idx) = foo;
        if (idx != null) {
          return MapEntry(key, value[idx]);
        }
        return MapEntry(key, value);
      }));
    }
    return results;
  }

  /// Example: write("myKey", DynamicValue(value: 42, typeId: NodeId.int16))
  Future<void> write(String key, DynamicValue value) async {
    key = resolveKey(key);

    // Check Modbus (and other DeviceClient protocols)
    final modbusDc = _resolveModbusDeviceClient(key);
    if (modbusDc != null) {
      await modbusDc.write(key, value);
      return;
    }

    try {
      final client = _getClientWrapper(key).client;
      final nodeId = _lookupNodeId(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      final (id, idx) = nodeId;
      await client.awaitConnect();
      if (idx != null) {
        // a bit special, we need to read to be able to write
        // not sure I like this
        final readValue = await client.read(id);
        readValue[idx] = value;
        await client.write(id, readValue);
        return;
      }
      await client.write(id, value);
    } catch (e) {
      throw StateManException('Failed to write node: \"$key\": $e');
    }
  }

  /// Subscribe to data changes on a specific node with type safety.
  /// Returns a Stream that can be cancelled to stop the subscription.
  ///
  /// Routes to [DeviceClient] instances first (e.g., M2400), falling through
  /// to OPC UA [_monitor] if no device client claims the key.
  ///
  /// Example: subscribe("myIntKey") or subscribe("BATCH.weight")
  Future<Stream<DynamicValue>> subscribe(String key) async {
    key = resolveKey(key);

    // Check M2400 key mappings first
    final m2400 = _resolveM2400Key(key);
    if (m2400 != null) {
      Stream<DynamicValue> stream = m2400.dc.subscribe(m2400.subscribeKey);
      if (m2400.statusFilter != null) {
        stream = stream.where(
            (dv) => dv['status'].asInt == m2400.statusFilter);
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

    // Fall through to OPC UA
    return _monitor(key);
  }

  void updateKeyMappings(KeyMappings newKeyMappings) {
    keyMappings = newKeyMappings;
  }

  List<String> get keys => keyMappings.keys.toList();

  /// Close the connection to the server.
  Future<void> close() async {
    _shouldRun = false;
    logger.d('Closing connection');

    // Dispose device clients (M2400, etc.)
    for (final dc in deviceClients) {
      dc.dispose();
    }

    for (final wrapper in clients) {
      try {
        if (wrapper.client is ClientIsolate) {
          await (wrapper.client as ClientIsolate).disconnect();
        } else {
          (wrapper.client as Client).disconnect();
        }
      } catch (_) {}
      wrapper.client.delete();
      wrapper.dispose();
    }
    // Clean up subscriptions
    for (final entry in _subscriptions.values) {
      entry._rawSub?.cancel();
      entry._subject.close();
    }
    _subscriptions.clear();

    _subsMap$.close();
  }

  (NodeId, int?)? _lookupNodeId(String key) {
    return keyMappings.lookupNodeId(key);
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

  Future<Stream<DynamicValue>> _monitor(String key,
      {bool resub = false}) async {
    if (_subscriptions.containsKey(key) && !resub) {
      return _subscriptions[key]!.stream;
    }

    logger.d(
        '[$alias] _monitor($key, resub=$resub) hasExisting=${_subscriptions.containsKey(key)}');

    // Register entry synchronously before any await so concurrent
    // callers for the same key hit the early return above.
    if (!_subscriptions.containsKey(key)) {
      final ads = AutoDisposingStream<DynamicValue>(key, (key) {
        _subscriptions.remove(key);
        // Remove from wrapper's stream set on disposal
        for (final w in clients) {
          w.streams.remove(_subscriptions[key]);
        }
        logger.d('Unsubscribed from $key');
      });
      _subscriptions[key] = ads;
      try {
        _getClientWrapper(key).streams.add(ads);
      } catch (_) {
        // No wrapper for this key (e.g. addSubscription path)
      }
    }

    late ClientApi client;
    try {
      client = _getClientWrapper(key).client;
      await client.awaitConnect();
    } catch (e) {
      logger.e('Failed to connect to client for key: "$key": $e');
      return Stream.error(
          StateManException('Failed to connect to client for key: "$key": $e'));
    }

    final nodeId = _lookupNodeId(key);
    if (nodeId == null) {
      throw StateManException('Key: "$key" not found');
    }
    final (id, idx) = nodeId;

    int retries = 0;
    while (_shouldRun) {
      final wrapper = _getClientWrapper(key);
      try {
        // Cancel any leftover subscription from a previous failed attempt
        // so we don't leak monitored items while retrying.
        _subscriptions[key]?._rawSub?.cancel();
        _subscriptions[key]?._rawSub = null;

        await client.awaitConnect();

        if (wrapper.subscriptionId == null &&
            await wrapper.worker.doTheWork()) {
          try {
            // keepAliveCount=30 → inactivity after (100ms×30)+5s ≈ 8s.
            // Tolerates intermittent packet loss on unstable connections.
            wrapper.subscriptionId = await client.subscriptionCreate(
              requestedMaxKeepAliveCount: 30,
            );
            logger.i(
                '[$alias ${wrapper.config.endpoint}] Created subscription ${wrapper.subscriptionId}');
            wrapper.startHeartbeat(wrapper.subscriptionId!);
          } catch (e) {
            logger.e('Failed to create subscription: $e');
          } finally {
            wrapper.worker.complete();
          }
        }
        if (wrapper.subscriptionId == null) {
          continue;
        }

        final ads = _subscriptions[key]!;
        final hadPrevious = ads._rawSub != null;

        logger.d('[$alias] Creating monitored items for $key on sub=${wrapper.subscriptionId}');

        var stream = client.monitor(id, wrapper.subscriptionId!);
        if (idx != null) {
          stream = stream.map((value) => value[idx]);
        }

        // Wait for monitor to deliver first value. No asBroadcastStream()
        // needed — subscribe() holds _rawSub, and cancel propagates
        // properly to delete monitored items on retry.
        final firstEmission = Completer<void>();
        final wrappedStream = stream.map((value) {
          if (!firstEmission.isCompleted) firstEmission.complete();
          return value;
        });
        ads.subscribe(wrappedStream, null);
        await firstEmission.future.timeout(const Duration(seconds: 5));
        logger.i('[$alias] Subscribed $key (replaced previous: $hadPrevious)');

        return ads.stream;
      } catch (e) {
        retries++;
        if (retries > 10) {
          logger.w('Failed to get initial value for $key: $e');
          retries = 0;
        }
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
    }
    throw StateManException('StateMan closed while monitoring "$key"');
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

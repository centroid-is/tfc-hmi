import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:modbus_client/modbus_client.dart' show ModbusEndianness;
import 'package:modbus_client_tcp/modbus_client_tcp.dart' show ModbusClientTcp;
import 'package:rxdart/rxdart.dart' show BehaviorSubject;
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart'
    show ConnectionStatus, DeviceClient, KeyMappings, ModbusConfig, ModbusNodeConfig, StateMan;
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart'
    show TypedVariableValue, UmasException;

/// Adapter that wraps [ModbusClientWrapper] as a [DeviceClient] for use in
/// [StateMan].
///
/// Translates between [ModbusClientWrapper]'s `Object?` value streams and the
/// [DynamicValue]-based [DeviceClient] interface. Uses [ModbusRegisterSpec]
/// metadata (not runtime type inference) to assign correct [NodeId] typeIds.
///
/// B-1/B-2 (v1.1.x): when an entry has `variableName != null` and the
/// server has `umasEnabled == true`, reads + writes route through a
/// lazily-created per-adapter [UmasClient] keyed off the symbol name
/// rather than the Modbus address. See [_getUmasClient].
class ModbusDeviceClientAdapter implements DeviceClient {
  /// The underlying Modbus transport wrapper.
  final ModbusClientWrapper wrapper;

  /// Optional alias for display/logging purposes.
  final String? serverAlias;

  /// Register specs keyed by their subscription key.
  final Map<String, ModbusRegisterSpec> _specs;

  /// UMAS variable names per key (null for keys that use classic Modbus
  /// addressing). Populated from `KeyMappingEntry.variableName` at
  /// adapter construction.
  final Map<String, String?> _variableNames;

  /// True when this adapter's server has `umasEnabled == true` in its
  /// [ModbusConfig]. Determines whether variableName-bearing keys can
  /// route by name; when false they surface as errors per B-1.
  final bool umasEnabled;

  /// Last-known typed UMAS reads, mirroring [ModbusClientWrapper]'s
  /// last-cached-value semantics for keys whose data has not yet been
  /// polled. Updated by [read]/[subscribe] when they fire successfully.
  final Map<String, DynamicValue> _umasLastValues = {};

  /// Long-lived per-key broadcast subjects for UMAS-by-name keys (F-1).
  /// [subscribe] hands out the subject's stream and the subject stays
  /// open for the lifetime of the adapter. Every successful
  /// [readUmasVariable] adds the fresh [DynamicValue] so subscribers
  /// see updates without the stream completing. Disposed in [dispose].
  final Map<String, BehaviorSubject<DynamicValue>> _umasSubjects = {};

  /// Lazy UMAS client. Re-created when the underlying
  /// [ModbusClientWrapper.client] changes (reconnect).
  UmasClient? _umasClient;
  ModbusClientTcp? _umasClientFor;

  ModbusDeviceClientAdapter(
    this.wrapper, {
    required Map<String, ModbusRegisterSpec> specs,
    this.serverAlias,
    Map<String, String?> variableNames = const {},
    this.umasEnabled = false,
  })  : _specs = Map.unmodifiable(specs),
        _variableNames = Map.unmodifiable(variableNames);

  /// All keys claimed by this adapter — the union of classic-Modbus
  /// specs and UMAS-by-name keys.
  @override
  Set<String> get subscribableKeys =>
      {..._specs.keys, ..._variableNames.keys.where((k) => _variableNames[k] != null)};

  @override
  bool canSubscribe(String key) =>
      _specs.containsKey(key) ||
      (_variableNames[key] != null);

  /// Returns the UMAS variable name for [key], or null if [key] is not
  /// routed by name.
  String? variableNameFor(String key) => _variableNames[key];

  /// Get or lazily construct a UmasClient bound to the wrapper's current
  /// TCP client. Returns null if the wrapper is disconnected (no
  /// underlying ModbusClientTcp yet).
  UmasClient? _getUmasClient() {
    final tcp = wrapper.client;
    if (tcp == null) {
      // Connection torn down — drop the stale client so the next
      // successful reconnect rebuilds it against the fresh socket.
      _umasClient?.dispose();
      _umasClient = null;
      _umasClientFor = null;
      return null;
    }
    if (_umasClient != null && identical(_umasClientFor, tcp)) {
      return _umasClient;
    }
    _umasClient?.dispose();
    _umasClient = UmasClient(sendFn: tcp.send, unitId: wrapper.unitId);
    _umasClientFor = tcp;
    return _umasClient;
  }

  @override
  Stream<DynamicValue> subscribe(String key) {
    // UMAS-by-name routing (F-1): return a long-lived BehaviorSubject
    // per key so subscribers don't see `onDone` after a single emit.
    // The subject is seeded with the most-recent cached value (if any)
    // and stays open for the adapter's lifetime. Every successful
    // [readUmasVariable] pushes the fresh DynamicValue. MonitorPlc-
    // driven streaming polling is a v1.2 follow-up; see B-4 TODO at
    // the bottom of this file.
    final variableName = _variableNames[key];
    if (variableName != null) {
      return _umasSubjectFor(key).stream;
    }
    final spec = _specs[key];
    if (spec == null) throw ArgumentError('Unknown Modbus key: $key');
    return wrapper.subscribe(spec).map((v) => _toDynamicValue(v, spec));
  }

  /// Get-or-create the long-lived [BehaviorSubject] for a UMAS-by-name
  /// [key]. Seeded with the cached last value when present (so a fresh
  /// subscriber sees the most-recent typed read), otherwise unseeded.
  /// Reused across subscribe/unsubscribe cycles for the same key.
  BehaviorSubject<DynamicValue> _umasSubjectFor(String key) {
    final existing = _umasSubjects[key];
    if (existing != null && !existing.isClosed) return existing;
    final cached = _umasLastValues[key];
    final subject = cached != null
        ? BehaviorSubject<DynamicValue>.seeded(cached)
        : BehaviorSubject<DynamicValue>();
    _umasSubjects[key] = subject;
    return subject;
  }

  @override
  DynamicValue? read(String key) {
    final variableName = _variableNames[key];
    if (variableName != null) {
      // Synchronous reads return the last cached typed value; live
      // reads happen via [readUmasVariable] (await). The async fetch
      // is wired from StateMan.read() which already awaits and so can
      // call the typed path; this synchronous fallback exists for
      // [readMany] which only consults the cache.
      return _umasLastValues[key];
    }
    final spec = _specs[key];
    if (spec == null) return null;
    final raw = wrapper.read(key);
    if (raw == null) return null;
    return _toDynamicValue(raw, spec);
  }

  /// Read a single UMAS-by-name key. Throws [StateError] if [key] is
  /// not routed by name. Throws [UmasException] when the server has
  /// `umasEnabled == false` (B-1 contract) or when the underlying
  /// PLC read fails. Caches the typed result for the next [read].
  Future<DynamicValue> readUmasVariable(String key) async {
    final variableName = _variableNames[key];
    if (variableName == null) {
      throw StateError('readUmasVariable: key "$key" is not UMAS-by-name');
    }
    if (!umasEnabled) {
      throw UmasException(
        errorCode: 0,
        message: "Server '${serverAlias ?? '<unknown>'}' does not have UMAS "
            "enabled — variable name '$variableName' cannot be read",
      );
    }
    final umas = _getUmasClient();
    if (umas == null) {
      throw StateError(
          'readUmasVariable: server "${serverAlias ?? '<unknown>'}" not connected');
    }
    // Prime the session so blockCrcs is populated before readVariable.
    await umas.readPlcStatus();
    final typed = await umas.readVariableByName(variableName);
    final dv = _typedVariableToDynamicValue(typed);
    _umasLastValues[key] = dv;
    // F-1: push the fresh value to any active subscribers so
    // StreamBuilder / StreamProvider keep updating across reads. Only
    // forward when a subject already exists — don't materialize one on
    // every read.
    final subject = _umasSubjects[key];
    if (subject != null && !subject.isClosed) {
      subject.add(dv);
    }
    return dv;
  }

  /// Write a single UMAS-by-name key. Same UX contract as
  /// [readUmasVariable]: throws [UmasException] when the server has
  /// `umasEnabled == false`, [StateError] when the key is not routed by
  /// name or when the server is disconnected.
  Future<void> writeUmasVariable(String key, DynamicValue value) async {
    final variableName = _variableNames[key];
    if (variableName == null) {
      throw StateError('writeUmasVariable: key "$key" is not UMAS-by-name');
    }
    if (!umasEnabled) {
      throw UmasException(
        errorCode: 0,
        message: "Server '${serverAlias ?? '<unknown>'}' does not have UMAS "
            "enabled — variable name '$variableName' cannot be written",
      );
    }
    final umas = _getUmasClient();
    if (umas == null) {
      throw StateError(
          'writeUmasVariable: server "${serverAlias ?? '<unknown>'}" not connected');
    }
    await umas.readPlcStatus();
    // Encode via the resolved symbol so the byte layout matches the
    // PLC's declared type. `writeVariableByName` runs the encode via
    // `VariableWriteRef.fromVariable` -> `encodeVariableValue`.
    await umas.writeVariableByName(variableName, value.value);
  }

  /// Convert a TypedVariableValue from UMAS to a DynamicValue with the
  /// correct [NodeId] type id. Best-effort mapping — STRING / BYTE
  /// strings preserve their parsed Dart value. Unknown UMAS type names
  /// fall back to `NodeId.byte` because [DynamicValue] requires a
  /// non-null typeId; the raw value stays untouched so the consumer
  /// can still inspect it.
  static DynamicValue _typedVariableToDynamicValue(TypedVariableValue t) {
    final upper = t.typeName.toUpperCase();
    final typeId = switch (upper) {
      'BOOL' || 'EBOOL' => NodeId.boolean,
      'INT' => NodeId.int16,
      'UINT' || 'WORD' => NodeId.uint16,
      'DINT' || 'TIME' => NodeId.int32,
      'UDINT' || 'DWORD' => NodeId.uint32,
      'REAL' => NodeId.float,
      'LREAL' => NodeId.double,
      'LINT' => NodeId.int64,
      'ULINT' => NodeId.uint64,
      'BYTE' => NodeId.byte,
      'STRING' || 'WSTRING' || 'BYTE_STRING' => NodeId.uastring,
      _ => NodeId.byte,
    };
    return DynamicValue(value: t.value, typeId: typeId);
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    // UMAS-by-name routing takes precedence.
    if (_variableNames[key] != null) {
      await writeUmasVariable(key, value);
      return;
    }
    final spec = _specs[key];
    if (spec == null) throw ArgumentError('Unknown Modbus key: $key');

    if (spec.bitMask != null) {
      // Read-modify-write: preserve unmasked bits.
      // Note: reads the last-polled cached value, not a fresh device read.
      // A concurrent write between the last poll and this write could be
      // overwritten. Modbus has no atomic bit-set instruction, so this is
      // inherent to the protocol. The race window is bounded by poll interval.
      final current = wrapper.read(key);
      final currentInt = (current is num) ? current.toInt() : 0;
      final shift = spec.bitShift ?? 0;
      final isSingle =
          spec.bitMask! != 0 && (spec.bitMask! & (spec.bitMask! - 1)) == 0;
      int newValue;
      if (isSingle) {
        final boolVal = value.value == true || value.value == 1;
        if (boolVal) {
          newValue = currentInt | spec.bitMask!;
        } else {
          newValue = currentInt & ~spec.bitMask!;
        }
      } else {
        final writeInt =
            (value.value is num) ? (value.value as num).toInt() : 0;
        newValue =
            (currentInt & ~spec.bitMask!) | ((writeInt << shift) & spec.bitMask!);
      }
      await wrapper.write(spec, newValue);
    } else {
      await wrapper.write(spec, value.value);
    }
  }

  @override
  ConnectionStatus get connectionStatus => wrapper.connectionStatus;

  @override
  Stream<ConnectionStatus> get connectionStream => wrapper.connectionStream;

  @override
  void connect() => wrapper.connect();

  @override
  void dispose() {
    _umasClient?.dispose();
    _umasClient = null;
    _umasClientFor = null;
    // F-1: close every long-lived UMAS-by-name subject so subscribers
    // see `onDone` exactly once at adapter teardown rather than after
    // a single read.
    for (final subject in _umasSubjects.values) {
      if (!subject.isClosed) subject.close();
    }
    _umasSubjects.clear();
    wrapper.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Wraps a raw Modbus value in a [DynamicValue] with the correct [typeId]
  /// derived from the register spec's declared data type, then applies
  /// optional bit masking.
  static DynamicValue _toDynamicValue(Object? value, ModbusRegisterSpec spec) {
    final dv = DynamicValue(value: value, typeId: _typeIdFromDataType(spec.dataType));
    return StateMan.applyBitMask(dv, spec.bitMask, spec.bitShift);
  }

  /// Maps [ModbusDataType] to the corresponding OPC UA [NodeId] type identifier.
  static NodeId _typeIdFromDataType(ModbusDataType dataType) {
    switch (dataType) {
      case ModbusDataType.bit:
        return NodeId.boolean;
      case ModbusDataType.int16:
        return NodeId.int16;
      case ModbusDataType.uint16:
        return NodeId.uint16;
      case ModbusDataType.int32:
        return NodeId.int32;
      case ModbusDataType.uint32:
        return NodeId.uint32;
      case ModbusDataType.float32:
        return NodeId.float;
      case ModbusDataType.int64:
        return NodeId.int64;
      case ModbusDataType.uint64:
        return NodeId.uint64;
      case ModbusDataType.float64:
        return NodeId.double;
    }
  }
}

// ---------------------------------------------------------------------------
// Config-to-spec helpers (Phase 9)
// ---------------------------------------------------------------------------

/// Converts [KeyMappings] entries with a [ModbusNodeConfig] into a map of
/// [ModbusRegisterSpec] instances, filtered by [serverAlias].
///
/// Entries without a `modbusNode`, or whose `modbusNode.serverAlias` does not
/// match [serverAlias], are skipped.
///
/// The [endianness] parameter is the per-device byte order from
/// [ModbusConfig.endianness]. All specs for a given device share the same
/// endianness since byte order is a device-level property.
Map<String, ModbusRegisterSpec> buildSpecsFromKeyMappings(
  KeyMappings keyMappings,
  String? serverAlias, {
  ModbusEndianness endianness = ModbusEndianness.ABCD,
  int addressBase = 0,
}) {
  final specs = <String, ModbusRegisterSpec>{};
  for (final entry in keyMappings.nodes.entries) {
    final modbusNode = entry.value.modbusNode;
    if (modbusNode == null) continue;
    if (modbusNode.serverAlias != serverAlias) continue;
    // UMAS-by-name keys still carry a modbusNode for serverAlias/registerType
    // metadata but route through the symbol cache at runtime — the
    // ModbusRegisterSpec is built defensively so a misconfigured key
    // (umasEnabled flipped off post-pick) still has an address-space
    // fallback, but adapter routing prefers the variableName path.
    specs[entry.key] = ModbusRegisterSpec(
      key: entry.key,
      registerType: modbusNode.registerType.toModbusElementType(),
      address: modbusNode.address,
      dataType: modbusNode.dataType,
      pollGroup: modbusNode.pollGroup,
      endianness: endianness,
      addressBase: addressBase,
      bitMask: entry.value.bitMask,
      bitShift: entry.value.bitShift,
    );
  }
  return specs;
}

/// Extract `KeyMappingEntry.variableName` for every entry whose
/// `modbusNode.serverAlias` matches [serverAlias]. Returns a map of
/// `key → variableName` (only entries with a non-null variableName are
/// present). Used by [ModbusDeviceClientAdapter] to route reads/writes
/// by name when the server has UMAS enabled.
Map<String, String> buildVariableNamesFromKeyMappings(
  KeyMappings keyMappings,
  String? serverAlias,
) {
  final out = <String, String>{};
  for (final entry in keyMappings.nodes.entries) {
    final modbusNode = entry.value.modbusNode;
    if (modbusNode == null) continue;
    if (modbusNode.serverAlias != serverAlias) continue;
    final vn = entry.value.variableName;
    if (vn != null && vn.isNotEmpty) out[entry.key] = vn;
  }
  return out;
}

/// Builds Modbus [DeviceClient] instances from config and key mappings.
///
/// For each [ModbusConfig], translates key mappings into [ModbusRegisterSpec]s
/// via [buildSpecsFromKeyMappings], pre-configures poll groups from
/// [ModbusConfig.pollGroups], and creates the adapter.
///
/// This is the primary entry point for both data_acquisition_isolate and
/// the Flutter UI provider.
List<DeviceClient> buildModbusDeviceClients(
  List<ModbusConfig> modbusConfigs,
  KeyMappings keyMappings,
) {
  return modbusConfigs.map((config) {
    final specs = buildSpecsFromKeyMappings(
      keyMappings, config.serverAlias,
      endianness: config.endianness,
      addressBase: config.addressBase,
    );
    final variableNames =
        buildVariableNamesFromKeyMappings(keyMappings, config.serverAlias);
    final wrapper = ModbusClientWrapper(
      config.host,
      config.port,
      config.unitId,
    );
    // Pre-configure poll groups from config BEFORE adapter creation
    for (final pg in config.pollGroups) {
      wrapper.addPollGroup(pg.name, pg.interval);
    }
    return ModbusDeviceClientAdapter(
      wrapper,
      specs: specs,
      serverAlias: config.serverAlias,
      variableNames: variableNames,
      umasEnabled: config.umasEnabled,
    );
  }).toList();
}

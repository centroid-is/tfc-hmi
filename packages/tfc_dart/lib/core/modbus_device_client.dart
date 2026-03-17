import 'package:open62541/open62541.dart' if (dart.library.js_interop) 'web_stubs/open62541_stub.dart' show DynamicValue, NodeId;
import 'package:modbus_client/modbus_client.dart' if (dart.library.js_interop) 'web_stubs/modbus_client_stub.dart' show ModbusEndianness;
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart'
    show ConnectionStatus, DeviceClient, KeyMappings, ModbusConfig, ModbusNodeConfig, StateMan;

/// Adapter that wraps [ModbusClientWrapper] as a [DeviceClient] for use in
/// [StateMan].
///
/// Translates between [ModbusClientWrapper]'s `Object?` value streams and the
/// [DynamicValue]-based [DeviceClient] interface. Uses [ModbusRegisterSpec]
/// metadata (not runtime type inference) to assign correct [NodeId] typeIds.
class ModbusDeviceClientAdapter implements DeviceClient {
  /// The underlying Modbus transport wrapper.
  final ModbusClientWrapper wrapper;

  /// Optional alias for display/logging purposes.
  final String? serverAlias;

  /// Register specs keyed by their subscription key.
  final Map<String, ModbusRegisterSpec> _specs;

  ModbusDeviceClientAdapter(
    this.wrapper, {
    required Map<String, ModbusRegisterSpec> specs,
    this.serverAlias,
  }) : _specs = Map.unmodifiable(specs);

  @override
  Set<String> get subscribableKeys => _specs.keys.toSet();

  @override
  bool canSubscribe(String key) => _specs.containsKey(key);

  @override
  Stream<DynamicValue> subscribe(String key) {
    final spec = _specs[key];
    if (spec == null) throw ArgumentError('Unknown Modbus key: $key');
    return wrapper.subscribe(spec).map((v) => _toDynamicValue(v, spec));
  }

  @override
  DynamicValue? read(String key) {
    final spec = _specs[key];
    if (spec == null) return null;
    final raw = wrapper.read(key);
    if (raw == null) return null;
    return _toDynamicValue(raw, spec);
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
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
  void dispose() => wrapper.dispose();

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
    );
  }).toList();
}

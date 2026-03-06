import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart' show ConnectionStatus, DeviceClient;

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
    await wrapper.write(spec, value.value);
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
  /// derived from the register spec's declared data type.
  static DynamicValue _toDynamicValue(Object? value, ModbusRegisterSpec spec) {
    return DynamicValue(value: value, typeId: _typeIdFromDataType(spec.dataType));
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

/// Creates [DeviceClient] instances for Modbus devices.
///
/// Each entry produces one [ModbusDeviceClientAdapter] wrapping a
/// [ModbusClientWrapper]. Phase 8 will add [ModbusDeviceConfig] and Phase 9
/// will wire this into data_acquisition_isolate.
List<DeviceClient> createModbusDeviceClients(
  List<({String host, int port, int unitId, Map<String, ModbusRegisterSpec> specs, String? alias})> configs,
) {
  return configs.map((config) {
    final wrapper = ModbusClientWrapper(config.host, config.port, config.unitId);
    return ModbusDeviceClientAdapter(
      wrapper,
      specs: config.specs,
      serverAlias: config.alias,
    );
  }).toList();
}

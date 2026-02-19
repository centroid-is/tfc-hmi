import 'dart:async';

import 'package:logger/logger.dart';
import 'package:modbus_client/modbus_client.dart' as modbus;
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import 'state_man.dart';

/// Manages a single Modbus TCP client connection with polling-based data access.
///
/// Handles connection lifecycle, reconnection, poll group timers, and
/// read/write operations. Converts Modbus register data to/from [DynamicValue].
class ModbusClientWrapper {
  final ModbusClientTcp client;
  final ModbusConfig config;
  final Logger _logger;
  final String _alias;

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final StreamController<ConnectionStatus> _connectionController =
      StreamController<ConnectionStatus>.broadcast();

  /// Per-key polling streams. Keys are the user-facing key names.
  final Map<String, BehaviorSubject<DynamicValue>> polledValues = {};

  /// Timers for each poll group.
  final Map<String, Timer> _pollTimers = {};

  /// Keys grouped by poll group name. Set by [start] or [updateKeyGroups].
  Map<String, List<MapEntry<String, ModbusNodeConfig>>> _keyGroups = {};

  bool _shouldRun = true;
  bool _disposed = false;

  ModbusClientWrapper(this.config, {String alias = '', Logger? logger})
      : _alias = alias,
        _logger = logger ?? Logger(),
        client = ModbusClientTcp(
          config.host,
          serverPort: config.port,
          unitId: config.unitId,
          connectionMode:
              modbus.ModbusConnectionMode.autoConnectAndKeepConnected,
          connectionTimeout: const Duration(seconds: 3),
          responseTimeout: const Duration(seconds: 3),
        );

  ConnectionStatus get connectionStatus => _connectionStatus;
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;

  void updateConnectionStatus(ConnectionStatus status) {
    if (_disposed || status == _connectionStatus) return;
    _connectionStatus = status;
    _connectionController.add(status);
  }

  /// Start connecting and polling with the given key groups.
  ///
  /// [keyGroups] maps poll group name to a list of (keyName, nodeConfig) pairs.
  void start(
      Map<String, List<MapEntry<String, ModbusNodeConfig>>> keyGroups) {
    _keyGroups = keyGroups;
    _connectLoop();
  }

  /// Update which keys belong to which poll groups without restarting.
  void updateKeyGroups(
      Map<String, List<MapEntry<String, ModbusNodeConfig>>> keyGroups) {
    _keyGroups = keyGroups;
  }

  // -------------------- Connection --------------------

  Future<void> _connectLoop() async {
    while (_shouldRun && !_disposed) {
      try {
        updateConnectionStatus(ConnectionStatus.connecting);
        final connected = await client.connect();
        if (connected) {
          updateConnectionStatus(ConnectionStatus.connected);
          _startPollGroups();
          return;
        }
        updateConnectionStatus(ConnectionStatus.disconnected);
      } catch (e) {
        _logger.e('[$_alias] Modbus connect failed for $config: $e');
        updateConnectionStatus(ConnectionStatus.disconnected);
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  // -------------------- Polling --------------------

  void _startPollGroups() {
    _stopPollGroups();
    for (final group in config.pollGroups) {
      final interval = Duration(milliseconds: group.pollIntervalMs);
      _pollTimers[group.name] = Timer.periodic(interval, (_) {
        _pollGroup(group.name);
      });
      _pollGroup(group.name); // Immediate first poll
    }
  }

  void _stopPollGroups() {
    for (final timer in _pollTimers.values) {
      timer.cancel();
    }
    _pollTimers.clear();
  }

  Future<void> _pollGroup(String groupName) async {
    if (_disposed || _connectionStatus != ConnectionStatus.connected) return;

    final keysInGroup = _keyGroups[groupName] ?? [];
    for (final entry in keysInGroup) {
      if (_disposed) return;
      try {
        final value = await readNode(entry.value);
        if (_disposed) return;
        final subject = polledValues.putIfAbsent(
          entry.key,
          () => BehaviorSubject<DynamicValue>(),
        );
        subject.add(value);
      } catch (e) {
        if (_disposed) return;
        _logger.e('[$_alias] Modbus poll failed for ${entry.key}: $e');
        if (!client.isConnected) {
          updateConnectionStatus(ConnectionStatus.disconnected);
          _stopPollGroups();
          _connectLoop();
          return;
        }
      }
    }
  }

  // -------------------- Read --------------------

  /// Read a single Modbus node and return its value as a [DynamicValue].
  Future<DynamicValue> readNode(ModbusNodeConfig node) async {
    switch (node.registerType) {
      case ModbusRegisterType.coil:
      case ModbusRegisterType.discreteInput:
        return _readBoolNode(node);
      case ModbusRegisterType.holdingRegister:
        return _readRegister(
            node, modbus.ModbusElementType.holdingRegister);
      case ModbusRegisterType.inputRegister:
        return _readRegister(
            node, modbus.ModbusElementType.inputRegister);
    }
  }

  Future<DynamicValue> _readBoolNode(ModbusNodeConfig node) async {
    final modbus.ModbusElement element;
    if (node.registerType == ModbusRegisterType.coil) {
      element = modbus.ModbusCoil(name: 'read', address: node.address);
    } else {
      element =
          modbus.ModbusDiscreteInput(name: 'read', address: node.address);
    }
    final res = await client.send(element.getReadRequest());
    if (res != modbus.ModbusResponseCode.requestSucceed) {
      throw StateManException(
          'Modbus read ${node.registerType.name} failed: ${res.name}');
    }
    return DynamicValue(value: element.value as bool);
  }

  Future<DynamicValue> _readRegister(
    ModbusNodeConfig node,
    modbus.ModbusElementType elementType,
  ) async {
    final element =
        _createRegisterElement(node.dataType, node.address, elementType);

    final res = await client.send(element.getReadRequest());
    if (res != modbus.ModbusResponseCode.requestSucceed) {
      throw StateManException('Modbus read register failed: ${res.name}');
    }

    final rawValue = element.value;
    if (rawValue == null) {
      throw StateManException(
          'Modbus read returned null for address ${node.address}');
    }

    return _convertToDynamicValue(node.dataType, rawValue);
  }

  // -------------------- Write --------------------

  /// Write a [DynamicValue] to a Modbus node.
  Future<void> writeNode(
      ModbusNodeConfig node, DynamicValue value) async {
    if (node.registerType == ModbusRegisterType.inputRegister ||
        node.registerType == ModbusRegisterType.discreteInput) {
      throw StateManException(
          'Cannot write to read-only register type: ${node.registerType.name}');
    }

    if (node.registerType == ModbusRegisterType.coil) {
      final element =
          modbus.ModbusCoil(name: 'write', address: node.address);
      final res = await client
          .send(element.getWriteRequest(value.value as bool));
      if (res != modbus.ModbusResponseCode.requestSucceed) {
        throw StateManException('Modbus write coil failed: ${res.name}');
      }
      return;
    }

    // Holding register write
    final element = _createRegisterElement(
      node.dataType,
      node.address,
      modbus.ModbusElementType.holdingRegister,
    );
    final writeValue = _convertToWriteValue(node.dataType, value);
    final res = await client.send(element.getWriteRequest(writeValue));
    if (res != modbus.ModbusResponseCode.requestSucceed) {
      throw StateManException(
          'Modbus write register failed: ${res.name}');
    }
  }

  // -------------------- Subscribe --------------------

  /// Get or create the polling stream for a key, seeding with an initial
  /// read if the subject has no value yet.
  Future<Stream<DynamicValue>> subscribe(
      String key, ModbusNodeConfig node) async {
    final subject = polledValues.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    if (!subject.hasValue) {
      try {
        final value = await readNode(node);
        subject.add(value);
      } catch (e) {
        _logger
            .e('[$_alias] Failed to seed Modbus subscription for $key: $e');
      }
    }
    return subject.stream;
  }

  // -------------------- Lifecycle --------------------

  void dispose() {
    _disposed = true;
    _shouldRun = false;
    _stopPollGroups();
    for (final subject in polledValues.values) {
      subject.close();
    }
    polledValues.clear();
    _connectionController.close();
    client.disconnect();
  }

  // -------------------- Private helpers --------------------

  /// Create the appropriate [modbus.ModbusElement] for a given data type.
  static modbus.ModbusElement _createRegisterElement(
    ModbusDataType dataType,
    int address,
    modbus.ModbusElementType elementType,
  ) {
    return switch (dataType) {
      ModbusDataType.bit || ModbusDataType.uint16 =>
        modbus.ModbusUint16Register(
            name: 'reg', type: elementType, address: address),
      ModbusDataType.int16 => modbus.ModbusInt16Register(
          name: 'reg', type: elementType, address: address),
      ModbusDataType.int32 => modbus.ModbusInt32Register(
          name: 'reg', type: elementType, address: address),
      ModbusDataType.uint32 => modbus.ModbusUint32Register(
          name: 'reg', type: elementType, address: address),
      ModbusDataType.float32 => modbus.ModbusFloatRegister(
          name: 'reg', type: elementType, address: address),
      ModbusDataType.int64 => modbus.ModbusInt64Register(
          name: 'reg', type: elementType, address: address),
      ModbusDataType.uint64 => modbus.ModbusUint64Register(
          name: 'reg', type: elementType, address: address),
      ModbusDataType.float64 => modbus.ModbusDoubleRegister(
          name: 'reg', type: elementType, address: address),
    };
  }

  /// Convert a raw Modbus register value to a [DynamicValue].
  static DynamicValue _convertToDynamicValue(
      ModbusDataType dataType, dynamic rawValue) {
    return switch (dataType) {
      ModbusDataType.bit =>
        DynamicValue(value: (rawValue as num) != 0),
      ModbusDataType.int16 ||
      ModbusDataType.uint16 ||
      ModbusDataType.int32 ||
      ModbusDataType.uint32 ||
      ModbusDataType.int64 ||
      ModbusDataType.uint64 =>
        DynamicValue(value: (rawValue as num).toInt()),
      ModbusDataType.float32 || ModbusDataType.float64 =>
        DynamicValue(value: (rawValue as num).toDouble()),
    };
  }

  /// Convert a [DynamicValue] to the appropriate write value for a register.
  static dynamic _convertToWriteValue(
      ModbusDataType dataType, DynamicValue value) {
    return switch (dataType) {
      ModbusDataType.bit => (value.value as bool) ? 1 : 0,
      ModbusDataType.float32 || ModbusDataType.float64 =>
        (value.value as num).toDouble(),
      _ => value.value,
    };
  }
}

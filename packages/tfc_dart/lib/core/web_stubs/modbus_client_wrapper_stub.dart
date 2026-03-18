/// Web stub for modbus_client_wrapper.dart

// ignore_for_file: constant_identifier_names

enum ModbusDataType {
  bit,
  int16,
  uint16,
  int32,
  uint32,
  float32,
  int64,
  uint64,
  float64,
}

class ModbusRegisterSpec {
  final int address;
  final ModbusDataType dataType;
  final String? pollGroup;

  ModbusRegisterSpec({
    required this.address,
    required this.dataType,
    this.pollGroup,
  });
}

class ModbusClientWrapper {
  final String host;
  final int port;

  /// Stub — always null on web (no ModbusClientTcp).
  dynamic get client => null;

  ModbusClientWrapper(
    this.host,
    this.port, [
    int unitId = 1,
  ]) {
    throw UnsupportedError('Modbus not available on web');
  }
}

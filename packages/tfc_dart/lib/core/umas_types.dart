import 'package:tfc_dart/core/modbus_client_wrapper.dart' show ModbusDataType;

/// Maps a UMAS data type name to the corresponding Modbus data type.
///
/// Uses [byteSize] as a fallback for unknown type names.
ModbusDataType mapUmasDataTypeToModbus(String umasType, int byteSize) {
  switch (umasType.toUpperCase()) {
    case 'BOOL':
      return ModbusDataType.bit;
    case 'INT':
      return ModbusDataType.int16;
    case 'UINT':
      return ModbusDataType.uint16;
    case 'DINT':
      return ModbusDataType.int32;
    case 'UDINT':
      return ModbusDataType.uint32;
    case 'REAL':
      return ModbusDataType.float32;
    case 'LREAL':
      return ModbusDataType.float64;
    case 'LINT':
      return ModbusDataType.int64;
    case 'ULINT':
      return ModbusDataType.uint64;
    default:
      if (byteSize <= 2) return ModbusDataType.uint16;
      if (byteSize <= 4) return ModbusDataType.uint32;
      return ModbusDataType.float64;
  }
}

/// UMAS sub-function codes for Schneider PLC communication via FC90.
enum UmasSubFunction {
  init(0x01),
  readId(0x02),
  readProjectInfo(0x03),
  readDataDictionary(0x26);

  const UmasSubFunction(this.code);
  final int code;
}

/// A variable discovered from the UMAS data dictionary (0xDD02 records).
class UmasVariable {
  final String name;
  final int blockNo;
  final int offset;
  final int dataTypeId;
  final String? parentPath;

  const UmasVariable({
    required this.name,
    required this.blockNo,
    required this.offset,
    required this.dataTypeId,
    this.parentPath,
  });

  @override
  String toString() => 'UmasVariable($name, block=$blockNo, offset=$offset, '
      'typeId=$dataTypeId)';
}

/// A data type reference from the UMAS data dictionary (0xDD03 records).
class UmasDataTypeRef {
  final int id;
  final String name;
  final int byteSize;

  /// Class identifier from the PLC4X mspec (0xDD03 record field).
  /// 2 = UDT/struct, 4 = array, other values = elementary.
  final int classIdentifier;

  /// Data type code from the PLC4X mspec (0xDD03 record field).
  final int dataType;

  const UmasDataTypeRef({
    required this.id,
    required this.name,
    required this.byteSize,
    this.classIdentifier = 0,
    this.dataType = 0,
  });

  @override
  String toString() => 'UmasDataTypeRef($id: $name, ${byteSize}B)';
}

/// PLC identification data from sub-function 0x02 response.
class UmasPlcIdent {
  /// Hardware identifier (uint32 from ident field).
  final int hardwareId;

  /// Memory block index used for 0x26 data dictionary requests.
  final int index;

  /// Number of memory banks reported by the PLC.
  final int numberOfMemoryBanks;

  const UmasPlcIdent({
    required this.hardwareId,
    required this.index,
    required this.numberOfMemoryBanks,
  });

  @override
  String toString() => 'UmasPlcIdent(hwId=0x${hardwareId.toRadixString(16)}, '
      'index=$index, banks=$numberOfMemoryBanks)';
}

/// A node in the hierarchical variable tree built from data dictionary.
class UmasVariableTreeNode {
  final String name;
  final String path;
  final List<UmasVariableTreeNode> children;
  final UmasVariable? variable;
  final UmasDataTypeRef? dataType;

  UmasVariableTreeNode({
    required this.name,
    required this.path,
    List<UmasVariableTreeNode>? children,
    this.variable,
    this.dataType,
  }) : children = children ?? [];

  bool get isFolder => children.isNotEmpty && variable == null;

  @override
  String toString() => 'UmasVariableTreeNode($path, '
      '${isFolder ? "folder" : "leaf"}, '
      '${children.length} children)';
}

/// Exception thrown by UMAS operations.
class UmasException implements Exception {
  final int errorCode;
  final String message;

  const UmasException({required this.errorCode, required this.message});

  @override
  String toString() => 'UmasException($errorCode): $message';
}

/// Result of UMAS init communication (sub-function 0x01).
class UmasInitResult {
  final int maxFrameSize;
  final String? firmwareVersion;

  const UmasInitResult({required this.maxFrameSize, this.firmwareVersion});

  @override
  String toString() => 'UmasInitResult(maxFrame=$maxFrameSize)';
}

/// UMAS data type lookup table (from PLC4X).
/// Maps UMAS data type IDs to their standard names and byte sizes.
class UmasDataTypes {
  static const Map<int, UmasDataTypeRef> builtIn = {
    1: UmasDataTypeRef(id: 1, name: 'INT', byteSize: 2),
    2: UmasDataTypeRef(id: 2, name: 'UINT', byteSize: 2),
    3: UmasDataTypeRef(id: 3, name: 'DINT', byteSize: 4),
    4: UmasDataTypeRef(id: 4, name: 'UDINT', byteSize: 4),
    5: UmasDataTypeRef(id: 5, name: 'REAL', byteSize: 4),
    6: UmasDataTypeRef(id: 6, name: 'BOOL', byteSize: 1),
    7: UmasDataTypeRef(id: 7, name: 'STRING', byteSize: 256),
    8: UmasDataTypeRef(id: 8, name: 'TIME', byteSize: 4),
    9: UmasDataTypeRef(id: 9, name: 'BYTE', byteSize: 1),
    10: UmasDataTypeRef(id: 10, name: 'WORD', byteSize: 2),
    11: UmasDataTypeRef(id: 11, name: 'DWORD', byteSize: 4),
    12: UmasDataTypeRef(id: 12, name: 'LREAL', byteSize: 8),
    13: UmasDataTypeRef(id: 13, name: 'LINT', byteSize: 8),
    14: UmasDataTypeRef(id: 14, name: 'ULINT', byteSize: 8),
  };

  /// Resolve a data type ID, first checking custom types then built-in.
  static UmasDataTypeRef? resolve(
      int id, List<UmasDataTypeRef> customTypes) {
    for (final t in customTypes) {
      if (t.id == id) return t;
    }
    return builtIn[id];
  }
}

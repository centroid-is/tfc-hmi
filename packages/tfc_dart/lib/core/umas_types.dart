import 'dart:convert';
import 'dart:typed_data';

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

/// Session state for UMAS client lifecycle.
///
/// Tracks the progression through the UMAS handshake:
/// uninitialized -> identified (after readPlcId) -> paired (after init).
enum UmasSessionState {
  /// No UMAS session. Pairing key is invalid/unknown.
  uninitialized,

  /// readPlcId (0x02) succeeded. Have hardwareId and index.
  identified,

  /// init (0x01) succeeded. Have valid pairing key.
  paired,
}

/// UMAS sub-function codes for Schneider PLC communication via FC90.
enum UmasSubFunction {
  init(0x01),
  readId(0x02),
  readProjectInfo(0x03),
  plcStatus(0x04),
  echo(0x0A),
  takePlcReservation(0x10),
  releasePlcReservation(0x11),
  keepAlive(0x12),
  readVariable(0x22),
  writeVariable(0x23),
  readCoilsRegisters(0x24),
  writeCoilsRegisters(0x25),
  readCardInfo(0x06),
  readMemoryBlock(0x20),
  readDataDictionary(0x26),
  readEthMasterData(0x39),
  monitorPlc(0x50),
  checkPlc(0x58),
  readIoObject(0x70),
  getStatusModule(0x73);

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

/// Inclusive bounds for one array dimension (PLC4X UmasArrayDimension).
class UmasArrayDimension {
  /// Inclusive lower index (e.g. 1 for `ARRAY[1..100]`).
  final int startIndex;

  /// Inclusive upper index (e.g. 100 for `ARRAY[1..100]`).
  final int upperBound;

  const UmasArrayDimension({required this.startIndex, required this.upperBound});

  /// Element count for this dimension = `upperBound - startIndex + 1`.
  int get count => upperBound - startIndex + 1;

  @override
  String toString() => '[$startIndex..$upperBound]';
}

/// Parsed UmasArrayTypeDefinition returned by a DD02 query for an array
/// data-type id (PLC4X mspec).
///
/// Wire format (LE): `classId(1) + elementTypeId(2) + numberOfDimensions(1)
/// + dimensions[N]`, where each [UmasArrayDimension] is `startIndex(4) +
/// upperBound(4)`.
class UmasArrayTypeDefinition {
  /// Always 0x04 for arrays.
  final int classId;

  /// PLC-assigned type id of the element (built-in or custom UDT).
  final int elementTypeId;

  /// Inclusive bounds per dimension (PLC4X observes 1D in production but
  /// the wire format and mspec support N-dimensional definitions).
  final List<UmasArrayDimension> dimensions;

  const UmasArrayTypeDefinition({
    required this.classId,
    required this.elementTypeId,
    required this.dimensions,
  });

  /// Total flattened element count across all dimensions.
  int get totalElementCount {
    if (dimensions.isEmpty) return 0;
    int n = 1;
    for (final d in dimensions) {
      final c = d.count;
      if (c <= 0) return 0;
      n *= c;
    }
    return n;
  }

  /// Parse from raw DD02 response payload bytes (the body returned by
  /// [UmasClient.readDD02Raw] for an array type id).
  ///
  /// Returns null if the buffer is too short or `classId` is not 0x04.
  static UmasArrayTypeDefinition? tryParse(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] != 0x04) return null;
    final bd = ByteData.sublistView(bytes);
    final elementTypeId = bd.getUint16(1, Endian.little);
    final numberOfDimensions = bd.getUint8(3);
    final dimensions = <UmasArrayDimension>[];
    int pos = 4;
    for (int i = 0; i < numberOfDimensions; i++) {
      if (pos + 8 > bytes.length) return null;
      final startIndex = bd.getUint32(pos, Endian.little);
      final upperBound = bd.getUint32(pos + 4, Endian.little);
      dimensions.add(UmasArrayDimension(
        startIndex: startIndex,
        upperBound: upperBound,
      ));
      pos += 8;
    }
    return UmasArrayTypeDefinition(
      classId: 0x04,
      elementTypeId: elementTypeId,
      dimensions: dimensions,
    );
  }

  @override
  String toString() => 'UmasArrayTypeDefinition(elementTypeId=$elementTypeId, '
      'dims=${dimensions.length})';
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

/// Exception thrown when PLC reservation cannot be acquired (conflict).
///
/// Indicates another client currently holds the exclusive write reservation.
/// The [message] is suitable for user-facing feedback (WRITE-04).
class UmasReservationException extends UmasException {
  const UmasReservationException({
    required super.errorCode,
    required super.message,
  });

  @override
  String toString() => 'UmasReservationException($errorCode): $message';
}

/// Result of UMAS init communication (sub-function 0x01).
class UmasInitResult {
  final int maxFrameSize;
  final String? firmwareVersion;

  const UmasInitResult({required this.maxFrameSize, this.firmwareVersion});

  @override
  String toString() => 'UmasInitResult(maxFrame=$maxFrameSize)';
}

/// Result of PlcStatus (0x04) sub-function call.
///
/// Contains PLC run state and memory block CRC checksums needed by
/// ReadVariable (0x22) and WriteVariable (0x23).
class PlcStatusResult {
  /// Raw status byte from the first byte of payload. PLC run states are vendor-specific.
  final int statusByte;

  /// Number of memory blocks reported by PLC.
  final int numberOfBlocks;

  /// CRC checksums for each memory block (uint32 LE). Required by ReadVariable (0x22).
  final List<int> blockCrcs;

  /// Raw additional data bytes after the block CRCs (M580 has extra status data).
  final Uint8List additionalData;

  /// Whether the CRCs changed compared to the previous poll.
  /// False on the first poll (no previous data to compare).
  /// True when CRC list length or values differ from the previous poll.
  final bool crcChanged;

  const PlcStatusResult({
    required this.statusByte,
    required this.numberOfBlocks,
    required this.blockCrcs,
    required this.additionalData,
    this.crcChanged = false,
  });

  @override
  String toString() => 'PlcStatusResult(status=0x${statusByte.toRadixString(16)}, '
      'blocks=$numberOfBlocks, crcs=$blockCrcs)';
}

/// Result of ProjectInfo (0x03) sub-function call.
///
/// Contains the raw response bytes and a best-effort extracted project name.
class ProjectInfoResult {
  /// Raw response bytes (opaque -- format varies by PLC firmware).
  final Uint8List rawData;

  /// Extracted project name (best-effort: longest printable ASCII run).
  /// Null if no printable ASCII sequence found.
  final String? projectName;

  const ProjectInfoResult({required this.rawData, this.projectName});

  @override
  String toString() => 'ProjectInfoResult(${rawData.length} bytes, '
      'name=${projectName ?? "unknown"})';
}

/// Result of an Echo/Repeat (0x0A) sub-function call.
class UmasEchoResult {
  /// The payload bytes echoed back by the PLC.
  final Uint8List payload;

  /// Round-trip latency measured via [Stopwatch].
  final Duration latency;

  const UmasEchoResult({required this.payload, required this.latency});

  @override
  String toString() =>
      'UmasEchoResult(${payload.length} bytes, ${latency.inMilliseconds}ms)';
}

/// UMAS data type lookup table (from PLC4X).
/// Maps UMAS data type IDs to their standard names and byte sizes.
class UmasDataTypes {
  // Per the PLC4X UmasDataType enum (protocols/umas/.../umas.mspec). The
  // Schneider PLC's `dataType` byte uses these values, NOT the contiguous
  // 1..14 mapping we previously assumed. dataType=1 is BOOL (1 byte), not
  // INT — getting this wrong causes 0x94 read errors when an INT-sized
  // request hits a BOOL-sized member.
  static const Map<int, UmasDataTypeRef> builtIn = {
    1: UmasDataTypeRef(id: 1, name: 'BOOL', byteSize: 1),
    // Schneider also uses 2 and 3 for BOOL-like fields per PLC4X (UNKNOWN2,
    // UNKNOWN3 in mspec) — both 1 byte.
    2: UmasDataTypeRef(id: 2, name: 'BOOL', byteSize: 1),
    3: UmasDataTypeRef(id: 3, name: 'BOOL', byteSize: 1),
    4: UmasDataTypeRef(id: 4, name: 'INT', byteSize: 2),
    5: UmasDataTypeRef(id: 5, name: 'UINT', byteSize: 2),
    6: UmasDataTypeRef(id: 6, name: 'DINT', byteSize: 4),
    7: UmasDataTypeRef(id: 7, name: 'UDINT', byteSize: 4),
    8: UmasDataTypeRef(id: 8, name: 'REAL', byteSize: 4),
    9: UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256),
    10: UmasDataTypeRef(id: 10, name: 'TIME', byteSize: 4),
    14: UmasDataTypeRef(id: 14, name: 'DATE', byteSize: 4),
    15: UmasDataTypeRef(id: 15, name: 'TIME_OF_DAY', byteSize: 4),
    16: UmasDataTypeRef(id: 16, name: 'DATE_AND_TIME', byteSize: 8),
    21: UmasDataTypeRef(id: 21, name: 'BYTE', byteSize: 1),
    22: UmasDataTypeRef(id: 22, name: 'WORD', byteSize: 2),
    23: UmasDataTypeRef(id: 23, name: 'DWORD', byteSize: 4),
    25: UmasDataTypeRef(id: 25, name: 'EBOOL', byteSize: 1),
    // Extended/non-mspec entries kept for parser tests; not emitted by the
    // Schneider PLCs we've observed but supported for completeness.
    12: UmasDataTypeRef(id: 12, name: 'LREAL', byteSize: 8),
    13: UmasDataTypeRef(id: 13, name: 'LINT', byteSize: 8),
    24: UmasDataTypeRef(id: 24, name: 'ULINT', byteSize: 8),
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

/// Maps a data type byte size to the UMAS dataSizeIndex used in ReadVariable (0x22) requests.
///
/// Per PLC4X: 1B->1 (BOOL), 2B->2 (INT/UINT/WORD), 4B->3 (DINT/UDINT/REAL/
/// TIME/DWORD). The PLC rejects (0x86) any dsi outside this set, so for
/// types larger than 4 bytes (e.g. TON, struct instances) we clamp to 3
/// and return only the first 4 bytes — matching plc4j's behavior.
/// STRING (256 bytes) is a special case returning 17 per PLC4X table.
int dataSizeIndexFromByteSize(int byteSize) {
  if (byteSize >= 256) return 17; // STRING special case
  if (byteSize > 4) return 3; // clamp wide types to 4 bytes (PLC4X behaviour)
  int index = 1;
  int size = 1;
  while (size < byteSize && index < 16) {
    size *= 2;
    index++;
  }
  return index;
}

/// A reference to a variable for ReadVariable (0x22) requests.
///
/// Encodes the wire format: isArray:4bits + dataSizeIndex:4bits (1 byte)
/// + block(2 LE) + 0x01(1) + baseOffset(2 LE) + offset(1)
/// + [arrayLength(2 LE) if isArray]
class VariableReadRef {
  final int blockNo;
  final int baseOffset;
  final int offset;
  final int dataSizeIndex;
  final bool isArray;
  final int arrayLength;

  const VariableReadRef({
    required this.blockNo,
    required this.baseOffset,
    required this.offset,
    required this.dataSizeIndex,
    this.isArray = false,
    this.arrayLength = 0,
  });

  /// Create a [VariableReadRef] from a [UmasVariable] and its resolved [UmasDataTypeRef].
  ///
  /// Detects array variables via [UmasDataTypeRef.classIdentifier] == 4.
  /// For arrays, computes [arrayLength] as byteSize / element size (using
  /// the base data type size from [UmasDataTypeRef.dataType]).
  factory VariableReadRef.fromVariable(
      UmasVariable variable, UmasDataTypeRef dataType) {
    final isArray = dataType.classIdentifier == 4;
    int arrayLength = 0;

    if (isArray) {
      // Determine element size from the base data type ID
      final elementType = UmasDataTypes.builtIn[dataType.dataType];
      final elementSize = elementType?.byteSize ?? 4; // default to 4 bytes
      arrayLength =
          elementSize > 0 ? dataType.byteSize ~/ elementSize : 1;
    }

    // Per PLC4X driver, the Schneider VariableReadRef uses a paged byte
    // address: `baseOffset` is the 256-byte page index (address >> 8),
    // `offset` is the low byte (address & 0xFF). BOOL access also
    // requires this split form — putting the byte address directly in
    // baseOffset returns 0x94. Verified against plc4j packet captures
    // (e.g. byte 0x11a0 -> baseOffset=0x11 offset=0xa0).
    final addr = variable.offset;
    return VariableReadRef(
      blockNo: variable.blockNo,
      baseOffset: addr >> 8,
      offset: addr & 0xFF,
      dataSizeIndex: dataSizeIndexFromByteSize(
          isArray ? (UmasDataTypes.builtIn[dataType.dataType]?.byteSize ?? dataType.byteSize) : dataType.byteSize),
      isArray: isArray,
      arrayLength: arrayLength,
    );
  }

  /// Serialize to wire format bytes for the 0x22 request payload.
  Uint8List toBytes() {
    final length = isArray ? 9 : 7;
    final bytes = Uint8List(length);
    final bd = ByteData.sublistView(bytes);

    // Byte 0: isArray(4 bits) | dataSizeIndex(4 bits)
    bytes[0] = (isArray ? 0x10 : 0x00) | (dataSizeIndex & 0x0F);

    // Block number (2 bytes LE)
    bd.setUint16(1, blockNo, Endian.little);

    // Constant 0x01
    bytes[3] = 0x01;

    // Base offset (2 bytes LE)
    bd.setUint16(4, baseOffset, Endian.little);

    // Offset (1 byte)
    bytes[6] = offset & 0xFF;

    // Array length (2 bytes LE) if isArray
    if (isArray) {
      bd.setUint16(7, arrayLength, Endian.little);
    }

    return bytes;
  }
}

/// Result of a ReadVariable (0x22) call.
///
/// Contains raw response bytes; typed parsing is handled by
/// [parseVariableValue] and [parseVariableValues].
class ReadVariableResult {
  /// Raw concatenated bytes of all requested variable values.
  final Uint8List rawBytes;

  const ReadVariableResult({required this.rawBytes});

  @override
  String toString() => 'ReadVariableResult(${rawBytes.length} bytes)';
}

/// A parsed variable value with its Dart type, type name, and raw bytes.
class TypedVariableValue {
  /// The parsed Dart value: [int], [double], [bool], [String], or [Uint8List].
  final dynamic value;

  /// The UMAS data type name (e.g. 'REAL', 'INT', 'BOOL').
  final String typeName;

  /// The original raw bytes for this value.
  final Uint8List rawBytes;

  const TypedVariableValue({
    required this.value,
    required this.typeName,
    required this.rawBytes,
  });

  @override
  String toString() => 'TypedVariableValue($typeName: $value)';
}

/// Maximum allowed STRING byte size for parsing (T-05-06 mitigation).
const _maxStringByteSize = 1024;

/// Parse a single variable value from [bytes] at [offset] using [dataType] info.
///
/// Returns a [TypedVariableValue] with the correctly typed Dart value.
/// Throws [UmasException] if the buffer is too short (T-05-04 mitigation).
TypedVariableValue parseVariableValue(
    Uint8List bytes, int offset, UmasDataTypeRef dataType) {
  final declared = dataType.byteSize;
  final available = bytes.length - offset;

  // For wide types (TON, struct instances) the PLC clamps the read to 4
  // bytes — accept what arrived and parse the slice as raw bytes. For
  // known scalar types we still require the declared size to be present.
  // STRING is intentionally NOT in this set: Schneider stores STRING(N) at
  // arbitrary sizes (N=16 inside ARRAY OF STRING(16)) and the PLC may
  // truncate reads of >4-byte elements via the dsi clamp; the parser must
  // gracefully decode whatever bytes arrive.
  final knownScalar = const {
        'BOOL', 'EBOOL', 'INT', 'UINT', 'WORD', 'DINT', 'TIME', 'UDINT',
        'DWORD', 'REAL', 'LREAL', 'LINT', 'ULINT', 'BYTE',
        'DATE', 'TIME_OF_DAY', 'DATE_AND_TIME',
      }.contains(dataType.name.toUpperCase());

  if (offset + declared > bytes.length) {
    if (knownScalar || available < 0) {
      throw UmasException(
        errorCode: 0,
        message: 'Buffer underflow: need $declared bytes at offset $offset, '
            'but buffer is ${bytes.length} bytes',
      );
    }
  }

  final needed = (offset + declared > bytes.length) ? available : declared;
  final slice = bytes.sublist(offset, offset + needed);
  final bd = ByteData.sublistView(bytes);
  dynamic value;

  switch (dataType.name.toUpperCase()) {
    case 'BOOL':
    case 'EBOOL':
      value = bytes[offset] != 0;
    case 'INT':
      value = bd.getInt16(offset, Endian.little);
    case 'UINT':
    case 'WORD':
      value = bd.getUint16(offset, Endian.little);
    case 'DINT':
      value = bd.getInt32(offset, Endian.little);
    case 'TIME':
    case 'UDINT':
    case 'DWORD':
      value = bd.getUint32(offset, Endian.little);
    case 'REAL':
      value = bd.getFloat32(offset, Endian.little);
    case 'LREAL':
      value = bd.getFloat64(offset, Endian.little);
    case 'LINT':
      value = bd.getInt64(offset, Endian.little);
    case 'ULINT':
      value = bd.getUint64(offset, Endian.little);
    case 'BYTE':
      value = bytes[offset];
    case 'STRING':
      // T-05-06: Cap string read length
      final maxRead =
          needed > _maxStringByteSize ? _maxStringByteSize : needed;
      final stringBytes = bytes.sublist(offset, offset + maxRead);
      // Find null terminator
      int nullPos = stringBytes.indexOf(0x00);
      if (nullPos < 0) nullPos = maxRead;
      value = utf8.decode(stringBytes.sublist(0, nullPos));
    default:
      // Unknown type: return raw bytes
      value = slice;
  }

  return TypedVariableValue(
    value: value,
    typeName: dataType.name,
    rawBytes: slice,
  );
}

/// Parse multiple variable values from a concatenated byte buffer.
///
/// Walks [rawBytes] sequentially, parsing each variable according to its
/// type's [UmasDataTypeRef.byteSize].
///
/// Throws [UmasException] if:
/// - [types] list exceeds 255 entries (T-05-05 cap)
/// - Total expected bytes exceed [rawBytes] length (T-05-05 validation)
List<TypedVariableValue> parseVariableValues(
    Uint8List rawBytes, List<UmasDataTypeRef> types) {
  // T-05-05: Cap types list to max variableCount byte (255)
  if (types.length > 255) {
    throw UmasException(
      errorCode: 0,
      message: 'Too many types: ${types.length} exceeds max 255',
    );
  }

  // T-05-05: Validate total expected bytes fit in buffer.
  // Wide types (TON, struct instances) are clamped to 4 bytes per the PLC's
  // dataSizeIndex range, so use the on-wire size (max 4) for the bound
  // check rather than the declared byteSize.
  int totalExpected = 0;
  for (final type in types) {
    totalExpected += type.byteSize > 4 ? 4 : type.byteSize;
  }
  if (totalExpected > rawBytes.length) {
    throw UmasException(
      errorCode: 0,
      message: 'Buffer underflow: need $totalExpected bytes '
          'but buffer is ${rawBytes.length} bytes',
    );
  }

  final results = <TypedVariableValue>[];
  int offset = 0;
  for (final type in types) {
    results.add(parseVariableValue(rawBytes, offset, type));
    // Advance by the actual on-wire size (clamped to 4 for wide types).
    offset += type.byteSize > 4 ? 4 : type.byteSize;
  }
  return results;
}

/// Encode a Dart value to raw bytes matching the given UMAS [dataType].
///
/// Supports: BOOL, INT, UINT, WORD, DINT, UDINT, DWORD, TIME, REAL, LREAL,
/// LINT, ULINT, BYTE, STRING. Throws [UmasException] for unknown types
/// or type mismatches (T-06-07 mitigation).
Uint8List encodeVariableValue(dynamic value, UmasDataTypeRef dataType) {
  switch (dataType.name.toUpperCase()) {
    case 'BOOL':
      if (value is! bool) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected bool for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      return Uint8List.fromList([value ? 1 : 0]);

    case 'INT':
      if (value is! int) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected int for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(2);
      ByteData.sublistView(bytes).setInt16(0, value, Endian.little);
      return bytes;

    case 'UINT':
    case 'WORD':
      if (value is! int) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected int for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(2);
      ByteData.sublistView(bytes).setUint16(0, value, Endian.little);
      return bytes;

    case 'DINT':
      if (value is! int) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected int for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(4);
      ByteData.sublistView(bytes).setInt32(0, value, Endian.little);
      return bytes;

    case 'UDINT':
    case 'DWORD':
    case 'TIME':
      if (value is! int) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected int for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(4);
      ByteData.sublistView(bytes).setUint32(0, value, Endian.little);
      return bytes;

    case 'REAL':
      if (value is! num) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected num for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(4);
      ByteData.sublistView(bytes).setFloat32(0, value.toDouble(), Endian.little);
      return bytes;

    case 'LREAL':
      if (value is! num) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected num for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(8);
      ByteData.sublistView(bytes).setFloat64(0, value.toDouble(), Endian.little);
      return bytes;

    case 'LINT':
      if (value is! int) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected int for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(8);
      ByteData.sublistView(bytes).setInt64(0, value, Endian.little);
      return bytes;

    case 'ULINT':
      if (value is! int) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected int for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final bytes = Uint8List(8);
      ByteData.sublistView(bytes).setUint64(0, value, Endian.little);
      return bytes;

    case 'BYTE':
      if (value is! int) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected int for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      return Uint8List.fromList([value & 0xFF]);

    case 'STRING':
      if (value is! String) {
        throw UmasException(
          errorCode: 0,
          message: 'Expected String for ${dataType.name}, got ${value.runtimeType}',
        );
      }
      final encoded = utf8.encode(value);
      final bytes = Uint8List(dataType.byteSize);
      final copyLen = encoded.length < dataType.byteSize
          ? encoded.length
          : dataType.byteSize;
      bytes.setRange(0, copyLen, encoded);
      // Remaining bytes are already 0 (null padding)
      return bytes;

    default:
      throw UmasException(
        errorCode: 0,
        message: 'Unknown data type for encoding: ${dataType.name}',
      );
  }
}

/// A reference to a variable for WriteVariable (0x23) requests.
///
/// Encodes the wire format: isArray:4bits + dataSizeIndex:4bits (1 byte)
/// + block(2 LE) + baseOffset(2 LE) + offset(2 LE)
/// + [arrayLength(2 LE) if isArray] + data[dataSize * arrayLength]
class VariableWriteRef {
  final int blockNo;
  final int baseOffset;
  final int offset;
  final int dataSizeIndex;
  final bool isArray;
  final int arrayLength;

  /// The raw data bytes to write.
  final Uint8List data;

  const VariableWriteRef({
    required this.blockNo,
    required this.baseOffset,
    required this.offset,
    required this.dataSizeIndex,
    required this.data,
    this.isArray = false,
    this.arrayLength = 0,
  });

  /// Create a [VariableWriteRef] from a [UmasVariable], its resolved
  /// [UmasDataTypeRef], and the value to write.
  ///
  /// Detects array variables via [UmasDataTypeRef.classIdentifier] == 4.
  factory VariableWriteRef.fromVariable(
      UmasVariable variable, UmasDataTypeRef dataType, dynamic value) {
    final isArray = dataType.classIdentifier == 4;
    int arrayLength = 0;

    if (isArray) {
      final elementType = UmasDataTypes.builtIn[dataType.dataType];
      final elementSize = elementType?.byteSize ?? 4;
      arrayLength =
          elementSize > 0 ? dataType.byteSize ~/ elementSize : 1;
    }

    final encodedData = encodeVariableValue(value, dataType);

    // Per the Schneider paged-address convention (see VariableReadRef):
    // baseOffset is the 256-byte page index, offset is the low byte.
    final addr = variable.offset;
    return VariableWriteRef(
      blockNo: variable.blockNo,
      baseOffset: addr >> 8,
      offset: addr & 0xFF,
      dataSizeIndex: dataSizeIndexFromByteSize(
          isArray
              ? (UmasDataTypes.builtIn[dataType.dataType]?.byteSize ??
                  dataType.byteSize)
              : dataType.byteSize),
      isArray: isArray,
      arrayLength: arrayLength,
      data: encodedData,
    );
  }

  /// Serialize to wire format bytes for the 0x23 request payload.
  ///
  /// Returns header bytes + data bytes appended.
  Uint8List toBytes() {
    final headerLength = isArray ? 9 : 7;
    final bytes = Uint8List(headerLength + data.length);
    final bd = ByteData.sublistView(bytes);

    // Byte 0: isArray(4 bits) | dataSizeIndex(4 bits)
    bytes[0] = (isArray ? 0x10 : 0x00) | (dataSizeIndex & 0x0F);

    // Block number (2 bytes LE)
    bd.setUint16(1, blockNo, Endian.little);

    // Base offset (2 bytes LE)
    bd.setUint16(3, baseOffset, Endian.little);

    // Offset (2 bytes LE)
    bd.setUint16(5, offset, Endian.little);

    // Array length (2 bytes LE) if isArray
    if (isArray) {
      bd.setUint16(7, arrayLength, Endian.little);
    }

    // Append data bytes after header
    bytes.setRange(headerLength, headerLength + data.length, data);

    return bytes;
  }
}

/// PLC memory area types for direct register access (0x24/0x25).
///
/// Area codes are best-effort based on Schneider Modbus conventions.
/// May need adjustment when verified against a real PLC.
enum RegisterType {
  coil(0x00),          // %M -- discrete memory bits
  memoryWord(0x04),    // %MW -- 16-bit memory words
  systemBit(0x06),     // %S -- system bits
  systemWord(0x07);    // %SW -- system words

  const RegisterType(this.areaCode);
  final int areaCode;
}

/// A direct register address for ReadCoilsRegisters (0x24) / WriteCoilsRegisters (0x25).
///
/// Wire format: memoryArea(1) + startAddress(2 LE) + quantity(2 LE)
/// NOTE: Wire format is UNVERIFIED (PLC4X marks as opaque bytes).
/// May need adjustment when tested against a real PLC.
class RegisterAddress {
  final RegisterType type;
  final int startAddress;
  final int quantity;

  const RegisterAddress({
    required this.type,
    required this.startAddress,
    required this.quantity,
  });

  Uint8List toBytes() {
    final bytes = Uint8List(5);
    final bd = ByteData.sublistView(bytes);
    bytes[0] = type.areaCode;
    bd.setUint16(1, startAddress, Endian.little);
    bd.setUint16(3, quantity, Endian.little);
    return bytes;
  }

  /// Expected response data size in bytes.
  /// Coils/system bits: ceil(quantity / 8) bytes (bit-packed).
  /// Words/system words: quantity * 2 bytes.
  int get expectedDataBytes {
    switch (type) {
      case RegisterType.coil:
      case RegisterType.systemBit:
        return (quantity + 7) ~/ 8;
      case RegisterType.memoryWord:
      case RegisterType.systemWord:
        return quantity * 2;
    }
  }
}

/// Result of ReadCoilsRegisters (0x24).
class CoilsRegistersResult {
  final Uint8List rawBytes;
  const CoilsRegistersResult({required this.rawBytes});
}

// ---------------------------------------------------------------------------
// Diagnostic result types (0x06, 0x20, 0x39, 0x58, 0x70, 0x73)
// ---------------------------------------------------------------------------

/// Result of ReadCardInfo (0x06) -- SD card status.
class CardInfoResult {
  final Uint8List rawData;
  const CardInfoResult({required this.rawData});

  @override
  String toString() => 'CardInfoResult(${rawData.length} bytes)';
}

/// Request payload for ReadMemoryBlock (0x20).
///
/// Wire format (9 bytes LE):
/// range(1) + blockNumber(2) + offset(2) + unknownObj(2) + numberOfBytes(2)
class ReadMemoryBlockRequest {
  final int range;
  final int blockNumber;
  final int offset;
  final int numberOfBytes;
  final int unknownObj;

  const ReadMemoryBlockRequest({
    required this.range,
    required this.blockNumber,
    required this.offset,
    required this.numberOfBytes,
    this.unknownObj = 0,
  });

  /// Serialize to 9-byte LE wire payload.
  Uint8List toBytes() {
    final bytes = Uint8List(9);
    final bd = ByteData.sublistView(bytes);
    bytes[0] = range & 0xFF;
    bd.setUint16(1, blockNumber, Endian.little);
    bd.setUint16(3, offset, Endian.little);
    bd.setUint16(5, unknownObj, Endian.little);
    bd.setUint16(7, numberOfBytes, Endian.little);
    return bytes;
  }
}

/// Result of ReadMemoryBlock (0x20).
///
/// Response format: range(1) + numberOfBytes(2 LE) + data[numberOfBytes]
class ReadMemoryBlockResult {
  final int range;
  final int numberOfBytes;
  final Uint8List data;

  const ReadMemoryBlockResult({
    required this.range,
    required this.numberOfBytes,
    required this.data,
  });

  /// Parse from response payload bytes.
  ///
  /// Validates header length (>= 3 bytes) and that numberOfBytes
  /// does not exceed available data (T-09-01 mitigation).
  factory ReadMemoryBlockResult.fromPayload(Uint8List payload) {
    if (payload.length < 3) {
      throw UmasException(
        errorCode: 0,
        message: 'ReadMemoryBlock response too short: ${payload.length} bytes',
      );
    }
    final range = payload[0];
    final bd = ByteData.sublistView(payload);
    final numBytes = bd.getUint16(1, Endian.little);

    if (3 + numBytes > payload.length) {
      throw UmasException(
        errorCode: 0,
        message: 'ReadMemoryBlock numberOfBytes ($numBytes) exceeds '
            'available data (${payload.length - 3} bytes)',
      );
    }

    return ReadMemoryBlockResult(
      range: range,
      numberOfBytes: numBytes,
      data: payload.sublist(3, 3 + numBytes),
    );
  }

  @override
  String toString() =>
      'ReadMemoryBlockResult(range=$range, ${data.length} bytes)';
}

/// Result of ReadEthMasterData (0x39) -- network topology.
class EthMasterDataResult {
  final Uint8List rawData;
  const EthMasterDataResult({required this.rawData});

  @override
  String toString() => 'EthMasterDataResult(${rawData.length} bytes)';
}

/// Result of CheckPlc (0x58) -- PLC health verification.
class CheckPlcResult {
  final Uint8List rawData;
  const CheckPlcResult({required this.rawData});

  @override
  String toString() => 'CheckPlcResult(${rawData.length} bytes)';
}

/// Result of ReadIoObject (0x70) -- I/O module data.
class IoObjectResult {
  final Uint8List rawData;
  const IoObjectResult({required this.rawData});

  @override
  String toString() => 'IoObjectResult(${rawData.length} bytes)';
}

/// Result of GetStatusModule (0x73) -- per-module status.
class StatusModuleResult {
  final Uint8List rawData;
  const StatusModuleResult({required this.rawData});

  @override
  String toString() => 'StatusModuleResult(${rawData.length} bytes)';
}

// ---------------------------------------------------------------------------
// MonitorPlc (0x50) types
// ---------------------------------------------------------------------------

/// A reference to a variable for MonitorPlc (0x50) sub-operations.
///
/// Used to build Register (0x05) and RegisterAndRead (0x09) wire payloads.
class MonitorPlcRef {
  final int variableIndex;
  final int blockNo;
  final int offset;

  const MonitorPlcRef({
    required this.variableIndex,
    required this.blockNo,
    required this.offset,
  });

  /// Create from a [UmasVariable] with a given [variableIndex].
  factory MonitorPlcRef.fromVariable(int variableIndex, UmasVariable variable) {
    return MonitorPlcRef(
      variableIndex: variableIndex,
      blockNo: variable.blockNo,
      offset: variable.offset,
    );
  }

  /// Serialize to Register (0x05) sub-operation wire format (7 bytes).
  ///
  /// Per PLC4X mspec, every MonitorPlcSubOperation in the array begins with
  /// its own operationType discriminator byte, even when it duplicates the
  /// outer subCommand. Format:
  ///   operationType(0x05) + variableIndex(1) + block(2 LE) + offset(2 LE)
  ///                       + action(1)
  /// Action: 0x02 = register, 0x01 = deregister.
  Uint8List toRegisterBytes({bool register = true}) {
    final bytes = Uint8List(7);
    final bd = ByteData.sublistView(bytes);
    bytes[0] = 0x05;
    bytes[1] = variableIndex & 0xFF;
    bd.setUint16(2, blockNo, Endian.little);
    bd.setUint16(4, offset, Endian.little);
    bytes[6] = register ? 0x02 : 0x01;
    return bytes;
  }

  /// Serialize to RegisterAndRead (0x09) sub-operation wire format (6 bytes).
  ///
  /// Per PLC4X mspec, every MonitorPlcSubOperation begins with its own
  /// operationType discriminator byte. Format:
  ///   operationType(0x09) + variableIndex(1) + block(2 LE) + offset(2 LE)
  Uint8List toRegisterAndReadBytes() {
    final bytes = Uint8List(6);
    final bd = ByteData.sublistView(bytes);
    bytes[0] = 0x09;
    bytes[1] = variableIndex & 0xFF;
    bd.setUint16(2, blockNo, Endian.little);
    bd.setUint16(4, offset, Endian.little);
    return bytes;
  }
}

/// Client-side registration table for MonitorPlc (0x50).
///
/// Maps variable indices to their data types so that the concatenated
/// ReadAll (0x07) response bytes can be parsed into typed values.
/// Variable index is 1 byte, so max registrations is 255 (T-08-01).
class MonitorPlcRegistrationTable {
  /// Maximum number of registrations (variableIndex is 1 byte).
  static const maxRegistrations = 255;

  final Map<int, UmasDataTypeRef> _types = {};

  /// Auto-incrementing counter for assigning variable indices.
  int _nextIndex = 0;

  /// Register a variable index with its data type.
  void register(int variableIndex, UmasDataTypeRef type) {
    if (_types.length >= maxRegistrations && !_types.containsKey(variableIndex)) {
      throw UmasException(
        errorCode: 0,
        message: 'MonitorPlc registration table full (max $maxRegistrations)',
      );
    }
    _types[variableIndex] = type;
    if (variableIndex >= _nextIndex) {
      _nextIndex = variableIndex + 1;
    }
  }

  /// Remove a variable index registration.
  void deregister(int variableIndex) {
    _types.remove(variableIndex);
  }

  /// Clear all registrations.
  void reset() {
    _types.clear();
    _nextIndex = 0;
  }

  /// Get the data type for a registered variable index.
  UmasDataTypeRef? getType(int variableIndex) => _types[variableIndex];

  /// All registered variable indices, sorted ascending.
  List<int> get registeredIndices => _types.keys.toList()..sort();

  /// Whether the table has no registrations.
  bool get isEmpty => _types.isEmpty;

  /// The next auto-assigned variable index.
  int get nextIndex => _nextIndex;

  /// Allocate the next variable index and return it.
  int allocateIndex() {
    final idx = _nextIndex;
    _nextIndex++;
    return idx;
  }

  /// Parse a ReadAll (0x07) response by walking bytes in registration order.
  ///
  /// Iterates sorted registered indices, parsing each variable's bytes
  /// using [parseVariableValue]. Throws [UmasException] on buffer underflow.
  List<TypedVariableValue> parseReadAllResponse(Uint8List rawBytes) {
    final indices = registeredIndices;
    if (indices.isEmpty) return [];

    final results = <TypedVariableValue>[];
    int offset = 0;

    for (final idx in indices) {
      final type = _types[idx]!;
      // parseVariableValue throws UmasException on buffer underflow
      results.add(parseVariableValue(rawBytes, offset, type));
      offset += type.byteSize;
    }

    return results;
  }
}

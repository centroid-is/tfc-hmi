import 'dart:typed_data';

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

  const UmasDataTypeRef({
    required this.id,
    required this.name,
    required this.byteSize,
  });

  @override
  String toString() => 'UmasDataTypeRef($id: $name, ${byteSize}B)';
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

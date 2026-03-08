import 'dart:convert';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

/// A Modbus request carrying a UMAS (FC90) payload.
///
/// PDU structure: FC(0x5A) + PairingKey(1) + SubFunction(1) + Payload(N)
class UmasRequest extends ModbusRequest {
  final int umasSubFunction;
  final int pairingKey;
  final Uint8List umasPayload;

  /// Stores the raw response PDU after [internalSetFromPduResponse].
  Uint8List? responsePdu;

  // CRITICAL: All fields must be initialized via the initializer list
  // BEFORE super() runs, because ModbusRequest's constructor calls
  // protocolDataUnit getter during initialization.
  UmasRequest({
    required this.umasSubFunction,
    this.pairingKey = 0x00,
    Uint8List? payload,
    int? unitId,
    Duration? responseTimeout,
  })  : umasPayload = payload ?? Uint8List(0),
        super(unitId: unitId, responseTimeout: responseTimeout);

  @override
  FunctionCode get functionCode =>
      const ModbusFunctionCode(0x5A, FunctionType.custom);

  @override
  Uint8List get protocolDataUnit {
    final pdu = Uint8List(3 + umasPayload.length);
    pdu[0] = 0x5A; // Function code 90
    pdu[1] = pairingKey;
    pdu[2] = umasSubFunction;
    pdu.setAll(3, umasPayload);
    return pdu;
  }

  /// Variable length -- UMAS responses vary in size.
  @override
  int get responsePduLength => -1;

  @override
  ModbusResponseCode internalSetFromPduResponse(Uint8List pdu) {
    responsePdu = pdu;
    return ModbusResponseCode.requestSucceed;
  }
}

/// Client for UMAS protocol communication with Schneider PLCs via FC90.
///
/// Accepts a send function for dependency injection (use ModbusClientTcp.send
/// in production, or a mock in tests).
class UmasClient {
  /// Maximum allowed variable name length in bytes (defense against malformed responses).
  static const _maxNameLength = 1024;

  /// Maximum number of variables/data types parsed from a single response.
  static const _maxVariables = 10000;
  final Future<ModbusResponseCode> Function(ModbusRequest request) sendFn;
  int _pairingKey = 0x00;
  int? maxFrameSize;

  UmasClient({required this.sendFn});

  /// Initialize UMAS communication (sub-function 0x01).
  /// Returns max frame size and optionally firmware version.
  Future<UmasInitResult> init() async {
    final request = UmasRequest(umasSubFunction: UmasSubFunction.init.code, pairingKey: _pairingKey);
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
          errorCode: code.code, message: 'UMAS init failed: ${code.name}');
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 4) {
      throw UmasException(errorCode: 0, message: 'Empty UMAS init response');
    }

    // PDU: FC(0x5A) + pairingKey + status + subFuncEcho + payload
    final responsePairingKey = pdu[1];
    final status = pdu[2];

    if (status == 0xFD) {
      final errorCode = pdu.length > 3 ? pdu[3] : 0;
      throw UmasException(
          errorCode: errorCode, message: 'UMAS init error: 0x${errorCode.toRadixString(16)}');
    }

    _pairingKey = responsePairingKey;

    // Parse payload after the 4-byte header (FC + pairing + status + subFunc)
    if (pdu.length >= 6) {
      final payloadView = ByteData.sublistView(pdu, 4);
      maxFrameSize = payloadView.getUint16(0, Endian.little);
    }

    return UmasInitResult(maxFrameSize: maxFrameSize ?? 240);
  }

  /// Read variable names from the data dictionary (0x26 with record type 0xDD02).
  Future<List<UmasVariable>> readVariableNames() async {
    // Payload: record type 0xDD02 sent as [0x02, 0xDD] (little-endian)
    final request = UmasRequest(
      umasSubFunction: UmasSubFunction.readDataDictionary.code,
      pairingKey: _pairingKey,
      payload: Uint8List.fromList([0x02, 0xDD]),
    );
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
          errorCode: code.code,
          message: 'Data Dictionary read failed: ${code.name}');
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 4) {
      throw UmasException(
          errorCode: 0, message: 'Empty data dictionary response');
    }

    final status = pdu[2];
    if (status == 0xFD) {
      final errorCode = pdu.length > 3 ? pdu[3] : 0;
      throw UmasException(
          errorCode: errorCode,
          message: 'Data Dictionary not enabled on PLC (error: '
              '0x${errorCode.toRadixString(16)})');
    }

    // Parse variable records from payload after 4-byte header
    return _parseVariableRecords(pdu.sublist(4));
  }

  /// Parse variable name records from the 0xDD02 response payload.
  /// Each record: name_length(2 LE) + name(UTF-8) + block_no(2 LE) +
  ///              offset(2 LE) + data_type_id(2 LE)
  List<UmasVariable> _parseVariableRecords(Uint8List data) {
    final variables = <UmasVariable>[];
    int pos = 0;

    while (pos + 2 <= data.length) {
      if (variables.length >= _maxVariables) break;

      final view = ByteData.sublistView(data, pos);
      final nameLen = view.getUint16(0, Endian.little);
      if (nameLen > _maxNameLength) break;
      pos += 2;

      if (pos + nameLen + 6 > data.length) break;

      final name = utf8.decode(data.sublist(pos, pos + nameLen));
      pos += nameLen;

      final fieldView = ByteData.sublistView(data, pos);
      final blockNo = fieldView.getUint16(0, Endian.little);
      final offset = fieldView.getUint16(2, Endian.little);
      final dataTypeId = fieldView.getUint16(4, Endian.little);
      pos += 6;

      variables.add(UmasVariable(
        name: name,
        blockNo: blockNo,
        offset: offset,
        dataTypeId: dataTypeId,
      ));
    }

    return variables;
  }

  /// Read data type references from the data dictionary (0x26 with record type 0xDD03).
  Future<List<UmasDataTypeRef>> readDataTypes() async {
    final request = UmasRequest(
      umasSubFunction: UmasSubFunction.readDataDictionary.code,
      pairingKey: _pairingKey,
      payload: Uint8List.fromList([0x03, 0xDD]),
    );
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
          errorCode: code.code,
          message: 'Data Dictionary type read failed: ${code.name}');
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 4) {
      throw UmasException(
          errorCode: 0, message: 'Empty data type response');
    }

    final status = pdu[2];
    if (status == 0xFD) {
      final errorCode = pdu.length > 3 ? pdu[3] : 0;
      throw UmasException(
          errorCode: errorCode,
          message: 'Data Dictionary not enabled on PLC (error: '
              '0x${errorCode.toRadixString(16)})');
    }

    return _parseDataTypeRecords(pdu.sublist(4));
  }

  /// Parse data type records from the 0xDD03 response payload.
  /// Each record: type_id(2 LE) + name_length(2 LE) + name(UTF-8) +
  ///              byte_size(2 LE)
  List<UmasDataTypeRef> _parseDataTypeRecords(Uint8List data) {
    final types = <UmasDataTypeRef>[];
    int pos = 0;

    while (pos + 4 <= data.length) {
      if (types.length >= _maxVariables) break;

      final view = ByteData.sublistView(data, pos);
      final typeId = view.getUint16(0, Endian.little);
      final nameLen = view.getUint16(2, Endian.little);
      if (nameLen > _maxNameLength) break;
      pos += 4;

      if (pos + nameLen + 2 > data.length) break;

      final name = utf8.decode(data.sublist(pos, pos + nameLen));
      pos += nameLen;

      final sizeView = ByteData.sublistView(data, pos);
      final byteSize = sizeView.getUint16(0, Endian.little);
      pos += 2;

      types.add(UmasDataTypeRef(id: typeId, name: name, byteSize: byteSize));
    }

    return types;
  }

  /// Build a hierarchical variable tree from a flat list of variables.
  /// Variable names use dot-separated paths (e.g. "App.GVL.temp").
  List<UmasVariableTreeNode> buildVariableTree(
      List<UmasVariable> variables, List<UmasDataTypeRef> dataTypes) {
    // Use a nested map structure for efficient tree construction,
    // then convert to UmasVariableTreeNode at the end.
    final tree = _TreeBuilder();

    for (final v in variables) {
      tree.insert(v, dataTypes);
    }

    return tree.build();
  }

  /// Convenience method: init -> readVariableNames -> readDataTypes -> buildVariableTree.
  /// This is the primary entry point for the browse dialog.
  Future<List<UmasVariableTreeNode>> browse() async {
    await init();
    final variables = await readVariableNames();
    final dataTypes = await readDataTypes();
    return buildVariableTree(variables, dataTypes);
  }
}

/// Internal helper for building the variable tree from flat paths.
class _TreeBuilderNode {
  final String name;
  final String path;
  final Map<String, _TreeBuilderNode> children = {};
  UmasVariable? variable;
  UmasDataTypeRef? dataType;

  _TreeBuilderNode(this.name, this.path);

  UmasVariableTreeNode toTreeNode() {
    return UmasVariableTreeNode(
      name: name,
      path: path,
      children: children.values.map((c) => c.toTreeNode()).toList(),
      variable: variable,
      dataType: dataType,
    );
  }
}

class _TreeBuilder {
  final Map<String, _TreeBuilderNode> roots = {};

  void insert(UmasVariable v, List<UmasDataTypeRef> dataTypes) {
    final parts = v.name.split('.');
    var currentLevel = roots;
    var pathSoFar = '';

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      pathSoFar = pathSoFar.isEmpty ? part : '$pathSoFar.$part';
      final isLeaf = (i == parts.length - 1);

      currentLevel.putIfAbsent(part, () => _TreeBuilderNode(part, pathSoFar));
      final node = currentLevel[part]!;

      if (isLeaf) {
        node.variable = v;
        node.dataType = UmasDataTypes.resolve(v.dataTypeId, dataTypes);
      } else {
        currentLevel = node.children;
      }
    }
  }

  List<UmasVariableTreeNode> build() {
    return roots.values.map((n) => n.toTreeNode()).toList();
  }
}

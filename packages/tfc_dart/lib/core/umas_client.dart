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

  /// Optional Modbus unit ID for UMAS requests.
  /// Schneider PLCs typically use 255 (0xFF) or 254 (0xFE).
  final int? unitId;
  int _pairingKey = 0x00;
  int? maxFrameSize;

  /// Hardware ID from 0x02 (Read PLC Identification) response.
  int? _hardwareId;

  /// Memory block index from 0x02 response, used in 0x26 payloads.
  int? _index;

  UmasClient({required this.sendFn, this.unitId});

  /// UMAS success status byte value.
  static const _statusSuccess = 0xFE;

  /// UMAS error status byte value (followed by error code byte).
  static const _statusError = 0xFD;

  /// Check UMAS response PDU and throw on error.
  ///
  /// Real Schneider PLC response format:
  ///   pdu[0] = FC (0x5A)
  ///   pdu[1] = PairingKey
  ///   pdu[2] = SubFuncEcho
  ///   pdu[3] = Status (0xFE=success, 0xFD=error, other=error code)
  ///   pdu[4+] = Payload (on success) or error code (on 0xFD error)
  void _checkStatus(Uint8List pdu, String operation) {
    if (pdu.length < 4) {
      throw UmasException(
          errorCode: 0, message: 'UMAS $operation response too short');
    }
    final status = pdu[3];
    if (status == _statusError) {
      final errorCode = pdu.length > 4 ? pdu[4] : 0;
      throw UmasException(
          errorCode: errorCode,
          message: 'UMAS $operation error: '
              '0x${errorCode.toRadixString(16)}');
    }
    if (status != _statusSuccess) {
      throw UmasException(
          errorCode: status,
          message: 'UMAS $operation failed with status '
              '0x${status.toRadixString(16)}');
    }
  }

  /// Read PLC identification (sub-function 0x02).
  ///
  /// Extracts hardwareId and memory block index needed for 0x26 requests.
  /// Must be called before readVariableNames/readDataTypes/browse.
  Future<UmasPlcIdent> readPlcId() async {
    final request = UmasRequest(
      umasSubFunction: UmasSubFunction.readId.code,
      pairingKey: _pairingKey,
      unitId: unitId,
    );
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
          errorCode: code.code,
          message: 'UMAS readPlcId failed: ${code.name}');
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 4) {
      throw UmasException(
          errorCode: 0, message: 'Empty UMAS readPlcId response');
    }

    _checkStatus(pdu, 'readPlcId');

    // Parse payload after the 4-byte header (FC + pairing + subFuncEcho + status)
    final payload = pdu.sublist(4);
    if (payload.length < 7) {
      throw UmasException(
          errorCode: 0,
          message: 'UMAS readPlcId response too short: ${payload.length}');
    }

    final pd = ByteData.sublistView(payload);
    // range(2) + ident/hardwareId(4 LE) + numberOfMemoryBanks(1) + memBlockEntries
    // Skip range (2 bytes), read hardwareId (4 bytes LE)
    final hardwareId = pd.getUint32(2, Endian.little);

    // numberOfMemoryBanks at offset 6
    final numberOfMemoryBanks = pd.getUint8(6);

    // First memory block entry starts at offset 7:
    //   address(2 LE) + blockType(1) + unknown(2) + memoryLength(4) = 9 bytes
    int index = 0;
    if (numberOfMemoryBanks > 0 && payload.length >= 9) {
      index = pd.getUint16(7, Endian.little);
    }

    _hardwareId = hardwareId;
    _index = index;

    return UmasPlcIdent(
      hardwareId: hardwareId,
      index: index,
      numberOfMemoryBanks: numberOfMemoryBanks,
    );
  }

  /// Initialize UMAS communication (sub-function 0x01).
  /// Returns max frame size and optionally firmware version.
  Future<UmasInitResult> init() async {
    final request = UmasRequest(
        umasSubFunction: UmasSubFunction.init.code,
        pairingKey: _pairingKey,
        unitId: unitId);
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
          errorCode: code.code, message: 'UMAS init failed: ${code.name}');
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 4) {
      throw UmasException(errorCode: 0, message: 'Empty UMAS init response');
    }

    _checkStatus(pdu, 'init');

    // PDU: FC(0x5A) + pairingKey + subFuncEcho + status + payload
    final responsePairingKey = pdu[1];
    _pairingKey = responsePairingKey;

    // Parse payload after the 4-byte header (FC + pairing + subFuncEcho + status)
    if (pdu.length >= 6) {
      final payloadView = ByteData.sublistView(pdu, 4);
      maxFrameSize = payloadView.getUint16(0, Endian.little);
    }

    return UmasInitResult(maxFrameSize: maxFrameSize ?? 240);
  }

  /// Build the full 13-byte payload for 0x26 (ReadDataDictionary) requests.
  ///
  /// Format per PLC4X mspec:
  /// recordType(2 LE) + index(1) + hardwareId(4 LE) + blockNo(2 LE) +
  /// offset(2 LE) + blank(2 LE)
  Uint8List _build0x26Payload({
    required int recordType,
    required int blockNo,
    required int offset,
  }) {
    final bd = ByteData(13);
    bd.setUint16(0, recordType, Endian.little);
    bd.setUint8(2, _index ?? 0);
    bd.setUint32(3, _hardwareId ?? 0, Endian.little);
    bd.setUint16(7, blockNo, Endian.little);
    bd.setUint16(9, offset, Endian.little);
    bd.setUint16(11, 0x0000, Endian.little); // blank
    return bd.buffer.asUint8List();
  }

  /// Read variable names from the data dictionary (0x26 with record type 0xDD02).
  ///
  /// Paginates: loops until nextAddress == 0 after first response.
  Future<List<UmasVariable>> readVariableNames() async {
    final allVariables = <UmasVariable>[];
    int offset = 0x0000;
    bool firstMessage = true;

    while (offset != 0x0000 || firstMessage) {
      firstMessage = false;

      final payload = _build0x26Payload(
        recordType: 0xDD02,
        blockNo: 0xFFFF,
        offset: offset,
      );
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readDataDictionary.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
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

      _checkStatus(pdu, 'readVariableNames');

      // Parse variable records from payload after 4-byte UMAS header
      final (nextAddress, variables) = _parseVariableRecords(pdu.sublist(4));
      allVariables.addAll(variables);
      offset = nextAddress;
    }

    return allVariables;
  }

  /// Parse variable name records from the 0xDD02 response payload.
  ///
  /// Header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE)
  /// Each record: dataType(2 LE) + block(2 LE) + offset(2 LE) + unknown4(2 LE) +
  ///              stringLength(2 LE) + name (null-terminated)
  (int nextAddress, List<UmasVariable>) _parseVariableRecords(Uint8List data) {
    if (data.length < 7) return (0, []);

    final hd = ByteData.sublistView(data);
    // Header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE)
    // Skip range byte
    final nextAddress = hd.getUint16(1, Endian.little);
    // Skip unknown1 (2 bytes) at offset 3
    final noOfRecords = hd.getUint16(5, Endian.little);

    final variables = <UmasVariable>[];
    int pos = 7; // Start of records after 7-byte header

    for (int i = 0; i < noOfRecords && pos + 10 <= data.length; i++) {
      if (variables.length >= _maxVariables) break;

      final view = ByteData.sublistView(data, pos);
      final dataTypeId = view.getUint16(0, Endian.little);
      final blockNo = view.getUint16(2, Endian.little);
      final offset = view.getUint16(4, Endian.little);
      // skip unknown4 (2 bytes) at relative offset 6
      final stringLength = view.getUint16(8, Endian.little);
      pos += 10;

      if (stringLength > _maxNameLength || pos + stringLength > data.length) {
        break;
      }

      // Read name bytes and strip trailing null
      var nameBytes = data.sublist(pos, pos + stringLength);
      while (nameBytes.isNotEmpty && nameBytes.last == 0x00) {
        nameBytes = nameBytes.sublist(0, nameBytes.length - 1);
      }
      final name = utf8.decode(nameBytes);
      pos += stringLength;

      variables.add(UmasVariable(
        name: name,
        blockNo: blockNo,
        offset: offset,
        dataTypeId: dataTypeId,
      ));
    }

    return (nextAddress, variables);
  }

  /// Read data type references from the data dictionary (0x26 with record type 0xDD03).
  ///
  /// Paginates: loops until nextAddress == 0 after first response.
  Future<List<UmasDataTypeRef>> readDataTypes() async {
    final allTypes = <UmasDataTypeRef>[];
    int blockNo = 0x0000;
    bool firstMessage = true;

    while (blockNo != 0x0000 || firstMessage) {
      firstMessage = false;

      final payload = _build0x26Payload(
        recordType: 0xDD03,
        blockNo: blockNo,
        offset: 0x0000,
      );
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readDataDictionary.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
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

      _checkStatus(pdu, 'readDataTypes');

      final (nextAddress, types) = _parseDataTypeRecords(pdu.sublist(4));
      allTypes.addAll(types);
      blockNo = nextAddress;
    }

    return allTypes;
  }

  /// Parse data type records from the 0xDD03 response payload.
  ///
  /// Header: range(1) + nextAddress(2 LE) + unknown1(1) + noOfRecords(2 LE)
  /// Each record: dataSize(2 LE) + unknown1(2 LE) + classIdentifier(1) +
  ///              dataType(1) + stringLength(1) + name (null-terminated)
  (int nextAddress, List<UmasDataTypeRef>) _parseDataTypeRecords(
      Uint8List data) {
    if (data.length < 6) return (0, []);

    final hd = ByteData.sublistView(data);
    // Header: range(1) + nextAddress(2 LE) + unknown1(1) + noOfRecords(2 LE)
    // Skip range byte
    final nextAddress = hd.getUint16(1, Endian.little);
    // Skip unknown1 (1 byte) at offset 3
    final noOfRecords = hd.getUint16(4, Endian.little);

    final types = <UmasDataTypeRef>[];
    int pos = 6; // Start of records after 6-byte header

    for (int i = 0; i < noOfRecords && pos + 7 <= data.length; i++) {
      if (types.length >= _maxVariables) break;

      final view = ByteData.sublistView(data, pos);
      final dataSize = view.getUint16(0, Endian.little);
      // skip unknown1 (2 bytes) at relative offset 2
      final classIdentifier = view.getUint8(4);
      final dataType = view.getUint8(5);
      final stringLength = view.getUint8(6);
      pos += 7;

      if (stringLength > _maxNameLength || pos + stringLength > data.length) {
        break;
      }

      // Read name bytes and strip trailing null
      var nameBytes = data.sublist(pos, pos + stringLength);
      while (nameBytes.isNotEmpty && nameBytes.last == 0x00) {
        nameBytes = nameBytes.sublist(0, nameBytes.length - 1);
      }
      final name = utf8.decode(nameBytes);
      pos += stringLength;

      // Use a running ID based on position (PLC4X assigns IDs sequentially
      // starting from an offset; for now use 100 + index as a simple scheme).
      // The actual ID comes from the data dictionary ordering.
      types.add(UmasDataTypeRef(
        id: 100 + i,
        name: name,
        byteSize: dataSize,
        classIdentifier: classIdentifier,
        dataType: dataType,
      ));
    }

    return (nextAddress, types);
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

  /// Convenience method: readPlcId -> init -> readDataTypes -> readVariableNames -> buildVariableTree.
  /// This is the primary entry point for the browse dialog.
  Future<List<UmasVariableTreeNode>> browse() async {
    await readPlcId();
    await init();
    final dataTypes = await readDataTypes();
    final variables = await readVariableNames();
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

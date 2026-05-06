/// End-to-end integration test: UmasClient + ModbusClientTcp -> stub server.
///
/// Starts the Python stub UMAS server, connects via real ModbusClientTcp,
/// and exercises the full browse() flow including readPlcId, init,
/// readDataTypes, readVariableNames, and tree building.
///
/// Run: dart test test/umas_e2e_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:test/test.dart';

/// Port assigned by the OS after the stub server binds to port 0.
late int _stubPort;

/// Resolves the project root from the tfc_dart package directory.
String get _projectRoot {
  // When running from packages/tfc_dart, go up two levels
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/test/umas_stub_server.py').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  // Fallback: assume packages/tfc_dart
  return '${Directory.current.path}/../..';
}

Process? _serverProcess;

/// Pattern to extract the actual bound port from the stub's stdout.
/// The stub prints: "[STUB] UMAS stub server listening on PORT=<N>"
final _portPattern = RegExp(r'PORT=(\d+)');

Future<void> _startStub() async {
  final stubScript = '$_projectRoot/test/umas_stub_server.py';

  // Try python3 first (Unix, some Windows setups), fall back to python.
  String python;
  try {
    final r = await Process.run('python3', ['--version']);
    python = r.exitCode == 0 ? 'python3' : 'python';
  } catch (_) {
    python = 'python';
  }

  // Use port 0 so the OS assigns a free port — no cleanup needed.
  _serverProcess = await Process.start(
    python,
    ['-u', stubScript, '--port', '0'], // -u = unbuffered stdout
  );

  // Collect stderr for debugging
  final stderrBuf = StringBuffer();
  _serverProcess!.stderr
      .transform(const SystemEncoding().decoder)
      .listen((line) {
    stderr.write('[STUB ERR] $line');
    stderrBuf.write(line);
  });

  // Wait for the stub to print its actual port.
  final completer = Completer<int>();
  _serverProcess!.stdout
      .transform(const SystemEncoding().decoder)
      .listen((line) {
    stdout.write('[STUB] $line');
    if (!completer.isCompleted) {
      final match = _portPattern.firstMatch(line);
      if (match != null) {
        completer.complete(int.parse(match.group(1)!));
      }
    }
  });

  _stubPort = await completer.future.timeout(const Duration(seconds: 5),
      onTimeout: () => throw StateError(
          'Stub server did not start (python=$python, '
          'script=$stubScript, stderr=$stderrBuf)'));
}

void _stopStub() {
  _serverProcess?.kill();
  _serverProcess = null;
}

void main() {
  late ModbusClientTcp tcp;

  setUpAll(() async {
    await _startStub();
  });

  tearDownAll(() {
    _stopStub();
  });

  setUp(() {
    tcp = ModbusClientTcp(
      '127.0.0.1',
      serverPort: _stubPort,
      connectionTimeout: const Duration(seconds: 3),
    );
  });

  tearDown(() async {
    await tcp.disconnect();
  });

  test('full browse() via real TCP to stub server', () async {
    await tcp.connect();
    expect(tcp.isConnected, isTrue);

    final umas = UmasClient(sendFn: tcp.send);
    // browse() now does: readPlcId -> init -> readDataTypes -> readVariableNames -> tree
    final tree = await umas.browse();

    // Stub serves 10 variables under "Application" root
    expect(tree, hasLength(1), reason: 'single root: Application');
    final app = tree.first;
    expect(app.name, 'Application');
    expect(app.isFolder, isTrue);

    // Application has 3 child folders: GVL, Motor, Counters
    expect(app.children, hasLength(3));
    final childNames = app.children.map((c) => c.name).toSet();
    expect(childNames, containsAll(['GVL', 'Motor', 'Counters']));

    // GVL has 6 variables (5 scalars + 1 array)
    final gvl = app.children.firstWhere((c) => c.name == 'GVL');
    expect(gvl.children, hasLength(6));
    expect(gvl.isFolder, isTrue);

    // Check a leaf variable -- verify data survived the format change
    final temp = gvl.children.firstWhere((c) => c.name == 'temperature');
    expect(temp.isFolder, isFalse);
    expect(temp.variable, isNotNull);
    expect(temp.variable!.blockNo, 1);
    expect(temp.variable!.offset, 0);
    expect(temp.variable!.dataTypeId, 8); // REAL
    expect(temp.dataType?.name, 'REAL');
    expect(temp.dataType?.byteSize, 4);

    // Motor folder
    final motor = app.children.firstWhere((c) => c.name == 'Motor');
    expect(motor.children, hasLength(3));
    final speed = motor.children.firstWhere((c) => c.name == 'speed');
    expect(speed.variable!.blockNo, 2);
    expect(speed.variable!.dataTypeId, 8); // REAL
    expect(speed.dataType?.name, 'REAL');

    // Counters folder
    final counters = app.children.firstWhere((c) => c.name == 'Counters');
    expect(counters.children, hasLength(2));
    final runtime =
        counters.children.firstWhere((c) => c.name == 'runtime_ms');
    expect(runtime.dataType?.name, 'TIME');

    // Array variable: GVL.colors is `ARRAY[1..4] OF UINT` mapped to type 120.
    // Browse must expand it into 4 per-element children whose addresses fall
    // 2 bytes apart (UINT element size), with natural [1..4] indexing because
    // the array is 1D.
    final colors = gvl.children.firstWhere((c) => c.name == 'colors');
    expect(colors.dataType?.classIdentifier, 4,
        reason: 'colors is the array parent');
    expect(colors.children, hasLength(4),
        reason: 'array should expand into 4 per-element nodes');
    expect(colors.children.map((c) => c.name).toList(),
        ['[1]', '[2]', '[3]', '[4]']);
    final base = colors.variable!.offset;
    final addrs = colors.children
        .map((c) => c.variable!.offset - base)
        .toList();
    expect(addrs, [0, 2, 4, 6],
        reason: 'each UINT element occupies 2 bytes');
    for (final c in colors.children) {
      expect(c.variable!.dataTypeId, 5,
          reason: 'element type id is UINT');
      expect(c.dataType?.name, 'UINT');
      expect(c.dataType?.byteSize, 2);
    }
  });

  test('readPlcStatus returns CRC blocks from stub', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    // readPlcStatus uses _withSession which auto-calls readPlcId + init
    final result = await umas.readPlcStatus();

    expect(result.blockCrcs, hasLength(6));
    expect(result.numberOfBlocks, 6);
    expect(result.statusByte, 0x03); // running state
    // Verify deterministic CRC values from stub
    expect(result.blockCrcs[0], 0xAABBCCDD);
    expect(result.blockCrcs[5], 0x12345678);
  });

  test('keepAlive succeeds after init', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    // sendKeepAlive uses _withSession which auto-calls readPlcId + init
    await umas.sendKeepAlive();
    // If we get here without exception, keepAlive succeeded
  });

  test('echo returns round-trip payload and latency', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    final testPayload = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
    // sendEcho uses _withSession which auto-calls readPlcId + init
    final result = await umas.sendEcho(testPayload);

    expect(result.payload, equals(testPayload));
    expect(result.latency.inMicroseconds, greaterThan(0));
  });

  test('readProjectInfo returns project data', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    // readProjectInfo uses _withSession which auto-calls readPlcId + init
    final result = await umas.readProjectInfo();

    expect(result.rawData, isNotEmpty);
    expect(result.rawData.length, greaterThanOrEqualTo(20));
    // The stub returns "StubProject" embedded in the payload
    expect(result.projectName, isNotNull);
    expect(result.projectName, contains('StubProject'));
  });

  test('init() returns maxFrameSize (standalone, no readPlcId needed)',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    final result = await umas.init();

    // Stub returns 1021 matching real PLC at 10.50.10.12
    expect(result.maxFrameSize, 1021);
  });

  test('readVariableNames returns all 11 variables (requires readPlcId + init)',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    // readPlcId sets _hardwareId and _index needed by 0x26 payload
    await umas.readPlcId();
    await umas.init();

    final vars = await umas.readVariableNames();
    expect(vars, hasLength(11));

    // Check first variable
    expect(vars[0].name, 'Application.GVL.temperature');
    expect(vars[0].blockNo, 1);
    expect(vars[0].offset, 0);
    expect(vars[0].dataTypeId, 8); // REAL
  });

  test('readDataTypes returns custom types (requires readPlcId + init)',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcId();
    await umas.init();

    final types = await umas.readDataTypes();
    expect(types, hasLength(3));
    expect(types[0].name, 'MY_STRUCT');
    expect(types[0].byteSize, 16);
    expect(types[0].classIdentifier, 2);
    expect(types[1].name, 'ALARM_TYPE');
    expect(types[1].byteSize, 8);
    // Stub now uses non-conflicting custom type ids (real PLCs allocate
    // custom ids >=27 to avoid collisions with built-in scalar ids).
    expect(types[1].dataType, 28);
    // Array type definition: ARRAY[1..4] OF UINT
    expect(types[2].name, 'ARRAY[1..4] OF UINT');
    expect(types[2].byteSize, 8);
    expect(types[2].classIdentifier, 4);
  });

  test('readPlcId returns valid hardware identification', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    final ident = await umas.readPlcId();

    expect(ident.hardwareId, 0x12345678);
    expect(ident.index, 0);
    expect(ident.numberOfMemoryBanks, 1);
  });

  test('browse-derived array element addresses round-trip through readVariables',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcStatus();

    final tree = await umas.browse();
    final app = tree.first;
    final gvl = app.children.firstWhere((c) => c.name == 'GVL');
    final colors = gvl.children.firstWhere((c) => c.name == 'colors');

    // Each element should read back its stub-stored UINT value: 100, 200, 300, 400.
    final pairs = [
      for (final c in colors.children) (c.variable!, c.dataType!),
    ];
    final values = await umas.readVariables(pairs);
    expect(values.map((v) => v.value).toList(), [100, 200, 300, 400]);
    expect(values.every((v) => v.typeName == 'UINT'), isTrue);
  });

  test('stub responds to ReadVariable (0x22) with variable data', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    // Need session for pairing key
    await umas.readPlcId();
    await umas.init();
    final status = await umas.readPlcStatus();

    // Build ReadVariable request payload:
    // crc(4 LE) + count(1) + ref: byte0(1) + block(2 LE) + 0x01(1) + baseOffset(2 LE) + offset(1)
    // Read temperature: block=1, baseOffset=0, REAL=dataSizeIndex 3 (4 bytes)
    final crc = ByteData(4)..setUint32(0, status.blockCrcs[0], Endian.little);
    final payload = BytesBuilder();
    payload.add(crc.buffer.asUint8List()); // CRC (4 bytes)
    payload.addByte(1); // variableCount = 1
    // VariableRef: isArray=0, dataSizeIndex=3 (REAL=4B) => byte0 = 0x03
    payload.addByte(0x03); // isArray(0) | dataSizeIndex(3)
    payload.add((ByteData(2)..setUint16(0, 1, Endian.little))
        .buffer
        .asUint8List()); // block = 1
    payload.addByte(0x01); // constant 0x01
    payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
        .buffer
        .asUint8List()); // baseOffset = 0
    payload.addByte(0x00); // offset byte

    final request = UmasRequest(
      umasSubFunction: 0x22,
      pairingKey: 0x00,
      payload: Uint8List.fromList(payload.toBytes()),
    );
    final code = await tcp.send(request);
    expect(code, ModbusResponseCode.requestSucceed);

    final pdu = request.responsePdu!;
    // 3-byte header + 4 bytes (REAL)
    expect(pdu.length, greaterThanOrEqualTo(7));
    expect(pdu[2], 0xFE); // success status

    // Parse REAL value from response payload (after 3-byte header)
    final bd = ByteData.sublistView(pdu, 3);
    final temperature = bd.getFloat32(0, Endian.little);
    expect(temperature, closeTo(22.5, 0.01));
  });

  test('stub responds to WriteVariable (0x23) with success', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcId();
    await umas.init();
    final status = await umas.readPlcStatus();

    // Build WriteVariable request payload:
    // crc(4 LE) + count(1) + writeRef: byte0(1) + block(2 LE) + baseOffset(2 LE) + offset(2 LE) + data
    // Write setpoint: block=1, baseOffset=9, INT=dataSizeIndex 2 (2 bytes), value=200
    final crc = ByteData(4)..setUint32(0, status.blockCrcs[0], Endian.little);
    final payload = BytesBuilder();
    payload.add(crc.buffer.asUint8List()); // CRC
    payload.addByte(1); // variableCount = 1
    // WriteRef: isArray=0, dataSizeIndex=2 (INT=2B) => byte0 = 0x02
    payload.addByte(0x02);
    payload.add((ByteData(2)..setUint16(0, 1, Endian.little))
        .buffer
        .asUint8List()); // block = 1
    payload.add((ByteData(2)..setUint16(0, 9, Endian.little))
        .buffer
        .asUint8List()); // baseOffset = 9
    payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
        .buffer
        .asUint8List()); // offset = 0
    // Data: INT value 200 as 2 bytes LE
    payload.add(
        (ByteData(2)..setInt16(0, 200, Endian.little)).buffer.asUint8List());

    final request = UmasRequest(
      umasSubFunction: 0x23,
      pairingKey: 0x00,
      payload: Uint8List.fromList(payload.toBytes()),
    );
    final code = await tcp.send(request);
    expect(code, ModbusResponseCode.requestSucceed);

    final pdu = request.responsePdu!;
    expect(pdu[2], 0xFE); // success status
    // WriteVariable returns empty payload (just 3-byte header)
    expect(pdu.length, 3);
  });

  test('write then read returns updated value', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcId();
    await umas.init();
    final status = await umas.readPlcStatus();

    final crc = ByteData(4)..setUint32(0, status.blockCrcs[0], Endian.little);

    // Step 1: Write temperature (block=1, offset=0, REAL) to 42.0
    {
      final payload = BytesBuilder();
      payload.add(crc.buffer.asUint8List());
      payload.addByte(1); // count
      payload.addByte(0x03); // dataSizeIndex=3 (REAL=4B)
      payload.add((ByteData(2)..setUint16(0, 1, Endian.little))
          .buffer
          .asUint8List()); // block=1
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List()); // baseOffset=0
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List()); // offset=0
      // Data: REAL 42.0
      payload.add((ByteData(4)..setFloat32(0, 42.0, Endian.little))
          .buffer
          .asUint8List());

      final writeReq = UmasRequest(
        umasSubFunction: 0x23,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      final code = await tcp.send(writeReq);
      expect(code, ModbusResponseCode.requestSucceed);
      expect(writeReq.responsePdu![2], 0xFE);
    }

    // Step 2: Read temperature back
    {
      final payload = BytesBuilder();
      payload.add(crc.buffer.asUint8List());
      payload.addByte(1); // count
      payload.addByte(0x03); // dataSizeIndex=3 (REAL=4B)
      payload.add((ByteData(2)..setUint16(0, 1, Endian.little))
          .buffer
          .asUint8List()); // block=1
      payload.addByte(0x01); // constant
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List()); // baseOffset=0
      payload.addByte(0x00); // offset byte

      final readReq = UmasRequest(
        umasSubFunction: 0x22,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      final code = await tcp.send(readReq);
      expect(code, ModbusResponseCode.requestSucceed);

      final pdu = readReq.responsePdu!;
      expect(pdu[2], 0xFE);
      final bd = ByteData.sublistView(pdu, 3);
      final readBack = bd.getFloat32(0, Endian.little);
      expect(readBack, closeTo(42.0, 0.01));
    }
  });

  test('MonitorPlc register and read via raw PDU', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcId();
    await umas.init();

    // Step 1: Register temperature (block=1, offset=0) at variableIndex=0
    // MonitorPlc (0x50) Register (0x05): subCmd(1) + unknown(1) + numSubOps(1)
    //   + [opType(0x05) + variableIndex(1) + block(2 LE) + offset(2 LE)
    //      + action(1)]
    {
      final payload = BytesBuilder();
      payload.addByte(0x05); // subCommand = Register
      payload.addByte(0x00); // unknown
      payload.addByte(1); // numberOfSubOps = 1
      payload.addByte(0x05); // sub-op operationType discriminator
      payload.addByte(0); // variableIndex = 0
      payload.add((ByteData(2)..setUint16(0, 1, Endian.little))
          .buffer
          .asUint8List()); // block = 1
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List()); // offset = 0
      payload.addByte(0x02); // action = register

      final request = UmasRequest(
        umasSubFunction: 0x50,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);
      expect(request.responsePdu![2], 0xFE); // success
    }

    // Step 2: ReadAll (0x07) -- should return temperature bytes
    {
      final payload = BytesBuilder();
      payload.addByte(0x07); // subCommand = ReadAll

      final request = UmasRequest(
        umasSubFunction: 0x50,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);

      final pdu = request.responsePdu!;
      expect(pdu[2], 0xFE); // success
      // Should have 3-byte header + 4 bytes (REAL temperature)
      expect(pdu.length, greaterThanOrEqualTo(7));
      final bd = ByteData.sublistView(pdu, 3);
      final temperature = bd.getFloat32(0, Endian.little);
      expect(temperature, closeTo(22.5, 0.01));
    }
  });

  test('MonitorPlc reset clears registrations', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcId();
    await umas.init();

    // Register a variable
    {
      final payload = BytesBuilder();
      payload.addByte(0x05); // subCommand = Register
      payload.addByte(0x00);
      payload.addByte(1);
      payload.addByte(0x05); // sub-op operationType discriminator
      payload.addByte(0); // variableIndex = 0
      payload.add((ByteData(2)..setUint16(0, 1, Endian.little))
          .buffer
          .asUint8List());
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List());
      payload.addByte(0x02); // register

      final request = UmasRequest(
        umasSubFunction: 0x50,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      await tcp.send(request);
    }

    // Reset
    {
      final payload = BytesBuilder();
      payload.addByte(0x0B); // Reset

      final request = UmasRequest(
        umasSubFunction: 0x50,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);
      expect(request.responsePdu![2], 0xFE);
    }

    // ReadAll should return empty (just 3-byte header)
    {
      final payload = BytesBuilder();
      payload.addByte(0x07); // ReadAll

      final request = UmasRequest(
        umasSubFunction: 0x50,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);

      final pdu = request.responsePdu!;
      expect(pdu[2], 0xFE);
      // Empty payload -- just 3-byte header
      expect(pdu.length, 3);
    }
  });

  test('diagnostic sub-functions return responses', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcId();
    await umas.init();

    // ReadCardInfo (0x06)
    {
      final request = UmasRequest(
        umasSubFunction: 0x06,
        pairingKey: 0x00,
        payload: Uint8List(0),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);
      expect(request.responsePdu![2], 0xFE);
      expect(request.responsePdu!.length, greaterThan(3));
    }

    // ReadMemoryBlock (0x20): range(1) + blockNumber(2 LE) + offset(2 LE) + unknownObj(2 LE) + numberOfBytes(2 LE)
    {
      final payload = BytesBuilder();
      payload.addByte(0x00); // range
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List()); // blockNumber
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List()); // offset
      payload.add((ByteData(2)..setUint16(0, 0, Endian.little))
          .buffer
          .asUint8List()); // unknownObj
      payload.add((ByteData(2)..setUint16(0, 8, Endian.little))
          .buffer
          .asUint8List()); // numberOfBytes = 8

      final request = UmasRequest(
        umasSubFunction: 0x20,
        pairingKey: 0x00,
        payload: Uint8List.fromList(payload.toBytes()),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);
      expect(request.responsePdu![2], 0xFE);
      // Response: 3-byte header + range(1) + numberOfBytes(2 LE) + data[8]
      expect(request.responsePdu!.length, greaterThanOrEqualTo(3 + 1 + 2 + 8));
    }

    // ReadEthMasterData (0x39)
    {
      final request = UmasRequest(
        umasSubFunction: 0x39,
        pairingKey: 0x00,
        payload: Uint8List(0),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);
      expect(request.responsePdu![2], 0xFE);
      expect(request.responsePdu!.length, greaterThan(3));
    }

    // CheckPlc (0x58)
    {
      final request = UmasRequest(
        umasSubFunction: 0x58,
        pairingKey: 0x00,
        payload: Uint8List(0),
      );
      final code = await tcp.send(request);
      expect(code, ModbusResponseCode.requestSucceed);
      expect(request.responsePdu![2], 0xFE);
    }
  });

  test('variable tree paths are correct for BrowseDataSource IDs', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    final tree = await umas.browse();

    final app = tree.first;
    expect(app.path, 'Application');

    final gvl = app.children.firstWhere((c) => c.name == 'GVL');
    expect(gvl.path, 'Application.GVL');

    final temp = gvl.children.firstWhere((c) => c.name == 'temperature');
    expect(temp.path, 'Application.GVL.temperature');
  });
}

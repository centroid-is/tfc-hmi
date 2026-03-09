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

import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:test/test.dart';

const _stubPort = 15020; // High port to avoid conflicts

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

Future<void> _startStub() async {
  // Kill any leftover stub on our port
  try {
    final result =
        await Process.run('lsof', ['-ti', ':$_stubPort']);
    final pids = (result.stdout as String).trim();
    if (pids.isNotEmpty) {
      await Process.run('kill', ['-9', ...pids.split('\n')]);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  } catch (_) {}

  final stubScript = '$_projectRoot/test/umas_stub_server.py';
  _serverProcess = await Process.start(
    'python3',
    ['-u', stubScript, '$_stubPort'], // -u = unbuffered stdout
  );

  // Collect stderr for debugging
  _serverProcess!.stderr
      .transform(const SystemEncoding().decoder)
      .listen((line) => stderr.write('[STUB ERR] $line'));

  // Wait for "listening" in stdout
  final completer = Completer<void>();
  _serverProcess!.stdout
      .transform(const SystemEncoding().decoder)
      .listen((line) {
    stdout.write('[STUB] $line');
    if (!completer.isCompleted && line.contains('listening')) {
      completer.complete();
    }
  });

  await completer.future.timeout(const Duration(seconds: 5),
      onTimeout: () => throw StateError('Stub server did not start'));
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

    // GVL has 5 variables
    final gvl = app.children.firstWhere((c) => c.name == 'GVL');
    expect(gvl.children, hasLength(5));
    expect(gvl.isFolder, isTrue);

    // Check a leaf variable -- verify data survived the format change
    final temp = gvl.children.firstWhere((c) => c.name == 'temperature');
    expect(temp.isFolder, isFalse);
    expect(temp.variable, isNotNull);
    expect(temp.variable!.blockNo, 1);
    expect(temp.variable!.offset, 0);
    expect(temp.variable!.dataTypeId, 5); // REAL
    expect(temp.dataType?.name, 'REAL');
    expect(temp.dataType?.byteSize, 4);

    // Motor folder
    final motor = app.children.firstWhere((c) => c.name == 'Motor');
    expect(motor.children, hasLength(3));
    final speed = motor.children.firstWhere((c) => c.name == 'speed');
    expect(speed.variable!.blockNo, 2);
    expect(speed.variable!.dataTypeId, 5); // REAL
    expect(speed.dataType?.name, 'REAL');

    // Counters folder
    final counters = app.children.firstWhere((c) => c.name == 'Counters');
    expect(counters.children, hasLength(2));
    final runtime =
        counters.children.firstWhere((c) => c.name == 'runtime_ms');
    expect(runtime.dataType?.name, 'TIME');
  });

  test('init() returns maxFrameSize (standalone, no readPlcId needed)',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    final result = await umas.init();

    // Stub returns 1024
    expect(result.maxFrameSize, 1024);
  });

  test('readVariableNames returns all 10 variables (requires readPlcId + init)',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    // readPlcId sets _hardwareId and _index needed by 0x26 payload
    await umas.readPlcId();
    await umas.init();

    final vars = await umas.readVariableNames();
    expect(vars, hasLength(10));

    // Check first variable
    expect(vars[0].name, 'Application.GVL.temperature');
    expect(vars[0].blockNo, 1);
    expect(vars[0].offset, 0);
    expect(vars[0].dataTypeId, 5); // REAL
  });

  test('readDataTypes returns custom types (requires readPlcId + init)',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    await umas.readPlcId();
    await umas.init();

    final types = await umas.readDataTypes();
    expect(types, hasLength(2));
    expect(types[0].name, 'MY_STRUCT');
    expect(types[0].byteSize, 16);
    expect(types[0].classIdentifier, 2);
    expect(types[1].name, 'ALARM_TYPE');
    expect(types[1].byteSize, 8);
    expect(types[1].dataType, 5);
  });

  test('readPlcId returns valid hardware identification', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    final ident = await umas.readPlcId();

    expect(ident.hardwareId, 0x12345678);
    expect(ident.index, 0);
    expect(ident.numberOfMemoryBanks, 1);
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

/// End-to-end integration tests for UMAS diagnostic sub-functions.
///
/// Starts the Python stub UMAS server, connects via real ModbusClientTcp,
/// and exercises all 6 diagnostic client methods over real TCP.
///
/// Run: cd packages/tfc_dart && dart test test/umas_diagnostics_e2e_test.dart -t e2e
@Tags(['e2e'])
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
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

  // Use port 0 so the OS assigns a free port -- no cleanup needed.
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
  late UmasClient umas;

  setUpAll(() async {
    await _startStub();
  });

  tearDownAll(() {
    _stopStub();
  });

  setUp(() async {
    tcp = ModbusClientTcp(
      '127.0.0.1',
      serverPort: _stubPort,
      connectionTimeout: const Duration(seconds: 3),
    );
    await tcp.connect();
    umas = UmasClient(sendFn: tcp.send);
  });

  tearDown(() async {
    await tcp.disconnect();
  });

  test('readCardInfo returns card info over TCP', () async {
    final result = await umas.readCardInfo();
    expect(result.rawData.length, 16);
    expect(result.rawData[0], 0x01); // card present
  });

  test('readMemoryBlock returns requested bytes over TCP', () async {
    final result = await umas.readMemoryBlock(
      ReadMemoryBlockRequest(
        range: 0,
        blockNumber: 0,
        offset: 0,
        numberOfBytes: 32,
      ),
    );
    expect(result.range, 0);
    expect(result.numberOfBytes, 32);
    expect(result.data.length, 32);
  });

  test('readEthMasterData returns network data over TCP', () async {
    final result = await umas.readEthMasterData();
    expect(result.rawData.length, 32);
    expect(result.rawData[0], 0x01); // module count
  });

  test('checkPlc returns health data over TCP', () async {
    final result = await umas.checkPlc();
    expect(result.rawData.length, 8);
  });

  test('readIoObject returns I/O data over TCP', () async {
    final result = await umas.readIoObject();
    expect(result.rawData.length, 16);
    expect(result.rawData[0], 0x01); // module count
  });

  test('getStatusModule returns module status over TCP', () async {
    final result = await umas.getStatusModule();
    expect(result.rawData.length, 12);
    expect(result.rawData[0], 0x01); // module count
  });
}

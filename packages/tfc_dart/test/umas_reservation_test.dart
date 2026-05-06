/// Tests for PLC reservation lifecycle (0x10/0x11).
///
/// Covers: takePlcReservation, releasePlcReservation, withReservation,
/// conflict handling, and session error cleanup.
///
/// Run: dart test test/umas_reservation_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

/// Port assigned by the OS after the stub server binds to port 0.
late int _stubPort;

/// Resolves the project root from the tfc_dart package directory.
String get _projectRoot {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/test/umas_stub_server.py').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return '${Directory.current.path}/../..';
}

Process? _serverProcess;

final _portPattern = RegExp(r'PORT=(\d+)');

Future<void> _startStub() async {
  final stubScript = '$_projectRoot/test/umas_stub_server.py';

  String python;
  try {
    final r = await Process.run('python3', ['--version']);
    python = r.exitCode == 0 ? 'python3' : 'python';
  } catch (_) {
    python = 'python';
  }

  _serverProcess = await Process.start(
    python,
    ['-u', stubScript, '--port', '0'],
  );

  final stderrBuf = StringBuffer();
  _serverProcess!.stderr
      .transform(const SystemEncoding().decoder)
      .listen((line) {
    stderr.write('[STUB ERR] $line');
    stderrBuf.write(line);
  });

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

  group('UmasSubFunction enum', () {
    test('has takePlcReservation with code 0x10', () {
      expect(UmasSubFunction.takePlcReservation.code, 0x10);
    });

    test('has releasePlcReservation with code 0x11', () {
      expect(UmasSubFunction.releasePlcReservation.code, 0x11);
    });
  });

  group('takePlcReservation', () {
    test('acquires reservation and sets hasReservation=true', () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);
      expect(umas.hasReservation, isFalse);

      await umas.takePlcReservation();
      expect(umas.hasReservation, isTrue);
    });

    test('throws UmasReservationException on conflict', () async {
      await tcp.connect();

      // Use a mock sendFn that returns error for 0x10
      final umas = UmasClient(sendFn: (request) async {
        // For readPlcId and init, delegate to tcp
        if (request is UmasRequest &&
            request.umasSubFunction != UmasSubFunction.takePlcReservation.code) {
          return tcp.send(request);
        }
        // For takePlcReservation, simulate conflict error response
        if (request is UmasRequest) {
          final pdu = Uint8List.fromList([0x5A, 0x00, 0xFD, 0x01]);
          request.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        }
        return ModbusResponseCode.requestSucceed;
      });

      expect(
        () => umas.takePlcReservation(),
        throwsA(isA<UmasReservationException>()),
      );
    });
  });

  group('releasePlcReservation', () {
    test('releases reservation and sets hasReservation=false', () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);

      await umas.takePlcReservation();
      expect(umas.hasReservation, isTrue);

      await umas.releasePlcReservation();
      expect(umas.hasReservation, isFalse);
    });

    test('sets hasReservation=false even on error (best-effort)', () async {
      await tcp.connect();
      var callCount = 0;

      final umas = UmasClient(sendFn: (request) async {
        if (request is UmasRequest &&
            request.umasSubFunction == UmasSubFunction.releasePlcReservation.code) {
          callCount++;
          // Simulate error response
          final pdu = Uint8List.fromList([0x5A, 0x00, 0xFD, 0x02]);
          request.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        }
        return tcp.send(request);
      });

      // First acquire normally
      await umas.takePlcReservation();
      expect(umas.hasReservation, isTrue);

      // Release will get error but should still clear hasReservation
      await umas.releasePlcReservation();
      expect(umas.hasReservation, isFalse);
      expect(callCount, 1);
    });
  });

  group('withReservation', () {
    test('acquires, runs operation, releases on success', () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);

      var operationRan = false;
      final result = await umas.withReservation(() async {
        expect(umas.hasReservation, isTrue);
        operationRan = true;
        return 42;
      });

      expect(result, 42);
      expect(operationRan, isTrue);
      expect(umas.hasReservation, isFalse);
    });

    test('releases reservation even when operation throws', () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);

      expect(
        () => umas.withReservation(() async {
          expect(umas.hasReservation, isTrue);
          throw StateError('operation failed');
        }),
        throwsA(isA<StateError>()),
      );

      // Wait for async to settle
      await Future<void>.delayed(Duration.zero);
      expect(umas.hasReservation, isFalse);
    });
  });

  group('session error clears reservation', () {
    test('_handleSessionError clears hasReservation', () async {
      await tcp.connect();
      var failBrowse = false;

      final umas = UmasClient(sendFn: (request) async {
        if (failBrowse &&
            request is UmasRequest &&
            request.umasSubFunction == UmasSubFunction.readDataDictionary.code) {
          throw UmasException(errorCode: 0, message: 'connection lost');
        }
        return tcp.send(request);
      });

      // Get into paired state and acquire reservation
      await umas.takePlcReservation();
      expect(umas.hasReservation, isTrue);

      // Now make next operation fail -- browse uses _withSessionAndRecovery
      // which calls _handleSessionError on UmasException
      failBrowse = true;
      try {
        await umas.browse();
      } catch (_) {}

      // _handleSessionError should have cleared hasReservation
      expect(umas.hasReservation, isFalse);
      expect(umas.sessionState, UmasSessionState.uninitialized);
    });
  });

  group('E2E reservation via stub', () {
    test('acquire and release reservation via stub server', () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);

      // Acquire reservation
      await umas.takePlcReservation();
      expect(umas.hasReservation, isTrue);

      // Release reservation
      await umas.releasePlcReservation();
      expect(umas.hasReservation, isFalse);
    });

    test('withReservation wraps operation E2E', () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);

      final result = await umas.withReservation(() async {
        // Could do a read here to prove we're in a reservation
        expect(umas.hasReservation, isTrue);
        return 'success';
      });

      expect(result, 'success');
      expect(umas.hasReservation, isFalse);
    });
  });
}

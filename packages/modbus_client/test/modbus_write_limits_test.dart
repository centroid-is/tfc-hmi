import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';

void main() {
  group('FC16 write quantity limits (BUG-05)', () {
    /// Helper to create byte array for N registers (2 bytes per register).
    Uint8List registerBytes(int registerCount) {
      return Uint8List(registerCount * 2);
    }

    test('FC16 writeMultiple with 123 registers (max allowed) succeeds', () {
      final reg = ModbusUint16Register(
          name: 'r', address: 0, type: ModbusElementType.holdingRegister);
      // 123 registers = 246 bytes (max for FC16)
      final bytes = registerBytes(123);
      expect(
        () => reg.getMultipleWriteRequest(bytes),
        returnsNormally,
      );
    });

    test('FC16 writeMultiple with 124 registers throws AssertionError', () {
      final reg = ModbusUint16Register(
          name: 'r', address: 0, type: ModbusElementType.holdingRegister);
      // 124 registers = 248 bytes (exceeds FC16 max of 123)
      final bytes = registerBytes(124);
      expect(
        () => reg.getMultipleWriteRequest(bytes),
        throwsA(isA<AssertionError>()),
      );
    });

    test('FC16 writeMultiple with 1 register (min) succeeds', () {
      final reg = ModbusUint16Register(
          name: 'r', address: 0, type: ModbusElementType.holdingRegister);
      final bytes = registerBytes(1);
      expect(
        () => reg.getMultipleWriteRequest(bytes),
        returnsNormally,
      );
    });
  });

  group('FC15 write quantity limits (BUG-05)', () {
    /// Helper to build packed coil bytes.
    Uint8List packedCoilBytes(int coilCount) {
      final byteCount = (coilCount + 7) ~/ 8;
      return Uint8List(byteCount);
    }

    test('FC15 writeMultiple with 1968 coils (max allowed) succeeds', () {
      final coil = ModbusCoil(name: 'c', address: 0);
      // 1968 coils = 246 bytes (max for FC15)
      final bytes = packedCoilBytes(1968);
      expect(
        () => coil.getMultipleWriteRequest(bytes, quantity: 1968),
        returnsNormally,
      );
    });

    test('FC15 writeMultiple with 1969 coils throws AssertionError', () {
      final coil = ModbusCoil(name: 'c', address: 0);
      // 1969 coils = 247 bytes (exceeds FC15 byte limit of 246)
      final bytes = packedCoilBytes(1969);
      expect(
        () => coil.getMultipleWriteRequest(bytes, quantity: 1969),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('byte count field limit (BUG-05)', () {
    test('bytes.length > 246 throws AssertionError for FC16', () {
      final reg = ModbusUint16Register(
          name: 'r', address: 0, type: ModbusElementType.holdingRegister);
      // 247 bytes (exceeds uint8 safe limit of 246)
      final bytes = Uint8List(247);
      expect(
        () => reg.getMultipleWriteRequest(bytes),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

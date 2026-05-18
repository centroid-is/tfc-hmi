import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_types.dart';

void main() {
  group('MonitorPlcRegistrationTable.parseReadAllResponse — STRING clamp', () {
    test('STRING registered with byteSize=256 decodes from 4-byte clamped response', () {
      final table = MonitorPlcRegistrationTable();
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      const boolType = UmasDataTypeRef(id: 1, name: 'BOOL', byteSize: 1);

      table.register(0, stringType);
      table.register(1, boolType); // second variable proves offset advanced by 4, not 256

      // PLC returns DSI=3 clamped 4 bytes for STRING, then 1 byte for BOOL.
      // Hex shape from /tmp/umas-string-bug-report.md (live M580 @ 192.168.112.159).
      final bytes = Uint8List.fromList([
        /* STRING — 4 clamped bytes */ 0x4f, 0x4b, 0x00, 0x00, // "OK" null-padded
        /* BOOL */ 0x01,
      ]);

      final result = table.parseReadAllResponse(bytes);

      expect(result.length, 2);
      expect(result[0].typeName, 'STRING');
      // Assertion (a): decoded value matches expected string.
      expect(result[0].value, equals('OK'));
      // Assertion (b): offset advanced by 4 (actual), not 256 (declared) —
      // otherwise the BOOL parse would have thrown underflow.
      expect(result[1].typeName, 'BOOL');
      expect(result[1].value, equals(true));
    });

    test('STRING with empty PLC response decodes to empty string', () {
      final table = MonitorPlcRegistrationTable();
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      table.register(0, stringType);

      final result = table.parseReadAllResponse(Uint8List(0));

      expect(result.length, 1);
      expect(result[0].value, equals(''));
    });
  });

  group('parseVariableValues — STRING bound check (CRIT-1)', () {
    test('STRING(byteSize=256) with 1-byte 0x22 response does not throw', () {
      // Live M580 (0x22 ReadVariable) returns 1 byte for an empty STRING(256).
      // The pre-loop bound check used to require 4 bytes per STRING (clamped
      // ceiling), which threw "Buffer underflow" before any value was parsed.
      // Phase 1 fixed the 0x50 MonitorPlc path; CRIT-1 covers the 0x22 path.
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      final bytes = Uint8List.fromList([0x00]);

      final result = parseVariableValues(bytes, [stringType]);

      expect(result.length, 1);
      expect(result[0].typeName, 'STRING');
      expect(result[0].value, equals(''));
    });

    test('STRING(byteSize=256) with "OK"+null+pad 4-byte response decodes', () {
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      final bytes = Uint8List.fromList([0x4f, 0x4b, 0x00, 0x00]);

      final result = parseVariableValues(bytes, [stringType]);

      expect(result.length, 1);
      expect(result[0].value, equals('OK'));
    });
  });
}

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

  // JOB-A (v1.1): defensive belt-and-braces — even when a hypothetical
  // PLC-side bug or upstream parser advance hands us an out-of-range
  // offset, STRING/BYTE_STRING/WSTRING must NEVER throw "Buffer
  // underflow". The HMI UMAS browse dialog catches that exception via
  // `'read error: $e'`, surfacing the literal text "underflow" to the
  // operator. The fix here is at the parser; the dialog also renders a
  // neutral placeholder on exception.
  group('parseVariableValue — STRING never throws (JOB-A)', () {
    test('STRING with empty buffer at offset 0 returns empty string', () {
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      final result = parseVariableValue(Uint8List(0), 0, stringType);
      expect(result.value, equals(''));
      expect(result.typeName, 'STRING');
    });

    test('STRING with offset > bytes.length returns empty string', () {
      // This is the defensive case: a prior iteration in
      // parseReadAllResponse over-advanced past the buffer. Pre-fix the
      // `available < 0` branch threw "Buffer underflow". Post-fix, STRING
      // gracefully returns an empty string.
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      final bytes = Uint8List.fromList([0x4f]); // 1 byte
      final result = parseVariableValue(bytes, 4, stringType);
      expect(result.value, equals(''));
      expect(result.typeName, 'STRING');
    });

    test('STRING with malformed UTF-8 mid-codepoint does not throw', () {
      // Schneider's 4-byte clamp can split a multi-byte UTF-8 codepoint —
      // a hard utf8.decode would throw FormatException and re-surface as
      // an error string in the UI. JOB-A: decode with allowMalformed.
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      // 0xC3 0x84 = 'Ä' (2 bytes); 0xC3 alone is half of a codepoint.
      final bytes = Uint8List.fromList([0xC3, 0x4f, 0x00, 0x00]);
      final result = parseVariableValue(bytes, 0, stringType);
      // Malformed first byte is replaced; rest decodes cleanly.
      expect(result.typeName, 'STRING');
      expect(result.value, isA<String>());
      // No throw — that's the assertion that matters.
    });

    test('BYTE_STRING with under-read does not throw', () {
      const bsType = UmasDataTypeRef(id: 30, name: 'BYTE_STRING', byteSize: 64);
      final result = parseVariableValue(Uint8List(0), 0, bsType);
      expect(result.value, equals(''));
    });
  });

  // parseReadAllResponse defensive advance clamp (JOB-A): the M580 0x50
  // path normally pads STRING to a 4-byte slot, but if the PLC ever
  // returns fewer bytes than expected, advancing by the static clamp
  // can push `offset` past `rawBytes.length`. The clamp prevents
  // subsequent reads from receiving a negative `available` and falling
  // into a throw path. This is purely defensive — current observation
  // of the M580 at 192.168.112.159 shows reliable 4-byte STRING slots.
  group('parseReadAllResponse advance clamp for STRING (JOB-A)', () {
    test('STRING-only over-clamp still decodes the available bytes', () {
      final table = MonitorPlcRegistrationTable();
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      table.register(0, stringType);

      // PLC returned only 1 byte for STRING instead of the standard 4.
      // The parser must consume what arrived and not throw.
      final result =
          table.parseReadAllResponse(Uint8List.fromList([0x4e]));
      expect(result.length, 1);
      expect(result[0].typeName, 'STRING');
      expect(result[0].value, equals('N'));
    });

    test('STRING with zero-byte response decodes to empty string', () {
      final table = MonitorPlcRegistrationTable();
      const stringType = UmasDataTypeRef(id: 9, name: 'STRING', byteSize: 256);
      table.register(0, stringType);

      final result = table.parseReadAllResponse(Uint8List(0));
      expect(result.length, 1);
      expect(result[0].value, equals(''));
    });
  });
}

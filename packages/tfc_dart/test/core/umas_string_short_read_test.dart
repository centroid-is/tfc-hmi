import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_types.dart';

/// A STRING whose declared width exceeds what an M580 actually returns. The
/// PLC clamps wide STRING reads, so the decoder must cope with a slice that
/// is shorter than `byteSize` -- including zero bytes.
const str8 = UmasDataTypeRef(id: 30, name: 'STRING', byteSize: 8);
const int16 = UmasDataTypeRef(id: 4, name: 'INT', byteSize: 2);

void main() {
  group('STRING short reads decode rather than throw', () {
    test('a STRING truncated mid-buffer yields the bytes that arrived', () {
      final wire = Uint8List.fromList([0x61, 0x62, 0x00]); // "ab\0"
      final parsed = parseVariableValues(wire, [str8]);
      expect(parsed.single.value, 'ab');
    });

    test('two STRINGs sharing a 3-byte buffer both decode', () {
      final wire = Uint8List.fromList([0x61, 0x62, 0x00]);
      final parsed = parseVariableValues(wire, [str8, str8]);
      expect(parsed.length, 2);
      expect(parsed[0].value, 'ab');
      // Nothing is left for the second one; it must decode empty, not throw
      // and not read backwards into the first string's bytes.
      expect(parsed[1].value, '');
    });

    test('a zero-byte STRING decodes empty', () {
      final parsed = parseVariableValues(Uint8List(0), [str8]);
      expect(parsed.single.value, '');
    });

    test('a scalar after a clamped STRING still aligns', () {
      // STRING declares 8; the walk steps over it by the clamped 4, so the
      // INT must be decoded from offset 4.
      final wire = Uint8List.fromList([
        0x61, 0x62, 0x63, 0x64, // "abcd", no NUL -> fills the 4-byte slot
        ...encodeVariableValue(1234, int16),
      ]);
      final parsed = parseVariableValues(wire, [str8, int16]);
      expect(parsed[1].value, 1234,
          reason: 'the scalar after a clamped STRING read the wrong bytes');
    });

    test('CHARACTERISATION: an unterminated STRING over-reads its slot', () {
      // Pinning current behaviour, NOT asserting it is correct. The walk
      // advances over a STRING by min(byteSize, 4), but parseVariableValue
      // slices min(byteSize, available) -- so a STRING with no NUL inside its
      // slot keeps reading into whatever follows it. Here the trailing bytes
      // are the next variable's INT encoding, which land inside the string.
      //
      // Reader and advancer disagree for STRING exactly as they did for the
      // 64-bit scalars fixed alongside this test. Which side is wrong depends
      // on whether the M580 really clamps STRING to 4 bytes on the wire; the
      // capture that would settle it (/tmp/umas-string-bug-report.md, cited
      // in umas_types.dart) is not in the repo. Left as-is deliberately
      // rather than guessed at -- see the review notes.
      final wire = Uint8List.fromList([
        0x61, 0x62, 0x63, 0x64,
        ...encodeVariableValue(1234, int16),
      ]);
      final parsed = parseVariableValues(wire, [str8, int16]);
      expect((parsed[0].value as String).length, 6,
          reason: 'current behaviour: 4 slot bytes + 2 bytes of the next var');
    });

    test('MonitorPlc demux survives a STRING with nothing left after it', () {
      final table = MonitorPlcRegistrationTable();
      final a = table.allocateIndex();
      table.register(a, str8);
      final b = table.allocateIndex();
      table.register(b, str8);

      final parsed =
          table.parseReadAllResponse(Uint8List.fromList([0x78, 0x00]));
      expect(parsed.length, 2);
      expect(parsed[0].value, 'x');
      expect(parsed[1].value, '');
    });
  });
}

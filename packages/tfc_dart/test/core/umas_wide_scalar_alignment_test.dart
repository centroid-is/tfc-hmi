import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_types.dart';

/// The four elementary UMAS types the PLC's data dictionary declares as 8
/// bytes (umas_types.dart:525,532-534). Every one of them is decoded by
/// [parseVariableValue] with an 8-byte read.
const lreal = UmasDataTypeRef(id: 12, name: 'LREAL', byteSize: 8);
const lint = UmasDataTypeRef(id: 13, name: 'LINT', byteSize: 8);
const int16 = UmasDataTypeRef(id: 4, name: 'INT', byteSize: 2);

Uint8List concat(List<Uint8List> parts) {
  final out = BytesBuilder();
  for (final p in parts) {
    out.add(p);
  }
  return Uint8List.fromList(out.toBytes());
}

void main() {
  group('a 64-bit scalar must not corrupt the variables after it', () {
    test('parseVariableValues round-trips two LREALs', () {
      // Built with the production encoder, which writes a full 8 bytes for
      // LREAL -- so the fixture is a genuine wire image, not a hand-rolled
      // guess that could agree with the bug it is meant to catch.
      final wire = concat([
        encodeVariableValue(1.5, lreal),
        encodeVariableValue(2.5, lreal),
      ]);
      expect(wire.length, 16, reason: 'sanity: the encoder wrote 8 bytes each');

      final parsed = parseVariableValues(wire, [lreal, lreal]);

      expect(parsed[0].value, 1.5);
      expect(parsed[1].value, 2.5,
          reason: 'the second LREAL was decoded from the wrong offset');
    });

    test('parseVariableValues round-trips LREAL followed by INT', () {
      final wire = concat([
        encodeVariableValue(1.5, lreal),
        encodeVariableValue(1234, int16),
      ]);
      expect(wire.length, 10);

      final parsed = parseVariableValues(wire, [lreal, int16]);

      expect(parsed[0].value, 1.5);
      expect(parsed[1].value, 1234,
          reason: 'the INT after a 64-bit scalar read the wrong bytes');
    });

    test('parseVariableValues round-trips LINT followed by INT', () {
      final wire = concat([
        encodeVariableValue(-2, lint),
        encodeVariableValue(7, int16),
      ]);

      final parsed = parseVariableValues(wire, [lint, int16]);

      expect(parsed[0].value, -2);
      expect(parsed[1].value, 7,
          reason: 'the INT after a 64-bit scalar read the wrong bytes');
    });

    test('MonitorPlc parseReadAllResponse round-trips LREAL then INT', () {
      final table = MonitorPlcRegistrationTable();
      final a = table.allocateIndex();
      table.register(a, lreal);
      final b = table.allocateIndex();
      table.register(b, int16);

      final wire = concat([
        encodeVariableValue(1.5, lreal),
        encodeVariableValue(1234, int16),
      ]);

      final parsed = table.parseReadAllResponse(wire);

      expect(parsed[0].value, 1.5);
      expect(parsed[1].value, 1234,
          reason: 'MonitorPlc demux misaligned after a 64-bit scalar -- every '
              'key registered after an LREAL reads another key\'s bytes');
    });
  });
}

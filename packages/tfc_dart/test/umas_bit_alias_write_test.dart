/// Lock-down + dispatch tests for the BOOL / bit-alias write path.
///
/// Two scopes in this file:
///
///   1. **Byte-per-bool encoding lock-down** — pure unit tests against
///      `encodeVariableValue` + `VariableWriteRef.fromVariable`. No
///      UmasClient, no network. Regression net for the M580 default
///      `ARRAY[..] OF BOOL` layout (one byte per bool, `bitOffset==0`):
///      if anyone "tidies" 1-byte BOOL to 2-byte BOOL or undoes the
///      v1.1.x write-path baseOffset/offset swap, these fail first.
///
///   2. **`UmasClient.writeBitAlias` dispatch** — primes the bit-alias
///      map + symbol cache via test hooks and exercises the three
///      branches: unknown-alias → `StateError`; packed-bits-16 →
///      `UnsupportedError`; byte-per-bool → forwards canonical alias
///      to `writeVariableByName`.
///
/// The encoding lock-down is the headline regression net. `writeBitAlias`
/// dispatch is the behavioural assertion. Together they pin the M580
/// FB-member write contract without needing a live PLC.

import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_bit_alias_map.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Headline lock-down: byte-per-bool encoding round-trip.
  //
  // Mirrors the live M580 `Elevator.BMEP58_ECPU_EXT.DROP_HEALTH[5]` shape:
  //   parent block 0x33, array starts at offset 0x90, byte-per-bool,
  //   element [5] → byte offset 0x95.
  // ---------------------------------------------------------------------------
  group(
      'byte-per-bool encoding lock-down '
      '(DROP_HEALTH[5] shape: block=0x33, off=0x95, BOOL)', () {
    const block = 0x33;
    const elementByteOffset = 0x90 + 5;

    UmasVariable boolAt(int blockNo, int offset) => UmasVariable(
          name: 'DROP_HEALTH[5]',
          blockNo: blockNo,
          offset: offset,
          dataTypeId: 1, // BOOL
        );

    const boolType = UmasDataTypeRef(
      id: 1,
      name: 'BOOL',
      byteSize: 1,
    );

    test('encodeVariableValue(true)  → [0x01] for BOOL', () {
      final bytes = encodeVariableValue(true, boolType);
      expect(bytes, equals(Uint8List.fromList([0x01])));
    });

    test('encodeVariableValue(false) → [0x00] for BOOL', () {
      final bytes = encodeVariableValue(false, boolType);
      expect(bytes, equals(Uint8List.fromList([0x00])));
    });

    test(
        'VariableWriteRef.fromVariable encodes BOOL true at '
        '(block=0x33, off=0x95) with the v1.1.x write-path address swap',
        () {
      final variable = boolAt(block, elementByteOffset);
      final ref = VariableWriteRef.fromVariable(variable, boolType, true);

      expect(ref.blockNo, equals(block));
      // v1.1.x write-path swap (see VariableWriteRef.fromVariable):
      //   baseOffset = addr & 0xFF   (low byte)
      //   offset     = addr >> 8     (high byte)
      expect(ref.baseOffset, equals(elementByteOffset & 0xFF),
          reason: 'low byte must land in baseOffset (write-path swap)');
      expect(ref.offset, equals(elementByteOffset >> 8),
          reason: 'high byte must land in offset (write-path swap)');
      expect(ref.dataSizeIndex, equals(1)); // 1-byte BOOL
      expect(ref.isArray, isFalse);
      expect(ref.data, equals(Uint8List.fromList([0x01])));
    });

    test(
        'VariableWriteRef.fromVariable encodes BOOL false → 0x00 '
        'with same address layout', () {
      final variable = boolAt(block, elementByteOffset);
      final ref = VariableWriteRef.fromVariable(variable, boolType, false);

      expect(ref.blockNo, equals(block));
      expect(ref.baseOffset, equals(elementByteOffset & 0xFF));
      expect(ref.offset, equals(elementByteOffset >> 8));
      expect(ref.dataSizeIndex, equals(1));
      expect(ref.data, equals(Uint8List.fromList([0x00])));
    });

    test(
        'toBytes() wire format: 7-byte header + 1-byte data for scalar BOOL '
        '(dataSizeIndex=1, block=0x33 LE, baseOffset=0x95 LE, '
        'offset=0x00 LE, data=0x01)', () {
      final variable = boolAt(block, elementByteOffset);
      final ref = VariableWriteRef.fromVariable(variable, boolType, true);
      final wire = ref.toBytes();

      // Expected wire layout for a non-array scalar BOOL:
      //   [0]      = (isArray=0) | (dataSizeIndex=1)            = 0x01
      //   [1..2]   = blockNo LE                                 = 0x33 0x00
      //   [3..4]   = baseOffset LE (low byte of addr)           = 0x95 0x00
      //   [5..6]   = offset LE     (high byte of addr)          = 0x00 0x00
      //   [7]      = data                                       = 0x01
      expect(
        wire,
        equals(Uint8List.fromList([
          0x01,
          0x33, 0x00,
          0x95, 0x00,
          0x00, 0x00,
          0x01,
        ])),
      );
    });

    test(
        'higher byte offsets (>= 0x100) still place the low byte in '
        'baseOffset and the high byte in offset', () {
      // 0x1234 → baseOffset=0x34, offset=0x12.
      final variable = boolAt(0x77, 0x1234);
      final ref = VariableWriteRef.fromVariable(variable, boolType, true);
      expect(ref.blockNo, equals(0x77));
      expect(ref.baseOffset, equals(0x34));
      expect(ref.offset, equals(0x12));

      final wire = ref.toBytes();
      expect(wire.sublist(1, 3), equals(Uint8List.fromList([0x77, 0x00])));
      expect(wire.sublist(3, 5), equals(Uint8List.fromList([0x34, 0x00])));
      expect(wire.sublist(5, 7), equals(Uint8List.fromList([0x12, 0x00])));
      expect(wire[7], equals(0x01));
    });
  });

  // ---------------------------------------------------------------------------
  // UmasClient.writeBitAlias dispatch behaviour.
  //
  // Uses debugInjectBitAliasMap to bypass the network-backed build.
  // Where the byte-per-bool path needs to ride writeVariableByName,
  // we also prime the symbol cache via debugInjectSymbol and the
  // project CRC via debugSetProjectCrc.
  // ---------------------------------------------------------------------------
  group('UmasClient.writeBitAlias dispatch', () {
    test(
        'throws StateError when alias is unknown to the map (and sends '
        'no bytes)', () async {
      var sendCalls = 0;
      final umas = UmasClient(
        sendFn: (_) async {
          sendCalls++;
          return ModbusResponseCode.requestSucceed;
        },
      );
      umas.debugInjectBitAliasMap(UmasBitAliasMap(const []));

      expect(
        () => umas.writeBitAlias('NoSuchAlias[0]', true),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('NoSuchAlias[0]'),
        )),
      );
      expect(sendCalls, equals(0),
          reason: 'unknown alias must not trigger any UMAS request');
    });

    test(
        'throws UnsupportedError for packed-bits-16 entries '
        '(bitOffset > 0) and names the alias / block / bit', () async {
      var sendCalls = 0;
      final umas = UmasClient(
        sendFn: (_) async {
          sendCalls++;
          return ModbusResponseCode.requestSucceed;
        },
      );
      // bitOffset > 0 → packed-bits-16 layout.
      umas.debugInjectBitAliasMap(UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: '%M5',
          parentBlock: 1,
          parentByteOffset: 0,
          bitOffset: 4,
          parentVariableName: 'mBits',
        ),
      ]));

      try {
        await umas.writeBitAlias('%M5', true);
        fail('expected UnsupportedError for packed-bits-16 alias');
      } on UnsupportedError catch (e) {
        // Error message must be debuggable — name the alias and
        // bit position so the operator can identify the physical bit.
        expect(e.message, contains('%M5'));
        expect(e.message?.toLowerCase(), contains('bit 4'));
        expect(e.message,
            anyOf(contains('packed'), contains('read-modify')));
      }
      expect(sendCalls, equals(0),
          reason: 'packed-bits-16 refusal must not send any UMAS request');
    });

    test(
        'byte-per-bool path forwards canonical alias name to '
        'writeVariableByName (resolved via injected symbol)', () async {
      // Capture every UmasRequest the client sends so we can assert
      // (a) exactly one writeVariable (0x23) PDU was issued, and
      // (b) its embedded ref encodes the correct (block, baseOffset,
      //     offset, data) for our alias's address.
      final sent = <UmasRequest>[];
      final umas = UmasClient(
        sendFn: (req) async {
          if (req is! UmasRequest) {
            return ModbusResponseCode.requestRxFailed;
          }
          sent.add(req);
          // Generic UMAS success PDU. writeVariable only checks for
          // FE status + pdu.length >= 3.
          req.setFromPduResponse(Uint8List.fromList([0x5A, 0x00, 0xFE]));
          return ModbusResponseCode.requestSucceed;
        },
      );

      const aliasName = 'Elevator.BMEP58_ECPU_EXT.DROP_HEALTH[5]';
      umas.debugInjectBitAliasMap(UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: aliasName,
          parentBlock: 0x33,
          parentByteOffset: 0x95, // 0x90 + 5
          bitOffset: 0, // byte-per-bool
          parentVariableName: 'DROP_HEALTH',
        ),
      ]));
      umas.debugInjectSymbol(ResolvedSymbol(
        path: aliasName,
        variable: const UmasVariable(
          name: 'DROP_HEALTH[5]',
          blockNo: 0x33,
          offset: 0x95,
          dataTypeId: 1, // BOOL
        ),
        dataType: const UmasDataTypeRef(
          id: 1,
          name: 'BOOL',
          byteSize: 1,
        ),
      ));
      umas.debugSetProjectCrc(0xCAFEBABE);

      await umas.writeBitAlias(aliasName, true);

      final writeReqs = sent
          .where((r) =>
              r.umasSubFunction == UmasSubFunction.writeVariable.code)
          .toList();
      expect(writeReqs, hasLength(1),
          reason:
              'byte-per-bool writeBitAlias should issue one 0x23 PDU');

      // WriteVariable payload: crc(4 LE) + count(1) + ref.toBytes()*
      final payload = writeReqs.single.umasPayload;
      expect(payload.sublist(0, 4),
          equals(Uint8List.fromList([0xBE, 0xBA, 0xFE, 0xCA])),
          reason: 'project CRC echoes back in first 4 LE bytes');
      expect(payload[4], equals(1), reason: 'exactly one ref');
      // The embedded ref must encode the byte-per-bool address + 0x01.
      final ref = payload.sublist(5);
      expect(
        ref,
        equals(Uint8List.fromList([
          0x01,           // (isArray=0) | (dataSizeIndex=1)
          0x33, 0x00,     // blockNo LE
          0x95, 0x00,     // baseOffset LE (low byte of addr)
          0x00, 0x00,     // offset LE     (high byte of addr)
          0x01,           // data (true)
        ])),
      );
    });

    test(
        'byte-per-bool writeBitAlias(..., false) encodes 0x00 in the '
        'data byte', () async {
      final sent = <UmasRequest>[];
      final umas = UmasClient(
        sendFn: (req) async {
          if (req is! UmasRequest) {
            return ModbusResponseCode.requestRxFailed;
          }
          sent.add(req);
          req.setFromPduResponse(Uint8List.fromList([0x5A, 0x00, 0xFE]));
          return ModbusResponseCode.requestSucceed;
        },
      );

      const aliasName = 'Elevator.BMEP58_ECPU_EXT.DROP_HEALTH[5]';
      umas.debugInjectBitAliasMap(UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: aliasName,
          parentBlock: 0x33,
          parentByteOffset: 0x95,
          bitOffset: 0,
          parentVariableName: 'DROP_HEALTH',
        ),
      ]));
      umas.debugInjectSymbol(ResolvedSymbol(
        path: aliasName,
        variable: const UmasVariable(
          name: 'DROP_HEALTH[5]',
          blockNo: 0x33,
          offset: 0x95,
          dataTypeId: 1,
        ),
        dataType:
            const UmasDataTypeRef(id: 1, name: 'BOOL', byteSize: 1),
      ));
      umas.debugSetProjectCrc(0xCAFEBABE);

      await umas.writeBitAlias(aliasName, false);

      final writeReqs = sent
          .where((r) =>
              r.umasSubFunction == UmasSubFunction.writeVariable.code)
          .toList();
      expect(writeReqs, hasLength(1));
      expect(writeReqs.single.umasPayload.last, equals(0x00),
          reason: 'false must encode as 0x00 in the data byte');
    });
  });
}

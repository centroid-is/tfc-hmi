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
      // writeVariable refuses to send until block CRCs are seeded
      // (normally populated by readPlcStatus). _projectCrc takes
      // precedence on the wire, so the actual contents here don't
      // matter — only that the guard is satisfied.
      umas.debugSetBlockCrcs(const [0xDEADBEEF]);
      // Mark the session as paired so _withSession short-circuits and
      // does NOT try to drive the init handshake against our mock
      // sendFn (which only knows how to answer writeVariable PDUs).
      umas.debugSetSessionState(UmasSessionState.paired);

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

    // -------------------------------------------------------------------------
    // Regression net for the fuzz finding "writeBitAlias driver gap":
    //
    // 11/30 byte-per-bool aliases (DIO_CTRL[#], DIO_HEALTH[#], LS_HEALTH[#])
    // threw "symbol not found in data dictionary" on write because the old
    // implementation rode writeVariableByName → lookupSymbol. Those alias
    // names live ONLY in the bit-alias map (synthesized from DD02 ARRAY OF
    // BOOL short-records), NOT in the DD03 symbol space.
    //
    // The fix: writeBitAlias must synthesize a UmasVariable from the
    // BitAliasEntry directly (mirroring readBitAlias) and call
    // writeVariable() — bypassing lookupSymbol entirely.
    // -------------------------------------------------------------------------
    test(
        'writeBitAlias synthesizes UmasVariable for aliases NOT in the '
        'DD03 symbol cache (DIO_CTRL[#] regression)', () async {
      // Verifies: even with an EMPTY symbol cache, writeBitAlias must
      // succeed for a byte-per-bool alias that exists only in the
      // bit-alias map. Pre-fix, lookupSymbol would throw
      // UmasException(0, "symbol not found in data dictionary").
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

      const aliasName = 'BMEP58_ECPU_EXT.DIO_CTRL[5]';
      umas.debugInjectBitAliasMap(UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: aliasName,
          parentBlock: 0x44,
          parentByteOffset: 0xA5,
          bitOffset: 0,
          parentVariableName: 'DIO_CTRL',
        ),
      ]));
      // NB: NO debugInjectSymbol call — the alias is intentionally
      // absent from the symbol cache, exactly mirroring the live PLC
      // behaviour where DD03 has no entry for these synthesized names.
      umas.debugSetProjectCrc(0xCAFEBABE);
      umas.debugSetBlockCrcs(const [0xDEADBEEF]);
      umas.debugSetSessionState(UmasSessionState.paired);

      await umas.writeBitAlias(aliasName, true);

      final writeReqs = sent
          .where((r) =>
              r.umasSubFunction == UmasSubFunction.writeVariable.code)
          .toList();
      expect(writeReqs, hasLength(1),
          reason: 'writeBitAlias must succeed without a symbol-cache hit');

      // The embedded ref must encode the synthesized (block=0x44,
      // offset=0xA5) — proving the write rode the synthesized
      // UmasVariable, not a lookupSymbol() result.
      final payload = writeReqs.single.umasPayload;
      final ref = payload.sublist(5);
      expect(
        ref,
        equals(Uint8List.fromList([
          0x01,           // (isArray=0) | (dataSizeIndex=1)
          0x44, 0x00,     // blockNo LE  (synthesized from entry.parentBlock)
          0xA5, 0x00,     // baseOffset LE = low byte of entry.parentByteOffset
          0x00, 0x00,     // offset LE     = high byte of entry.parentByteOffset
          0x01,           // data (true)
        ])),
        reason:
            'wire address must come from BitAliasEntry, not from a '
            'lookupSymbol() symbol cache entry',
      );
    });

    test(
        'symmetric read/write parity: both paths derive the same '
        '(block, byteOffset) from the BitAliasEntry without a symbol '
        'cache entry', () async {
      // Both readBitAlias and writeBitAlias must build the SAME wire
      // address from the SAME BitAliasEntry — and neither may depend on
      // the symbol cache. We assert this by running both with an empty
      // symbol cache and checking that the read-side ReadVariable PDU
      // and the write-side WriteVariable PDU encode the same
      // (blockNo, baseOffset, offset) triple.
      final sent = <UmasRequest>[];
      final umas = UmasClient(
        sendFn: (req) async {
          if (req is! UmasRequest) {
            return ModbusResponseCode.requestRxFailed;
          }
          sent.add(req);
          // Generic success — for read we also need to provide a
          // plausible 0x22 response body. The minimum payload that
          // parseVariableValues accepts for a 1-byte BOOL: status
          // header + 1 data byte. We don't actually assert the
          // returned bool value here — only the request shape.
          req.setFromPduResponse(Uint8List.fromList([0x5A, 0x00, 0xFE, 0x01]));
          return ModbusResponseCode.requestSucceed;
        },
      );

      const aliasName = 'BMEP58_ECPU_EXT.DIO_HEALTH[3]';
      const block = 0x44;
      const byteOffset = 0x12C;
      umas.debugInjectBitAliasMap(UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: aliasName,
          parentBlock: block,
          parentByteOffset: byteOffset,
          bitOffset: 0,
          parentVariableName: 'DIO_HEALTH',
        ),
      ]));
      umas.debugSetProjectCrc(0xCAFEBABE);
      umas.debugSetBlockCrcs(const [0xDEADBEEF]);
      umas.debugSetSessionState(UmasSessionState.paired);

      // Drive both paths. Either may legally throw on the synthetic
      // response shape (read parser is strict); the assertion is that
      // BOTH issued a PDU with the same wire address, NOT that they
      // succeeded end-to-end on a hand-rolled fake.
      try {
        await umas.readBitAlias(aliasName);
      } catch (_) {
        // Parser may bail on the synthetic payload — fine, we only
        // care about the outgoing request shape.
      }
      try {
        await umas.writeBitAlias(aliasName, true);
      } catch (_) {
        // Same — protect against response-parsing strictness.
      }

      expect(
        sent,
        isNotEmpty,
        reason: 'both read and write must issue PDUs without symbol cache',
      );

      final readReqs = sent
          .where((r) =>
              r.umasSubFunction == UmasSubFunction.readVariable.code)
          .toList();
      final writeReqs = sent
          .where((r) =>
              r.umasSubFunction == UmasSubFunction.writeVariable.code)
          .toList();
      expect(readReqs, isNotEmpty,
          reason: 'readBitAlias must issue a ReadVariable (0x22) PDU '
              'without consulting the symbol cache');
      expect(writeReqs, hasLength(1),
          reason: 'writeBitAlias must issue exactly one WriteVariable '
              '(0x23) PDU without consulting the symbol cache');

      // Pull the embedded address bytes out of each ref. Wire layouts
      // (umas_types.dart): both PDUs share `crc(4 LE) + count(1)` before
      // the first ref, hence the `.sublist(5)` strip.
      //
      // VariableReadRef.toBytes() — 7 bytes for a scalar:
      //   [0]    size byte
      //   [1..2] blockNo LE
      //   [3]    constant 0x01
      //   [4..5] baseOffset LE (= addr >> 8 — HIGH byte of paged addr)
      //   [6]    offset        (= addr & 0xFF — LOW  byte of paged addr)
      //
      // VariableWriteRef.toBytes() — 7-byte header + data for a scalar:
      //   [0]    size byte
      //   [1..2] blockNo LE
      //   [3..4] baseOffset LE (= addr & 0xFF — LOW  byte; write-path swap)
      //   [5..6] offset LE     (= addr >> 8  — HIGH byte; write-path swap)
      //   [7..]  data
      final readPayload = readReqs.first.umasPayload;
      final readRef = readPayload.sublist(5); // skip crc(4) + count(1)
      final readBlock = readRef[1] | (readRef[2] << 8);
      final readBaseHi = readRef[4] | (readRef[5] << 8);
      final readOffLo = readRef[6];
      final readTargetByte = (readBaseHi << 8) | readOffLo;

      final writePayload = writeReqs.single.umasPayload;
      final writeRef = writePayload.sublist(5);
      final writeBlock = writeRef[1] | (writeRef[2] << 8);
      final writeBaseLo = writeRef[3] | (writeRef[4] << 8);
      final writeOffHi = writeRef[5] | (writeRef[6] << 8);
      final writeTargetByte = (writeOffHi << 8) | writeBaseLo;

      expect(readBlock, equals(block),
          reason: 'read path block must come from BitAliasEntry');
      expect(writeBlock, equals(block),
          reason: 'write path block must come from BitAliasEntry');
      expect(readTargetByte, equals(byteOffset),
          reason: 'read path must target BitAliasEntry.parentByteOffset');
      expect(writeTargetByte, equals(byteOffset),
          reason: 'write path must target BitAliasEntry.parentByteOffset');
      expect(readTargetByte, equals(writeTargetByte),
          reason: 'read and write must target the same byte address');
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
      umas.debugSetBlockCrcs(const [0xDEADBEEF]);
      umas.debugSetSessionState(UmasSessionState.paired);

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

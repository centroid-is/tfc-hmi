/// FB-DynamicValue poll-loop fallback (v1.1.x): the UMAS poll path must
/// detect FB-instance bindings (via [UmasNotScalarException]) and fall
/// back to a batched member fan-out read, producing a struct
/// [DynamicValue] (`{member: value}` LinkedHashMap) that subscribers
/// (FB-DynamicValue widget, Conveyor FB asset) can render directly.
///
/// Background — commit `8c03c68d` made `readVariableByName` on an
/// FB-instance root throw [UmasNotScalarException]. The intent was to
/// surface the bug instead of silently returning empty bytes. But the
/// poll loop in [ModbusDeviceClientAdapter.readUmasVariable] used to
/// just bubble the throw — every tick logged
///
///   UMAS fallback poll for key "K" failed: UmasNotScalarException ...
///
/// when an operator bound a key to an FB instance, and the subject never
/// emitted. The fix: catch the exception and route through the new
/// [UmasClient.readFbInstanceMembers] helper, producing a struct
/// DynamicValue with `value: LinkedHashMap<String, DynamicValue>`.
///
/// Run: `cd packages/tfc_dart && dart test test/core/umas_fb_dynamic_value_poll_test.dart`
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

// ---------------------------------------------------------------------------
// Helpers — mirror the wire-level mocking patterns from
// umas_bit_alias_write_test.dart and umas_coils_registers_test.dart.
// ---------------------------------------------------------------------------

/// Build a minimal ReadVariable (0x22) success PDU.
///
/// Layout: FC(0x5A) + pairingKey(1) + status(0xFE) + concatenated value bytes.
/// The caller supplies the value bytes pre-laid-out in declaration order.
Uint8List _buildReadVariableSuccessPdu(Uint8List payload) {
  final pdu = Uint8List(3 + payload.length);
  pdu[0] = 0x5A;
  pdu[1] = 0x00;
  pdu[2] = 0xFE;
  pdu.setAll(3, payload);
  return pdu;
}

/// FB instance + 3 members. Mirrors the live PLC shape
/// `M_F2_RC_01.{HMI.p_Stat_xRunningFwd, HMI.p_Stat_xStopped, q_rVelocity}`
/// — two BOOLs at the head, one REAL at the tail.
void _injectFbAndMembers(UmasClient umas) {
  // FB root — classIdentifier 7. Reads on this path throw
  // UmasNotScalarException.
  umas.debugInjectSymbol(ResolvedSymbol(
    path: 'M_F2_RC_01',
    variable: const UmasVariable(
      name: 'M_F2_RC_01',
      blockNo: 0x30,
      offset: 0,
      dataTypeId: 0xB6,
    ),
    dataType: const UmasDataTypeRef(
      id: 0xB6,
      name: 'FB',
      byteSize: 0,
      classIdentifier: 7,
    ),
  ));
  umas.debugInjectSymbol(ResolvedSymbol(
    path: 'M_F2_RC_01.HMI.p_Stat_xRunningFwd',
    variable: const UmasVariable(
      name: 'p_Stat_xRunningFwd',
      blockNo: 0x30,
      offset: 0x10,
      dataTypeId: 1,
    ),
    dataType: const UmasDataTypeRef(
      id: 1,
      name: 'BOOL',
      byteSize: 1,
    ),
  ));
  umas.debugInjectSymbol(ResolvedSymbol(
    path: 'M_F2_RC_01.HMI.p_Stat_xStopped',
    variable: const UmasVariable(
      name: 'p_Stat_xStopped',
      blockNo: 0x30,
      offset: 0x11,
      dataTypeId: 1,
    ),
    dataType: const UmasDataTypeRef(
      id: 1,
      name: 'BOOL',
      byteSize: 1,
    ),
  ));
  umas.debugInjectSymbol(ResolvedSymbol(
    path: 'M_F2_RC_01.q_rVelocity',
    variable: const UmasVariable(
      name: 'q_rVelocity',
      blockNo: 0x30,
      offset: 0x20,
      dataTypeId: 6,
    ),
    dataType: const UmasDataTypeRef(
      id: 6,
      name: 'REAL',
      byteSize: 4,
    ),
  ));
}

void main() {
  // ---------------------------------------------------------------------------
  // UmasClient.readFbInstanceMembers — public helper that walks the
  // already-built symbol cache for `<fbPath>.<...>` entries, issues a single
  // batched readVariables for the readable scalar leaves, and returns a
  // Map<String, TypedVariableValue> keyed by the member sub-path (the
  // suffix AFTER the FB root + `.`).
  // ---------------------------------------------------------------------------

  group('UmasClient.readFbInstanceMembers', () {
    test('returns one TypedVariableValue per scalar member, keyed by '
        'the member sub-path under the FB root', () async {
      final sent = <UmasRequest>[];
      final umas = UmasClient(
        sendFn: (req) async {
          if (req is! UmasRequest) {
            return ModbusResponseCode.requestRxFailed;
          }
          sent.add(req);
          // Two BOOLs (1 byte each, true/false) + one REAL (4 bytes, 12.5f).
          // Order MUST match the order readFbInstanceMembers walks the
          // symbol cache. We pin the order in the assertions below.
          final payload = Uint8List.fromList([
            0x01, // p_Stat_xRunningFwd = true
            0x00, // p_Stat_xStopped = false
            // 12.5f little-endian
            0x00, 0x00, 0x48, 0x41,
          ]);
          req.setFromPduResponse(_buildReadVariableSuccessPdu(payload));
          return ModbusResponseCode.requestSucceed;
        },
      );
      _injectFbAndMembers(umas);
      umas.debugSetProjectCrc(0xCAFEBABE);
      umas.debugSetBlockCrcs(const [0xDEADBEEF]);
      umas.debugSetSessionState(UmasSessionState.paired);

      final members = await umas.readFbInstanceMembers('M_F2_RC_01');

      // Must include every scalar leaf under the FB root.
      expect(members.keys, containsAll(<String>[
        'HMI.p_Stat_xRunningFwd',
        'HMI.p_Stat_xStopped',
        'q_rVelocity',
      ]));
      expect(members['HMI.p_Stat_xRunningFwd']!.value, isTrue);
      expect(members['HMI.p_Stat_xStopped']!.value, isFalse);
      expect((members['q_rVelocity']!.value as double), closeTo(12.5, 0.001));

      // One batched ReadVariable PDU — NOT N round-trips.
      final readReqs = sent
          .where((r) => r.umasSubFunction == UmasSubFunction.readVariable.code)
          .toList();
      expect(readReqs, hasLength(1),
          reason:
              'readFbInstanceMembers must issue a single batched 0x22 PDU');
    });

    test('throws UmasException when no scalar members are cached for '
        'the named FB root', () async {
      final umas = UmasClient(
        sendFn: (req) async => ModbusResponseCode.requestSucceed,
      );
      // Inject only the FB root — no children.
      umas.debugInjectSymbol(ResolvedSymbol(
        path: 'M_Empty',
        variable: const UmasVariable(
          name: 'M_Empty',
          blockNo: 0x40,
          offset: 0,
          dataTypeId: 0xC0,
        ),
        dataType: const UmasDataTypeRef(
          id: 0xC0,
          name: 'FB',
          byteSize: 0,
          classIdentifier: 7,
        ),
      ));
      umas.debugSetProjectCrc(0x0);
      umas.debugSetBlockCrcs(const [0x0]);
      umas.debugSetSessionState(UmasSessionState.paired);

      try {
        await umas.readFbInstanceMembers('M_Empty');
        fail('expected UmasException for FB with no enumerable members');
      } on UmasException catch (e) {
        expect(e.message, contains('M_Empty'));
        expect(e.message, contains('member'));
      }
    });

    test('skips unreadable members (e.g. VAR_IN_OUT) — they are NOT '
        'included in the returned map and do NOT show up in the wire '
        'PDU', () async {
      final sent = <UmasRequest>[];
      final umas = UmasClient(
        sendFn: (req) async {
          if (req is! UmasRequest) {
            return ModbusResponseCode.requestRxFailed;
          }
          sent.add(req);
          // Only ONE BOOL in the response — the unreadable member must NOT
          // be in the batch.
          req.setFromPduResponse(_buildReadVariableSuccessPdu(
            Uint8List.fromList([0x01]),
          ));
          return ModbusResponseCode.requestSucceed;
        },
      );

      umas.debugInjectSymbol(ResolvedSymbol(
        path: 'M_F2_RC_01',
        variable: const UmasVariable(
          name: 'M_F2_RC_01',
          blockNo: 0x30,
          offset: 0,
          dataTypeId: 0xB6,
        ),
        dataType: const UmasDataTypeRef(
          id: 0xB6,
          name: 'FB',
          byteSize: 0,
          classIdentifier: 7,
        ),
      ));
      umas.debugInjectSymbol(ResolvedSymbol(
        path: 'M_F2_RC_01.q_xActive',
        variable: const UmasVariable(
          name: 'q_xActive',
          blockNo: 0x30,
          offset: 0x10,
          dataTypeId: 1,
        ),
        dataType: const UmasDataTypeRef(
          id: 1,
          name: 'BOOL',
          byteSize: 1,
        ),
      ));
      umas.debugInjectSymbol(ResolvedSymbol(
        path: 'M_F2_RC_01.iq_handshake',
        variable: const UmasVariable(
          name: 'iq_handshake',
          blockNo: 0x30,
          offset: 0x14,
          dataTypeId: 6,
        ),
        dataType: const UmasDataTypeRef(
          id: 6,
          name: 'REAL',
          byteSize: 4,
        ),
        readable: false,
        unreadableReason: 'VAR_IN_OUT (PLC returns 0x94)',
      ));
      umas.debugSetProjectCrc(0xCAFEBABE);
      umas.debugSetBlockCrcs(const [0xDEADBEEF]);
      umas.debugSetSessionState(UmasSessionState.paired);

      final members = await umas.readFbInstanceMembers('M_F2_RC_01');

      expect(members.keys, equals(<String>['q_xActive']),
          reason: 'unreadable members must NOT be in the returned map');
      // The wire payload encoded exactly one ref (the readable BOOL).
      final readReqs = sent
          .where((r) => r.umasSubFunction == UmasSubFunction.readVariable.code)
          .toList();
      expect(readReqs, hasLength(1));
      expect(readReqs.single.umasPayload[4], equals(1),
          reason: 'exactly one ref in the batched ReadVariable PDU');
    });

    test('throws UmasException when the FB root has no members in the '
        'already-primed symbol cache (no implicit browse)', () async {
      // Cache is primed (debugInjectSymbol marks it built), but the
      // requested FB root has no children. We MUST surface a clear
      // operator-facing error here rather than (a) silently returning an
      // empty map or (b) trying to do an implicit browse() — the poll
      // loop catches UmasNotScalarException from the FB root itself,
      // which means the root IS in the cache. If there are no readable
      // members, that's a configuration/PLC problem, not a missing-data
      // one. The error must name the path so operators know which key
      // is broken.
      final umas = UmasClient(
        sendFn: (req) async => ModbusResponseCode.requestSucceed,
      );
      // Inject ONE unrelated symbol so debugInjectSymbol marks the cache
      // built. The lookup for Unknown_FB.<...> finds nothing.
      umas.debugInjectSymbol(ResolvedSymbol(
        path: 'Unrelated_Symbol',
        variable: const UmasVariable(
          name: 'Unrelated_Symbol',
          blockNo: 0,
          offset: 0,
          dataTypeId: 6,
        ),
        dataType: const UmasDataTypeRef(
          id: 6,
          name: 'REAL',
          byteSize: 4,
        ),
      ));
      umas.debugSetProjectCrc(0x0);
      umas.debugSetBlockCrcs(const [0x0]);
      umas.debugSetSessionState(UmasSessionState.paired);

      try {
        await umas.readFbInstanceMembers('Unknown_FB');
        fail('expected UmasException for FB root with no cached members');
      } on UmasException catch (e) {
        expect(e.message, contains('Unknown_FB'));
        expect(e.message.toLowerCase(), contains('member'));
      }
    });
  });
}

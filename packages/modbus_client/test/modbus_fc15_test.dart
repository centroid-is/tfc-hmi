import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';

void main() {
  group('FC15 Write Multiple Coils quantity (LIBFIX-01)', () {
    /// Helper to build packed coil bytes with all bits set.
    Uint8List packedCoilBytes(int coilCount) {
      final byteCount = (coilCount + 7) ~/ 8;
      final bytes = Uint8List(byteCount);
      // Set all coil bits to ON
      for (var i = 0; i < byteCount; i++) {
        final remainingCoils = coilCount - (i * 8);
        if (remainingCoils >= 8) {
          bytes[i] = 0xFF;
        } else {
          // Partial byte: set only the valid bits
          bytes[i] = (1 << remainingCoils) - 1;
        }
      }
      return bytes;
    }

    void testCoilQuantity(int coilCount) {
      test('$coilCount coils encodes quantity=$coilCount in PDU bytes [3][4]',
          () {
        final coil = ModbusCoil(name: 'c', address: 100);
        final bytes = packedCoilBytes(coilCount);
        final req = coil.getMultipleWriteRequest(bytes, quantity: coilCount);
        final pdu = req.protocolDataUnit;
        final pduView = ByteData.view(pdu.buffer);

        // [0] = 0x0F (FC15)
        expect(pdu[0], equals(0x0F), reason: 'Function code should be FC15');
        // [1][2] = address = 100
        expect(pduView.getUint16(1), equals(100),
            reason: 'Address should be 100');
        // [3][4] = quantity = coilCount (THE BUG: currently bytes.length ~/ 2)
        expect(pduView.getUint16(3), equals(coilCount),
            reason:
                'Quantity should be $coilCount, not ${bytes.length ~/ 2} (bytes.length ~/ 2)');
        // [5] = byte count = bytes.length
        expect(pdu[5], equals(bytes.length),
            reason: 'Byte count should be ${bytes.length}');
        // Verify packed coil data follows
        expect(pdu.sublist(6), equals(bytes),
            reason: 'Packed coil data should match');
      });
    }

    // Test all boundary cases from the plan
    testCoilQuantity(1); // 1 byte packed, bug: 0
    testCoilQuantity(8); // 1 byte packed, bug: 0
    testCoilQuantity(9); // 2 bytes packed, bug: 1
    testCoilQuantity(15); // 2 bytes packed, bug: 1
    testCoilQuantity(16); // 2 bytes packed, bug: 1
    testCoilQuantity(17); // 3 bytes packed, bug: 1
    testCoilQuantity(32); // 4 bytes packed, bug: 2
    testCoilQuantity(64); // 8 bytes packed, bug: 4
  });

  group('FC16 regression', () {
    test(
        'FC16 32-bit register: no quantity param preserves bytes.length ~/ 2 = 2',
        () {
      final reg = ModbusUint32Register(
          name: 'r', address: 0, type: ModbusElementType.holdingRegister);
      final req = reg.getWriteRequest(0x12345678);
      final pdu = req.protocolDataUnit;
      final pduView = ByteData.view(pdu.buffer);

      // FC16 = 0x10
      expect(pdu[0], equals(0x10), reason: 'Function code should be FC16');
      // Quantity = 2 registers (4 bytes / 2)
      expect(pduView.getUint16(3), equals(2),
          reason: 'Quantity should be 2 registers for uint32');
    });

    test(
        'FC16 64-bit register: no quantity param preserves bytes.length ~/ 2 = 4',
        () {
      final reg = ModbusDoubleRegister(
          name: 'r', address: 0, type: ModbusElementType.holdingRegister);
      final req = reg.getWriteRequest(3.14159);
      final pdu = req.protocolDataUnit;
      final pduView = ByteData.view(pdu.buffer);

      // FC16 = 0x10
      expect(pdu[0], equals(0x10), reason: 'Function code should be FC16');
      // Quantity = 4 registers (8 bytes / 2)
      expect(pduView.getUint16(3), equals(4),
          reason: 'Quantity should be 4 registers for double');
    });
  });

  group('FC15 response parsing (TEST-02)', () {
    test('server echo with correct quantity resolves with requestSucceed', () async {
      final coil = ModbusCoil(name: 'c', address: 0);
      final bytes = Uint8List.fromList([0xFF, 0xFF]); // 16 coils all ON
      final req = coil.getMultipleWriteRequest(bytes, quantity: 16);

      // Simulate server echoing back: FC=0x0F, address=0x00 0x00, quantity=0x00 0x10
      final responsePdu =
          Uint8List.fromList([0x0F, 0x00, 0x00, 0x00, 0x10]);
      req.setFromPduResponse(responsePdu);

      final code = await req.responseCode;
      expect(code, equals(ModbusResponseCode.requestSucceed));
    });
  });
}

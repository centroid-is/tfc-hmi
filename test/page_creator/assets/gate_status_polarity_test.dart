// A gate indicator has to be able to follow either polarity of signal.
//
// `GateStatusConfig` painted red on true and green on false, i.e. it assumed
// its key carried "tripped". The safety gates on this plant publish the
// opposite: `FB_MonitorOSSD.q_xOk` is TRUE when the gate is safe, and it is
// the only signal that reaches OPC UA — the PLC's own `xGateTripped` is
// assigned twice and ends up carrying the speedbatcher's emergency gate
// instead. Bound as it stood, every healthy gate would have shown red.
//
// A key mapping cannot fix this: it offers `bitMask` and `bitShift`, neither
// of which negates a bool. So the polarity belongs on the asset, exactly as
// `SensorConfig.invertActivePolarity` already does it.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/speedbatcher.dart';

void main() {
  group('gateIsTripped', () {
    test('a tripped-polarity key reads straight through', () {
      expect(gateIsTripped(rawBool: true, invertPolarity: false), isTrue);
      expect(gateIsTripped(rawBool: false, invertPolarity: false), isFalse);
    });

    test('an ok-polarity key is inverted', () {
      // q_xOk: true means the gate is safe, so the gate is NOT tripped.
      expect(gateIsTripped(rawBool: true, invertPolarity: true), isFalse);
      expect(gateIsTripped(rawBool: false, invertPolarity: true), isTrue);
    });
  });

  group('GateStatusConfig', () {
    test('defaults to the old behaviour so existing pages do not move', () {
      expect(GateStatusConfig(key: 'x').invertPolarity, isFalse);
    });

    test('round-trips through json', () {
      // Through a real encode/decode: this class is not annotated
      // `explicitToJson`, so toJson() leaves nested Coordinates as objects
      // and only survives the trip a persisted page actually takes.
      final c = GateStatusConfig(key: 'SB1.Gate.Ok', invertPolarity: true);
      final back = GateStatusConfig.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.key, 'SB1.Gate.Ok');
      expect(back.invertPolarity, isTrue);
    });

    test('a page saved before the flag existed still loads', () {
      // Pages persisted before this field must not fail to parse. Built from
      // a real serialization with the field removed, because fromJson also
      // needs the BaseAsset fields.
      final json = jsonDecode(jsonEncode(
          GateStatusConfig(key: 'SB2.EmgGateTripped').toJson()))
              as Map<String, dynamic>
        ..remove('invertPolarity');
      final back = GateStatusConfig.fromJson(json);
      expect(back.key, 'SB2.EmgGateTripped');
      expect(back.invertPolarity, isFalse);
    });

    test('the preview carries the flag too', () {
      expect(GateStatusConfig.preview().invertPolarity, isFalse);
    });
  });
}

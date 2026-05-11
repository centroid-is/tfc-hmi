import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/painter/advantys_stb/io16.dart';
import 'package:tfc/painter/beckhoff/io8.dart' show IOState;

void main() {
  group('kSTBChannelBitOrder + bitmaskToLedStates', () {
    // TODO(stb-bit-order): Bit-order is LSB-first per CONTEXT.md §Bit-Ordering.
    // Backend team must confirm Schneider Advantys STB convention before goldens
    // lock (Plan 02). If MSB-first: flip `kSTBChannelBitOrder` constant default +
    // flip the 0x0001/0x8000/0xAAAA index expectations in this group; painter math
    // is unchanged.

    test('bit-order constant default is LSB-first (locked canary)', () {
      expect(kSTBChannelBitOrder, STBBitOrder.lsbFirst);
    });

    test('output length contract is always 16', () {
      expect(bitmaskToLedStates(0).length, 16);
    });

    test('0x0000 → all 16 entries IOState.low', () {
      final states = bitmaskToLedStates(0x0000);
      expect(states, List.filled(16, IOState.low));
    });

    test('0x0001 → only channel 1 (index 0) lit', () {
      final states = bitmaskToLedStates(0x0001);
      expect(states[0], IOState.high);
      for (int i = 1; i < 16; i++) {
        expect(states[i], IOState.low, reason: 'index $i should be low');
      }
    });

    test('0x8000 → only channel 16 (index 15) lit', () {
      final states = bitmaskToLedStates(0x8000);
      expect(states[15], IOState.high);
      for (int i = 0; i < 15; i++) {
        expect(states[i], IOState.low, reason: 'index $i should be low');
      }
    });

    test('0xAAAA → odd indices (channels 2,4,6,8,10,12,14,16) lit', () {
      final states = bitmaskToLedStates(0xAAAA);
      for (int i = 0; i < 16; i++) {
        if (i.isOdd) {
          expect(states[i], IOState.high,
              reason: 'index $i (channel ${i + 1}) should be high');
        } else {
          expect(states[i], IOState.low,
              reason: 'index $i (channel ${i + 1}) should be low');
        }
      }
    });

    test('0xFFFF → all 16 entries IOState.high', () {
      final states = bitmaskToLedStates(0xFFFF);
      expect(states, List.filled(16, IOState.high));
    });

    test('forceValues[0] == 1 collapses raw high → forcedLow', () {
      // raw 0xFFFF would normally render all 16 channels high; the force value
      // on channel 1 must collapse that channel to forcedLow (no corner pip).
      final states = bitmaskToLedStates(
        0xFFFF,
        forceValues: const <int>[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(states[0], IOState.forcedLow);
      for (int i = 1; i < 16; i++) {
        expect(states[i], IOState.high,
            reason: 'index $i should remain high');
      }
    });

    test('forceValues[1] == 2 collapses raw low → forcedHigh', () {
      // raw 0x0000 would normally render all 16 channels low; the force value
      // on channel 2 must collapse that channel to forcedHigh (no corner pip).
      final states = bitmaskToLedStates(
        0x0000,
        forceValues: const <int>[0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(states[1], IOState.forcedHigh);
      expect(states[0], IOState.low);
      for (int i = 2; i < 16; i++) {
        expect(states[i], IOState.low, reason: 'index $i should remain low');
      }
    });
  });
}

import 'package:test/test.dart';
import 'package:tfc_dart/core/ring_buffer.dart';

import '../test_timing.dart';

void main() {
  enableTestTiming();
  group('RingBuffer', () {
    test('empty buffer operations', () {
      final buffer = RingBuffer<int>(3);
      expect(buffer.toList(), []);
      expect(buffer.last, null);
      expect(buffer.buffer, [null, null, null]);
    });

    test('buffer overflow behavior', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4); // Should overwrite 1
      expect(buffer.toList(), [2, 3, 4]);
      expect(buffer.last, 4);
    });

    test('size 1 buffer edge cases', () {
      final buffer = RingBuffer<int>(1);
      buffer.add(1);
      expect(buffer.toList(), [1]);
      buffer.add(2);
      expect(buffer.toList(), [2]);
      expect(buffer.last, 2);
    });

    test('buffer wrapping behavior', () {
      final buffer = RingBuffer<int>(3);
      // Fill buffer
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      // Wrap around
      buffer.add(4);
      buffer.add(5);
      buffer.add(6);
      expect(buffer.toList(), [4, 5, 6]);
      expect(buffer.last, 6);
    });

    test('partial fill behavior', () {
      final buffer = RingBuffer<int>(5);
      buffer.add(1);
      buffer.add(2);
      expect(buffer.toList(), [1, 2]);
      expect(buffer.last, 2);
    });

    test('zero size buffer', () {
      expect(() => RingBuffer<int>(0), throwsA(isA<AssertionError>()));
    });

    test('negative size buffer', () {
      expect(() => RingBuffer<int>(-1), throwsRangeError);
    });

    test('buffer with null values', () {
      final buffer = RingBuffer<int?>(3);
      buffer.add(1);
      buffer.add(null);
      buffer.add(3);
      expect(buffer.toList(), [1, null, 3]);
      expect(buffer.last, 3);
    });

    test('rapid additions', () {
      final buffer = RingBuffer<int>(3);
      for (int i = 0; i < 100; i++) {
        buffer.add(i);
      }
      expect(buffer.toList(), [97, 98, 99]);
      expect(buffer.last, 99);
    });

    test('should maintain most recent values when buffer overflows', () {
      final buffer = RingBuffer<int>(2); // Buffer size of 2

      // Add more values than buffer size
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);

      // Should only contain the most recent values
      expect(buffer.toList(), [2, 3],
          reason: 'Buffer should contain only the most recent values');
      expect(buffer.last, 3,
          reason: 'Last value should be the most recently added value');
    });
  });
}

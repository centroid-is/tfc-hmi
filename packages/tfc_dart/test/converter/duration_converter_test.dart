import 'package:test/test.dart';
import 'package:tfc_dart/converter/duration_converter.dart';

import '../test_timing.dart';

void main() {
  enableTestTiming();
  group('DurationMicrosecondsConverter', () {
    const converter = DurationMicrosecondsConverter();

    test('should convert microseconds to Duration', () {
      final result = converter.fromJson(1000000);
      expect(result, const Duration(seconds: 1));
    });

    test('should convert Duration to microseconds', () {
      const duration = Duration(seconds: 1);
      final result = converter.toJson(duration);
      expect(result, 1000000);
    });

    test('should handle null values', () {
      expect(converter.fromJson(null), null);
      expect(converter.toJson(null), null);
    });

    test('should handle zero duration', () {
      const duration = Duration.zero;
      final result = converter.toJson(duration);
      expect(result, 0);
    });
  });

  group('DurationMinutesConverter', () {
    const converter = DurationMinutesConverter();

    test('should convert minutes to Duration', () {
      final result = converter.fromJson(60);
      expect(result, const Duration(hours: 1));
    });

    test('should convert Duration to minutes', () {
      const duration = Duration(hours: 1);
      final result = converter.toJson(duration);
      expect(result, 60);
    });

    test('should handle null values', () {
      expect(converter.fromJson(null), null);
      expect(converter.toJson(null), null);
    });

    test('should handle zero duration', () {
      const duration = Duration.zero;
      final result = converter.toJson(duration);
      expect(result, 0);
    });
  });
}

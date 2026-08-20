// The unit a "minutes" field is actually stored in.
//
// json_serializable applies a converter only when its types match the field
// exactly. DurationMinutesConverter is JsonConverter<Duration?, int?>, so on a
// non-nullable `Duration` it was silently skipped and the generator fell back
// to its own Duration handling -- microseconds. Three fields named for minutes
// (drop_after_min, since_minutes, time_window_min) therefore held microseconds,
// and a one-year retention written as 525600 was read back as half a second.

import 'package:test/test.dart';
import 'package:tfc_dart/converter/duration_converter.dart';
import 'package:tfc_dart/core/database.dart';

void main() {
  const c = DurationMinutesConverterNonNull();

  group('DurationMinutesConverterNonNull', () {
    test('writes minutes', () {
      expect(c.toJson(const Duration(days: 365)), 525600);
      expect(c.toJson(const Duration(minutes: 30)), 30);
    });

    test('reads minutes', () {
      expect(c.fromJson(525600), const Duration(days: 365));
      expect(c.fromJson(30), const Duration(minutes: 30));
    });

    test('round-trips', () {
      for (final d in <Duration>[
        Duration(minutes: 1),
        Duration(hours: 1),
        Duration(days: 365),
      ]) {
        expect(c.fromJson(c.toJson(d)), d);
      }
    });

    test('reads a value written while the converter was inert as microseconds',
        () {
      // 365 days in microseconds -- what the UI stored in drop_after_min.
      expect(c.fromJson(31536000000000), const Duration(days: 365));
      // 30 minutes in microseconds -- what the speedbatcher readouts stored
      // in since_minutes, alongside an acceptWindowMinutes of 30.
      expect(c.fromJson(1800000000), const Duration(minutes: 30));
    });

    test('one year in minutes stays one year, and is nowhere near the cutoff',
        () {
      expect(c.fromJson(525600), const Duration(days: 365));
      expect(525600, lessThan(kLegacyMicrosecondCutoffMinutes));
      expect(1800000000, greaterThan(kLegacyMicrosecondCutoffMinutes));
    });
  });

  group('RetentionPolicy', () {
    test('a year of retention serialises as 525600, not 31536000000000', () {
      final json =
          const RetentionPolicy(dropAfter: Duration(days: 365)).toJson();
      expect(json['drop_after_min'], 525600);
    });

    test('525600 means a year, not half a second', () {
      final p = RetentionPolicy.fromJson({'drop_after_min': 525600});
      expect(p.dropAfter, const Duration(days: 365));
      expect(p.dropAfter.inMilliseconds, isNot(525));
    });
  });
}

import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_dart/converter/duration_converter.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// Retention is the one setting whose entire job is to delete data, so a value
/// that survives a round trip as something other than what was typed deletes
/// history without anybody asking.
///
/// The defect: `drop_after_min` is written as minutes and read back through
/// [durationFromMinutesTolerant], which treats anything above
/// [kLegacyMicrosecondCutoffMinutes] as *microseconds* instead. That cutoff was
/// ten years in minutes (5_256_000), and 3651 days is 5_257_440 minutes -- one
/// day over. A ten-year-and-one-day retention was therefore read back as
/// 5.25744 SECONDS, and Timescale dropped every chunk older than that.
///
/// The cutoff is meant to separate two populations that are orders of magnitude
/// apart. It was placed at the very top of the legitimate minutes range instead
/// of in the empty gap between the two, which is what put a cliff inside the
/// range an operator can type.
void main() {
  /// What a station's config file does to a value: the object is serialised on
  /// save and re-read on the next start.
  RetentionPolicy roundTrip(RetentionPolicy p) =>
      RetentionPolicy.fromJson(p.toJson());

  group('the cliff', () {
    test('ten years and one day does not become five seconds', () {
      final read = roundTrip(RetentionPolicy(dropAfter: Duration(days: 3651)));
      expect(read.dropAfter, greaterThan(const Duration(days: 3649)),
          reason: 'Read back as ${read.dropAfter}. Anything in the seconds '
              'range here means Timescale drops the entire history on the '
              'next run of the policy.');
    });

    test('a decade still round-trips exactly', () {
      final read = roundTrip(RetentionPolicy(dropAfter: Duration(days: 3650)));
      expect(read.dropAfter, const Duration(days: 3650));
    });

    test('no value the clamp permits lands past the microsecond cutoff', () {
      // The gap the cutoff is supposed to sit in: the largest retention the UI
      // can produce, in minutes, versus the smallest value the legacy
      // microsecond era could have written. A field measured in minutes cannot
      // hold less than one minute, so 60_000_000 us is the floor of the legacy
      // population.
      const maxLegitimateMinutes = kMaxRetentionDays * 24 * 60;
      const smallestLegacyMicroseconds = 60 * 1000 * 1000;
      expect(maxLegitimateMinutes, lessThan(kLegacyMicrosecondCutoffMinutes),
          reason: 'A retention the operator is allowed to type must never be '
              'mistaken for microseconds.');
      expect(kLegacyMicrosecondCutoffMinutes,
          lessThan(smallestLegacyMicroseconds),
          reason: 'A genuinely legacy microsecond value must still be '
              'recognised, or the older bug comes back.');
    });

    test('the legacy microsecond values this converter exists for still work',
        () {
      // 365 days written as microseconds, which is what the inert converter
      // stored before it was fixed.
      final p = RetentionPolicy.fromJson(
          {'drop_after_min': const Duration(days: 365).inMicroseconds});
      expect(p.dropAfter, const Duration(days: 365));
    });
  });

  group('clamping on read, for configs already on disk', () {
    test('a value beyond the maximum is capped, not reinterpreted', () {
      final p = RetentionPolicy.fromJson(
          {'drop_after_min': const Duration(days: 4000).inMinutes});
      expect(p.dropAfter, const Duration(days: kMaxRetentionDays));
    });

    test('a stored zero is left alone for updateRetentionPolicy to refuse', () {
      // Not silently rewritten to a default: inventing a retention is how the
      // operator ends up trusting a number nobody chose. It is refused loudly
      // at the point of use instead, which leaves the existing policy intact.
      final p = RetentionPolicy.fromJson({'drop_after_min': 0});
      expect(p.dropAfter, Duration.zero);
    });
  });

  group('RetentionPolicy.sanitized', () {
    test('rejects zero', () {
      expect(RetentionPolicy(dropAfter: Duration.zero).isUsable, isFalse);
    });

    test('rejects negative', () {
      expect(
          RetentionPolicy(dropAfter: const Duration(days: -5)).isUsable,
          isFalse);
    });

    test('rejects the seconds-range values the unit cliff produces', () {
      // The whole point of the floor. These are the artifact, not a choice:
      // the originally reported 5.26 s, and what the cliff can still produce
      // for an absurd day count now that the cutoff has moved.
      expect(
          RetentionPolicy(dropAfter: const Duration(milliseconds: 5257))
              .isUsable,
          isFalse);
      expect(RetentionPolicy(dropAfter: const Duration(seconds: 52)).isUsable,
          isFalse,
          reason: '36 500 days misread as microseconds is 52.6 s — the worst a '
              'plausible fat-finger can produce.');
      expect(RetentionPolicy(dropAfter: const Duration(seconds: 59)).isUsable,
          isFalse);
    });

    test('permits a short window that somebody might actually want', () {
      // A high-rate diagnostic tag — a vibration or current trace — is a
      // legitimate reason to keep only minutes. An hour floor forbade this,
      // which was over-reach: the defect was a unit conversion, not a bad
      // choice of window.
      expect(RetentionPolicy(dropAfter: const Duration(minutes: 1)).isUsable,
          isTrue);
      expect(RetentionPolicy(dropAfter: const Duration(minutes: 10)).isUsable,
          isTrue);
      expect(RetentionPolicy(dropAfter: const Duration(minutes: 30)).isUsable,
          isTrue);
    });

    test('the floor sits above every artifact the cliff can produce', () {
      // Ties the threshold to the thing it defends against, so that moving
      // either without the other fails here rather than in the field.
      const worstPlausibleTypo = 36500; // a hundred years, in days
      final artifact =
          Duration(microseconds: worstPlausibleTypo * 24 * 60);
      expect(artifact, lessThan(kMinRetentionDuration),
          reason: 'If the cutoff or the floor moves so that an artifact lands '
              'above the floor, it would be installed as a real retention.');
    });
  });

  group('updateRetentionPolicy refuses to install a destructive policy', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.inMemoryForTest());
    tearDown(() => db.close());

    test('a seconds-range dropAfter throws instead of deleting the history',
        () async {
      await expectLater(
        db.updateRetentionPolicy(
            't', RetentionPolicy(dropAfter: const Duration(seconds: 5))),
        throwsA(isA<DatabaseException>().having((e) => e.message, 'message',
            allOf(contains('5'), contains('t')))),
      );
    });

    test('zero throws', () async {
      await expectLater(
        db.updateRetentionPolicy('t', RetentionPolicy(dropAfter: Duration.zero)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('it throws BEFORE issuing any statement', () async {
      // The refusal has to happen before create_hypertable and, critically,
      // before remove_retention_policy: a refusal that has already removed the
      // old policy has made things worse, not better.
      await db.customStatement(
          'CREATE TABLE "t" (time TEXT, value INTEGER)');
      await expectLater(
        db.updateRetentionPolicy(
            't', RetentionPolicy(dropAfter: const Duration(seconds: 30))),
        throwsA(isA<DatabaseException>()),
      );
      // On sqlite create_hypertable would have thrown a *different* error; a
      // DatabaseException proves we never got that far.
    });

    test('a minute or more is accepted as far as the SQL', () async {
      // sqlite has no create_hypertable, so this fails -- but it must fail as
      // sqlite complaining, not as our own refusal.
      await expectLater(
        db.updateRetentionPolicy(
            't', RetentionPolicy(dropAfter: const Duration(days: 30))),
        throwsA(isNot(isA<DatabaseException>())),
      );
    });
  });

  group('pg.Interval still renders a clamped policy correctly', () {
    test('a decade goes into the SQL as its exact microsecond count', () {
      // Worth pinning: `Interval.duration` does not render "3650 days", it
      // renders microseconds, and `add_retention_policy(..., drop_after =>
      // INTERVAL '...')` is built by string interpolation from it. The number
      // has to be the decade, not a truncation of it.
      final i = pg.Interval.duration(const Duration(days: kMaxRetentionDays));
      expect(i.toString(),
          '${const Duration(days: kMaxRetentionDays).inMicroseconds} microseconds');
    });
  });
}

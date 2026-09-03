/// The outbound size discipline: the two ceilings, their derivation, and the
/// enforcement that refuses rather than truncates.
///
/// **Two lanes in one file, by design.** The derivation is arithmetic over
/// three numbers that already exist — `ServerConfig.maxPendingBytes`,
/// `ServerConfig.maxFrameBytes` and the protocol's own encoder — and needs no
/// database, so it runs in the ordinary lane where everybody sees it. The
/// enforcement is about what a real Postgres does when a window holds one row
/// too many, and that needs the `db` lane. The db cases carry `tags: 'db'`
/// individually rather than the file carrying `@Tags(['db'])`, because a
/// file-level tag would hide the arithmetic behind Docker.
///
/// **Every number in here is measured, or read off the thing it claims to be
/// derived from.** The lane ceiling is taken from a live `ServerConfig` rather
/// than copied as a literal, so a Phase 11 that moves it fails this file
/// instead of leaving a stale derivation that reads as though somebody checked.
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_relay_local/src/data/read_limits.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart'
    show TimeseriesData;
import 'package:tfc_relay_server/tfc_relay_server.dart' show ServerConfig;

// ---------------------------------------------------------------------------
// The plant's own numbers, with their provenance.
// ---------------------------------------------------------------------------

/// How often SVN samples a collected key.
///
/// `svn-key-mappings.json`: `"sample_interval_us": 5000000` — the interval on
/// fourteen of the entries that name one; twelve name 500 000 and the rest
/// inherit the collector's default. Five seconds is what the windows below are
/// computed from, because a hardcoded row count stops being about the plant
/// the moment the interval changes.
const Duration svnSampleInterval = Duration(seconds: 5);

/// The live preference store, encoded as one `getAll` answer.
///
/// Measured on 2026-09-03 from `svn-prefs-live-20260811.csv` (the 2026-08-11
/// dump) by decoding the CSV and JSON-encoding the resulting
/// `Map<String, String>`:
///
/// | row | raw bytes | encoded bytes |
/// |---|---|---|
/// | `key_mappings` | 530 287 | 590 539 |
/// | `page_editor_data` | 145 405 | 163 869 |
/// | `mcp.config` | 185 | 211 |
/// | `alarm_man_config` | 13 | 17 |
/// | **the map** | **675 890** | **754 707** |
///
/// The encoded figure is the one that matters and it is **11.7 % larger than
/// the raw one**: the store's two big rows are themselves JSON documents, so
/// every `"` in them becomes `\"` on the way out. 10-09 measured 19 % against
/// a synthetic row of the same size; the real row escapes at 11.4 %, because
/// the synthetic packs more quotes per byte than the plant's actual tag map.
/// Both are recorded rather than reconciled — the real file is the claim.
const int liveStoreEncodedBytes = 754707;

/// What the live store is before encoding, for the margin sentence.
const int liveStoreRawBytes = 675890;

// ---------------------------------------------------------------------------
// A corpus of samples shaped like the plant's.
// ---------------------------------------------------------------------------

/// The float64 a float32 widens to — `1423.7` becomes `1423.699951171875`.
double asFloat32(double v) => (Float32List(1)..[0] = v)[0];

/// Values shaped like the ones SVN actually records.
///
/// Every collected column is `double precision` and most of what fills it
/// arrives as a PLC `REAL` — a float32 widened to float64, which prints its
/// full binary artifact rather than the round number an engineer typed. A
/// corpus of tidy one-decimal values would measure a sample half the size of
/// the ones a conveyor speed or a freezer temperature actually produce, and a
/// ceiling derived from that is a ceiling that does not hold.
///
/// So the corpus is the mix: float32 artifacts positive and negative (the far
/// side of CN20 is the freezer and runs below zero), tidy scaled values, and
/// the 1/0 a boolean charts as.
final List<num> plantSampleCorpus = <num>[
  1423, // a raw counter
  1423.7, // a conveyor speed as an engineer types it
  asFloat32(1423.7), // …as the PLC REAL actually widens
  asFloat32(-18.1), // freezer air, below zero
  asFloat32(0.1), // a 4-20 mA input near its floor
  asFloat32(3.72), // drive current
  0, // a boolean, charted
  1, // a boolean, charted
  65535, // a counter at full scale
];

/// The instant every sample in this file is stamped with — fixed, so the
/// measurement is about the encoder rather than about today's date.
final DateTime anchor = DateTime.utc(2026, 9, 3, 12);

void main() {
  group('one sample, measured through the protocol\'s own encoder', () {
    test('the pinned bytes-per-sample is the worst the corpus produces', () {
      final sizes = <num, int>{
        for (final v in plantSampleCorpus)
          v: utf8
                  .encode(jsonEncode(TimeseriesData<num?>(v, anchor).toJson()))
                  .length +
              1, // the ',' that joins it to the next sample in the array
      };
      final worst = sizes.values.reduce(max);
      final mean = sizes.values.reduce((a, b) => a + b) / sizes.length;
      final widest = sizes.entries.reduce((a, b) => a.value >= b.value ? a : b);

      // ignore: avoid_print
      print('MEASURED bytes per encoded sample: worst=$worst '
          'mean=${mean.toStringAsFixed(1)} over ${sizes.length} plant-shaped '
          'values; the widest is ${widest.key} at ${widest.value} B');

      expect(ReadLimits.measuredBytesPerSample, worst,
          reason: 'the row ceiling is derived by dividing a byte budget by '
              'this number, so it must be the WORST a realistic sample '
              'produces and not the mean: half of a noisy series is above the '
              'mean, and a budget half a series exceeds is not a budget. If '
              'the encoder changes, this constant moves with it and the '
              'derived row cap is recomputed in the same commit');
    });
  });

  group('the row ceiling is derived from the priority lane', () {
    test('the priority lane is still 8 MiB, which the derivation divides', () {
      expect(ServerConfig().maxPendingBytes, 8 * 1024 * 1024,
          reason: 'every number in read_limits.dart is a fraction of this '
              'one. If it moved, the derivation in that file is stale — and a '
              'stale derivation is worse than none, because it reads as '
              'though somebody checked');
    });

    test('the default row cap fits a quarter of the lane at the measured size',
        () {
      final lane = ServerConfig().maxPendingBytes;
      final budget = lane ~/ 4;
      final derived = budget ~/ ReadLimits.measuredBytesPerSample;
      final chosen = ReadLimits.defaultMaxTimeseriesRows;
      final share =
          chosen * ReadLimits.measuredBytesPerSample * 100 / lane;

      // ignore: avoid_print
      print('DERIVATION: lane $lane B / 4 = $budget B budget; '
          '$budget / ${ReadLimits.measuredBytesPerSample} B per sample = '
          '$derived rows; chosen default = $chosen rows '
          '(${share.toStringAsFixed(1)}% of the whole lane)');

      expect(chosen, lessThanOrEqualTo(derived),
          reason: 'a response is budgeted at a quarter of the lane so a '
              'four-series chart plus the value updates and notifications the '
              'same session is receiving still fit — the lane is NOT '
              'conflated, so a response sits in it until the tick drains it');
      expect(chosen, greaterThan(derived ~/ 2),
          reason: 'headroom is not the same as timidity. A default far below '
              'the derived figure refuses windows the buffer could carry, and '
              'that refusal would be this file\'s fault rather than the '
              'lane\'s');
    });
  });

  group('the windows the default allows and the ones it refuses', () {
    int rowsIn(Duration window) =>
        window.inMicroseconds ~/ svnSampleInterval.inMicroseconds;

    test('a day of 5 s samples is answered and a month is refused', () {
      final cap = ReadLimits.defaultMaxTimeseriesRows;
      final day = rowsIn(const Duration(days: 1));
      final month = rowsIn(const Duration(days: 30));
      final widestDays =
          cap * svnSampleInterval.inSeconds / Duration.secondsPerDay;

      // ignore: avoid_print
      print('WINDOWS at ${svnSampleInterval.inSeconds} s sampling: '
          'a day = $day rows, a month = $month rows, cap = $cap rows; '
          'the widest window answered raw is '
          '${widestDays.toStringAsFixed(1)} days');

      expect(day, lessThan(cap),
          reason: 'a day is the window an operator scrolls to without '
              'thinking about it. A default that refused it would make the '
              'refusal the normal case, and a refusal nobody can avoid is a '
              'broken chart with a longer message');
      expect(month, greaterThan(cap),
          reason: 'a month is ${(month / cap).toStringAsFixed(0)}x the cap, '
              'about ${(month * ReadLimits.measuredBytesPerSample / (1024 * 1024)).toStringAsFixed(0)} '
              'MiB encoded — twice a whole session lane. This is the query '
              'that evicts a panel with 4004 and tells the operator they '
              'disconnected');
    });
  });

  group('the preference byte ceiling', () {
    test('it is above the live store, and the margin is printed', () {
      final cap = ReadLimits.defaultMaxPreferenceBytes;
      final margin = cap - liveStoreEncodedBytes;
      final escaping =
          (liveStoreEncodedBytes - liveStoreRawBytes) * 100 / liveStoreRawBytes;

      // ignore: avoid_print
      print('PREFERENCES: live store raw $liveStoreRawBytes B, encoded '
          '$liveStoreEncodedBytes B (+${escaping.toStringAsFixed(1)}%); '
          'cap $cap B; margin $margin B = '
          '${(margin * 100 / liveStoreEncodedBytes).toStringAsFixed(1)}% of '
          'today\'s store, which fills '
          '${(liveStoreEncodedBytes * 100 / cap).toStringAsFixed(1)}% of the '
          'cap');

      expect(cap, greaterThan(liveStoreEncodedBytes),
          reason: 'a cap below today\'s real store breaks getAll for the '
              'plant that is running now, and it breaks it as "the settings '
              'page will not open"');
    });

    test('it is maxFrameBytes, so one number bounds both directions', () {
      expect(ReadLimits.defaultMaxPreferenceBytes, ServerConfig().maxFrameBytes,
          reason: 'a value too large to be WRITTEN over the pipe is also too '
              'large to be read in bulk. Symmetric, and one number to '
              'remember instead of two');
    });
  });

  group('a limit that refuses everything is refused at construction', () {
    test('zero rows is refused, naming the field', () {
      expect(
          () => ReadLimits(maxTimeseriesRows: 0),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('maxTimeseriesRows'))),
          reason: 'a row cap of zero refuses every query, and a panel reports '
              'that as "the historian is empty"');
    });

    test('a negative row cap is refused, naming the field', () {
      expect(
          () => ReadLimits(maxTimeseriesRows: -1),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('maxTimeseriesRows'))));
    });

    test('zero preference bytes is refused, naming the field', () {
      expect(
          () => ReadLimits(maxPreferenceBytes: 0),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('maxPreferenceBytes'))));
    });

    test('a negative preference cap is refused, naming the field', () {
      expect(
          () => ReadLimits(maxPreferenceBytes: -1),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('maxPreferenceBytes'))));
    });
  });
}

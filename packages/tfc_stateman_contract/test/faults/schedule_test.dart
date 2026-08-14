/// The seeded fault-storm driver: generation is pure, playback is timed.
///
/// The generation arms are plain computation — no sockets, no timers, no
/// clock — which is the whole claim `scenario_schedule.dart` makes, and the
/// reason they run in milliseconds while the rest of this directory measures
/// wall-clock behaviour through loopback.
///
/// Tagged `faults` with the rest of the kit rather than left untagged: the
/// playback arm below does open a proxy and a client, so a run that excluded
/// this file by tag and still exercised it would be measuring sockets in a
/// lane that promised none.
@Tags(['faults'])
library;

import 'package:test/test.dart';
import 'package:tfc_stateman_contract/faults.dart';

/// The soak duration notes §7.8 specifies, used by the entry-count arm.
const _soakDuration = Duration(minutes: 30);

/// How many seeds the forbidden-pair sweep covers.
///
/// The plan asks for at least 100. The sweep is pure computation over a
/// half-hour timeline each, so the cost of the extra seeds is a second and the
/// benefit is that a rule with a narrow hole is more likely to fall into it.
const _sweepSeeds = 150;

void main() {
  group('ScenarioSchedule.generate — the pure part', () {
    test('the same seed produces an identical timeline', () {
      final first = ScenarioSchedule.generate(
        seed: 42,
        duration: _soakDuration,
      );
      final second = ScenarioSchedule.generate(
        seed: 42,
        duration: _soakDuration,
      );

      // Element-wise equality over the whole list, not a length comparison: a
      // generator that drifted in its parameters while keeping its cadence
      // would produce two lists of the same length describing two different
      // runs, and reproduction from a seed would be a claim nobody checked.
      expect(second, equals(first),
          reason: 'a soak failure is reproduced from its seed alone, so two '
              'generations of one seed that differ mean the repro procedure '
              'in notes §7.8 does not work');

      // And byte-identical once serialised, because the serialised form is
      // what a failing run prints and what a human pastes back.
      expect(ScenarioSchedule.reproLog(seed: 42, timeline: second),
          equals(ScenarioSchedule.reproLog(seed: 42, timeline: first)));
    });

    test('different seeds produce different timelines', () {
      final logs = <String>{};
      for (var seed = 1; seed <= 20; seed++) {
        final timeline =
            ScenarioSchedule.generate(seed: seed, duration: _soakDuration);
        logs.add(ScenarioSchedule.reproLog(seed: seed, timeline: timeline));
      }
      expect(logs, hasLength(20),
          reason: 'two seeds that generate the same storm make the seed '
              'useless as a way to vary a soak run');
    });

    test('a 30-minute run is a few hundred entries, generated in well under a '
        'second', () {
      final clock = Stopwatch()..start();
      final timeline = ScenarioSchedule.generate(
        seed: 7,
        duration: _soakDuration,
        weights: ScenarioWeights.everything,
      );
      clock.stop();

      // 30 minutes at a 1–10 s cadence is ~327 draws; conflict resolution adds
      // a clear or two per arming draw, so the band is wide on the top side.
      expect(timeline.length, inInclusiveRange(200, 1200),
          reason: 'notes §7.8 sizes a 30-minute storm at a few hundred '
              'entries; far outside that band means the cadence drifted');
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'Phase 11 generates the whole timeline before the soak '
              'starts, so generation cost must not show up as soak time');

      expect(timeline.first.offset, greaterThanOrEqualTo(Duration.zero));
      expect(timeline.last.offset, lessThan(_soakDuration));
    });

    test('offsets never go backwards', () {
      final timeline = ScenarioSchedule.generate(
        seed: 99,
        duration: _soakDuration,
        weights: ScenarioWeights.everything,
      );
      var previous = Duration.zero;
      for (final entry in timeline) {
        expect(entry.offset, greaterThanOrEqualTo(previous),
            reason: 'playback walks the list in order against a single '
                'drift-corrected timer, so an offset that went backwards '
                'would be applied immediately and out of sequence');
        previous = entry.offset;
      }
    });

    test('no forbidden mode pair is ever co-armed, over $_sweepSeeds seeds',
        () {
      for (var seed = 0; seed < _sweepSeeds; seed++) {
        final timeline = ScenarioSchedule.generate(
          seed: seed,
          duration: _soakDuration,
          weights: ScenarioWeights.everything,
        );
        _assertNeverCoArmed(seed, timeline);
      }
    });

    test('the returned timeline is unmodifiable', () {
      final timeline =
          ScenarioSchedule.generate(seed: 3, duration: const Duration(minutes: 1));

      expect(() => timeline.add(timeline.first), throwsUnsupportedError,
          reason: 'the timeline is the repro log; a caller that could append '
              'to it could make the log disagree with the seed that produced '
              'it');
      expect(() => timeline.clear(), throwsUnsupportedError);
      expect(() => timeline[0] = timeline.last, throwsUnsupportedError);
    });

    test('generation refuses arguments that cannot describe a run', () {
      expect(
          () => ScenarioSchedule.generate(seed: 1, duration: Duration.zero),
          throwsArgumentError);
      expect(
          () => ScenarioSchedule.generate(
              seed: 1,
              duration: const Duration(minutes: 1),
              minGap: Duration.zero),
          throwsArgumentError);
      expect(
          () => ScenarioSchedule.generate(
              seed: 1,
              duration: const Duration(minutes: 1),
              minGap: const Duration(seconds: 5),
              maxGap: const Duration(seconds: 1)),
          throwsArgumentError);
    });

    test('weights are checked against the mode registry', () {
      expect(() => ScenarioWeights(const {'flapp': 1}).validate(),
          throwsArgumentError,
          reason: 'a misspelled mode name would silently weight nothing, and '
              'the storm would quietly never exercise the mode its author '
              'asked for');
      expect(() => ScenarioWeights(const {'flap': 0}).validate(),
          throwsArgumentError,
          reason: 'a total weight of zero has no mode to draw');
      expect(() => ScenarioWeights(const {'flap': -1}).validate(),
          throwsArgumentError);
      expect(ScenarioWeights.soak.validate, returnsNormally);
      expect(ScenarioWeights.everything.validate, returnsNormally);
    });

    test('the default weights are the five notes §7.8 names', () {
      expect(ScenarioWeights.soak.byMode.keys,
          unorderedEquals(<String>['flap', 'latency', 'throttle', 'blackhole',
            ScenarioSchedule.cleanMode]));
    });

    test('the everything weights name every declared mode', () {
      expect(
          ScenarioWeights.everything.byMode.keys.where((m) => m != ScenarioSchedule.cleanMode),
          unorderedEquals(faultModes),
          reason: 'a mode declared in faultModes but absent here is a lever '
              'no storm can ever pull, which is the same silent gap the mode '
              'registry exists to prevent');
    });
  });
}

/// Fails if [timeline] ever arms a mode while a mode it excludes is armed.
///
/// Derived from [exclusiveModePairs] — the proxy's own table — rather than
/// from a second copy of the rule written here. A sweep that restated the
/// exclusions would pass whenever the generator and the test made the same
/// mistake, which is the only mistake worth catching.
void _assertNeverCoArmed(int seed, List<ScheduledFault> timeline) {
  final armed = <String>{};
  for (final entry in timeline) {
    final mutation = entry.mutation;
    if (!mutation.arms) {
      armed.remove(mutation.mode);
      continue;
    }
    for (final conflict in exclusiveModePairs) {
      final String other;
      if (conflict.a == mutation.mode) {
        other = conflict.b;
      } else if (conflict.b == mutation.mode) {
        other = conflict.a;
      } else {
        continue;
      }
      if (!armed.contains(other)) continue;
      fail('seed $seed arms ${mutation.mode} at ${entry.offset} while $other '
          'is armed — the proxy throws a StateError at set time for that '
          'pair, so this storm would abort the soak it was generated for '
          'instead of testing it.\n'
          '${ScenarioSchedule.reproLog(seed: seed, timeline: timeline)}');
    }
    armed.add(mutation.mode);
  }
}

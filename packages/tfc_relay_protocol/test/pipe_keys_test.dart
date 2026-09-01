import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// The vocabulary is only worth having if it is the *only* spelling. These
/// arms judge that property directly: every declared name is in the reserved
/// namespace, the two lanes partition the roster by set arithmetic rather than
/// by a second hand-written list, and the per-alias builders round-trip the
/// alias they were given.
void main() {
  // A never-before-seen alias, deliberately not one of the plant's four, so
  // that anything answering correctly for it is answering by rule rather than
  // by having the name written down somewhere.
  const aliases = ['ST101', 'ST201', 'ST301', 'baader', 'bench-rig-7'];

  List<String> Function(String) allBuilders() => (alias) => [
        PipeKeys.upstreamConnected(alias),
        PipeKeys.upstreamState(alias),
        PipeKeys.upstreamLastError(alias),
        PipeKeys.upstreamEpoch(alias),
        PipeKeys.upstreamBirthCount(alias),
        PipeKeys.upstreamLastDeathAt(alias),
      ];

  group('the reserved namespace', () {
    test('the roster is not empty', () {
      // Anti-vacuity, first: every sweep below iterates `declared`, and a
      // sweep over an empty list passes against nothing.
      expect(PipeKeys.declared, isNotEmpty);
      expect(PipeKeys.declared.length, PipeKeys.declared.toSet().length,
          reason: 'a duplicate in the roster would make the partition '
              'arithmetic below pass while one lane silently held two copies '
              'of the same key');
    });

    test('every declared key starts with the prefix', () {
      for (final key in PipeKeys.declared) {
        expect(key.startsWith(PipeKeys.prefix), isTrue,
            reason: '$key is not in the reserved namespace, which means the '
                'freshness sweep will not skip it (HLTH-02), the keymapping '
                'ingest will not reserve it (HLTH-03), and nothing will ever '
                'route it — a roster entry that forgot the prefix is a key '
                'that does not exist');
      }
    });

    test('every key a builder mints starts with the prefix', () {
      for (final alias in aliases) {
        for (final key in allBuilders()(alias)) {
          expect(key.startsWith(PipeKeys.prefix), isTrue, reason: key);
        }
      }
    });

    test('isPipeKey is a prefix test, never a roster lookup', () {
      // The distinction is the whole design of HLTH-03: a key invented in a
      // later phase must be reserved on the day it is invented, without an
      // edit here. A roster lookup would leave every new health key
      // unreserved and unswept until somebody remembered to add it.
      expect(PipeKeys.isPipeKey('PIPE.invented_next_year'), isTrue);
      expect(PipeKeys.declared, isNot(contains('PIPE.invented_next_year')),
          reason: 'the point of the previous line is that it answers true for '
              'a key the roster has never heard of');

      expect(PipeKeys.isPipeKey('ST101.CN01.MOT01.speed'), isFalse);
      expect(PipeKeys.isPipeKey('PIPES.connected'), isFalse,
          reason: 'the prefix carries its dot, so a plant area called PIPES '
              'is not accidentally reserved wholesale');
    });
  });

  group('the per-alias builders', () {
    test('build the documented spelling', () {
      expect(PipeKeys.upstreamConnected('st101'), 'PIPE.upstream.st101.connected');
      expect(PipeKeys.upstreamState('st101'), 'PIPE.upstream.st101.state');
      expect(PipeKeys.upstreamLastError('st101'), 'PIPE.upstream.st101.last_error');
      expect(PipeKeys.upstreamEpoch('st101'), 'PIPE.upstream.st101.epoch');
      expect(
          PipeKeys.upstreamBirthCount('st101'), 'PIPE.upstream.st101.birth_count');
      expect(PipeKeys.upstreamLastDeathAt('st101'),
          'PIPE.upstream.st101.last_death_at');
    });

    test('round-trip the alias through aliasOf', () {
      for (final alias in aliases) {
        for (final key in allBuilders()(alias)) {
          expect(PipeKeys.aliasOf(key), alias,
              reason: '$key must name $alias back. The per-link health '
                  'producer reads the alias out of the key to attribute a '
                  'degradation to one PLC; a key it cannot parse degrades '
                  'nothing, or everything');
        }
      }
    });

    test('aliasOf is null for anything that is not an upstream key', () {
      for (final notUpstream in [
        PipeKeys.connected,
        PipeKeys.epoch,
        PipeKeys.certDaysToExpiry,
        PipeKeys.eventLoopLagMs,
        'ST101.CN01.MOT01.speed',
        'PIPE.upstream.st101', // truncated: no field
        'PIPE.upstream.st101.connected.extra', // one segment too many
      ]) {
        expect(PipeKeys.aliasOf(notUpstream), isNull, reason: notUpstream);
      }
    });

    test('an alias that would mint an unparseable key is refused', () {
      // Rule-2 guard rather than plan text: the key is dot-delimited, so an
      // alias carrying a dot produces a name `aliasOf` reads back as null.
      // That is precisely the "key nothing will ever route" this file exists
      // to prevent, and it is cheaper to refuse it at the mint than to
      // diagnose a link whose health keys attribute to no link.
      expect(() => PipeKeys.upstreamConnected('st101.plc'),
          throwsA(isA<ArgumentError>()));
      expect(() => PipeKeys.upstreamState(''), throwsA(isA<ArgumentError>()));
    });
  });

  group('the priority / conflated split', () {
    test('the two lanes partition the declared roster', () {
      final roster = PipeKeys.declared.toSet();

      expect(PipeKeys.priorityLane.union(PipeKeys.conflatedLane), roster,
          reason: 'a declared key in neither lane is a key the send buffer '
              'has no rule for');
      expect(PipeKeys.priorityLane.intersection(PipeKeys.conflatedLane), isEmpty,
          reason: 'a key in both lanes is delivered twice by two different '
              'disciplines, and the conflated copy can overtake the priority '
              'one');
    });

    test('state changes ride the priority lane', () {
      // "A degraded link must still deliver the news that it is degraded" —
      // that is the news, not the telemetry.
      for (final key in [
        PipeKeys.connected,
        PipeKeys.epoch,
        PipeKeys.linkDegraded,
        PipeKeys.upstreamConnected('ST201'),
        PipeKeys.upstreamState('ST201'),
        PipeKeys.upstreamLastError('ST201'),
        PipeKeys.upstreamEpoch('ST201'),
        PipeKeys.upstreamBirthCount('ST201'),
        PipeKeys.upstreamLastDeathAt('ST201'),
      ]) {
        expect(PipeKeys.ridesPriorityLane(key), isTrue, reason: key);
      }
    });

    test('gauges ride the conflated lane', () {
      // An unconflated fast-moving gauge is a queue, which the core value
      // forbids outright.
      for (final key in [
        PipeKeys.rttMs,
        PipeKeys.dataAgeMs,
        PipeKeys.reconnects,
        PipeKeys.effectiveHz,
        PipeKeys.egressKbps,
        PipeKeys.pendingKeys,
        PipeKeys.eventLoopLagMs,
        PipeKeys.droppedHoldTicks,
        PipeKeys.certDaysToExpiry,
      ]) {
        expect(PipeKeys.ridesPriorityLane(key), isFalse, reason: key);
      }
    });

    test('the lane is decided by suffix, so a new alias needs no edit here',
        () {
      // `bench-rig-7` appears in no list in the library. If this passes, the
      // rule is doing the work.
      expect(PipeKeys.ridesPriorityLane('PIPE.upstream.bench-rig-7.connected'),
          isTrue);
      expect(PipeKeys.ridesPriorityLane('PIPE.upstream.bench-rig-7.rtt_ms'),
          isFalse);
    });

    test('a plant key never rides the priority lane on a matching suffix', () {
      // `ST101.CN01.MOT01.connected` ends in a priority suffix and is an
      // ordinary tag. Promoting it would put plant telemetry on the lane that
      // is never conflated.
      expect(PipeKeys.ridesPriorityLane('ST101.CN01.MOT01.connected'), isFalse);
      expect(PipeKeys.ridesPriorityLane('ST101.CN01.MOT01.state'), isFalse);
    });
  });

  group('agreement with the rest of the workspace', () {
    test('the certificate key is spelled the way every deployment spells it',
        () {
      // Moved verbatim from `cert_health_state_man.dart`, where it shipped in
      // Phase 6. The alarm configuration in the plant matches on this string;
      // a rename here compiles, keeps every suite green, and quietly stops
      // matching.
      expect(PipeKeys.certDaysToExpiry, 'PIPE.cert.days_to_expiry');
    });

    test('the five client-side keys match the reference implementation', () {
      // Asserted against literals rather than against the contract kit's
      // `FakeStateMan.healthKeys` (`fake_state_man.dart:102-107`), because
      // this package has no dependencies at all and the kit depends on *it* —
      // importing the kit here would invert the workspace. The literals are
      // the enforcement available in this direction; the roster there stays
      // at five (a sixth entry puts a key on every contract leg, including
      // the in-memory ones with no upstream and no certificate).
      expect(
        [
          PipeKeys.connected,
          PipeKeys.rttMs,
          PipeKeys.dataAgeMs,
          PipeKeys.reconnects,
          PipeKeys.epoch,
        ],
        [
          'PIPE.connected',
          'PIPE.rtt_ms',
          'PIPE.data_age_ms',
          'PIPE.reconnects',
          'PIPE.epoch',
        ],
      );
    });

    test('the prefix is the one the reference implementation reserves', () {
      expect(PipeKeys.prefix, 'PIPE.');
    });
  });
}

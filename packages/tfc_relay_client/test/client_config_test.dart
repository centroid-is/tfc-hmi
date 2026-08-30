/// Every client timing number has one home, and the combinations that cannot
/// work are refused at construction.
///
/// Source: 04-RESEARCH Finding 8 measured this transport at a **50.0 ms mean
/// round trip over 50 `ping` calls**, quantised to the server's fan-out
/// period, which itself runs 50–100 ms. A deadline anywhere near that floor
/// fires on a healthy link, and on the write path a fired deadline is not an
/// error the operator can act on — it resolves `WriteUnknown`. A plant where
/// every ordinary write comes back "unknown" is a plant where nobody trusts
/// the screen, which is the one thing this product sells.
///
/// Source: 04-CONTEXT post-research ruling — the freshness deadline is
/// **configured, default 3 s**, never derived from the transport period. Three
/// times a 50 ms period is 150 ms, and a GC pause would grey the whole plant.
///
/// Source: STACK rejected `web_socket_client` for an infinite backoff loop, so
/// a cap above 30 s is refused rather than merely discouraged: a panel that
/// backs off to ten minutes is a panel the operator reboots.
library;

import 'dart:io';

import 'package:tfc_relay_client/src/client_config.dart';
import 'package:test/test.dart';

void main() {
  group('ClientConfig defaults', () {
    test('the researched numbers are what you get for free', () {
      final config = ClientConfig();

      expect(config.controlDeadline, const Duration(seconds: 1),
          reason: 'a control-plane call that never returns leaves the panel '
              'showing a connecting spinner forever');
      expect(config.writeDeadline, const Duration(seconds: 2),
          reason: 'a write with no deadline hangs the operator on a button '
              'press instead of telling them the outcome is unknown');
      expect(config.freshnessDeadline, const Duration(seconds: 3),
          reason: 'the design band is 2-5 s; a value outside it either greys '
              'a healthy plant or hides a dead link');
      expect(config.backoffBase, const Duration(milliseconds: 250));
      expect(config.backoffCap, const Duration(seconds: 30));
      expect(config.implausibleClockThreshold, const Duration(minutes: 5));
      expect(config.deadlineFloor, const Duration(milliseconds: 500));
    });

    test('the floor is the measured round trip rounded up, not a guess', () {
      expect(ClientConfig.defaultDeadlineFloor,
          const Duration(milliseconds: 500),
          reason: 'a bare round trip on this transport is one server period; '
              'a floor under it makes a healthy link look broken');
      expect(ClientConfig.maxBackoffCap, const Duration(seconds: 30),
          reason: 'an unbounded cap is the infinite-backoff bug that got '
              'web_socket_client rejected');
    });
  });

  group('a deadline under the floor is refused, naming the floor', () {
    test('writeDeadline under the floor names the field, value and floor', () {
      expect(
        () => ClientConfig(writeDeadline: const Duration(milliseconds: 200)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(
              contains('writeDeadline'),
              contains('200 ms'),
              contains('500 ms'),
            ),
          ),
        ),
        reason: 'a deadline under one round trip turns every write on a '
            'healthy link into a false unknown, and the message has to say '
            'which number and which bound so the operator who set it can '
            'undo it',
      );
    });

    test('controlDeadline under the floor is refused by name', () {
      expect(
        () => ClientConfig(controlDeadline: const Duration(milliseconds: 100)),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('controlDeadline'), contains('100 ms')),
        )),
        reason: 'a subscribe that times out before the server can answer '
            'reconnects forever and never shows a value',
      );
    });

    test('freshnessDeadline under the floor is refused by name', () {
      expect(
        () =>
            ClientConfig(freshnessDeadline: const Duration(milliseconds: 150)),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('freshnessDeadline'), contains('150 ms')),
        )),
        reason: 'three times the transport period is 150 ms, and a single GC '
            'pause at that setting greys the whole plant',
      );
    });

    test('exactly at the floor is allowed', () {
      final config =
          ClientConfig(writeDeadline: const Duration(milliseconds: 500));
      expect(config.writeDeadline, const Duration(milliseconds: 500),
          reason: 'the floor is a floor, not an exclusive bound; refusing it '
              'would make the documented minimum unusable');
    });
  });

  group('the floor itself is injectable, on purpose and greppably', () {
    test('lowering deadlineFloor admits a sub-floor write deadline', () {
      final config = ClientConfig(
        deadlineFloor: const Duration(milliseconds: 10),
        writeDeadline: const Duration(milliseconds: 100),
      );

      expect(config.writeDeadline, const Duration(milliseconds: 100),
          reason: "truncated_write_test's polarity flip only means something "
              'if the write deadline can fire inside the case\'s own budget; '
              'a hard floor would make the flip untestable');
      expect(config.deadlineFloor, const Duration(milliseconds: 10));
    });

    test('a raised floor refuses a default that was fine before', () {
      expect(
        () => ClientConfig(deadlineFloor: const Duration(seconds: 5)),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('controlDeadline'), contains('5000 ms')),
        )),
        reason: 'the floor is checked against every deadline including the '
            'defaults, so a floor raised past them fails loudly at '
            'construction instead of quietly at 3 a.m.',
      );
    });

    test('a non-positive floor is refused', () {
      expect(
        () => ClientConfig(deadlineFloor: Duration.zero),
        throwsA(isA<ArgumentError>()),
        reason: 'a zero floor disables the only check standing between a '
            'typo and a plant full of false unknowns',
      );
    });
  });

  group('backoff bounds', () {
    test('a cap above 30 s is refused', () {
      expect(
        () => ClientConfig(backoffCap: const Duration(minutes: 2)),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('backoffCap'), contains('30000 ms')),
        )),
        reason: 'a panel that backs off past half a minute looks dead to the '
            'operator, who power-cycles it instead of waiting',
      );
    });

    test('a base above the cap is refused', () {
      expect(
        () => ClientConfig(
          backoffBase: const Duration(seconds: 20),
          backoffCap: const Duration(seconds: 5),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          contains('backoffBase'),
        )),
        reason: 'a base over the cap means the very first retry is already '
            'clamped, so the schedule is a constant and the herd re-forms',
      );
    });

    test('a non-positive base is refused', () {
      expect(
        () => ClientConfig(backoffBase: Duration.zero),
        throwsA(isA<ArgumentError>()),
        reason: 'a zero base is a reconnect loop with no pause, which is a '
            'denial of service the panel commits against its own gateway',
      );
    });

    test('a non-positive implausible-clock threshold is refused', () {
      expect(
        () => ClientConfig(implausibleClockThreshold: Duration.zero),
        throwsA(isA<ArgumentError>()),
        reason: 'a zero threshold warns about clock skew on every hello, and '
            'a warning that is always on is a warning nobody reads',
      );
    });
  });

  group('the hold-to-run cadence and the deadman ratio', () {
    test("the default hold cadence and ratio multiply out to the plant's one "
        'second', () {
      final config = ClientConfig();

      expect(config.holdPulsePeriod, const Duration(milliseconds: 100),
          reason: 'the deadman is fed at 10 Hz; a slower cadence spends the '
              "PLC's tolerance budget on fewer pulses and a faster one buys "
              'nothing the operator can feel');
      expect(config.holdMissedPulsesBeforeStop, 10);
      // The product, not the constant. A change to either factor moves the
      // number the PLC's TON preset was chosen against, and the whole point of
      // spelling the deadman as a ratio is that the two cannot drift apart
      // silently.
      expect(config.holdPulsePeriod * config.holdMissedPulsesBeforeStop,
          const Duration(seconds: 1),
          reason: 'the cadence and the ratio no longer multiply out to the one '
              'second the plant was configured for, so the panel and the PLC '
              'now disagree about how long a machine may coast after the '
              'operator lets go — and only the PLC stops it');
      expect(config.holdDeadman, const Duration(seconds: 1),
          reason: 'holdDeadman is the derived answer to "how long until the '
              'machine stops"; a value other than the product means it is '
              'being stored somewhere instead of computed, which is how two '
              'numbers that must agree stop agreeing');
    });

    test('the default config constructs, because a cadence is not a deadline',
        () {
      // The named regression case for the phase's most likely mechanical
      // mistake (05-RESEARCH "Traps for the executor" #1). `_atLeastFloor`
      // rejects anything under `deadlineFloor`, which defaults to 500 ms; the
      // hold cadence is 100 ms, one fifth of it.
      final config =
          ClientConfig(holdPulsePeriod: const Duration(milliseconds: 100));

      expect(config.holdPulsePeriod, const Duration(milliseconds: 100),
          reason: 'a 100 ms cadence against the default 500 ms deadline floor '
              'threw at construction, which means the hold cadence was routed '
              'through the deadline-floor validator. A cadence is not a '
              'deadline: nothing waits on one pulse, and a dropped one costs '
              'nothing the next one 100 ms later does not fix. Routed that '
              'way, `ClientConfig()` with no arguments throws — so the panel '
              'does not come up at all, and every screen in the plant is dark '
              'at shift start');
      expect(config.deadlineFloor, const Duration(milliseconds: 500),
          reason: 'the floor is still the researched 500 ms, so the case above '
              'was judged against the default and not against a floor the case '
              'quietly lowered for itself');
    });

    test('a zero cadence is refused by name', () {
      expect(
        () => ClientConfig(holdPulsePeriod: Duration.zero),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('holdPulsePeriod'), contains('0 ms')),
        )),
        reason: 'a zero cadence is a timer that fires as fast as the event '
            'loop will let it, which floods the socket the deadman is fed '
            'over and starves everything else on the panel',
      );
    });

    test('a negative cadence is refused by name', () {
      expect(
        () => ClientConfig(holdPulsePeriod: const Duration(milliseconds: -100)),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('holdPulsePeriod'), contains('-100 ms')),
        )),
        reason: 'a negative cadence disables the feed, so the button lights '
            'and the machine never jogs',
      );
    });

    test('fewer than three missed pulses inverts the tolerance decision', () {
      expect(
        () => ClientConfig(holdMissedPulsesBeforeStop: 2),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('holdMissedPulsesBeforeStop'), contains('2')),
        )),
        reason: 'at two missed pulses a single Wi-Fi retransmit stops the '
            'machine mid-jog. The plant chose the opposite: up to a second of '
            'coasting is accepted so that a panel hiccup does not drop the '
            'output, and a ratio under three turns that decision into its '
            'opposite while still looking like a safety tightening',
      );
    });

    test('exactly three missed pulses is allowed', () {
      final config = ClientConfig(holdMissedPulsesBeforeStop: 3);

      expect(config.holdMissedPulsesBeforeStop, 3,
          reason: 'three is the documented bound, and a bound that refuses its '
              'own minimum is a bound nobody can set');
      expect(config.holdDeadman, const Duration(milliseconds: 300),
          reason: 'the deadman follows the ratio it was given rather than the '
              'default it was not, or it is not derived at all');
    });

    test('the deadman follows an injected cadence rather than a constant', () {
      final config = ClientConfig(
        holdPulsePeriod: const Duration(milliseconds: 50),
        holdMissedPulsesBeforeStop: 20,
      );

      expect(config.holdDeadman, const Duration(seconds: 1),
          reason: 'a panel on a slow link is fed at a cadence of its own, and '
              'the deadman it reports has to be that cadence times that ratio '
              '— a hard-coded second would tell the integrator the wrong '
              'number for every panel that is not on the default');
    });
  });

  group('the freshness deadline cannot learn a transport period', () {
    test('no field or parameter of the config is derived from the server '
        'cadence', () {
      final source = File('lib/src/client_config.dart');
      expect(source.existsSync(), isTrue,
          reason: 'this case reads the implementation as text, so it must be '
              'run from the package root the CI step sets as its '
              'working-directory');

      final code = source
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('///'))
          .join('\n')
          .toLowerCase();

      expect(code, isNot(contains('tick')),
          reason: 'the moment the config can read the server cadence, someone '
              'will multiply it by three and ship a 150 ms freshness deadline '
              'that greys the plant on a GC pause; the deadline is configured '
              'and the ratio is asserted against an injected period instead');
    });
  });
}

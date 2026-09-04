/// The checkers' own instruments, proved against fixtures rather than against
/// a storm — and the positive controls that make each of them fail on demand.
///
/// **Why this file exists next to `soak_test.dart`.** A checker is an
/// instrument, and an instrument nobody has ever seen deflect is a green tick
/// with no warrant behind it. `soak_test.dart` runs the storm and asserts the
/// invariants hold; this file asserts that the things asserting them *can
/// report a breach*. 11-01's whole argument about vacuity applies one level up:
/// an invariant that cannot fail and an invariant that held look identical in a
/// run report.
///
/// **Everything here is seconds-scale.** The unit arms drive the checkers
/// through the two narrow interfaces in `soak_observables.dart` with fixtures
/// that hold still, and the two arms that need a real pipe use
/// `SoakDriver.start()` without `play()` — a composed gateway, five real panels
/// over real sockets, and no thirty-five-minute storm behind it. A control that
/// costs a full run is a control somebody eventually stops running.
///
/// **What the fixtures are allowed to be.** A control replaces an *answer* and
/// never the stack that produced it. The live control below blackholes a real
/// panel through its real `FaultProxy`, lets the real client's real watchdog
/// notice, and then lies about exactly one verdict — which is the closest this
/// lane can get to 07-REVIEW CR-01's own defect. See [_LyingPanelView] for what
/// it is a substitute for and why the real thing is unavailable in CI.
@TestOn('vm')
@Tags(['soak'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/write_outcome_log.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';

import '../support/soak/applied_write_ledger.dart';
import '../support/soak/checkers/freshness_honesty.dart';
import '../support/soak/checkers/terminal_state.dart';
import '../support/soak/invariant.dart';
import '../support/soak/soak_driver.dart';
import '../support/soak/soak_observables.dart';

void main() {
  group('invariant 1: freshness honesty', () {
    test('a value rendered fresh past its deadline is a recorded violation',
        () {
      final source = _Source();
      final checker = FreshnessHonestyChecker(source);

      // Two readings a whole budget apart, with the value frozen in between and
      // the panel insisting the whole time that everything is current.
      source.panel(1).say('ST101.CN01.MOT01.setpoint', 7);
      checker.sample(SoakClock.frozenAt(Duration.zero,
          declaredDuration: const Duration(minutes: 1)));
      source.offset = const Duration(seconds: 40);
      checker.sample(SoakClock.frozenAt(const Duration(seconds: 40),
          declaredDuration: const Duration(minutes: 1)));

      expect(checker.violations, hasLength(1),
          reason: 'the panel said "fresh" about a value it had not heard '
              'about for forty seconds against a budget of '
              '${source.freshnessBudget}, and nothing recorded it');
    });

    test('the violation names the panel, the key, the schedule offset and the '
        'seed', () {
      final source = _Source(
          seed: 4242, keys: <String>['ST201.CN01.MOT01.setpoint'])
        ..offset = const Duration(minutes: 3, seconds: 20);
      final checker = FreshnessHonestyChecker(source);
      source.panel(2).say('ST201.CN01.MOT01.setpoint', 1);
      checker.sample(_at(Duration.zero));
      source.offset = const Duration(minutes: 4);
      checker.sample(_at(const Duration(seconds: 45)));

      final rendered = checker.violations.single.toString();
      for (final fragment in <String>[
        'panel-2',
        'ST201.CN01.MOT01.setpoint',
        '+04:00.000',
        '4242',
      ]) {
        expect(rendered, contains(fragment),
            reason: 'a trip record has to be quotable into an issue without '
                'the run that produced it. Missing "$fragment":\n$rendered');
      }
    });

    test('an honest stale verdict is counted and is never a violation', () {
      final source = _Source();
      final checker = FreshnessHonestyChecker(source);
      source.panel(1).say('ST101.CN01.MOT01.setpoint', 7);
      checker.sample(_at(Duration.zero));
      source.panel(1).viewIsStale = true;
      source.offset = const Duration(seconds: 40);
      checker.sample(_at(const Duration(seconds: 40)));

      expect(checker.violations, isEmpty,
          reason: 'the invariant is that the panel did not LIE, not that '
              'values were young: a panel showing a forty-second-old value '
              'with the link marked stale is telling the operator exactly '
              'what is true');
      expect(checker.staleSamples, greaterThan(0));
    });

    test('a key with no value yet is not judged', () {
      final source = _Source();
      final checker = FreshnessHonestyChecker(source);
      checker.sample(_at(Duration.zero));

      expect(checker.judgedSamples, 0,
          reason: 'nothing has arrived for any key on any panel, so there is '
              'no reading to judge — and a checker that counted the call '
              'would clear its own vacuity gate while measuring nothing '
              '(11-01 sabotage 3)');
    });

    test('a key that has never arrived is not judged, and is not counted as '
        'stale', () {
      // Measured, not imagined: for the first ~100 ms of every composed run
      // each panel renders `Quality.uncertainNotYetKnown` with a null value for
      // every key — a placeholder node, before the first snapshot lands. The
      // gateway's own sweep makes exactly this distinction
      // (`freshness_sweep.dart`: "A key with no recorded arrival is skipped.
      // Nothing has ever come for it, so it is uncertainNotYetKnown and not
      // stale — those are different statements"), and a checker that counted
      // the placeholder as a stale reading would report 200 phantom stale
      // readings per panel per run, including on the control, where they read
      // as the strongest arm in the soak tripping on startup.
      final source = _Source();
      final checker = FreshnessHonestyChecker(source);
      source.panel(1).sayNothingYet('ST101.CN01.MOT01.setpoint');
      checker.sample(_at(Duration.zero));

      expect(checker.judgedSamples, 0);
      expect(checker.staleSamples, 0,
          reason: '"nothing has arrived" and "what arrived is old" are '
              'different statements, and only the second is a freshness '
              'verdict at all');
    });

    test('the counters partition: fresh plus stale is every judged reading',
        () {
      final source = _Source();
      final checker = FreshnessHonestyChecker(source);
      source.panel(1).say('ST101.CN01.MOT01.setpoint', 1);
      source.panel(2).say('ST201.CN01.MOT01.setpoint', 1);
      source.panel(2).viewIsStale = true;
      checker.sample(_at(Duration.zero));
      checker.sample(_at(const Duration(milliseconds: 25)));

      expect(checker.freshSamples + checker.staleSamples, checker.judgedSamples,
          reason: 'a reading is either one or the other, and a partition that '
              'does not add up is a counter nobody can read the verdict block '
              'against');
    });

    group('the PIPE. exclusion', () {
      test('skips a health key invented in this test, by prefix', () {
        // 08-05 task 3's `PIPE.invented.later` proof, restated: the skip has to
        // be `PipeKeys.isPipeKey`, so a health key nobody has thought of yet is
        // excluded on the day it is invented. An enumerated list would judge
        // this one and grey it out permanently while nothing is wrong
        // (06-SUMMARY on `PIPE.cert.days_to_expiry`).
        const invented = 'PIPE.invented.later';
        final source = _Source(keys: <String>[invented]);
        final checker = FreshnessHonestyChecker(source);
        source.panel(1).say(invented, true);
        checker.sample(_at(Duration.zero));
        source.offset = const Duration(minutes: 5);
        checker.sample(_at(const Duration(minutes: 5)));

        expect(checker.violations, isEmpty,
            reason: 'a value in the gateway\'s own namespace changes on an '
                'event and is older than any plant deadline by design');
        expect(checker.judgedSamples, 0,
            reason: 'skipped and NOT judged: counting a skipped key would let '
                'a run of nothing but health keys clear the vacuity gate');
      });

      test('and it does judge a plant key that merely mentions the prefix',
          () {
        const plantKey = 'ST101.CN01.PIPE01.setpoint';
        final source = _Source(keys: <String>[plantKey]);
        final checker = FreshnessHonestyChecker(source);
        source.panel(1).say(plantKey, 3);
        checker.sample(_at(Duration.zero));

        expect(checker.judgedSamples, greaterThan(0),
            reason: 'the prefix is "PIPE." with its dot, so a plant device '
                'called PIPE01 is a plant key and is judged like one');
      });
    });

    group('the run-end distribution', () {
      test('fails a run in which nothing ever went stale', () {
        final source = _Source();
        final checker = FreshnessHonestyChecker(source);
        source.panel(1).say('ST101.CN01.MOT01.setpoint', 1);
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(checker.violations, hasLength(1));
        expect(checker.violations.single.toString(), contains('staleSamples'),
            reason: 'a freshness verdict from a run where nothing ever went '
                'stale is a broken soak wearing a green tick, and the message '
                'has to say WHICH of the two numbers was zero');
      });

      test('fails a run in which nothing was ever fresh', () {
        final source = _Source();
        final checker = FreshnessHonestyChecker(source);
        source.panel(1)
          ..say('ST101.CN01.MOT01.setpoint', 1)
          ..viewIsStale = true;
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(checker.violations, hasLength(1));
        expect(checker.violations.single.toString(), contains('freshSamples'),
            reason: 'the panels never recovered, so the run measured a dead '
                'pipe rather than a storm');
      });

      test('passes a run that produced both', () {
        final source = _Source();
        final checker = FreshnessHonestyChecker(source);
        source.panel(1).say('ST101.CN01.MOT01.setpoint', 1);
        checker.sample(_at(Duration.zero));
        source.panel(1).viewIsStale = true;
        checker.sample(_at(const Duration(milliseconds: 25)));
        checker.finish();

        expect(checker.violations, isEmpty);
      });
    });

    group('the control panel\'s arm', () {
      test('a control that went stale with no plant-wide arm played is a '
          'violation', () {
        final source = _Source();
        final checker = FreshnessHonestyChecker(source);
        source.panel(0)
          ..say('ST101.CN01.MOT01.setpoint', 1)
          ..viewIsStale = true;
        source.panel(1).say('ST101.CN01.MOT01.setpoint', 1);
        checker.sample(_at(Duration.zero));
        checker.finish();

        final control = checker.violations
            .where((one) => one.toString().contains('control'))
            .toList();
        expect(control, hasLength(1),
            reason: 'the storm aimed at nothing plant-wide, so every fault it '
                'played was panel-targeted and the control was not one of the '
                'targets. A control that went stale anyway is the pre-07-08b '
                'bug class — a gateway punishing healthy panels');
      });

      test('and a plant-wide arm licenses it, because the control is not '
          'exempt from a gateway restart', () {
        final source = _Source()..plantWideArmsApplied = 1;
        final checker = FreshnessHonestyChecker(source);
        source.panel(0)
          ..say('ST101.CN01.MOT01.setpoint', 1)
          ..viewIsStale = true;
        source.panel(1).say('ST101.CN01.MOT01.setpoint', 1);
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(
            checker.violations
                .where((one) => one.toString().contains('control')),
            isEmpty,
            reason: 'GatewayRestart, KeymappingReload and every upstream arm '
                'reach the control like everybody else. The control\'s '
                'property is that the storm never AIMS at it, never that it '
                'is undisturbed — and an arm written against the second '
                'reading is flaky rather than strong');
      });

      test('a control stale for longer than its grace is a violation whatever '
          'the storm played', () {
        final source = _Source()..plantWideArmsApplied = 99;
        final checker = FreshnessHonestyChecker(source,
            controlStaleGrace: const Duration(seconds: 2));
        source.panel(0)
          ..say('ST101.CN01.MOT01.setpoint', 1)
          ..viewIsStale = true;
        source.panel(1).say('ST101.CN01.MOT01.setpoint', 1);
        for (var ms = 0; ms <= 4000; ms += 250) {
          checker.sample(_at(Duration(milliseconds: ms)));
        }
        checker.finish();

        expect(
            checker.violations
                .where((one) => one.toString().contains('never came back')),
            hasLength(1),
            reason: 'a plant-wide disturbance is transient. A control that '
                'never recovers is a finding no number of restarts excuses');
      });
    });

    test('the floor scales with the declared duration and never reaches zero',
        () {
      final short = FreshnessHonestyChecker(_Source(),
          declared: const Duration(seconds: 90), floorPerMinute: 4800);
      final full = FreshnessHonestyChecker(_Source(),
          declared: const Duration(minutes: 35), floorPerMinute: 4800);
      final tiny = FreshnessHonestyChecker(_Source(),
          declared: const Duration(milliseconds: 1), floorPerMinute: 4800);

      expect(short.minimumSamplesForAVerdict, 7200);
      expect(full.minimumSamplesForAVerdict, 168000);
      expect(tiny.minimumSamplesForAVerdict, greaterThanOrEqualTo(1),
          reason: 'a floor of zero is an assertion that cannot fail');
    });

    test('POSITIVE CONTROL: a blackholed panel forced to report fresh records '
        'exactly one violation, naming it', () async {
      // What this is a substitute FOR, and why the real thing is unavailable.
      //
      // 07-REVIEW CR-01's own defect is a freshness verdict aged on
      // `DateTime.now()` and then flipped by an NTP step. Neither half is
      // injectable here: `FreshnessWatchdog` takes a monotonic `int Function()`
      // and has no wall-clock seam left to hand in (07-REVIEW's note on
      // c4e62845 — "a seam that accepts a steppable clock is a seam somebody
      // steps"), and stepping the process clock is not something a CI job may
      // do. So the control holds a REAL panel behind a REAL blackholed proxy
      // until its REAL watchdog has judged the view stale, and then overrides
      // the one boolean a widget would render. Everything except the answer is
      // the shipping stack.
      //
      // A control that quietly tested something easier than the real defect
      // would be worse than none, so: this proves the checker catches a panel
      // whose verdict disagrees with its own arrival times. It does NOT prove
      // the checker would catch a client that aged its verdict on a wall clock
      // — nothing in this lane can, and 11-07's ledger says so.
      final driver = SoakDriver(
        seed: 11,
        duration: const Duration(seconds: 30),
        herdSize: 3,
        journalPath: _tempJournal(),
      );
      addTearDown(driver.dispose);
      await driver.start();

      const blackholed = 2;
      final honest = FreshnessHonestyChecker(driver);
      final lying = FreshnessHonestyChecker(
          _LyingSource(driver, liar: blackholed));
      // Both start sampling BEFORE the blackhole, so each has a record of when
      // the panel last genuinely heard about each key. A checker that first
      // looked after the link died would date every arrival to that moment and
      // find nothing old, which is the way this control fails silently.
      void sampleBoth() {
        for (final checker in <FreshnessHonestyChecker>[honest, lying]) {
          checker.sample(driver.clock);
        }
      }

      sampleBoth();
      driver.fixture.panels[blackholed].proxy.blackhole();
      // Past the client's 3 s link deadline, past the gateway's staleAfter, and
      // past the whole composed budget with room for a loaded runner.
      final until = driver.freshnessBudget + const Duration(seconds: 4);
      for (var waited = Duration.zero;
          waited < until;
          waited += const Duration(milliseconds: 250)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        sampleBoth();
      }

      expect(driver.panelViews[blackholed].viewIsStale, isTrue,
          reason: 'the control is worthless if the panel it lies about was '
              'never actually stale: the blackhole did not bite');

      expect(honest.violations, isEmpty,
          reason: 'the unmodified panel told the truth about being stale, so '
              'the checker must record nothing — otherwise the arm below is '
              'catching the blackhole rather than the lie');
      expect(lying.violations, isNotEmpty,
          reason: 'a panel reporting fresh over a value its own arrival times '
              'say is ${driver.freshnessBudget.inSeconds}s old is exactly the '
              'failure PROJECT.md names, and the checker did not see it');
      final first = lying.violations.first.toString();
      expect(first, contains(soakPanelName(blackholed)));
      expect(first, contains('seed=11'));
    });
  });

  group('the plant-side applied-write ledger', () {
    test('the same key and value applied twice under two cmd ids appears '
        'twice', () {
      // The question the ledger exists to answer, and the one WriteOutcomeLog
      // structurally cannot: was this applied more than once? Two ids, because
      // one id twice is a different failure the client already refuses
      // (04-REVIEW CR-05).
      final ledger = AppliedWriteLedger();
      ledger.recordApplied(
          key: 'ST101.CN01.MOT01.setpoint', value: 1500, cmd: 'cmd-a');
      ledger.recordApplied(
          key: 'ST101.CN01.MOT01.setpoint', value: 1500, cmd: 'cmd-b');

      expect(ledger.appearances('ST101.CN01.MOT01.setpoint', 1500), 2);
      expect(ledger.appearances('ST101.CN01.MOT01.setpoint', 1400), 0,
          reason: 'the pair is the question; a different value is a '
              'different write');
    });

    test('nthWrite is run-stable and the cmd id is carried opaque', () {
      // Cmd ids are minted with Random.secure (ulid.dart:17-21), deliberately:
      // a predictable write id lets a hostile client re-query another
      // operator's outcome. So they differ between two runs of ONE seed, and
      // nothing reproducible may key on them.
      AppliedWriteLedger runWith(List<String> cmds) {
        final ledger = AppliedWriteLedger();
        for (final cmd in cmds) {
          ledger.recordApplied(key: 'ST201.CN02.MOT03.setpoint',
              value: cmds.indexOf(cmd), cmd: cmd);
        }
        return ledger;
      }

      final first = runWith(<String>['01JA', '01JB', '01JC']);
      final second = runWith(<String>['01ZZ', '01ZY', '01ZX']);

      expect(second.entries.map((one) => one.nthWrite),
          first.entries.map((one) => one.nthWrite),
          reason: 'two runs of one seed apply the same writes in the same '
              'order, so the n-th write is the identity that reproduces');
      expect(second.entries.map((one) => one.cmd),
          isNot(first.entries.map((one) => one.cmd)),
          reason: 'and the cmd ids are exactly what does not');
    });

    test('a panel attributed before the write lands is carried on the entry',
        () {
      final ledger = AppliedWriteLedger()..attribute('cmd-a', 'panel-3');
      ledger.recordApplied(
          key: 'ST301.CN01.MOT01.setpoint', value: 9, cmd: 'cmd-a');

      expect(ledger.entries.single.panel, 'panel-3',
          reason: 'the plant side does not know which panel acted; the driver '
              'does, and says so before the write crosses');
    });

    test('an unattributed application is recorded rather than dropped', () {
      final ledger = AppliedWriteLedger()
        ..recordApplied(key: 'ST301.CN01.MOT01.setpoint', value: 9,
            cmd: 'stranger');

      expect(ledger.entries.single.panel, isNull);
      expect(ledger.total, 1,
          reason: 'a write nobody attributed still reached the plant, and a '
              'ledger that dropped it would answer "applied once" about a '
              'key that moved twice');
    });

    test('DEVIATION 3\'s evidence: the entry outlives the gateway\'s own log',
        () {
      // The measurement the deviation rests on, taken rather than asserted.
      // WriteOutcomeLog prunes on every record AND every read
      // (write_outcome_log.dart:210-214, removeWhere against now() - ttl)
      // against ServerConfig.writeOutcomeTtl, default 60 s
      // (server_config.dart:337). After thirty-five minutes it holds at most
      // the last minute, so "compared after the run" is a comparison of the
      // last sixty seconds wearing the label of the whole soak.
      var wall = 1_700_000_000_000;
      final ttl = ServerConfig().writeOutcomeTtl;
      final gateway = WriteOutcomeLog(ttl: ttl, now: () => wall);
      final ledger = AppliedWriteLedger();

      gateway.record('cmd-a', const WriteApplied('cmd-a', readback: 1500, at: 0));
      ledger.recordApplied(
          key: 'ST101.CN01.MOT01.setpoint', value: 1500, cmd: 'cmd-a');

      expect(gateway.entryFor('cmd-a'), isNotNull,
          reason: 'inside the window the gateway does hold it, so the arm '
              'below is measuring the TTL and not a log that never recorded');

      wall += const Duration(seconds: 61).inMilliseconds;

      // Asked the way a post-run comparison would have to ask it. Note that
      // `recordedOutcomes` alone does NOT prune — it reads the raw map, and
      // only `record`, `entryFor` and `prune` sweep the horizon — so a reader
      // who took that counter as the log's contents would see an entry the
      // gateway will answer `null` about the moment anybody asks.
      final answer = gateway.entryFor('cmd-a');
      print('deviation 3, at +61 s: WriteOutcomeLog.entryFor(cmd-a)='
          '$answer, recordedOutcomes=${gateway.recordedOutcomes}, '
          'AppliedWriteLedger.total=${ledger.total} '
          '(ttl=$ttl)');

      expect(answer, isNull,
          reason: 'the gateway pruned it, which is correct behaviour and is '
              'exactly why §7.8\'s "compared after the run" cannot be done');
      expect(gateway.recordedOutcomes, 0,
          reason: 'and the sweep the question triggered dropped it from the '
              'map as well');
      expect(ledger.appearances('ST101.CN01.MOT01.setpoint', 1500), 1,
          reason: 'and the ledger still answers, which is what makes '
              '"applied twice?" a question minute 35 can ask about minute 3');
    });

    test('the cap bounds it and the overflow is counted', () {
      final ledger = AppliedWriteLedger(capacity: 10);
      for (var i = 0; i < 84; i++) {
        ledger.recordApplied(
            key: 'ST101.CN01.MOT01.setpoint', value: i, cmd: 'cmd-$i');
      }

      expect(ledger.entries, hasLength(10));
      expect(ledger.overflow, 74);
      expect(ledger.total, 84,
          reason: 'a capped list without a counter reports ten applications '
              'for a run that had eighty-four, which is a worse lie than the '
              'memory it saves');
      expect(ledger.entries.first.nthWrite, 1,
          reason: 'the FIRST applications are kept, as ViolationLog keeps the '
              'first violations: what a soak needs is when it started');
    });

    test('a truncated ledger says so rather than answering a question it can '
        'no longer answer', () {
      final ledger = AppliedWriteLedger(capacity: 1);
      expect(ledger.isTruncated, isFalse);
      ledger.recordApplied(key: 'k', value: 1, cmd: 'a');
      ledger.recordApplied(key: 'k', value: 2, cmd: 'b');

      expect(ledger.isTruncated, isTrue,
          reason: 'past the cap, appearances() is a FLOOR and not an answer, '
              'and a reconciliation that read it as an answer would report '
              '"applied once" about a write it had forgotten');
    });
  });

  group('invariant 2: one terminal state per write', () {
    test('POSITIVE CONTROL (a): a command resolved twice is a violation '
        'recorded at the instant it happened, carrying both states', () {
      final source = _WriteSource()
        ..issue('cmd-a', panel: 'panel-2', key: 'ST101.CN01.MOT01.setpoint',
            value: 7)
        ..resolve('cmd-a', 'applied', at: const Duration(seconds: 30))
        // The failure: the same operator action reaching a second terminal
        // state. One id is one action (04-REVIEW CR-05), so a second settled
        // answer means one of the two is being reported about the wrong write.
        ..resolve('cmd-a', 'rejected', at: const Duration(minutes: 4));
      final checker = TerminalStateChecker(source);
      checker.sample(_at(const Duration(minutes: 4)));

      expect(checker.violations, hasLength(1));
      final rendered = checker.violations.single.toString();
      for (final fragment in <String>[
        'applied',
        'rejected',
        '+04:00.000',
        '11',
      ]) {
        expect(rendered, contains(fragment),
            reason: 'the schedule offset at the instant is what makes a double '
                'resolution diagnosable — thirty minutes later the gateway\'s '
                'own log has forgotten. Missing "$fragment":\n$rendered');
      }
    });

    test('POSITIVE CONTROL (b): a write that reached a socket and is in '
        'neither map is a violation at run end', () {
      // PROJECT.md's named failure: a write silently lost. It is not in the
      // terminal map, so nothing ever settled it, and it is not in
      // debugUnresolvedCmds, so the client is not going to ask about it either.
      final source = _WriteSource()
        ..issue('cmd-lost', panel: 'panel-1', key: 'ST201.CN01.MOT01.setpoint',
            value: 3)
        ..direct('cmd-lost', 'unknown', reachedASocket: true);
      final checker = TerminalStateChecker(source);
      checker.sample(_at(Duration.zero));
      checker.finish();

      final lost = checker.violations
          .where((one) => one.toString().contains('in NEITHER'))
          .toList();
      expect(lost, hasLength(1),
          reason: 'a write nobody is tracking and nobody settled is exactly '
              'the "never silently lost" half of the Core Value');
      expect(lost.single.toString(), contains('cmd-lost'));
    });

    test('the SAME terminal state re-reported through the recovery path is '
        'counted, not a violation', () {
      // Measured in the lane, in roughly half of ninety-second runs, always on
      // a probe write to the flapping panel. The sequence is the pipe working:
      //
      //   1. write() sends; the cmd is in `_unresolved` from before it left.
      //   2. the gateway records the outcome and answers.
      //   3. the link flaps; on the next entry to `ready` the client re-queries
      //      writeStatus for everything still unresolved, and the gateway
      //      answers from its own log — `_settle` fires `onWriteResolved`.
      //   4. the original write() future ALSO returns, with the same outcome.
      //
      // One operator action, ONE terminal state, reported through two channels
      // that agree. The invariant forbids a write reaching two terminal states,
      // not an outcome being reported twice — and treating agreement as a
      // breach would make the strongest arm in invariant 2 fire on a healthy
      // pipe about half the time. What stays a violation is DISAGREEMENT, and
      // the "never duplicated server-side" half is answered by the plant-side
      // ledger, which is a different arm entirely.
      final source = _WriteSource()
        ..issue('cmd-a', panel: 'panel-1', key: 'PIPE.connected', value: 1)
        ..resolve('cmd-a', 'rejected', at: const Duration(seconds: 34))
        ..direct('cmd-a', 'rejected', reachedASocket: true,
            at: const Duration(seconds: 34))
        ..settled('cmd-b', 'applied')
        ..issue('cmd-c', panel: 'panel-1', key: 'k', value: 1)
        ..direct('cmd-c', 'unknown', reachedASocket: true)
        ..stillUnresolved('cmd-c');
      final checker = TerminalStateChecker(source);
      checker.sample(_at(const Duration(seconds: 34)));
      checker.finish();

      expect(checker.violations, isEmpty);
      expect(checker.reResolvedInAgreement, 1,
          reason: 'counted rather than swallowed: a run where the recovery '
              'path re-reports half the writes is telling you something about '
              'the storm, and a number nobody prints is a number nobody reads');
    });

    test('a write that never reached a socket is NOT demanded to be terminal',
        () {
      // The client removes an undispatched cmd from `_unresolved` on purpose
      // (remote_state_man.dart:832-836): re-querying it every reconnect for the
      // rest of the shift is how a panel with a dead link grows the unresolved
      // set until writeStatus is refused for being over maxKeysPerSubscribe,
      // taking the recovery path for the GENUINE unknowns down with it. A
      // checker that demanded terminality here would be asserting against that
      // protection.
      final source = _WriteSource()
        ..issue('cmd-stillborn', panel: 'panel-4',
            key: 'ST301.CN01.MOT01.setpoint', value: 1)
        ..direct('cmd-stillborn', 'unknown', reachedASocket: false)
        // One healthy write so the distribution arms have something to pass on.
        ..issue('cmd-ok', panel: 'panel-1', key: 'ST101.CN01.MOT01.setpoint',
            value: 2)
        ..direct('cmd-ok', 'applied', reachedASocket: true)
        ..issue('cmd-no', panel: 'panel-1', key: 'PIPE.connected', value: 2)
        ..direct('cmd-no', 'rejected', reachedASocket: true);
      final checker = TerminalStateChecker(source);
      checker.sample(_at(Duration.zero));
      checker.finish();

      expect(
          checker.violations
              .where((one) => one.toString().contains('cmd-stillborn')),
          isEmpty);
      expect(checker.neverReachedASocket, 1,
          reason: 'counted rather than ignored: a run where every write died '
              'in the process is a run that measured nothing, and the number '
              'has to be readable next to judgedSamples');
    });

    test('a command in BOTH the terminal map and the unresolved set is a '
        'violation', () {
      final source = _WriteSource()
        ..issue('cmd-a', panel: 'panel-1', key: 'k', value: 1)
        ..direct('cmd-a', 'applied', reachedASocket: true)
        ..stillUnresolved('cmd-a');
      final checker = TerminalStateChecker(source);
      checker.sample(_at(Duration.zero));
      checker.finish();

      expect(
          checker.violations.where((one) => one.toString().contains('in BOTH')),
          hasLength(1),
          reason: 'a settled command the client is still going to re-query is '
              'one the operator will be told about twice, and the second '
              'answer may disagree with the first');
    });

    test('judgedSamples counts resolved writes and never sample calls', () {
      final source = _WriteSource()
        ..issue('cmd-a', panel: 'panel-1', key: 'k', value: 1)
        ..direct('cmd-a', 'applied', reachedASocket: true);
      final checker = TerminalStateChecker(source);
      for (var i = 0; i < 40; i++) {
        checker.sample(_at(Duration(milliseconds: 25 * i)));
      }

      expect(checker.judgedSamples, 1,
          reason: 'forty sample calls and one resolved write. 11-01\'s third '
              'sabotage: a counter that counted calls let a permanently broken '
              'checker clear the very gate built to catch it');
    });

    group('the run-end distribution', () {
      test('fails a run that produced no unknown', () {
        final source = _WriteSource()
          ..settled('cmd-a', 'applied')
          ..settled('cmd-b', 'rejected');
        final checker = TerminalStateChecker(source);
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(
            checker.violations.where((one) => one.toString().contains('unknown')),
            hasLength(1),
            reason: 'a storm that produced no unknown never broke a link '
                'during a write\'s round trip, so the invariant\'s hard case '
                'was never tested at all');
      });

      test('fails a run that produced no rejected', () {
        final source = _WriteSource()
          ..settled('cmd-a', 'applied')
          ..issue('cmd-b', panel: 'panel-1', key: 'k', value: 1)
          ..direct('cmd-b', 'unknown', reachedASocket: true)
          ..stillUnresolved('cmd-b');
        final checker = TerminalStateChecker(source);
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(
            checker.violations
                .where((one) => one.toString().contains('rejected')),
            hasLength(1));
      });

      test('is not asked of a run too short to have produced one', () {
        // Measured: `soak_test.dart`'s auxiliary cases declare eight and twelve
        // seconds to prove the seed reaches stdout and that two runs of one
        // seed play the same storm. Eight seconds is three probe writes, and an
        // `unknown` needs a link to break DURING a write's round trip — a
        // coincidence three writes cannot be relied on to produce. Asserting
        // the distribution there would make a smoke test of the machinery fail
        // for a property it was never running long enough to have.
        //
        // Invariant 1's distribution is deliberately NOT gated the same way,
        // and the asymmetry is real rather than an oversight: freshness is
        // sampled forty times a second from the first tick, so both a fresh and
        // a stale reading appear in any run of any length that has a fault in
        // it. Writes are two seconds apart.
        final source = _WriteSource()
          ..declaredDuration = const Duration(seconds: 8)
          ..settled('cmd-a', 'applied');
        final checker = TerminalStateChecker(source);
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(checker.violations, isEmpty);
        expect(checker.distributionWasAsked, isFalse,
            reason: 'and the run has to SAY it was not asked, or a green '
                'eight-second run reads as a distribution that held');
      });

      test('is asked of any run at or past the floor', () {
        final source = _WriteSource()
          ..declaredDuration = distributionArmFloor
          ..settled('cmd-a', 'applied');
        final checker = TerminalStateChecker(source);
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(checker.distributionWasAsked, isTrue);
        expect(checker.violations, hasLength(2),
            reason: 'no rejected and no unknown, each failing by name');
      });

      test('passes a run that produced all three', () {
        final source = _WriteSource()
          ..settled('cmd-a', 'applied')
          ..settled('cmd-b', 'rejected')
          ..issue('cmd-c', panel: 'panel-1', key: 'k', value: 1)
          ..direct('cmd-c', 'unknown', reachedASocket: true)
          ..stillUnresolved('cmd-c');
        final checker = TerminalStateChecker(source);
        checker.sample(_at(Duration.zero));
        checker.finish();

        expect(checker.violations, isEmpty);
        expect(checker.applied, 1);
        expect(checker.rejected, 1);
        expect(checker.unknown, 1);
      });
    });

    test('the plant applying one command twice is a violation', () {
      final source = _WriteSource()
        ..settled('cmd-a', 'applied')
        ..settled('cmd-b', 'rejected')
        ..issue('cmd-c', panel: 'panel-1', key: 'k', value: 1)
        ..direct('cmd-c', 'unknown', reachedASocket: true)
        ..stillUnresolved('cmd-c');
      // Two applications under one command id: the question the ledger exists
      // to answer and the gateway's sixty-second log cannot.
      source.appliedWrites
        ..attribute('cmd-a', 'panel-1')
        ..recordApplied(key: 'ST101.CN01.MOT01.setpoint', value: 5, cmd: 'cmd-a')
        ..recordApplied(key: 'ST101.CN01.MOT01.setpoint', value: 5, cmd: 'cmd-a');
      final checker = TerminalStateChecker(source);
      checker.sample(_at(Duration.zero));
      checker.finish();

      expect(
          checker.violations
              .where((one) => one.toString().contains('the plant applied')),
          hasLength(1));
    });

    test('a truncated ledger is reported rather than read as an answer', () {
      final source = _WriteSource(ledgerCapacity: 1)
        ..settled('cmd-a', 'applied')
        ..settled('cmd-b', 'rejected')
        ..issue('cmd-c', panel: 'panel-1', key: 'k', value: 1)
        ..direct('cmd-c', 'unknown', reachedASocket: true)
        ..stillUnresolved('cmd-c');
      source.appliedWrites
        ..recordApplied(key: 'k', value: 1, cmd: 'cmd-a')
        ..recordApplied(key: 'k', value: 2, cmd: 'cmd-b');
      final checker = TerminalStateChecker(source);
      checker.finish();

      expect(
          checker.violations
              .where((one) => one.toString().contains('truncated')),
          hasLength(1),
          reason: 'past the cap appearances() is a floor, and a reconciliation '
              'that reported "no duplicates" off a floor would be answering a '
              'question it could no longer ask');
    });

    test('the unresolved set is bounded across the run, and the worst is '
        'recorded', () {
      final source = _WriteSource()
        ..settled('cmd-a', 'applied')
        ..settled('cmd-b', 'rejected');
      for (var i = 0; i < 9; i++) {
        source
          ..issue('cmd-p$i', panel: 'panel-1', key: 'k', value: i)
          ..direct('cmd-p$i', 'unknown', reachedASocket: true)
          ..stillUnresolved('cmd-p$i');
      }
      final checker = TerminalStateChecker(source, unresolvedCeiling: 4);
      checker.sample(_at(Duration.zero));
      checker.finish();

      expect(checker.worstUnresolved, 9);
      expect(
          checker.violations
              .where((one) => one.toString().contains('against a ceiling of')),
          hasLength(1),
          reason: 'the same counter invariant 4 watches as a slope (11-05 '
              'task 1). Here the question is whether it is bounded at all: an '
              'unresolved set that only grows is a writeStatus re-query that '
              'will eventually be refused for being over maxKeysPerSubscribe');
    });

    test('the floor scales with the declared duration', () {
      expect(
          TerminalStateChecker(_WriteSource(),
                  declared: const Duration(seconds: 90))
              .minimumSamplesForAVerdict,
          12);
      expect(
          TerminalStateChecker(_WriteSource(),
                  declared: const Duration(minutes: 35))
              .minimumSamplesForAVerdict,
          280);
    });
  });
}

// ------------------------------------------------------------- the fixtures

/// A clock stopped at [elapsed], for the arms that need an offset rather than a
/// wait.
SoakClock _at(Duration elapsed) =>
    SoakClock.frozenAt(elapsed, declaredDuration: const Duration(minutes: 1));

/// A journal directory an auxiliary case owns, so it cannot overwrite the
/// artifact the real arm writes to `build/soak/`.
String _tempJournal() {
  final dir = Directory.systemTemp.createTempSync('relay-soak-meta-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir.path;
}

/// A freshness source whose panels hold still, for the unit arms.
final class _Source implements SoakFreshnessSource {
  _Source({
    this.seed = 11,
    List<String>? keys,
    int panels = 3,
  })  : freshnessKeys = keys ?? const <String>['ST101.CN01.MOT01.setpoint'],
        panelViews = <_Panel>[
          for (var i = 0; i < panels; i++) _Panel(i),
        ];

  @override
  final int seed;

  @override
  Duration declaredDuration = const Duration(minutes: 1);

  @override
  final List<String> freshnessKeys;

  @override
  final List<_Panel> panelViews;

  @override
  Duration scheduleOffset = Duration.zero;

  Duration get offset => scheduleOffset;
  set offset(Duration value) => scheduleOffset = value;

  @override
  int controlPanelIndex = 0;

  @override
  int plantWideArmsApplied = 0;

  @override
  Duration freshnessBudget = const Duration(seconds: 12);

  _Panel panel(int index) => panelViews[index];
}

final class _Panel implements SoakPanelView {
  _Panel(this.index);

  @override
  final int index;

  @override
  String get name => 'panel-$index';

  @override
  bool viewIsStale = false;

  @override
  bool pageIsStale = false;

  final Map<String, DynamicValue> _values = <String, DynamicValue>{};

  /// Delivers one value, exactly as a frame arriving would.
  void say(String key, Object? value) {
    _values[key] = DynamicValue(value: value, quality: Quality.good);
  }

  /// The placeholder a real panel renders before its first snapshot lands.
  void sayNothingYet(String key) {
    _values[key] =
        DynamicValue(value: null, quality: Quality.uncertainNotYetKnown);
  }

  @override
  DynamicValue? read(String key) => _values[key];
}

/// A live source with one panel's freshness verdict overridden to `fresh`.
///
/// **Test-only, and a substitute** — see the control's own comment for what it
/// stands in for. It wraps rather than replaces: every panel but [liar] is the
/// real one, and even [liar]'s values are the real client's.
final class _LyingSource implements SoakFreshnessSource {
  _LyingSource(this._real, {required this.liar});

  final SoakFreshnessSource _real;
  final int liar;

  @override
  int get seed => _real.seed;

  @override
  Duration get declaredDuration => _real.declaredDuration;

  @override
  Duration get scheduleOffset => _real.scheduleOffset;

  @override
  List<String> get freshnessKeys => _real.freshnessKeys;

  @override
  int get controlPanelIndex => _real.controlPanelIndex;

  @override
  int get plantWideArmsApplied => _real.plantWideArmsApplied;

  @override
  Duration get freshnessBudget => _real.freshnessBudget;

  @override
  List<SoakPanelView> get panelViews => <SoakPanelView>[
        for (final view in _real.panelViews)
          view.index == liar ? _LyingPanelView(view) : view,
      ];
}

/// One panel that reports fresh whatever its own watchdog says.
final class _LyingPanelView implements SoakPanelView {
  _LyingPanelView(this._real);

  final SoakPanelView _real;

  @override
  int get index => _real.index;

  @override
  String get name => _real.name;

  @override
  bool get viewIsStale => false;

  @override
  bool get pageIsStale => false;

  @override
  DynamicValue? read(String key) {
    final value = _real.read(key);
    // The quality is part of the verdict a widget renders, so a lie that left
    // `badStale` on the value would be caught by the quality arm rather than by
    // the age arm and would prove the wrong thing.
    return value?.copyWith(quality: Quality.good);
  }
}

/// A write source driven by hand, for the arms that need a specific sequence
/// rather than a storm.
final class _WriteSource implements SoakWriteSource {
  _WriteSource({int ledgerCapacity = appliedWriteLedgerCapacity})
      : appliedWrites = AppliedWriteLedger(capacity: ledgerCapacity);

  @override
  final int seed = 11;

  @override
  Duration declaredDuration = const Duration(minutes: 1);

  @override
  Duration scheduleOffset = Duration.zero;

  @override
  final AppliedWriteLedger appliedWrites;

  final List<SoakWriteRecord> _records = <SoakWriteRecord>[];
  final List<String> _unresolved = <String>[];
  final Map<String, SoakWriteRecord> _issued = <String, SoakWriteRecord>{};
  int _nth = 0;

  @override
  List<SoakWriteRecord> get writeRecords =>
      List<SoakWriteRecord>.unmodifiable(_records);

  @override
  List<String> get unresolvedCmds => List<String>.unmodifiable(_unresolved);

  void issue(String cmd,
      {required String panel, required String key, required Object? value}) {
    final record = SoakWriteRecord(
      nth: ++_nth,
      cmd: cmd,
      panel: panel,
      key: key,
      value: value,
      stage: SoakWriteStage.issued,
      at: scheduleOffset,
      probe: true,
    );
    _issued[cmd] = record;
    _records.add(record);
  }

  void direct(String cmd, String outcome,
      {required bool reachedASocket, Duration? at}) {
    _append(cmd, outcome, SoakWriteStage.direct, at,
        reachedASocket: reachedASocket);
  }

  void resolve(String cmd, String outcome, {Duration? at}) {
    _append(cmd, outcome, SoakWriteStage.lateResolution, at,
        reachedASocket: true);
  }

  /// Issue and settle in one call, for the arms that only need the outcome.
  void settled(String cmd, String outcome) {
    issue(cmd, panel: 'panel-1', key: 'ST101.CN01.MOT01.setpoint', value: 1);
    direct(cmd, outcome, reachedASocket: true);
  }

  void stillUnresolved(String cmd) => _unresolved.add(cmd);

  void _append(String cmd, String outcome, SoakWriteStage stage, Duration? at,
      {required bool reachedASocket}) {
    final issued = _issued[cmd];
    _records.add(SoakWriteRecord(
      nth: issued?.nth ?? -1,
      cmd: cmd,
      panel: issued?.panel ?? 'panel-1',
      key: issued?.key ?? '(unknown)',
      value: issued?.value,
      stage: stage,
      outcome: outcome,
      reachedASocket: reachedASocket,
      at: at ?? scheduleOffset,
      probe: true,
    ));
  }
}

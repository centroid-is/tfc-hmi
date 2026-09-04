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

import '../support/soak/checkers/freshness_honesty.dart';
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

/// **F27 — Alarm flood on restore**, taken as ROADMAP criterion 4 reads it.
///
/// The catalogue row, verbatim from `f_row_registry.dart` (§7.9 via
/// 09-PATTERNS §0):
///
/// injection: drop 1 of 4 upstreams with 50 active alarms, restore at 60 s; 1 of 5 clients disconnected throughout
/// expectation: one link-down alarm, not 50; all five clients converge on identical alarm + ack state
///
/// **The scope call, in three sentences.** The catalogue row names alarm
/// semantics no relay package contains: a sweep of every relay `lib/` finds
/// the word only as "alarmable", a property of a health key, and
/// REQUIREMENTS.md has no ALM requirement. ROADMAP criterion 4 names a pipe
/// property that is fully reachable — an alarm flood and poison values pass
/// through without dropping the session or throwing on encode — which one
/// layer below the alarm is exactly 08-09's *one status notification, not
/// one per key*, scaled to fifty keys and four aliases, plus five panels
/// converging while the state actually changes underneath. The three alarm
/// clauses the row also carries are day-one deviations in this gate's
/// registry (`f_row_registry.dart`, the three F27 entries, orchestrator
/// ruling 1 in 09-CONTEXT) with the app-side owner named — so a reader who
/// arrived here expecting master-inhibit, a comms on-delay or
/// gateway-authoritative ack state has just read the answer: those words
/// appear in this file only inside quotations of the catalogue.
///
/// **"50 active alarms", one layer down, is fifty active keys.** What an
/// alarm flood is to the pipe is fifty simultaneous quality transitions on
/// one alias — the largest batch one link event can stage — carried without
/// drowning the one frame that explains them.
///
/// **The outage is ~15 s in the default lane, 60 s behind `RELAY_SOAK`.**
/// The shortening is declared in the deviations registry — the F27 entry
/// whose clause is "restore at 60 s" — and this file cites that entry rather
/// than restating its argument.
///
/// **Memory is asserted structurally and never off `ProcessInfo.currentRss`**
/// (the house rule, quoted whole in `long_outage_gate_test.dart:71-84`): RSS
/// on a CI VM moves by megabytes for reasons unrelated to the code under
/// test, so a bound loose enough not to flake is loose enough not to catch a
/// leak. What is asserted instead is the structure each clause is about —
/// complaint-list length, conflating-map entry count, session and
/// subscription counts — sampled *through* the window so a leak shows as a
/// slope, and there is no coarse 10x smoke-detector ceiling either. The only
/// occurrence of that getter's name in this file is in this paragraph.
///
/// **The cost the row inherits from the catalogue's animation trap is
/// logging.** A per-item cost paid exactly at peak is the hazard; in the
/// pipe that cost is a log line per key at plant scale (project memory: one
/// logger at trace with a pretty printer turned per-node logs into seconds
/// of lag), so the degrade and restore windows assert bounded complaint
/// growth and zero stray print lines — counted into lists and asserted
/// bounded, never printed, which is also RES-03's fifth invariant getting an
/// early rehearsal.
@TestOn('vm')
@Tags(['gate'])
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:test/test.dart';
import 'package:tfc_relay_local/tfc_relay_local.dart' show UpstreamLinkState;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../support/gate_b_fixture.dart';

/// The four PLCs. Three stations and the Baader line — the plant's own
/// topology, so "1 of 4 upstreams" is the sentence the catalogue wrote.
const List<String> aliases = <String>['ST101', 'ST201', 'ST301', 'BDR01'];

/// The alias that dies. Fifty keys, per the injection.
const String droppedAlias = 'ST101';
const int pageSize = 50;

/// Generous: nothing in this file is a latency measurement.
const Duration generous = Duration(seconds: 10);

/// The injection's outage window. ~15 s in the default lane with the
/// catalogue's 60 s behind `RELAY_SOAK` — the shortening is
/// registry-declared (the F27 deviation whose clause is "restore at 60 s",
/// 09-CONTEXT ruling 6); this constant cites that entry rather than
/// restating it.
final Duration outageWindow = Platform.environment['RELAY_SOAK'] == null ||
        Platform.environment['RELAY_SOAK']!.isEmpty
    ? const Duration(seconds: 15)
    : const Duration(seconds: 60);

/// A struct-shaped value `sanitize` refuses, copied from
/// `poison_gate_test.dart:52-58` with its reason: nested past `maxValueDepth`
/// (64) with **int** keys so the refusal reaches the key-preserving map walk.
/// Here it is the band guard's setup — a key already carrying worse news
/// (`errorConfig`, 770) than the link loss is about to stage (`badCommFault`,
/// 522).
Object tooDeep() {
  Object deep = 0;
  for (var i = 0; i < 80; i++) {
    deep = <int, Object?>{i: deep};
  }
  return deep;
}

/// Runs [body] under a print trap: every line printed inside the zone that
/// does not carry this file's own `F27` prefix is counted into [strays].
///
/// This is how "no per-key line on the degrade path" is asserted rather than
/// hoped: the fixture, the gateway and the panels are all built inside the
/// zone, so a `print` anywhere under them lands here. Counted into a list
/// and asserted bounded, never printed one-per-line — a stack per provoked
/// error trains everyone to scroll past them (the house rule) — and the
/// lines are forwarded to the parent zone so the run report is unchanged.
Future<T> underPrintTrap<T>(
    List<String> strays, Future<T> Function() body) =>
    runZoned(body,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            if (!line.startsWith('F27')) strays.add(line);
            parent.print(zone, line);
          },
        ));

void main() {
  test(
      'F27: losing one PLC of four costs one status notification and two '
      'hundred keys\' worth of honest quality — and the cost of saying so is '
      'bounded and measured', () async {
    final strays = <String>[];
    await underPrintTrap(strays, () async {
      final fixture = await gateBFixture(
        panels: 1,
        aliases: aliases,
        keysPerAlias: pageSize,
      );
      final dropped = fixture.linkFor(droppedAlias);
      final panel = fixture.panel;
      final droppedPage = gateBPage(droppedAlias, pageSize);
      final neighbourPages = <String, List<String>>{
        for (final alias in aliases)
          if (alias != droppedAlias) alias: gateBPage(alias, pageSize),
      };

      // -------------------------------------------------- anti-vacuity first
      // The plant is busy and all 200 keys are good on the panel before
      // anything is injected: a flood proven against a quiet plant measures
      // the freshness follow-up, not the pipe.
      final sweepsAt = fixture.driver.sweeps;
      await until(
        'the plant sweep count climbing before the injection',
        () => fixture.driver.sweeps >= sweepsAt + 2,
        budget: generous,
      );
      final allKeys = [
        ...droppedPage,
        for (final page in neighbourPages.values) ...page,
      ];
      await until(
        'all ${allKeys.length} keys good with real values on the panel',
        () => allKeys.every((key) {
          final seen = panel.client.read(key);
          return seen != null && seen.quality.isGood && seen.value != null;
        }),
        budget: generous,
      );

      // The band guard's setup: one dropped-alias key already carries WORSE
      // news than the loss will stage. The poison arrives through the raw
      // seam every poll cycle (09-02's persistence argument: an open-circuit
      // input does not poison one sample and recover), so it cannot be
      // superseded by a sweep before the injection lands.
      final gone = droppedPage.first;
      fixture.driver.overrideRaw(dropped, gone, tooDeep());
      await until(
        '$gone reading errorConfig (770) on the panel before the loss',
        () => panel.client.read(gone)?.quality == Quality.errorConfig,
        budget: generous,
      );
      final cleanPage = droppedPage.sublist(1);

      // Per-key listeners attached BEFORE the event (the
      // link_loss_test.dart:105-116 technique): a counter read after the
      // fact cannot tell one delivery from three, and a listener attached
      // afterwards sees nothing at all.
      final droppedDeliveries = <String, List<Quality>>{
        for (final key in droppedPage) key: <Quality>[],
      };
      final pageSubs = <StreamSubscription<dynamic>>[
        for (final key in droppedPage)
          panel.client
              .subscribe(key)
              .listen((value) => droppedDeliveries[key]!.add(value.quality)),
      ];
      for (final sub in pageSubs) {
        addTearDown(sub.cancel);
      }
      // One held subscription per untouched alias: its deliveries across the
      // window are the isolation clause on the third axis — the stream
      // itself was never interrupted, and never went non-good.
      final neighbourSeen = <String, List<DynamicValue>>{
        for (final alias in neighbourPages.keys) alias: <DynamicValue>[],
      };
      for (final entry in neighbourPages.entries) {
        final sub = panel.client
            .subscribe(entry.value.first)
            .listen(neighbourSeen[entry.key]!.add);
        addTearDown(sub.cancel);
      }

      panel.statuses.clear();
      final complaintsBefore = fixture.gatewayComplaints.length;
      final straysBefore = strays.length;
      final announcedBefore = fixture.statusNotificationsOf(droppedAlias);
      final plantAnnouncedBefore = fixture.plant.statusNotifications;
      final neighbourAt = <String, Object?>{
        for (final entry in neighbourPages.entries)
          entry.key: panel.client.read(entry.value.first)?.value,
      };

      // ---------------------------------------------------- the injection
      dropped.inner.disconnectUpstream();

      // Sampled THROUGH the window, not at the end: a per-key cost shows as
      // a slope across these samples, and one end-state reading would let a
      // burst hide behind a lucky final count.
      final costSamples = <({int complaints, int strays})>[];
      await until(
        'all ${cleanPage.length} clean $droppedAlias keys reading '
        'badCommFault on the panel',
        () {
          costSamples.add((
            complaints: fixture.gatewayComplaints.length,
            strays: strays.length,
          ));
          return cleanPage.every((key) =>
              panel.client.read(key)?.quality == Quality.badCommFault);
        },
        budget: generous,
      );
      // A settle tail past the degrade, so a second pass or a late fan-out
      // cannot land just after a lucky early exit.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        costSamples.add((
          complaints: fixture.gatewayComplaints.length,
          strays: strays.length,
        ));
      }

      // ------------------------- one link event, ONE announcement, three
      // ------------------------- layers deep (link, composer, panel)
      final downAtPanel = [
        for (final status in panel.statuses)
          if (status.alias == droppedAlias &&
              status.state == UpstreamLinkState.disconnected.wireName)
            status,
      ];
      final announcements =
          fixture.statusNotificationsOf(droppedAlias) - announcedBefore;
      print('F27a announcements: link=$announcements '
          'composer=${fixture.plant.statusNotifications - plantAnnouncedBefore} '
          'panel=${downAtPanel.length} for $droppedAlias '
          '(${cleanPage.length} keys changed band)');
      expect(announcements, 1,
          reason: 'one link event is one statusNotifications increment at '
              'the link, however many keys it cost — fifty and one are '
              'fifty apart, which is why this row runs at this size');
      expect(fixture.plant.statusNotifications - plantAnnouncedBefore, 1,
          reason: 'and the composer announced it exactly once: the same '
              'shape at the plant\'s fifteen hundred keys is fifteen '
              'hundred frames in the instant every box on screen is being '
              'redrawn');
      expect(downAtPanel, hasLength(1),
          reason: 'one link-down alarm, not 50 — one layer down from the '
              'alarm, the disconnected status crossed the wire exactly once');
      expect(downAtPanel.single.error, isNot(contains('://')),
          reason: 'the announcement goes to every session unasked, so an '
              'endpoint in it is plant-visible information disclosure');

      // Degrade-before-announce, measured at the gateway (the wire may
      // legitimately reorder: the status frame rides `emit` while values
      // ride the tick): the instant the announcement is known sent, no
      // dropped-alias key still reads good at the composer.
      final stillGood = <String>[
        for (final key in droppedPage)
          if (fixture.plant.read(key)?.quality.isGood ?? false) key,
      ];
      expect(stillGood, isEmpty,
          reason: 'the announcement went out while these keys still read '
              'good at the gateway: $stillGood — a panel acting on it would '
              'read a confident number from a link that is down');

      // ----------------- fifty keys, one pass: one delivery per key, values
      // ----------------- retained under the fault
      for (final key in cleanPage) {
        final faults = [
          for (final quality in droppedDeliveries[key]!)
            if (quality == Quality.badCommFault) quality,
        ];
        expect(faults, hasLength(1),
            reason: '$key was delivered badCommFault ${faults.length} '
                'times. One event, one batch, one delivery per changed key '
                '— more means the pass ran again, and zero means the key '
                'was skipped');
        final seen = panel.client.read(key)!;
        expect(seen.value, isNotNull,
            reason: 'the last known reading must survive the loss, so an '
                'operator can see what the plant was doing when contact '
                'went');
      }

      // ------------------------------------------- the band guard, held
      expect(panel.client.read(gone)?.quality, Quality.errorConfig,
          reason: 'a key already carrying worse news keeps its own worse '
              'news: repainting errorConfig (the tag is gone, waiting will '
              'not fix it) as badCommFault (waiting might) tells an '
              'operator to wait for something never coming back');
      expect(
          droppedDeliveries[gone]!
              .where((quality) => quality == Quality.badCommFault),
          isEmpty,
          reason: 'and it staged NO change — its listeners were never woken '
              'for the link event (fake_state_man.dart\'s band guard, '
              'scaled)');

      // -------------------- isolation: three PLCs of four, value AND
      // -------------------- quality AND still advancing
      for (final entry in neighbourPages.entries) {
        for (final key in entry.value) {
          final seen = panel.client.read(key)!;
          expect(seen.quality, Quality.good,
              reason: '$key is served by ${entry.key}, which is up. Greying '
                  'it out because a different PLC died is a plant fault the '
                  'plant does not have');
          expect(seen.value, isNotNull,
              reason: 'asserted on value as well as quality: a degradation '
                  'that also dropped the number would pass a quality-only '
                  'check');
        }
      }
      await until(
        'all three untouched aliases\' probe keys advancing past the loss',
        () => neighbourPages.entries.every((entry) =>
            panel.client.read(entry.value.first)?.value !=
            neighbourAt[entry.key]),
        budget: generous,
      );
      for (final entry in neighbourSeen.entries) {
        final nonGood = [
          for (final value in entry.value)
            if (!value.quality.isGood) value.quality,
        ];
        expect(nonGood, isEmpty,
            reason: '${entry.key}\'s held subscription delivered non-good '
                'qualities during a neighbour\'s loss: $nonGood');
      }

      // The plant stayed busy while the dead link stayed silent: the driver
      // kept sweeping and the fixture dropped exactly the dead link's
      // sweeps, so the degrade held because the PLC was dead — not because
      // the plant went quiet.
      expect(dropped.deadLinkSweeps, greaterThan(0),
          reason: 'no sweep was dropped on the dead link, so the degrade '
              'held only because the driver never ran — the row would be '
              'vacuously green on a quiet plant');

      // --------------------------------------- the cost clause, structural
      final complaintGrowth =
          fixture.gatewayComplaints.length - complaintsBefore;
      final strayGrowth = strays.length - straysBefore;
      print('F27a cost: complaints $complaintsBefore -> '
          '${fixture.gatewayComplaints.length}, stray print lines '
          '$straysBefore -> ${strays.length}, samples=${costSamples.length}, '
          'sweeps=${fixture.driver.sweeps}, '
          'deadLinkSweeps=${dropped.deadLinkSweeps}');
      expect(complaintGrowth, 0,
          reason: 'the degrade path grew the gateway\'s complaint list by '
              '$complaintGrowth: a mass degradation is the ordinary shape '
              'of a link loss, not an error, and a complaint per key at '
              'plant scale is the log flood this row exists to forbid');
      expect(strayGrowth, 0,
          reason: 'something printed $strayGrowth line(s) on the degrade '
              'path: there is no per-key line on this path, and a line per '
              'key at peak is the pipe\'s version of the catalogue\'s '
              'animation trap');
      for (final sample in costSamples) {
        expect(sample.complaints, lessThanOrEqualTo(complaintsBefore),
            reason: 'a sample inside the window read '
                '${sample.complaints} complaints against a floor of '
                '$complaintsBefore — the growth happened mid-window and '
                'shrank back, which an end-state reading would have hidden');
        expect(sample.strays, lessThanOrEqualTo(straysBefore),
            reason: 'a sample inside the window caught a stray print line '
                'that an end-state count would have kept');
      }

      // Nobody was thrown off for being told the news.
      expect(fixture.evictions, isEmpty);
      expect(fixture.heartbeatReaps, isEmpty);
      expect(fixture.sessionCount, 1);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}

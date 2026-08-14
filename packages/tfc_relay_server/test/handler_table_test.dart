@TestOn('vm')
@Tags(['meta'])

/// The package's integrity sweep: properties of the test suite as a whole,
/// which no individual case can assert about itself.
///
/// **The filename undersells it.** The handler table itself is frozen next
/// door in `surface_test.dart`, where the hand-written literal lives. What is
/// here are the three checks that need to read the *suite* rather than the
/// server, plus the lane that times it. Four groups:
///
///  1. **Every close code is observed client-side.** A disconnect reason no
///     test ever watches arrive at a client is a reason we believe in on the
///     strength of the code that sends it. The sweep reads the test directory
///     as text and, for each code this server can emit, demands a line that
///     both names the code and reads the *client's* view of the close.
///  2. **The exempt list is itself checked.** An exemption names a code that
///     exists, and — this is the part that keeps the list honest — an exempt
///     code must still be genuinely unobserved. The plan that lands the
///     producer removes its line here, and the build says so.
///  3. **The dependency edge points one way.** The contract package never
///     mentions the server; the server's production `lib/` never mentions the
///     contract package, which is a dev dependency and must stay one.
///  4. **The suite's own wall-clock cost**, behind a named env gate, following
///     the `FAULT_LANE_BUDGET` precedent: exactly one CI job watches the
///     number and every other run skips it by name.
///
/// **Why the marker is `closeCode` and not `sentCloseCode`.** The session
/// records what it sent (`sentCloseCode`) because `web_socket_channel` #1698
/// makes the socket's own `closeCode` unreliable for a self-initiated close.
/// That field is the *server's* account of the disconnect, and a test asserting
/// on it proves the server formed an intention — not that a panel ever learned
/// it. `ws_harness.dart:75` makes the same point from the other side: a case
/// that asserts on the client's view says `closeCode` in the source. The two
/// spellings differ in exactly one character's case, which is what lets a text
/// sweep tell an intention from an observation.
///
/// This file excludes itself from its own scan. It contains every code number
/// and the marker word by necessity, so a sweep that read it would find its own
/// literals and report full coverage of a suite that tested nothing.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// This package's test directory, relative to the package root that
/// `dart test` runs from.
const _testDir = 'test';

/// The sweep's own file, excluded from the scan. See the library doc.
const _selfName = 'handler_table_test.dart';

/// Every close code this server can emit, code to the constant's name.
///
/// Hand-written, and cross-checked against the real constants below so a
/// renumbering cannot leave this map quietly describing codes nobody sends.
const Map<int, String> closeCodeNames = {
  4001: 'authExpired',
  4002: 'serverDraining',
  4003: 'heartbeatTimeout',
  4004: 'backpressureOverrun',
  4005: 'protocolMismatch',
};

/// Codes with no client-side observation yet, each with the reason and the
/// plan that owes one.
///
/// An entry here is a debt, not a dispensation. When the named plan lands its
/// producer and its test, the observation sweep finds the code, the
/// "an exemption is still needed" case below fails, and whoever landed it
/// deletes the line. That failure is the point: it is how the list empties.
const Map<int, String> exemptCodes = {
  4001: 'authExpired — Phase 6 supplies the producer (token expiry mid-session). '
      'The server records it today in session_hello_test via sentCloseCode, '
      'which is an intention, not an observation.',
  4003: 'heartbeatTimeout — 03-09 lands the reaper that emits it, together '
      'with the client-side case that watches the close arrive.',
  // 4004 was exempt until 03-09 wired the buffer's verdicts into the session's
  // close path. `backpressure_test.dart` now watches a real client observe it
  // over a real socket, so the debt is paid and the line is gone — which is
  // exactly the way this list is meant to empty.
};

/// The marker that distinguishes a client-observed close from a server-recorded
/// one. Case-sensitive on purpose — see the library doc.
const _clientObservationMarker = 'closeCode';

/// The env var that arms the suite budget lane.
///
/// Spelled after `FAULT_LANE_BUDGET` (`test.yml:110-116`), and armed the same
/// way: one job sets it, everything else skips by name.
const _laneBudgetEnvVar = 'RELAY_SERVER_LANE_BUDGET';

/// The ceiling this file owns.
///
/// A whole-suite number, not a per-assertion band: STATE.md's 20/100 ms Linux
/// and 75/150 ms elsewhere bands govern individual timed assertions, and this
/// is the sum of a suite that binds ephemeral ports and sleeps through real
/// heartbeat windows at `concurrency: 1`. Generous on purpose — it catches a
/// lane that has doubled, not one that drifted.
const _suiteBudget = Duration(minutes: 3);

/// Every `.dart` file under [directory], excluding this sweep itself.
List<File> _testFiles(Directory directory) {
  if (!directory.existsSync()) return const [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.endsWith(_selfName))
      .toList();
}

/// Maps each close code to the files holding a client-side observation of it.
///
/// A line counts when it carries the observation marker *and* names the code,
/// either numerically or through the constant. Same line, not same file: a
/// file that mentions 4004 in a comment and separately reads a client's
/// `closeCode` for some other reason has not tested 4004.
Map<int, List<String>> observationsIn(Directory directory) {
  final found = {for (final code in closeCodeNames.keys) code: <String>[]};

  for (final file in _testFiles(directory)) {
    final name = file.uri.pathSegments.last;
    for (final line in file.readAsLinesSync()) {
      if (!line.contains(_clientObservationMarker)) continue;
      closeCodeNames.forEach((code, constant) {
        final named =
            line.contains('$code') || line.contains('CloseCodes.$constant');
        if (named && !found[code]!.contains(name)) found[code]!.add(name);
      });
    }
  }
  return found;
}

/// Files under [directory] whose text mentions [needle], as `path:line`.
List<String> _mentions(Directory directory, String needle) {
  final hits = <String>[];
  if (!directory.existsSync()) return hits;
  for (final file in directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(needle)) hits.add('${file.path}:${i + 1}');
    }
  }
  return hits;
}

void main() {
  final tests = Directory(_testDir);
  final observed = observationsIn(tests);

  group('the code table matches the protocol', () {
    test('every name in the literal is the real constant', () {
      // The exempt list below "names only codes that exist" only means
      // something if this map does too.
      expect(closeCodeNames[CloseCodes.authExpired], 'authExpired');
      expect(closeCodeNames[CloseCodes.serverDraining], 'serverDraining');
      expect(closeCodeNames[CloseCodes.heartbeatTimeout], 'heartbeatTimeout');
      expect(
          closeCodeNames[CloseCodes.backpressureOverrun], 'backpressureOverrun');
      expect(closeCodeNames[CloseCodes.protocolMismatch], 'protocolMismatch');
      expect(closeCodeNames, hasLength(5),
          reason: 'a sixth close code needs a line here and either an '
              'observation or an exemption');
    });

    test('every exempt entry names a code that exists', () {
      for (final code in exemptCodes.keys) {
        expect(closeCodeNames.containsKey(code), isTrue,
            reason: 'the exempt list excuses $code, which this server cannot '
                'emit — an exemption for a code nobody sends silently excuses '
                'nothing and hides a typo for the code it meant');
        expect(exemptCodes[code], isNotEmpty,
            reason: 'an exemption without a written reason is a TODO wearing '
                'a test');
      }
    });
  });

  group('every close code is observed client-side', () {
    test('the scan found files at all', () {
      // Anti-vacuity: an empty scan makes every "is it observed" check below
      // fail for the right reason and every exemption pass for the wrong one.
      expect(_testFiles(tests), isNotEmpty,
          reason: 'the sweep read no test files — it is scanning the wrong '
              'directory, and everything it reports is noise');
    });

    test('discovery reports zero for an empty directory', () {
      final empty = Directory.systemTemp.createTempSync('relay-sweep-');
      addTearDown(() => empty.deleteSync(recursive: true));

      final nothing = observationsIn(empty);

      expect(_testFiles(empty), isEmpty);
      expect(nothing.values.every((files) => files.isEmpty), isTrue,
          reason: 'pointed at an empty directory the sweep must report zero '
              'observations, not pass because it found nothing to disagree '
              'with');
      expect(nothing.keys, closeCodeNames.keys,
          reason: 'the shape of the report does not depend on what was found');
    });

    for (final entry in closeCodeNames.entries) {
      final code = entry.key;
      final constant = entry.value;
      final exemption = exemptCodes[code];

      if (exemption == null) {
        test('$code ($constant) is observed by some client-side test', () {
          expect(observed[code], isNotEmpty,
              reason: 'no test asserts a client observing $code. Either a case '
                  'reads the harness\'s $_clientObservationMarker on a close '
                  'carrying $code, or $code joins the exempt list with the '
                  'plan that owes one.');
        });
      } else {
        test('$code ($constant) is still exempt, and still needs to be', () {
          expect(observed[code], isEmpty,
              reason: 'the exempt list still excuses $code, but '
                  '${observed[code]} now observes it client-side. The debt is '
                  'paid — delete the $code entry from exemptCodes. Reason on '
                  'record was: $exemption');
        });
      }
    }

    test('the observation map is reported for the record', () {
      // Not an assertion: the SUMMARY and any future reader want the map, and
      // a sweep whose findings are invisible is hard to trust.
      closeCodeNames.forEach((code, constant) {
        final files = observed[code]!;
        print('close code $code ($constant): '
            '${files.isEmpty ? 'no client-side observation'
                '${exemptCodes.containsKey(code) ? ' — exempt' : ''}'
                : files.join(', ')}');
      });
    });
  });

  group('the dependency edge points one way', () {
    test('the contract package never mentions the server', () {
      final hits = [
        ..._mentions(Directory('../tfc_stateman_contract/lib'),
            'tfc_relay_server'),
        ..._mentions(Directory('../tfc_stateman_contract/test'),
            'tfc_relay_server'),
      ];

      expect(hits, isEmpty,
          reason: 'tfc_stateman_contract is the thing the gateway is judged '
              'against; a reference back to the gateway makes the judge depend '
              'on the defendant. Found at: $hits');
    });

    test('the server\'s production lib never mentions the contract package',
        () {
      final hits = _mentions(Directory('lib'), 'tfc_stateman_contract');

      expect(hits, isEmpty,
          reason: 'the contract package is a dev dependency — a test kit. An '
              'import from lib/ ships the kit to production and makes the '
              'fakes reachable from the running gateway. Found at: $hits');
    });

    test('the check is looking at directories that exist', () {
      // Anti-vacuity: both greps above pass trivially against a missing path.
      expect(Directory('lib').existsSync(), isTrue);
      expect(Directory('../tfc_stateman_contract/lib').existsSync(), isTrue,
          reason: 'the contract package moved; the grep above has been '
              'passing against nothing');
    });
  });

  group('the suite budget lane', () {
    test('the whole suite fits inside its declared ceiling', () async {
      final lane = Stopwatch()..start();
      // `--exclude-tags meta` keeps the child out of this file, which would
      // otherwise inherit the armed env var and recurse.
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['test', '--exclude-tags', 'meta'],
        workingDirectory: Directory.current.path,
      );
      lane.stop();

      print('the relay-server suite ran in ${lane.elapsed.inSeconds} s '
          'against a ${_suiteBudget.inSeconds} s ceiling');

      expect(result.exitCode, 0,
          reason: 'the budget lane cannot judge a suite that did not pass:\n'
              '${result.stdout}\n${result.stderr}');
      expect(lane.elapsed, lessThan(_suiteBudget),
          reason: 'the suite took ${lane.elapsed.inSeconds} s against a '
              '${_suiteBudget.inSeconds} s ceiling. This lane is wall-clock by '
              'design — ports, heartbeats and concurrency: 1 — so the question '
              'is not whether it is slow but whether it got slower.');
    },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: (Platform.environment[_laneBudgetEnvVar]?.isNotEmpty ?? false)
            ? false
            : 'set $_laneBudgetEnvVar to any non-empty value to run and time '
                'the whole suite; exactly one CI job does, per the '
                'FAULT_LANE_BUDGET precedent');
  });
}

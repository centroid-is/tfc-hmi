/// The five structural promises this package makes on day one.
///
/// These properties are *the reason* `LocalStateMan` is a new package rather
/// than five hundred more lines inside `tfc_relay_server`. That package pins
/// itself at exactly one repeating timer (`teardown_test.dart:495-540`) and it
/// is right to: one tick engine over one registry, and a second periodic timer
/// there would double every client's frame rate and halve the value of every
/// backpressure verdict. This package genuinely needs three — a `runIterate`
/// driver, a freshness sweep and a fan-in linger — and the honest answer to
/// that is a **named allow-list of its own**, not an exemption bolted onto
/// somebody else's sweep until their property means nothing.
///
/// So the promises are written down here, before there is anything to enforce
/// them against, and each one is proven to be *looking*. Three rules the file
/// follows, and the reasons are not stylistic:
///
///  1. **Every sweep takes its directory as an argument.** That is what makes
///     the empty-temp-directory falsification arm possible at all — a sweep
///     that hard-codes its own path cannot be pointed at a tree that is known
///     to contain nothing, so nothing can ever demonstrate that it counts.
///     `mode_integrity_test.dart:379`'s `_proofFiles(Directory)` is the shape.
///  2. **Every number is declared here**, as a `const` with a comment saying
///     what would legitimately move it — never derived from the thing it is
///     counting, because a count that recomputes its own expectation agrees
///     with every future.
///  3. **Anti-vacuity comes before the count.** Directory exists → directory
///     holds `.dart` files → the same sweep over an empty temp directory
///     reports zero → *then* the count
///     (`no_retry_test.dart:327-364`, `handler_table_test.dart:289-296`,
///     `teardown_test.dart:496-499` all learned this the same way).
///
/// Four of the five counts are **zero today**, because on day one this package
/// is one interface file. A case named "no timer outside the allow-list" that
/// passes over a tree with no timers in it is a case nobody should trust
/// without its empty-directory sibling, and the case names below say so out
/// loud rather than letting a future reader mistake an empty tree for a clean
/// one.
@TestOn('vm')
@Tags(['meta'])
library;

import 'dart:io';

import 'package:test/test.dart';

// ---------------------------------------------------------------- the scopes
//
// Relative to the package root, which is where `dart test` runs from. The
// anti-vacuity group's first case is what catches a working directory that is
// not what this file assumes.

final Directory libRoot = Directory('lib');
final Directory libSrc = Directory('lib/src');
final Directory testRoot = Directory('test');

// ------------------------------------------------------------- the allow-lists

/// Files permitted to hold a `Timer.periodic(`, each naming the plan that
/// earned the entry.
///
/// **Empty on day one.** Three entries are anticipated and none of them is
/// pre-approved — the plan that lands each one adds it here in the same
/// commit, which is what makes a fourth timer a decision rather than a drift:
///
///  * 08-05's freshness sweep — listener-gated, interval derived from
///    `staleAfter`. Only a clock can notice silence, so this one cannot be
///    replaced by a deadline check on paths that already run.
///  * 08-05's fan-in linger — a one-shot `Timer(linger, …)` per key at
///    refcount zero, not a periodic; it lands as a named `_timer` field
///    instead of an entry here.
///  * 08-07's `runIterate` driver — one per OPC UA link, started on connect
///    and stopped on disconnect.
const Map<String, String> periodicTimerAllowList = <String, String>{};

/// Test files permitted to hold a literal port number, each naming why.
///
/// **Empty, and it should stay that way.** Two worktrees must be able to run
/// this suite at once.
const Map<String, String> literalPortAllowList = <String, String>{};

// ----------------------------------------------------------- the pinned counts

/// `Timer.periodic(` occurrences under `lib/src`.
///
/// Moves when a plan on [periodicTimerAllowList] lands, and only then. A
/// timer that appears without its allow-list entry is caught by the offender
/// case rather than by this number, which is why both exist.
const int declaredPeriodicTimers = 0;

/// Lines under `lib/` that await an upstream `connect`/`read`/`write`.
///
/// Zero because this package is declarations only today. It moves the moment
/// 08-06's write path or 08-07's adapter lands, and it moves **by a number
/// somebody wrote down** — every one of those call sites has to carry a
/// `deadline` argument or a `.timeout(`, and the offender case is what
/// enforces that. `state_man.dart:1868` is one line of the shape this pins:
/// `await client.awaitConnect()` inside a read, with no deadline, leaving the
/// caller pending forever against a disconnected PLC (T-08-10).
const int declaredUpstreamAwaitSites = 0;

/// Lines under `lib/` that call `.write(` on an upstream.
///
/// The `no_retry_test.dart:182-293` seam shape, scoped to this package. Zero
/// today; 08-06 makes it one. It must never become "one per protocol with a
/// wrapper around them" — the wrapper is where a retry goes.
const int declaredUpstreamWriteSites = 0;

/// The dev-dependency test kit that must never be reachable from `lib/`.
const String contractKitPackage = 'tfc_stateman_contract';

/// Retry shapes forbidden on an upstream write line.
const List<String> retryShapes = <String>[
  'retry',
  'attempt',
  'backoff',
  'Future.doWhile',
];

void main() {
  group('the sweeps are looking at something', () {
    // Comes first, and this ordering is the whole lesson: every count below is
    // trivially satisfied by reading nothing.
    test('every scope exists', () {
      for (final scope in <Directory>[libRoot, libSrc, testRoot]) {
        expect(scope.existsSync(), isTrue,
            reason: 'no directory at "${scope.path}", so every count this file '
                'reports over it is 0 and every pin has been passing against '
                'nothing. These paths are relative to the package root; dart '
                'test was invoked from ${Directory.current.path}');
      }
    });

    test('every scope holds dart files', () {
      for (final scope in <Directory>[libRoot, libSrc, testRoot]) {
        expect(dartFilesIn(scope), isNotEmpty,
            reason: 'the scope "${scope.path}" exists and holds no .dart file, '
                'so the sweeps over it read nothing');
      }
    });

    test('all five sweeps report zero over an empty directory', () {
      final empty = Directory.systemTemp.createTempSync('relay-local-freeze-');
      addTearDown(() => empty.deleteSync(recursive: true));

      expect(dartFilesIn(empty), isEmpty);
      expect(timerOffenders(empty), isEmpty);
      expect(periodicTimerCount(empty), 0);
      expect(mentionsOf(empty, contractKitPackage), isEmpty);
      expect(upstreamAwaitSites(empty), isEmpty);
      expect(unboundedUpstreamAwaits(empty), isEmpty);
      expect(upstreamWriteSites(empty), isEmpty);
      expect(retryShapedWrites(empty), isEmpty);
      expect(literalPortLines(empty), isEmpty,
          reason: 'pointed at an empty directory a sweep that reports an '
              'occurrence is inventing rather than measuring, and nothing it '
              'says about the real scopes can be trusted');
    });
  });

  group('freeze 1: timers are named', () {
    test('no Timer.periodic outside the allow-list — which is empty today, so '
        'this case rests on its empty-directory sibling', () {
      expect(timerOffenders(libSrc), isEmpty,
          reason: 'a repeating or retained timer exists in a file that no plan '
              'put on the allow-list. Add the entry in the same commit as the '
              'timer, naming the plan, or the fourth one is a drift nobody '
              'decided on');
    });

    test('the repeating-timer count is the declared one', () {
      expect(periodicTimerCount(libSrc), declaredPeriodicTimers,
          reason: 'this package declares its own timer discipline rather than '
              'borrowing tfc_relay_server\'s one-timer pin, and the price of '
              'that freedom is writing the number down');
    });
  });

  group('freeze 2: the contract kit is not in lib/', () {
    test('no file under lib/ mentions the kit, comments included', () {
      expect(mentionsOf(libRoot, contractKitPackage), isEmpty,
          reason: 'the contract package is a dev dependency — a test kit with '
              'fakes in it. An import from lib/ ships those fakes to the '
              'plant, and this sweep reads comments too because a commented-'
              'out import is one keystroke from a real one. '
              '`cert_health_state_man.dart:20-23` names the kit by ROLE '
              'rather than by package for exactly this reason, and that is the '
              'discipline to copy when lib/ needs to talk about it');
    });

    test('the needle is the real package name, not a typo', () {
      // Non-vacuous on purpose: a misspelled needle would pass the case above
      // forever. The pubspec is where the name is independently written down.
      expect(File('pubspec.yaml').readAsStringSync(), contains(contractKitPackage),
          reason: 'no dev_dependency by that name, so the sweep above is '
              'hunting a string this repository does not use');
    });
  });

  group('freeze 3: no unbounded upstream await', () {
    test('every awaited upstream call carries a deadline or a timeout', () {
      expect(unboundedUpstreamAwaits(libRoot), isEmpty,
          reason: 'an upstream connect/read/write awaited with neither a '
              'deadline argument nor a .timeout() pends forever against a '
              'disconnected PLC, which hangs the poll cycle for every other '
              'key on that link. This is state_man.dart:1868 inherited rather '
              'than prevented (T-08-10)');
    });

    test('the upstream call-site count is the declared one — zero today, so '
        'the empty-directory arm is what carries this', () {
      expect(upstreamAwaitSites(libRoot), hasLength(declaredUpstreamAwaitSites),
          reason: 'a new upstream call site should be a deliberate edit to '
              'this number, so that the person adding it reads the rule '
              'above while they are here');
    });
  });

  group('freeze 4: no write retry', () {
    test('no retry shape on any upstream write line', () {
      expect(retryShapedWrites(libRoot), isEmpty,
          reason: 'no auto-retry, at any layer, ever. The three-state outcome '
              'is what makes a re-send the operator\'s decision, and readback '
              'is the only confirmation. A well-meaning wrapper that repeats '
              'an unknown write is one actuation the operator did not ask for '
              '— and on a hold-to-run engage it is a jog nobody is holding');
    });

    test('the upstream write call-site count is the declared one — zero today, '
        'so the empty-directory arm is what carries this', () {
      expect(upstreamWriteSites(libRoot), hasLength(declaredUpstreamWriteSites),
          reason: 'the gateway\'s crossing into the plant is the one place a '
              'retry could hide. no_retry_test.dart pins the server\'s at '
              'exactly one call site for this reason; this is the same pin '
              'with tfc_relay_local/lib as the scope');
    });
  });

  group('freeze 5: no literal port', () {
    test('no test file hard-codes a port number', () {
      expect(literalPortLines(testRoot), isEmpty,
          reason: 'two worktrees must be able to run this suite at once. A '
              'hard-coded listening port collides across parallel runs and '
              'the collision looks exactly like a real failure in the code '
              'under test — which is how an afternoon goes. Bind zero and ask '
              'the socket what it got; TcpProxy already defaults that way');
    });
  });
}

// ---------------------------------------------------------------- the sweeps
//
// Crude and line-based, in the style the two existing sweeps in this
// repository already use. A parsed AST would be more precise and would also be
// a thing to maintain; these are meant to be readable by the person they are
// about to stop.

/// Every `.dart` file under [directory], or none if it does not exist.
List<File> dartFilesIn(Directory directory) => directory.existsSync()
    ? directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
    : <File>[];

/// A doc comment arguing *about* a timer is not a timer
/// (`teardown_test.dart:510-512`).
bool _isDocComment(String line) => line.trimLeft().startsWith('///');

/// And neither is an ordinary comment, for the sweeps that say so.
/// `no_retry_test.dart:181` measures with both stripped.
bool _isAnyComment(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('///') || trimmed.startsWith('//');
}

/// Timer offences: a `Timer.periodic(` in a file no plan allow-listed, or a
/// retained `Timer(` that does not name a field.
List<String> timerOffenders(Directory directory) {
  final offenders = <String>[];
  for (final file in dartFilesIn(directory)) {
    final name = file.uri.pathSegments.last;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_isDocComment(line)) continue;
      if (line.contains('Timer.periodic(') &&
          !periodicTimerAllowList.containsKey(name)) {
        offenders.add('${file.path}:${i + 1}: $line');
      }
      // `Timer.run` is exempt and does not match this spelling anyway: it
      // cannot outlive the turn it was scheduled in and it holds nothing open
      // (`teardown_test.dart:519-522`). A constructed `Timer(...)` can do
      // both, so it has to be reachable through a named field to be
      // cancellable.
      if (line.contains('Timer(') && !line.contains('_timer')) {
        offenders.add('${file.path}:${i + 1}: $line');
      }
    }
  }
  return offenders;
}

/// How many `Timer.periodic(` occurrences live under [directory].
int periodicTimerCount(Directory directory) {
  var count = 0;
  for (final file in dartFilesIn(directory)) {
    for (final line in file.readAsLinesSync()) {
      if (_isDocComment(line)) continue;
      if (line.contains('Timer.periodic(')) count++;
    }
  }
  return count;
}

/// Every line under [directory] containing [needle] — **comments included**.
List<String> mentionsOf(Directory directory, String needle) {
  final hits = <String>[];
  for (final file in dartFilesIn(directory)) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(needle)) hits.add('${file.path}:${i + 1}');
    }
  }
  return hits;
}

/// An awaited call to something an upstream answers.
final RegExp _upstreamCall =
    RegExp(r'\.\s*(awaitConnect|connect|read|write)\s*\(');

/// Every line under [directory] that awaits an upstream call.
List<String> upstreamAwaitSites(Directory directory) {
  final sites = <String>[];
  for (final file in dartFilesIn(directory)) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_isAnyComment(line)) continue;
      if (!line.contains('await')) continue;
      if (!_upstreamCall.hasMatch(line)) continue;
      sites.add('${file.path}:${i + 1}: ${line.trim()}');
    }
  }
  return sites;
}

/// The subset of [upstreamAwaitSites] with no bound on how long they may take.
List<String> unboundedUpstreamAwaits(Directory directory) =>
    upstreamAwaitSites(directory)
        .where((site) => !site.contains('deadline') && !site.contains('.timeout('))
        .toList();

/// Every line under [directory] that calls `.write(` on something.
List<String> upstreamWriteSites(Directory directory) {
  final sites = <String>[];
  for (final file in dartFilesIn(directory)) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_isAnyComment(line)) continue;
      if (!line.contains('.write(')) continue;
      sites.add('${file.path}:${i + 1}: ${line.trim()}');
    }
  }
  return sites;
}

/// The subset of [upstreamWriteSites] carrying a retry shape.
List<String> retryShapedWrites(Directory directory) => upstreamWriteSites(
        directory)
    .where((site) => retryShapes.any((shape) => site.contains(shape)))
    .toList();

/// A four- or five-digit integer that is not part of a longer identifier.
final RegExp _portLiteral = RegExp(r'\b\d{4,5}\b');

/// Every line under [directory] that puts a literal number next to a port.
List<String> literalPortLines(Directory directory) {
  final hits = <String>[];
  for (final file in dartFilesIn(directory)) {
    final name = file.uri.pathSegments.last;
    if (literalPortAllowList.containsKey(name)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_isAnyComment(line)) continue;
      if (!line.toLowerCase().contains('port')) continue;
      if (!_portLiteral.hasMatch(line)) continue;
      hits.add('${file.path}:${i + 1}: ${line.trim()}');
    }
  }
  return hits;
}

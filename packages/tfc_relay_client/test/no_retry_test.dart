@TestOn('vm')

/// WRT-03: no code path in this system re-sends a write on its own.
///
/// **What the requirement claims.** A re-send is always an operator decision.
/// Not on a timeout, not on a reconnect, not on the one verdict that is
/// re-send-safe (`not_received`) — the machine never decides to actuate a
/// second time because the first answer was slow or absent. CLAUDE.md states
/// it as "never auto-retried", and it is the sentence the whole three-state
/// `WriteResult` exists to keep enforceable: "unknown" is only honest if
/// nothing downstream quietly turns it into "try again".
///
/// **The behavioural half already exists, in three places.** They are named
/// here rather than restated, because a fourth copy of an existing assertion is
/// a maintenance cost that buys nothing:
///
///  * `tfc_stateman_contract/lib/src/write_contract.dart:341-365` —
///    `checkExactlyOneUpstreamAttemptPerCmd`, which runs against every
///    implementation on every leg and asserts the plant's own attempt counter
///    is 1 for both an ordinary write and one whose outcome nobody knows.
///  * `test/contract/fault_contract_test.dart:432` — F5, a write across a
///    total blackhole: `debugWritesSent == 1`.
///  * `test/contract/fault_contract_test.dart:529-545` — F6/F7, the link killed
///    with a write on the wire: `debugWritesSent == 1` before the reconnect and
///    again after the `writeStatus` re-query, because the recovery asks about
///    the command rather than repeating it.
///
/// **What this file adds is the structural half.** Every one of those cases
/// judges a retry that exists. None of them says anything about a retry that
/// does not exist *yet* — and the way this property dies is not a broken test,
/// it is somebody wrapping a send in a `for` loop or a `.retry()` extension in
/// a refactor that looks like plumbing. So the four seams through which a write
/// can reach the plant are pinned at exactly one call site each, measured in
/// this tree, with the failure message naming the file and line of every
/// occurrence found — so a second call site reads as "here is the second
/// actuation" and not as "expected 1, got 2".
///
/// **What the structural arm does not prove** (05-RESEARCH §D.2). It pins
/// *call sites* and one scheduling primitive. It does not pin control flow: a
/// `for (var i = 0; i < 2; i++)` wrapped around the one existing
/// `sendRequest` passes every case in groups 1 and 2, because there is still
/// exactly one call site. That gap is what group 3 is for — it watches the
/// plant's own counter across a link flap, where a loop shows up as a second
/// attempt no matter how it was spelled. Neither group is sufficient alone;
/// the pair is.
///
/// An analyzer plugin would close the gap properly and was rejected for a
/// stated reason (05-RESEARCH §D.2 arm 3): it needs `analyzer` as a dependency,
/// which is the version-solve blocker three pubspecs in this workspace name
/// explicitly. A grep pin plus a behavioural arm is the cheapest honest
/// mechanism, and "honest" is doing work in that sentence — see the paragraph
/// above.
///
/// **Why there is no `retry` substring sweep.** It was measured and it is not
/// pinnable: `retry` appears 3 times in `lib/src/client_config.dart` and 10
/// times in `lib/src/connection_supervisor.dart` in non-comment text, and all
/// thirteen are *reconnect* vocabulary — `_retry` the backoff timer, "the very
/// first retry would already…" in a config refusal. Retrying a dial is
/// legitimate and necessary; retrying a write is the thing this file exists to
/// forbid. A sweep that could not tell them apart would be switched off within
/// a month. Do not add one.
///
/// **Precedent.** The sweep helpers are `tfc_relay_server`'s
/// `test/handler_table_test.dart:110-158` (`_testFiles` / `_mentions`) and both
/// of its anti-vacuity arms at `:192-214`; the read-the-source-as-text shape
/// with an `existsSync` guard is `test/client_config_test.dart:202-222`.
library;

import 'dart:io';

import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// The sweep.
// ---------------------------------------------------------------------------

/// Every `.dart` file under [directory], recursively; empty when it is absent.
///
/// Absence is reported as "nothing found" rather than thrown, because the
/// scopes below reach across package boundaries with `../` and the case that
/// notices a moved package should be the named `existsSync` one, not a
/// stack trace inside a helper.
List<File> _dartFiles(Directory directory) {
  if (!directory.existsSync()) return const [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

/// Every non-comment occurrence of [needle] in [file], as `(line, text)`.
///
/// A line is dropped when its `trimLeft()` starts with `///` or `//`, which is
/// the same rule `client_config_test.dart:213` uses. Docs on this path
/// *discuss* the seams at length — `deadline.dart:34` and
/// `failure_taxonomy.dart:12` both name `sendRequest` in prose — and a sweep
/// that counted prose would be pinned to the wording of a comment.
///
/// One entry per match, not per line: two call sites written on one line are
/// two call sites.
List<(int, String)> _mentions(File file, Pattern needle) {
  final hits = <(int, String)>[];
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.startsWith('///') || trimmed.startsWith('//')) continue;
    for (final _ in needle.allMatches(lines[i])) {
      hits.add((i + 1, lines[i]));
    }
  }
  return hits;
}

/// Every non-comment occurrence of [needle] under [scope], as `path:line  text`.
List<String> _occurrences(Directory scope, Pattern needle) {
  final hits = <String>[];
  for (final file in _dartFiles(scope)) {
    for (final (line, text) in _mentions(file, needle)) {
      hits.add('${file.path}:$line  ${text.trim()}');
    }
  }
  return hits;
}

// ---------------------------------------------------------------------------
// The seams.
// ---------------------------------------------------------------------------

/// One place a write can move one hop closer to the plant.
final class _Seam {
  const _Seam({
    required this.caseName,
    required this.spelling,
    required this.scope,
    required this.needle,
    required this.expected,
    required this.soleSite,
    required this.consequence,
  });

  /// The case name, written as the property rather than as the grep, so a
  /// failure in CI reads as a claim about the system.
  final String caseName;

  /// How the seam is spelled in the source, for the failure message.
  final String spelling;

  /// Directory to walk, **relative to the `tfc_relay_client` package root**.
  ///
  /// `dart test` runs with the package root as its working directory, which is
  /// what makes `../` reach the sibling packages. The `existsSync` case below
  /// is the one that notices when that stops being true.
  final String scope;

  final Pattern needle;

  /// Measured in this tree at plan time. An assertion, not a guess.
  final int expected;

  /// Where the one call site was when this pin was written. Informational: the
  /// line number will drift and the count will not.
  final String soleSite;

  /// What a second call site would mean on a plant, in the operator's terms.
  final String consequence;
}

/// The four hops, gateway-ward, each singular today.
///
/// Measured 2026-08-14 in this worktree with `///` and `//` lines stripped.
final List<_Seam> _seams = <_Seam>[
  _Seam(
    // This exact name is what a second `peer.sendRequest(` under `lib/` trips.
    caseName: 'the client has exactly one place where a request leaves for '
        'the gateway',
    spelling: 'sendRequest',
    scope: 'lib',
    needle: RegExp(r'sendRequest'),
    expected: 1,
    soleSite: 'lib/src/deadline.dart:95, inside callWithDeadline',
    consequence: 'every request this client makes — writes included — goes '
        'through one line, and that line reads the peer into a local before it '
        'suspends so a reconnect cannot retarget a request at the replacement '
        'socket (deadline.dart:90-95). A second send site is a second place '
        'that guarantee has to be re-established by hand, and the first time '
        'it is not, an operator\'s one press of a button strokes the ram '
        'twice.',
  ),
  _Seam(
    caseName: 'the client names the write method in exactly one place',
    spelling: 'Methods.write',
    scope: 'lib',
    // Word-bounded on purpose: `Methods.writeStatus` at
    // remote_state_man.dart:691 contains `Methods.write` as a substring, and
    // it is the *recovery* method — the one that asks about a command instead
    // of repeating it. A substring sweep would count the cure as a symptom.
    needle: RegExp(r'Methods\.write\b'),
    expected: 1,
    soleSite: 'lib/src/remote_state_man.dart:544, inside RemoteStateMan.write',
    consequence: 'the write method is named once, by the method that mints the '
        'id, registers it as unresolved and counts the send. A second mention '
        'is a write leaving the client without that bookkeeping, so its '
        'outcome is unattributable and `writeStatus` can never ask about it.',
  ),
  _Seam(
    caseName: 'the gateway hands a write to the source in exactly one place',
    spelling: 'api.write(',
    scope: '../tfc_relay_server/lib',
    needle: RegExp(r'api\.write\('),
    expected: 1,
    soleSite: '../tfc_relay_server/lib/src/value_handlers.dart:309',
    consequence: 'this is the gateway\'s only crossing into the plant, and it '
        'is wrapped by the outcome log that makes the write answerable after a '
        'reconnect. A retry here is the worst of the four: the client sent '
        'once, believes it sent once, and reports one outcome for two '
        'actuations.',
  ),
  _Seam(
    caseName: 'the plant counts an upstream attempt in exactly one place',
    spelling: '_attempt(cmd)',
    scope: '../tfc_stateman_contract/lib',
    needle: RegExp(r'_attempt\(cmd\)'),
    expected: 1,
    soleSite: '../tfc_stateman_contract/lib/testing/fake_state_man.dart:688, '
        'inside attemptUpstreamWrite',
    consequence: 'this counter is what every behavioural no-retry check in the '
        'suite reads. A second increment site does not cause a double '
        'actuation — it makes the number that would have detected one stop '
        'meaning "attempts", which is worse, because the suite goes on '
        'reporting green (fake_state_man.dart:670-681 argues the same point '
        'from the other side).',
  ),
];

/// The one file group 2 reads, relative to the package root.
const _remoteStateManPath = 'lib/src/remote_state_man.dart';

void main() {
  group('the write path has one call site per seam', () {
    // Anti-vacuity, and the reason it comes first: every count case below is
    // trivially satisfiable by reading nothing. `handler_table_test.dart:
    // 192-214` learned this the same way.
    test('every scope the sweep reads exists', () {
      for (final scope in {for (final seam in _seams) seam.scope}) {
        expect(Directory(scope).existsSync(), isTrue,
            reason: 'the sweep found no directory at "$scope", so every count '
                'it reports for that scope is 0 and every pin over it has '
                'been passing against nothing. These paths are relative to '
                'the tfc_relay_client package root; dart test was invoked '
                'from ${Directory.current.path}. Either a package moved or '
                'the working directory did.');
      }
    });

    test('the sweep found dart files in every scope', () {
      for (final scope in {for (final seam in _seams) seam.scope}) {
        expect(_dartFiles(Directory(scope)), isNotEmpty,
            reason: 'the scope "$scope" exists and holds no .dart file, so '
                'the sweep over it read nothing. A scope that resolves to '
                'nothing makes every count zero and every assertion below '
                'vacuous.');
      }
    });

    test('discovery reports zero for an empty directory', () {
      final empty = Directory.systemTemp.createTempSync('relay-no-retry-');
      addTearDown(() => empty.deleteSync(recursive: true));

      expect(_dartFiles(empty), isEmpty);
      for (final seam in _seams) {
        expect(_occurrences(empty, seam.needle), isEmpty,
            reason: 'pointed at an empty directory the sweep reported an '
                'occurrence of ${seam.spelling}, so the counter is inventing '
                'rather than measuring and nothing it says about the real '
                'scopes can be trusted');
      }
    });

    for (final seam in _seams) {
      test(seam.caseName, () {
        final found = _occurrences(Directory(seam.scope), seam.needle);

        expect(found, hasLength(seam.expected),
            reason: 'the ${seam.spelling} seam has ${found.length} '
                'non-comment call sites under "${seam.scope}", not '
                '${seam.expected}.\n\n'
                '${seam.consequence}\n\n'
                'At the time this pin was written the only one was '
                '${seam.soleSite}. Everything the sweep found now:\n'
                '${found.isEmpty ? '  (nothing — see the anti-vacuity cases '
                    'above)' : found.map((hit) => '  $hit').join('\n')}\n\n'
                'If the new site is genuinely not a second actuation — a '
                'rename, a second *read* path — raise the expected count here '
                'and say in this file why the new site cannot re-send a '
                'write. Raising the number without that sentence is how this '
                'pin stops being one.');
      });
    }
  });

  group('the client schedules nothing of its own on the write path', () {
    // A weaker claim than the group above and worth being precise about: this
    // pins one scheduling primitive in one file. A retry does not need a
    // `Timer` — a `for` loop around the existing call site would pass this
    // group and pass group 1 too, because it adds no call site. That is what
    // group 3 is for: the plant's own counter cannot be fooled by control
    // flow.
    //
    // `Timer` is pinned anyway because the *delayed* retry is the shape that
    // actually ships: "it timed out, wait 200 ms, send it again". The backoff
    // timer that legitimately exists lives in `connection_supervisor.dart` and
    // dials sockets; `remote_state_man.dart:283`'s `debugTimerCount` is a
    // delegation to it and contains no `Timer(` of its own.
    test('remote_state_man.dart schedules nothing', () {
      final source = File(_remoteStateManPath);
      expect(source.existsSync(), isTrue,
          reason: 'this case reads the implementation as text, so it must run '
              'with the tfc_relay_client package root as the working '
              'directory; dart test was invoked from '
              '${Directory.current.path} and found no '
              '$_remoteStateManPath');

      for (final needle in <Pattern>[RegExp(r'Timer\('), RegExp(r'Timer\.periodic')]) {
        final found = _mentions(source, needle)
            .map((hit) => '$_remoteStateManPath:${hit.$1}  ${hit.$2.trim()}')
            .toList();

        expect(found, isEmpty,
            reason: 'the client\'s write path now schedules something of its '
                'own:\n${found.map((hit) => '  $hit').join('\n')}\n\n'
                'Every legitimate timer this client owns belongs to the '
                'connection supervisor and its watchdog, which dial sockets '
                'and time out reads. A timer here schedules something about a '
                'write, and the only thing there is to schedule about a write '
                'whose answer has not come back is sending it again — which '
                'is an operator\'s decision and never this process\'s.');
      }
    });
  });
}

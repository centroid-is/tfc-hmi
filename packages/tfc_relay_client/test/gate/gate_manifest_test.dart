/// Properties of the *resilience gate as a whole*, which no gate case can
/// assert about itself.
///
/// **No row without a case, no case without a row.** `f_row_registry.dart`
/// names twenty-seven catalogue rows and this phase claims each one is either
/// judged by a case in this directory or owed by a named plan. That claim is a
/// property of the directory, so it is asserted here in both directions, for
/// the reason `mode_integrity_test.dart:6-12` gives about orphaned proofs: the
/// two failures are different and both are silent. A row nobody exercises is a
/// hostile network condition nobody is testing, sitting in the repository
/// looking like coverage. A case naming a row the registry does not declare is
/// a case that will never be reached from the list an auditor reads.
///
/// **How cases are discovered, and why the choice matters.** By reading the
/// `test(...)` names out of each file's source and matching them against a
/// grammar — not by matching a filename, and not by looking for the row id
/// anywhere in the file. `no_retry_test.dart:21` mentions `F5` four times in
/// prose; a bare-substring sweep would count that file as coverage of F5, which
/// is exactly the failure `mode_integrity_test.dart:14-22` argues against at
/// length. Prose about a row is what a file has instead of a test for it.
///
/// The grammar is `^(row)(arm)?(/(row)(arm)?)*: ` — so `F1/F8: …`, `F5a: …`,
/// `F7c: …` and `G1: …` all name rows and `F5 is fine now` names nothing.
/// 07-RESEARCH §F.1 asks for exactly one case per row; reality contradicts it
/// before the phase starts (F5 has two arms, F18 has two, the write-in-flight
/// family has four), so the 1:1 property is asserted between the *registry* and
/// the directory, and within a row the arm letters must be unique and gapless.
///
/// **The directory is read as text, never imported.** The sweep reads case
/// files with `readAsStringSync` and imports nothing from them, for
/// `fault_contract_test.dart:296-318`'s reason: importing couples the sweep to
/// the names most likely to change, and then a rename breaks the audit rather
/// than being audited by it.
///
/// **A sweep that stops looking reports full coverage of nothing.** So
/// [_cases] takes its directory as an argument, one case points it at an empty
/// temp directory and asserts zero, another points it at a temp directory
/// holding a single fabricated case and asserts it finds exactly that one, and
/// the "the matchers match" group holds every pattern in this file against a
/// sample of the thing it is looking for. That last group is what stops this
/// file being a decoration during the waves when `test/gate/` is still filling
/// up: on the day it lands, every content arm below has nothing to judge, and
/// an arm with nothing to judge is indistinguishable from a broken one.
///
/// **The counts live here, not in the registry.** [_declaredRows] and
/// [_declaredDeviations] are written down in this file on purpose. A sweep that
/// derives both sides of its comparison from the same source asserts nothing —
/// `mode_integrity_test.dart:86-92`'s argument, and the reason a row deleted
/// from `gateRows` is a failing suite here rather than a silently smaller
/// catalogue.
///
/// **The lane budget.** The gate lane is slower than every other lane in this
/// package by design: a flap window is a flap window and a rate has to be
/// measured over three-and-a-half seconds. The budget exists so that "slower by
/// design" cannot drift into "nobody runs it". Measuring it means running the
/// lane, which costs the lane's whole runtime again, so it is opt-in behind
/// [_laneBudgetEnvVar] — on by name on one CI job, skipped by name everywhere
/// else, never silently.
@TestOn('vm')
@Tags(['gate', 'meta'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'f_row_registry.dart';

/// Where the gate's cases live, relative to the package root — which is the
/// working directory `dart test` runs from.
const _gateDir = 'test/gate';

/// How many rows the catalogue is claimed to hold, and how many clauses the
/// phase's green is claimed not to cover.
///
/// Written down here rather than read from `f_row_registry.dart`, because a
/// sweep that derives both sides of its comparison from the same source asserts
/// nothing. A row deleted from `gateRows` deletes its own outstanding entry and
/// its own deviation in the same edit, and every in-file count still agrees
/// with itself. These two numbers are the only place the deletion is visible.
///
/// [_declaredDeviations] is a floor rather than an equality: 07-PLAN-INDEX
/// expects the registry to close between ten and twelve, with 07-11 and 07-12
/// appending their own. Nine is what this plan seeds, and a *shrinking*
/// registry is the failure worth catching — a deviation deleted without saying
/// what now asserts the clause is the gate quietly widening its own promise.
const _declaredRows = 27;
const _declaredDeviations = 9;

/// The whole gate lane's declared wall-clock budget.
///
/// 07-RESEARCH §F.3 estimates the finished lane at four to five minutes per
/// platform. Eight is deliberately slack against a loaded shared runner: the
/// number this bound is watching for is not 300 s, it is the day somebody adds
/// a row that waits sixty seconds. **Report it, never raise it.**
const _laneBudget = Duration(minutes: 8);

/// Set this to any non-empty value to actually run and time the lane.
const _laneBudgetEnvVar = 'GATE_LANE_BUDGET';

/// Shortest acceptable skip reason, in characters.
///
/// The same floor `platform_skip_audit_test.dart:56-62` sets for the fault kit,
/// re-implemented here because that audit scans its own package's `test/faults`
/// and `test/channel` and will never see this directory. Forty characters
/// forces at least a clause about the capability and a clause about the
/// consequence; `'not supported on windows'` is twenty-four and sends the next
/// engineer to read the source to find out what they lost.
const _skipReasonFloor = 40;

/// Getters whose value is derived from a wall clock, and must therefore never
/// be read at an instant.
///
/// This is the F5 lesson made general (07-RESEARCH §E.2). `fault_contract_test
/// .dart:472` asserted `viewIsStale` at a single moment against a 500 ms
/// deadline and failed one run in three on a loaded macOS runner — not because
/// the property was wrong but because the read landed on the wrong side of a
/// timer. The fix is a doctrine, not a wider band: read these inside an
/// `until()` or `within()` window, or do not read them.
const _wallClockSurfaces = <String>[
  'viewIsStale',
  'isReady',
  'linkState',
  'staleSubscriptions',
  'forwarding',
];

/// The calls that turn an instant into a window.
const _windowCalls = <String>['until(', 'within(', 'arrived('];

/// Files in the gate directory that are not gate cases, and why.
///
/// One entry, and it has to be here: this file names the row grammar, the
/// wall-clock surfaces and the skip spellings as *data* in order to search for
/// them, and it builds sample sources containing `test('F1: …')` to prove its
/// own matchers bite. A sweep that did not exempt it would report itself as the
/// worst offender in the directory, and whoever read that as the false positive
/// it is would loosen the rule rather than the exemption.
///
/// `f_row_registry.dart` needs no entry: it is not a `_test.dart` file, so
/// discovery never reaches it. It is still swept for instant reads, along with
/// every other `.dart` file here.
const _notAGateCase = <String, String>{
  'gate_manifest_test.dart':
      'declares the grammar, the wall-clock surfaces and the skip spellings it '
          'searches for, and fabricates sample case sources to prove its own '
          'matchers match; it injects no fault and judges no row',
};

void main() {
  final directory = Directory(_gateDir);
  final files = _gateFiles(directory);
  final cases = _cases(directory);
  final byRow = _byRow(cases);

  group('the sweep is looking where it thinks it is', () {
    test('the gate directory is on disk beside this file', () {
      expect(directory.existsSync(), isTrue,
          reason: 'there is no $_gateDir under ${Directory.current.path}, so '
              'every arm below is judging an empty list. `dart test` runs from '
              'the package root and this path is relative to it — check the '
              'directory the run was invoked from before believing any other '
              'result here');
      expect(File('$_gateDir/f_row_registry.dart').existsSync(), isTrue,
          reason: 'the row registry is not beside this sweep. The counts below '
              'come from an import, so they would still be right; what would '
              'be wrong is the assumption that the directory being read is the '
              'directory the registry describes');
    });

    test('every file exempted from discovery still exists', () {
      final missing = [
        for (final name in _notAGateCase.keys)
          if (!File('$_gateDir/$name').existsSync()) name,
      ];
      expect(missing, isEmpty,
          reason: 'these files are exempted from case discovery and are not on '
              'disk. An exemption for a file that no longer exists is a hole '
              'held open for nothing — and the next file to take one of these '
              'names inherits the exemption without anybody deciding to give '
              'it one');
    });

    test('discovery reports zero for an empty directory', () async {
      final empty = await Directory.systemTemp.createTemp('gate-manifest-');
      addTearDown(() => empty.delete(recursive: true));

      expect(_cases(empty), isEmpty,
          reason: 'discovery pointed at a directory with no test files in it '
              'still returned cases, so it is not reading the directory it was '
              'handed. Every count above would then be describing something '
              'other than $_gateDir');
    });

    test('discovery finds the one case in a directory that has one', () async {
      final one = await Directory.systemTemp.createTemp('gate-manifest-');
      addTearDown(() => one.delete(recursive: true));
      File('${one.path}/foo_test.dart').writeAsStringSync('''
void main() {
  test('F1: a fabricated case', () {});
}
''');

      final found = _cases(one);
      expect(found, hasLength(1),
          reason: 'discovery found ${found.length} cases in a directory '
              'holding exactly one, so the zero it reports for the empty '
              'directory above proves nothing: a matcher that matches nothing '
              'reports zero everywhere. This is the positive half of that '
              'control arm, and it is the half that has teeth while '
              '$_gateDir is still filling up');
      expect(found.single.rows, ['F1'],
          reason: 'the fabricated case is named `F1:` and discovery read its '
              'row as ${found.single.rows}. The name is parsed by the same '
              'grammar every real case is judged by');
      expect(found.single.file, 'foo_test.dart',
          reason: 'discovery attributed the case to ${found.single.file} '
              'rather than to the file it read it out of, so the '
              '"which file must quote the anchor" arm below is pointing at the '
              'wrong file');
    });

    test('every plan id in the outstanding list is well-formed', () {
      final malformed = [
        for (final entry in gateOutstanding.entries)
          if (!RegExp(r'^07-\d\d$').hasMatch(entry.value.owner))
            '${entry.key} -> ${entry.value.owner}',
      ];
      expect(malformed, isEmpty,
          reason: 'these outstanding entries name an owner that is not a Phase '
              '7 plan id: $malformed. The owner is the whole value of the '
              'entry — an outstanding row with no plan behind it is a row '
              'nobody has agreed to write, recorded as though somebody had');
    });
  });

  group('the counts are written down twice', () {
    test('the catalogue is still the size this phase claims', () {
      expect(gateRows, hasLength(_declaredRows),
          reason: 'gateRows holds ${gateRows.length} rows and this phase '
              'claims $_declaredRows. Every other arm in this file derives '
              'both of its sides from gateRows, so a row deleted there is '
              'invisible to all of them: it takes its outstanding entry and '
              'its deviations with it and every count still agrees with '
              'itself. This number is the only place the deletion shows');
    });

    test('no row id is declared twice', () {
      final seen = <String>{};
      final duplicated = [
        for (final row in gateRows)
          if (!seen.add(row.id)) row.id,
      ];
      expect(duplicated, isEmpty,
          reason: 'these row ids appear more than once in gateRows: '
              '$duplicated. The outstanding map is keyed by id, so a duplicate '
              'row silently shares one owner and one clause with its twin');
    });

    test('the deviations registry has not shrunk below its seed', () {
      expect(gateDeviations.length, greaterThanOrEqualTo(_declaredDeviations),
          reason: 'gateDeviations holds ${gateDeviations.length} entries and '
              'this plan seeded $_declaredDeviations. Later plans append; none '
              'may delete an entry without saying what now asserts the clause, '
              'because a deviation that disappears is a promise the gate '
              'quietly widened');
    });
  });

  group('no row without a case, no case without a row', () {
    test('every row has a case or a named plan that owes it', () {
      final unaccounted = [
        for (final row in gateRows)
          if (byRow[row.id] == null &&
              gateOutstanding[row.id]?.kind != OutstandingKind.missing)
            row.id,
      ];
      expect(unaccounted, isEmpty,
          reason: 'these catalogue rows have no case in $_gateDir and no '
              'missing entry in gateOutstanding: $unaccounted. A row in '
              'neither list is not deferred, it is forgotten — the phase '
              'reports its remaining work by running this sweep, and a row '
              'nobody claims does not appear in that report');
    });

    test('no row is both covered and still owed', () {
      final both = [
        for (final row in gateRows)
          if (byRow[row.id] != null &&
              gateOutstanding[row.id]?.kind == OutstandingKind.missing)
            '${row.id} (owed to ${gateOutstanding[row.id]!.owner}, covered by '
                '${byRow[row.id]!.map((c) => c.name).join(', ')})',
      ];
      expect(both, isEmpty,
          reason: 'these rows have a case and are still listed as missing: '
              '$both. Every plan deletes its own entries in the commit that '
              'lands its rows; an entry left behind makes the outstanding '
              'count overstate the remaining work, which is how 07-13\'s '
              '"the map is empty" closing condition fails for a reason that is '
              'not about the gate at all');
    });

    test('a partial entry names a row that has a case', () {
      final mislabelled = [
        for (final entry in gateOutstanding.entries)
          if (entry.value.kind == OutstandingKind.partial &&
              byRow[entry.key] == null)
            entry.key,
      ];
      expect(mislabelled, isEmpty,
          reason: 'these rows are listed as partially covered and have no case '
              'at all: $mislabelled. A partial entry for a row with no case is '
              'a missing entry wearing the wrong label, and it reads on the '
              'progress line as work that is nearly done');
    });

    test('every case names a row the catalogue declares', () {
      final declared = {for (final row in gateRows) row.id};
      final strangers = [
        for (final one in cases)
          for (final row in one.rows)
            if (!declared.contains(row)) '${one.file}: ${one.name} -> $row',
      ];
      expect(strangers, isEmpty,
          reason: 'these cases name rows gateRows does not declare: '
              '$strangers. An F22 here belongs in Phase 9 and a typo here is a '
              'row that reads as covered while its real name reads as missing '
              '— the reverse direction exists because those two failures look '
              'identical from the forward direction');
    });
  });

  group('arm letters are unique and gapless', () {
    test('a row with several cases lettered them a, b, c', () {
      final wrong = <String>[];
      for (final entry in byRow.entries) {
        final letters = [
          for (final one in entry.value) one.armOf(entry.key),
        ]..sort((a, b) => (a ?? '').compareTo(b ?? ''));

        if (letters.length == 1) {
          if (letters.single != null) {
            wrong.add('${entry.key}: one case, lettered '
                '${entry.key}${letters.single}');
          }
          continue;
        }
        final expected = [
          for (var i = 0; i < letters.length; i++)
            String.fromCharCode('a'.codeUnitAt(0) + i),
        ];
        if (!_sameList(letters, expected)) {
          wrong.add('${entry.key}: $letters, expected $expected');
        }
      }
      expect(wrong, isEmpty,
          reason: 'these rows letter their arms with a gap, a repeat, or a '
              'letter on a row that has only one case: $wrong. F5a beside F5c '
              'is not a naming quibble — it is the shape a deleted arm leaves '
              'behind, and the forward sweep cannot see it because the row '
              'still has a case');
    });
  });

  group('every case quotes its catalogue line', () {
    test('the file holding a row\'s case carries the row\'s quote anchor', () {
      final byName = {for (final file in files) file.name: file};
      final unquoted = <String>[];
      for (final row in gateRows) {
        final holders = byRow[row.id];
        if (holders == null) continue;
        for (final holder in {for (final one in holders) one.file}) {
          final source = byName[holder]?.source ?? '';
          if (!source.contains(row.quoteAnchor)) {
            unquoted.add('$holder is missing ${row.id}\'s anchor '
                '"${row.quoteAnchor}"');
          }
        }
      }
      expect(unquoted, isEmpty,
          reason: 'these files hold a row\'s case and do not contain the row\'s '
              'anchor: $unquoted. The anchor is a fragment of the catalogue '
              'text copied character-for-character, so a file that does not '
              'contain it has paraphrased the row it claims to gate — and a '
              'paraphrase is where a scenario quietly becomes a weaker '
              'scenario that still passes');
    });
  });

  group('the deviations name real clauses', () {
    test('every deviation quotes a row the catalogue declares', () {
      final declared = {for (final row in gateRows) row.id};
      final strangers = [
        for (final deviation in gateDeviations)
          if (!declared.contains(deviation.row)) deviation.row,
      ];
      expect(strangers, isEmpty,
          reason: 'these deviations name rows gateRows does not declare: '
              '$strangers. A deviation against a row that does not exist '
              'excuses nothing and is read by the verification document as '
              'though it excused something');
    });

    test('every deviation clause is verbatim catalogue text', () {
      final rows = {for (final row in gateRows) row.id: row};
      final paraphrased = [
        for (final deviation in gateDeviations)
          if (rows[deviation.row] != null &&
              !rows[deviation.row]!
                  .verbatimText
                  .any((text) => text.contains(deviation.clause)))
            '${deviation.row}: "${deviation.clause}"',
      ];
      expect(paraphrased, isEmpty,
          reason: 'these deviation clauses are not substrings of their row\'s '
              'catalogue text: $paraphrased. A deviation that paraphrases the '
              'clause it descopes is a deviation nobody can check against the '
              'catalogue — the reader cannot tell whether the thing being '
              'given up is the whole row or a corner of it');
    });
  });

  group('no case skips silently', () {
    test('no gate case carries an unconditional skip', () {
      final offenders = <String>[];
      for (final file in files) {
        for (final skip in _skips(file.code)) {
          if (_isUnconditional(skip.expression)) {
            offenders.add('${file.name}: `${skip.expression}`');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'these gate cases skip unconditionally: $offenders. A row '
              'green by a case that never runs is the "capability switched '
              'off" failure fault_contract_test.dart:9-14 warns about, one '
              'level up: the manifest counts the row as covered, the run '
              'report shows a skip, and the hostile network condition is as '
              'unjudged as it would have been with no case at all. 07-RESEARCH '
              '§A.5(4): no row goes green by a case that skips');
    });

    test('every conditional skip says what stopped being judged', () {
      final thin = <String>[];
      for (final file in files) {
        for (final skip in _skips(file.code)) {
          if (_isUnconditional(skip.expression)) continue;
          if (skip.literals.isEmpty) {
            if (!_tracesToAProbe(skip.expression, file.code)) {
              thin.add('${file.name}: `${skip.expression}` (no reason, and no '
                  'probe it could have come from)');
            }
            continue;
          }
          for (final reason in skip.literals) {
            if (reason.length < _skipReasonFloor) {
              thin.add('${file.name}: "$reason" (${reason.length} chars)');
            }
          }
        }
      }
      expect(thin, isEmpty,
          reason: 'these skip reasons are shorter than $_skipReasonFloor '
              'characters or are computed from something that is not a probe: '
              '$thin. On the Windows column of the matrix a skipped row and a '
              'passing row are the same green tick, and the reason is the only '
              'thing that tells them apart');
    });
  });

  group('no instant read of a wall-clock boolean', () {
    test('every staleness read happens inside a window', () {
      final instants = <String>[];
      for (final source in _allGateSources(directory)) {
        final lines = source.code.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!line.contains('expect(')) continue;
          if (_windowCalls.any(line.contains)) continue;
          for (final surface in _wallClockSurfaces) {
            if (line.contains(surface)) {
              instants.add('${source.name}:${i + 1} — $surface');
            }
          }
        }
      }
      expect(instants, isEmpty,
          reason: 'these lines read a wall-clock-derived value at an instant '
              'inside an expect(): $instants. This is the F5 flake exactly '
              '(07-RESEARCH §E.2) — fault_contract_test.dart:480 and :508 '
              'asserted viewIsStale at a single moment against a 500 ms '
              'deadline and failed one run in three on a loaded runner. The '
              'property is "it becomes stale", which is a window; asserting it '
              'at a point measures the scheduler. Wrap the read in until() or '
              'within(), and platform-scale the deadline');
    });
  });

  group('every gate file carries the tag', () {
    test('each case file is selected by --tags gate', () {
      final untagged = [
        for (final file in files)
          if (!_carriesTheGateTag(file.source)) file.name,
      ];
      expect(untagged, isEmpty,
          reason: 'these files under $_gateDir carry no @Tags naming gate: '
              '$untagged. The CI lane and the budget arm both select by tag, '
              'so an untagged file is a row that is in the manifest, on disk, '
              'and not in the lane — green locally on a full run and never '
              'executed by the job that owns the number');
    });
  });

  group('the matchers match', () {
    // Every content arm above passes today by having almost nothing to judge:
    // 07-01 lands this sweep before a single row does. A pattern with a typo in
    // it reports green forever under exactly those conditions, which is the
    // failure this file exists to catch, one level up. These cases hold each
    // matcher against a sample of the thing it is looking for, and against a
    // sample of the thing it must not mistake for it.
    test('the row grammar reads the names the phase will write', () {
      expect(_rowsIn('F1: a clean drop reconnects'), ['F1']);
      expect(_rowsIn('F1/F8: the changed-while-down key comes back'),
          ['F1', 'F8'],
          reason: 'a case that gates two rows at once names both, and the '
              'forward sweep has to credit both or one of them reads as '
              'missing while its assertion is right there');
      expect(_rowsIn('F5a: a write resolves unknown'), ['F5']);
      expect(_rowsIn('G1: silent divergence under a quiet plant'), ['G1']);
      expect(_rowsIn('F21: the link recovers'), ['F21']);
    });

    test('the row grammar refuses a row merely mentioned', () {
      expect(_rowsIn('F5 is fine now'), isEmpty,
          reason: 'a test name that mentions a row without gating it is being '
              'counted as coverage. This is the four doc-comment mentions in '
              'no_retry_test.dart:21 read as a gate case, which is the whole '
              'reason discovery matches a grammar rather than a substring');
      expect(_rowsIn('the F1 path is not this'), isEmpty,
          reason: 'the grammar is anchored at the start of the name; a row id '
              'in the middle of a sentence is prose');
      expect(_rowsIn('F5:no space after the colon'), isEmpty,
          reason: 'the grammar requires a colon and a space, which is what '
              'keeps a Dart type annotation or a map literal in a name from '
              'reading as a row');
    });

    test('arm letters are read off the name they are attached to', () {
      expect(_armIn('F5a: x', 'F5'), 'a');
      expect(_armIn('F5: x', 'F5'), isNull);
      expect(_armIn('F1/F8b: x', 'F8'), 'b',
          reason: 'in a two-row name each row carries its own arm letter, so '
              'reading the letter off the wrong token would letter F1 with '
              'F8\'s arm and report a gap in both rows');
    });

    test('an instant read is recognised and a windowed one is not', () {
      const instant = 'expect(api.viewIsStale, isTrue);';
      const windowed = 'await until(() => api.viewIsStale, reason: ...);';
      expect(
          instant.contains('expect(') &&
              !_windowCalls.any(instant.contains) &&
              _wallClockSurfaces.any(instant.contains),
          isTrue,
          reason: 'the instant-read sweep does not recognise an instant read '
              'written out longhand, so it has been passing on every file by '
              'matching nothing');
      expect(
          windowed.contains('expect(') && !_windowCalls.any(windowed.contains),
          isFalse,
          reason: 'a read already inside an until() window is being reported '
              'as an instant, which is the false positive that gets a sweep '
              'switched off rather than obeyed');
    });

    test('an unconditional skip is recognised and a probed one is not', () {
      expect(_isUnconditional('true'), isTrue);
      expect(_isUnconditional("'parked while the flake is investigated'"),
          isTrue,
          reason: 'a bare string handed to skip: is an unconditional skip '
              'wearing a reason. It is the most common spelling of the thing '
              'this arm forbids and the easiest one to miss');
      expect(_isUnconditional('probe.available ? null : probe.reason'), isFalse,
          reason: 'a runtime-decided skip is being read as unconditional, '
              'which would forbid the one shape platform_skip_audit_test.dart '
              'asks for');
    });

    test('a skip expression is read whole, across lines', () {
      const sample = '''
  }, skip: probe.available
      ? null
      : 'the probe declined and this is the reason it gave');
''';
      final skips = _skips(sample);
      expect(skips, hasLength(1),
          reason: 'the scanner found ${skips.length} skips in a sample with '
              'exactly one');
      expect(skips.single.literals.single,
          'the probe declined and this is the reason it gave',
          reason: 'the reason three lines below the `skip:` was not read, so a '
              'multi-line skip is judged on its condition alone — the house '
              'style puts the reason there and a line-bounded capture would '
              'accuse every file that follows it');
    });

    test('a skip written inside a string is not a skip', () {
      expect(_skips("expect(x, isTrue, reason: 'it becomes a Skip() later');"),
          isEmpty,
          reason: 'prose about skipping is being counted as a skip, which is '
              'how the files that document this rule best become the ones the '
              'audit accuses');
    });

    test('the tag matcher reads the tag off the header it will meet', () {
      expect(_carriesTheGateTag("@Tags(['gate'])"), isTrue);
      expect(_carriesTheGateTag("@Tags(['gate', 'faults'])"), isTrue);
      expect(_carriesTheGateTag("@Tags(['faults'])"), isFalse,
          reason: 'a file tagged for another lane is being read as tagged for '
              'this one, so the arm would pass for a row the gate lane never '
              'runs');
      expect(_carriesTheGateTag("/// the gate lane runs this"), isFalse,
          reason: 'the word "gate" in prose is being read as a tag');
    });

    test('comments are stripped before the source is scanned', () {
      const sample = '''
// skip: true
/// expect(api.viewIsStale, isTrue);
final x = 1;
''';
      final stripped = _stripCommentLines(sample);
      expect(stripped, isNot(contains('skip:')));
      expect(stripped, isNot(contains('viewIsStale')));
      expect(stripped, contains('final x = 1;'),
          reason: 'the comment stripper is eating code, which would hide real '
              'offenders from every source arm in this file');
    });
  });

  group('the sweep itself', () {
    test('the whole gate lane runs inside its declared budget', () async {
      final lane = Stopwatch()..start();
      final run = await Process.run(
        Platform.resolvedExecutable,
        ['test', _gateDir, '--exclude-tags', 'meta'],
        workingDirectory: Directory.current.path,
        // Cleared in the child, because the child inherits this process's
        // environment and would otherwise see the variable that turned this
        // arm on and run it again. The only other thing stopping that is the
        // `meta` tag being excluded above — so dropping or renaming that tag
        // would turn one CI job into an unbounded recursion of `dart test`
        // processes rather than into a failing assertion. Two guards, copied
        // from mode_integrity_test.dart:317-328, and neither of them alone.
        environment: {_laneBudgetEnvVar: ''},
      );
      lane.stop();

      print('the gate lane ran in ${lane.elapsed.inSeconds} s '
          '(budget ${_laneBudget.inSeconds} s)');
      expect(run.exitCode, 0,
          reason: 'the gate lane is not green, so the time below is the cost '
              'of a failing suite:\n${run.stdout}\n${run.stderr}');
      expect(lane.elapsed, lessThan(_laneBudget),
          reason: 'the gate lane took ${lane.elapsed.inSeconds} s against a '
              '${_laneBudget.inSeconds} s budget. The lane is slower than '
              'every other lane in this package by design — a flap window is a '
              'flap window and a rate needs three and a half seconds — and '
              'this bound is what keeps "slower by design" from becoming '
              '"nobody runs it". Report the number, do not raise the budget');
    },
        timeout: const Timeout(Duration(minutes: 12)),
        skip: Platform.environment[_laneBudgetEnvVar]?.isNotEmpty ?? false
            ? null
            : 'the lane budget is measured by running the lane, which costs '
                'the lane\'s full runtime a second time on top of the run that '
                'is already in progress. Set $_laneBudgetEnvVar=1 to measure '
                'it; CI sets it on the one job that owns the number. What '
                'stops being judged while it is unset: whether the whole gate '
                'lane still fits in ${_laneBudget.inSeconds} s, and whether it '
                'is green when run on its own rather than inside a full suite');
  });
}

// ---------------------------------------------------------------------------
// Discovery.
// ---------------------------------------------------------------------------

/// One `test('…')` in the gate directory whose name gates at least one row.
final class GateCase {
  const GateCase(this.file, this.name, this._tokens);

  /// The file it was read out of.
  final String file;

  /// The whole test name, as written.
  final String name;

  /// The `(row, arm)` pairs parsed off the front of [name].
  final List<({String row, String? arm})> _tokens;

  /// Every row this case gates.
  List<String> get rows => [for (final token in _tokens) token.row];

  /// The arm letter this case carries for [row], or null if it carries none.
  String? armOf(String row) =>
      _tokens.firstWhere((token) => token.row == row).arm;
}

/// One `.dart` file in the gate directory, with its source and its code.
typedef _Source = ({String name, String source, String code});

/// The grammar a gate case name has to satisfy: one or more `row` or `row+arm`
/// tokens separated by `/`, then a colon and a space.
///
/// The row half is deliberately looser than the registry — `F22` parses — so
/// that a case naming a row nobody declared is reported by the reverse sweep as
/// the stranger it is, rather than vanishing from discovery and reading as no
/// case at all.
final _rowGrammar =
    RegExp(r'^([FG]\d{1,2}[a-z]?(?:/[FG]\d{1,2}[a-z]?)*): ');

/// One token of that grammar, split into its row and its arm letter.
final _rowToken = RegExp(r'^([FG]\d{1,2})([a-z])?$');

/// A `test('…')` or `test("…")` call, with the first literal of its name.
final _testCall = RegExp(
    '''\\btest\\(\\s*(?:'((?:[^'\\\\]|\\\\.)*)'|"((?:[^"\\\\]|\\\\.)*)")''');

/// Every gate case in [directory].
///
/// Takes the directory as an argument so the empty-directory and
/// one-fabricated-case arms above can falsify it. A discovery function that
/// hard-codes its own input cannot be shown to be looking anywhere —
/// `mode_integrity_test.dart:379-383`'s reason, and the reason this sweep can
/// be trusted during the waves when `test/gate/` is nearly empty.
List<GateCase> _cases(Directory directory) => [
      for (final file in _gateFiles(directory))
        for (final match in _testCall.allMatches(file.code))
          ..._caseOf(file.name, match.group(1) ?? match.group(2) ?? ''),
    ];

/// [name] as a gate case, or nothing if it names no row.
List<GateCase> _caseOf(String file, String name) {
  final tokens = _tokensIn(name);
  return tokens.isEmpty ? const [] : [GateCase(file, name, tokens)];
}

/// The `(row, arm)` pairs at the front of [name].
List<({String row, String? arm})> _tokensIn(String name) {
  final prefix = _rowGrammar.firstMatch(name);
  if (prefix == null) return const [];
  return [
    for (final token in prefix.group(1)!.split('/'))
      if (_rowToken.firstMatch(token) case final parsed?)
        (row: parsed.group(1)!, arm: parsed.group(2)),
  ];
}

/// Every row [name] gates. Used by the matcher arms.
List<String> _rowsIn(String name) => [
      for (final token in _tokensIn(name)) token.row,
    ];

/// The arm letter [name] carries for [row]. Used by the matcher arms.
String? _armIn(String name, String row) =>
    _tokensIn(name).firstWhere((token) => token.row == row).arm;

/// Every gate case in [cases], grouped by the row it gates.
Map<String, List<GateCase>> _byRow(List<GateCase> cases) {
  final grouped = <String, List<GateCase>>{};
  for (final one in cases) {
    for (final row in one.rows) {
      (grouped[row] ??= <GateCase>[]).add(one);
    }
  }
  return grouped;
}

/// Every non-exempt `_test.dart` file in [directory], read.
List<_Source> _gateFiles(Directory directory) => [
      for (final source in _allGateSources(directory))
        if (source.name.endsWith('_test.dart'))
          if (!_notAGateCase.containsKey(source.name)) source,
    ];

/// Every non-exempt `.dart` file in [directory], read.
///
/// Wider than [_gateFiles] because the instant-read sweep is a rule about the
/// directory, not about its cases: a helper that reads `viewIsStale` at an
/// instant hands the flake to every case that calls it.
List<_Source> _allGateSources(Directory directory) {
  if (!directory.existsSync()) return const [];
  return [
    for (final entity
        in directory.listSync()..sort((a, b) => a.path.compareTo(b.path)))
      if (entity is File && entity.path.endsWith('.dart'))
        if (!_notAGateCase.containsKey(entity.uri.pathSegments.last))
          (
            name: entity.uri.pathSegments.last,
            source: entity.readAsStringSync(),
            code: _stripCommentLines(entity.readAsStringSync()),
          ),
  ];
}

/// [source] with whole-line `//` and `///` comments blanked out.
///
/// Blanked rather than removed, so a reported line number still matches the
/// file. Trailing comments after code stay, because stripping those safely
/// means parsing string literals and none of the patterns here are written that
/// way — `platform_skip_audit_test.dart:40-43`'s reasoning.
String _stripCommentLines(String source) => [
      for (final line in source.split('\n'))
        if (line.trimLeft().startsWith('//')) '' else line,
    ].join('\n');

/// Whether [source] declares the `gate` tag in its library header.
bool _carriesTheGateTag(String source) {
  final tags = RegExp(r'@Tags\(\[([^\]]*)\]\)').firstMatch(source);
  if (tags == null) return false;
  return RegExp(r"""['"]gate['"]""").hasMatch(tags.group(1)!);
}

// ---------------------------------------------------------------------------
// The skip rules, re-implemented for this directory.
//
// `platform_skip_audit_test.dart` enforces these over `test/faults` and
// `test/channel` in tfc_stateman_contract and will never see this package, so
// the scanner is ported rather than imported: it lives in that package's test
// tree, which is not on this one's import path. The rules are the same three —
// no unconditional skip, a forty-character reason floor, and a computed skip
// has to trace to a probe.
// ---------------------------------------------------------------------------

/// One skip site: the expression handed to `skip:`/`Skip(`, and the string
/// literals inside it.
typedef _Skip = ({String expression, List<String> literals});

/// Every skip site in [code], with its expression extracted exactly.
///
/// Exactly, rather than to the end of the line, because the house style puts a
/// multi-line ternary after `skip:` and a line-bounded capture reads only the
/// condition. The scan tracks bracket depth and steps over string literals, so
/// a `Skip(` written *inside* a failure message is not a site.
List<_Skip> _skips(String code) {
  final found = <_Skip>[];
  var quote = '';
  for (var i = 0; i < code.length; i++) {
    final char = code[i];
    if (quote.isNotEmpty) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = '';
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
      continue;
    }
    if (!code.startsWith('skip:', i) && !code.startsWith('Skip(', i)) continue;
    // Both spellings put the colon or bracket that opens the argument at i + 4.
    final expression = _argumentAt(code, i + 4);
    found.add(
        (expression: expression.trim(), literals: _literalsIn(expression)));
  }
  return found;
}

/// The argument text beginning at [from] (which indexes `:` or `(`), up to the
/// comma or closing bracket that ends it at depth zero.
String _argumentAt(String code, int from) {
  var depth = 0;
  var quote = '';
  for (var i = from + 1; i < code.length; i++) {
    final char = code[i];
    if (quote.isNotEmpty) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = '';
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
    } else if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char)) {
      if (depth == 0) return code.substring(from + 1, i);
      depth--;
    } else if (char == ',' && depth == 0) {
      return code.substring(from + 1, i);
    }
  }
  return code.substring(from + 1);
}

/// Every single-quoted literal in [expression], with adjacent segments joined
/// the way Dart joins them — so a two-line reason is judged as one sentence
/// rather than as two short ones.
List<String> _literalsIn(String expression) {
  final segments = RegExp(r"'((?:[^'\\]|\\.)*)'")
      .allMatches(expression)
      .map((m) => m.group(1)!);
  return segments.isEmpty ? const [] : [segments.join()];
}

/// Whether [expression] skips no matter what the platform says.
///
/// `skip: true` is the obvious spelling. `skip: 'the reason'` is the common one
/// and the one worth catching: a bare string reads like a justification and
/// behaves like `true`.
bool _isUnconditional(String expression) {
  final trimmed = expression.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == 'true') return true;
  final withoutLiterals = trimmed
      .replaceAll(RegExp(r"'((?:[^'\\]|\\.)*)'"), '')
      .replaceAll(RegExp(r'"((?:[^"\\]|\\.)*)"'), '')
      .trim();
  return withoutLiterals.isEmpty;
}

/// Whether a skip's text comes from a probe rather than from the call site.
final _probeReason = RegExp(r'[sS]kipReason|\.reason\b|\breason\b');

/// Whether [expression] carries a probe's reason, following one level of local
/// indirection.
///
/// `skip: needsNetem` says nothing on its own; `final needsNetem = tc.available
/// ? null : tc.reason;` says everything. Refusing to follow the identifier
/// would fail the file that does this correctly and pass the one that writes
/// its excuse inline, which is backwards.
bool _tracesToAProbe(String expression, String code) {
  if (_probeReason.hasMatch(expression)) return true;
  for (final identifier in RegExp(r'\b[a-z]\w*\b').allMatches(expression)) {
    final name = identifier.group(0)!;
    final declaration =
        RegExp('(?:final|const|var)\\s+$name\\s*=([^;]*);', dotAll: true)
            .firstMatch(code);
    if (declaration != null && _probeReason.hasMatch(declaration.group(1)!)) {
      return true;
    }
  }
  return false;
}

/// Whether two lists of nullable strings hold the same values in order.
bool _sameList(List<String?> a, List<String?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

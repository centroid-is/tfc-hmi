/// The soak's own audit: the deviations print, the counts are written down
/// twice, and no checker name appears that nobody declared.
///
/// The analogue of `gate_manifest_test.dart` one level up, with the row table
/// deliberately absent (11-RESEARCH §F.1). What this file audits is the two
/// things the soak's registry actually holds — the six checker names and the
/// declared departures from §7.8 — plus, from 11-01 task 2, the vacuity gate
/// that makes a checker's green mean something.
///
/// **The counts live here, not in the registry.** [_declaredDeviations] and
/// [_declaredCheckerNames] are written down in this file on purpose, which is
/// `gate_manifest_test.dart:44-50`'s argument: a sweep that derives both sides
/// of its comparison from the same source asserts nothing. An entry deleted
/// from `soakDeviations` takes its own `.length` with it and every in-file
/// count still agrees with itself; these two numbers are the only place the
/// deletion shows.
///
/// **The print is the point.** Later phases and the milestone audit read the
/// deviations block out of a run report rather than out of the source, so it
/// goes to stdout on every run whether or not anything below fails — the same
/// reason `gate_manifest_test.dart:597-601` gives.
///
/// **Why the clause cannot be machine-checked against the catalogue.** Gate A
/// asserts that each deviation's clause is a substring of its row's
/// `verbatimText`, which works because the catalogue text is embedded in
/// `f_row_registry.dart`. §7.8 lives in `relay-websocket-notes.md`, which is
/// **not in the repository** — it is a working document on the author's
/// machine. So the [SoakDeviation.clause] field *is* the embedded copy, and
/// the floor this file can enforce is that it exists and is not a paraphrase
/// of nothing. Quoting it verbatim is a discipline the reviewer checks, not
/// one a sweep can.
@TestOn('vm')
@Tags(['soak'])
library;

import 'package:test/test.dart';

import 'soak_registry.dart';

/// How many departures from §7.8 this plan seeded, and how many names the
/// checker list is claimed to hold.
///
/// Both are equalities rather than floors, which is where this file differs
/// from gate A's `_declaredDeviations >= 9`. Gate A expected its registry to
/// keep growing through a thirteen-plan phase and wanted only the *shrinking*
/// case caught. Here the growth is enumerated in advance — 11-PLAN-INDEX
/// expects five, six if 11-04's short-arm distribution needs gating, seven if
/// 11-05 deviates the server-side log clause — so an appending plan changes
/// this number in the same commit as its entry, and an entry that arrives
/// without one is a departure nobody declared in the index.
const int _declaredDeviations = 5;

/// Six: the five invariants of §7.8 plus the divergence ledger.
///
/// A seventh would be a finding rather than a breach (11-RESEARCH assumption
/// A10): §7.8 names five properties, and something the soak needs to check
/// that is not one of them is worth a conversation before it is worth a
/// checker.
const int _declaredCheckerNames = 6;

/// The shortest reasoning that can carry an argument, in characters.
///
/// Sixty, which is gate A's convention applied to a different field: an entry
/// too short to argue is an entry nobody argued. The failure mode this catches
/// is not a lazy author, it is a later edit that trims a reasoning down to a
/// label while leaving the entry in place — at which point the registry still
/// has five rows and none of them says anything.
const int _reasoningFloor = 60;

void main() {
  group('the deviations registry', () {
    test('is printed, in full, on every run', () {
      // The print is the deliverable. 11-01's SUMMARY pastes this block
      // verbatim and the milestone audit reads it beside gate A's and gate
      // B's; a registry only ever read by an assertion is a registry nobody
      // reads.
      print('');
      print('soak deviations from relay-websocket-notes.md §7.8 '
          '(${soakDeviations.length} entries)');
      print('');
      for (var i = 0; i < soakDeviations.length; i++) {
        final deviation = soakDeviations[i];
        print('${i + 1}. ${deviation.id}');
        print('   §7.8 says : "${deviation.clause}"');
        print('   instead   : ${deviation.instead}');
        print('   because   : ${deviation.reasoning}');
        print('');
      }

      expect(soakDeviations, isNotEmpty,
          reason: 'the deviations registry is empty, so this run reports that '
              'the soak does exactly what §7.8 says. That has not been true '
              'since the phase was planned: the lane default is 90 s and not '
              '30+ min, and invariant 4 is structural and not a heap '
              'high-water mark');
    });

    test('holds exactly the number of entries this phase declared', () {
      final ids = soakDeviations.map((d) => d.id).toList();
      expect(soakDeviations, hasLength(_declaredDeviations),
          reason: 'soakDeviations holds ${soakDeviations.length} entries and '
              'this phase declares $_declaredDeviations. The entries present '
              'are $ids. A plan that appends a deviation raises this number in '
              'the same commit; a deviation that disappears is a promise the '
              'soak quietly widened, and this count is the only place either '
              'shows — every other arm in this file derives both of its sides '
              'from the list itself');
    });

    test('still holds all five day-one departures, by id', () {
      // Written out rather than derived, and it is the arm that makes a
      // deletion *legible*. The count above catches that something went
      // missing; a bare count cannot say what, because the list it would name
      // it from is the list that lost it. These five ids are the second copy.
      expect(
          soakDeviations.map((d) => d.id),
          containsAll(<String>[
            'the 90-second default',
            'invariant 4 is asserted structurally; RSS is journalled and never '
                'asserted',
            'invariant 2 reconciles continuously against a test-only '
                'plant-side ledger',
            'the full arm is judged on Ubuntu only',
            'no docker-compose integration tier',
          ]),
          reason: 'one of the five departures 11-01 seeded is no longer in '
              'soakDeviations — the ids present are '
              '${soakDeviations.map((d) => d.id).toList()}. Every one of the '
              'five is a thing the soak does differently from §7.8, so an '
              'entry that disappears does not make the soak match the '
              'catalogue, it makes the mismatch undocumented');
    });

    test('every entry quotes a clause and argues for its replacement', () {
      final emptyClause = [
        for (final deviation in soakDeviations)
          if (deviation.clause.trim().isEmpty) deviation.id,
      ];
      expect(emptyClause, isEmpty,
          reason: 'these deviations name no §7.8 clause: $emptyClause. An '
              'entry without the catalogue text it departs from cannot be '
              'checked against the catalogue by anybody, which is the only '
              'thing an entry is for — and §7.8 is not in this repository, so '
              'the quoted copy is the only copy a reader has');

      final emptyInstead = [
        for (final deviation in soakDeviations)
          if (deviation.instead.trim().isEmpty) deviation.id,
      ];
      expect(emptyInstead, isEmpty,
          reason: 'these deviations do not say what the soak does instead: '
              '$emptyInstead. Four of the five departures are numbers, and a '
              'departure whose replacement number is not written down is a '
              'number nobody can check');

      final tooShort = [
        for (final deviation in soakDeviations)
          if (deviation.reasoning.length < _reasoningFloor)
            '${deviation.id} (${deviation.reasoning.length} chars)',
      ];
      expect(tooShort, isEmpty,
          reason: 'these deviations reason in fewer than $_reasoningFloor '
              'characters: $tooShort. An entry too short to argue is an entry '
              'nobody argued, and the failure this floor catches is a later '
              'edit that trims a reasoning to a label while leaving the row in '
              'place — five entries, none of which says anything');
    });

    test('no entry is declared twice', () {
      final seen = <String>{};
      final duplicated = [
        for (final deviation in soakDeviations)
          if (!seen.add('${deviation.id}|${deviation.clause}')) deviation.id,
      ];
      expect(duplicated, isEmpty,
          reason: 'these deviation ids appear more than once with the same '
              'clause: $duplicated. Two entries for one departure make the '
              'count agree with the declaration while covering one fewer '
              'thing than it claims. Two entries against the SAME clause with '
              'DIFFERENT ids are legitimate and deliberate — the heap clause '
              'is departed from twice, once for what is asserted and once for '
              'where it is judged');
    });
  });

  group('the checker names', () {
    test('are exactly the six this phase declared, all distinct', () {
      expect(declaredCheckers, hasLength(_declaredCheckerNames),
          reason: 'declaredCheckers holds ${declaredCheckers.length} names and '
              'this phase declares $_declaredCheckerNames — the five §7.8 '
              'invariants plus the divergence ledger. A sixth invariant is a '
              'finding worth a conversation, not a name added to a list; a '
              'missing one is a checker nobody will notice never registered, '
              'because an unregistered name prints as pending and an absent '
              'name prints as nothing at all');

      expect(declaredCheckers.toSet(), hasLength(_declaredCheckerNames),
          reason: 'declaredCheckers holds a duplicate: $declaredCheckers. The '
              'registration audit is keyed by name, so two checkers sharing '
              'one name would share one slot and the second would silently '
              'replace the first');
    });

    test('name the five invariants of §7.8 and the ledger', () {
      // Written out rather than derived, for the same reason the counts are:
      // a renamed constant that is still in the list passes every other arm
      // in this group.
      expect(
          declaredCheckers,
          containsAll(<String>[
            'freshnessHonesty',
            'terminalStateWrites',
            'eventualResync',
            'boundedMemory',
            'boundedLogs',
            'divergenceLedger',
          ]),
          reason: 'declaredCheckers is $declaredCheckers, which is missing one '
              'of the six names 11-04, 11-05 and 11-06 register against. A '
              'checker registering under a name this list does not hold fails '
              'the registration audit, so a rename here silently breaks a '
              'later plan rather than this one');
    });

    test('no name is empty or padded', () {
      final malformed = [
        for (final name in declaredCheckers)
          if (name.trim() != name || name.isEmpty) '"$name"',
      ];
      expect(malformed, isEmpty,
          reason: 'these checker names are empty or carry surrounding '
              'whitespace: $malformed. The names are map keys in the '
              'registration audit and in the per-checker verdict block, and a '
              'padded key reads identically to its unpadded twin in a run '
              'report while failing every lookup');
    });
  });
}

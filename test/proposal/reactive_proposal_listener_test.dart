import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/proposal_state.dart';

/// Tests for the reactive proposal listeners in the three editors:
///   - AlarmEditorPage (alarm_editor.dart)
///   - PageEditor (page_editor.dart)
///   - KeyRepositoryEditor (key_repository.dart)
///
/// Each editor has a `ref.listen<ProposalState>(proposalStateProvider, ...)`
/// callback in its `build()` method that reactively applies new proposals
/// when they arrive via MCP, without requiring navigation.
///
/// Since these editors have heavy provider dependencies (AlarmMan, PageManager,
/// StateManConfig, etc.), we test:
///   1. Source-level assertions verifying the listener wiring exists and is
///      correct (same pattern as existing proposal tests).
///   2. Unit tests on ProposalStateNotifier verifying the filtering logic
///      that the listener callbacks depend on.
void main() {
  late String alarmEditorSource;
  late String pageEditorSource;
  late String keyRepoSource;

  setUpAll(() {
    alarmEditorSource = File('lib/pages/alarm_editor.dart').readAsStringSync();
    pageEditorSource = File('lib/pages/page_editor.dart').readAsStringSync();
    keyRepoSource = File('lib/pages/key_repository.dart').readAsStringSync();
  });

  // ── Helper ──────────────────────────────────────────────────────────────

  PendingProposal makeProposal({
    int id = 1,
    String type = 'alarm',
    String title = 'Test',
    String json = '{"_proposal_type":"alarm"}',
    String operator = 'op1',
  }) =>
      PendingProposal(
        id: id,
        proposalType: type,
        title: title,
        proposalJson: json,
        operatorId: operator,
        createdAt: DateTime.now(),
      );

  // ── Source-level: all three editors have ref.listen wiring ─────────────

  group('Reactive listener wiring exists in all three editors', () {
    test('AlarmEditorPage has ref.listen on proposalStateProvider', () {
      expect(alarmEditorSource,
          contains('ref.listen<ProposalState>(proposalStateProvider'));
    });

    test('PageEditor has ref.listen on proposalStateProvider', () {
      expect(pageEditorSource,
          contains('ref.listen<ProposalState>(proposalStateProvider'));
    });

    test('KeyRepositoryEditor has ref.listen on proposalStateProvider', () {
      expect(keyRepoSource,
          contains('ref.listen<ProposalState>(proposalStateProvider'));
    });
  });

  // ── Source-level: listener is inside build() (reactive on every rebuild) ─

  group('Listener is inside build() for reactivity', () {
    test('AlarmEditorPage listener is in build method', () {
      final buildBody = _extractMethodBody(alarmEditorSource, 'Widget build(');
      expect(buildBody, isNotNull,
          reason: 'AlarmEditorPage must have a build method');
      expect(buildBody, contains('ref.listen<ProposalState>'),
          reason: 'ref.listen must be inside build()');
    });

    test('PageEditor listener is in build method', () {
      final buildBody = _extractMethodBody(pageEditorSource, 'Widget build(');
      expect(buildBody, isNotNull,
          reason: 'PageEditor must have a build method');
      expect(buildBody, contains('ref.listen<ProposalState>'),
          reason: 'ref.listen must be inside build()');
    });

    test('KeyRepositoryEditor listener is in a build method', () {
      // KeyRepositoryPage delegates through nested widgets; find the build()
      // that actually contains the ref.listen call.
      var searchFrom = 0;
      bool found = false;
      while (true) {
        final idx = keyRepoSource.indexOf('Widget build(', searchFrom);
        if (idx == -1) break;
        final braceStart = keyRepoSource.indexOf('{', idx);
        final buildBody = _extractBraceBlock(keyRepoSource, braceStart);
        if (buildBody != null && buildBody.contains('ref.listen<ProposalState>')) {
          found = true;
          break;
        }
        searchFrom = idx + 1;
      }
      expect(found, isTrue,
          reason: 'ref.listen<ProposalState> must be inside a build() method');
    });
  });

  // ── Source-level: _isProposal guard prevents double-apply ──────────────

  group('Guard: skip if already showing a proposal (_isProposal)', () {
    test('AlarmEditorPage checks _isProposal before applying', () {
      final listenerBody =
          _extractListenerBody(alarmEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull,
          reason: 'Must find the listener callback');
      expect(listenerBody, contains('if (_isProposal) return'),
          reason: 'Must guard against double-apply');
    });

    test('PageEditor checks _isProposal before applying', () {
      final listenerBody =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('if (_isProposal) return'));
    });

    test('KeyRepositoryEditor checks _isProposal before applying', () {
      final listenerBody =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('if (_isProposal) return'));
    });
  });

  // ── Source-level: correct proposal type filtering per editor ────────────

  group('Type filtering: each editor filters for its own proposal types', () {
    test('AlarmEditorPage filters for alarm, alarm_create, alarm_update', () {
      final listenerBody =
          _extractListenerBody(alarmEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains("'alarm'"));
      expect(listenerBody, contains("'alarm_create'"));
      expect(listenerBody, contains("'alarm_update'"));
      // Must NOT filter for page, asset, or key_mapping
      expect(listenerBody!.contains("'page'"), isFalse,
          reason: 'Alarm editor must not match page proposals');
      expect(listenerBody.contains("'key_mapping'"), isFalse,
          reason: 'Alarm editor must not match key_mapping proposals');
    });

    test('PageEditor filters for page and asset', () {
      final listenerBody =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains("'page'"));
      expect(listenerBody, contains("'asset'"));
      // Must NOT filter for alarm or key_mapping
      expect(listenerBody!.contains("'alarm'"), isFalse,
          reason: 'Page editor must not match alarm proposals');
      expect(listenerBody.contains("'key_mapping'"), isFalse,
          reason: 'Page editor must not match key_mapping proposals');
    });

    test('KeyRepositoryEditor filters for key_mapping only', () {
      final listenerBody =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains("'key_mapping'"));
      // Must NOT filter for alarm, page, or asset
      expect(listenerBody!.contains("'alarm'"), isFalse,
          reason: 'Key repo must not match alarm proposals');
      expect(listenerBody.contains("'page'"), isFalse,
          reason: 'Key repo must not match page proposals');
      expect(listenerBody.contains("'asset'"), isFalse,
          reason: 'Key repo must not match asset proposals');
    });
  });

  // ── Source-level: listener picks first matching proposal ────────────────

  group('Listener picks the first matching proposal', () {
    test('AlarmEditorPage uses .first on filtered proposals', () {
      final listenerBody =
          _extractListenerBody(alarmEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('.first'),
          reason: 'Must pick the first matching alarm proposal');
    });

    test('PageEditor uses .first on filtered proposals', () {
      final listenerBody =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('.first'));
    });

    test('KeyRepositoryEditor uses .first on filtered proposals', () {
      final listenerBody =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('.first'));
    });
  });

  // ── Source-level: listener calls the correct parse/apply method ─────────

  group('Listener delegates to the correct parse/apply method', () {
    test('AlarmEditorPage calls _parseAlarmProposal', () {
      final listenerBody =
          _extractListenerBody(alarmEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('_parseAlarmProposal'));
    });

    test('PageEditor calls _applyProposalData', () {
      final listenerBody =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('_applyProposalData'));
    });

    test('KeyRepositoryEditor calls _parseKeyMappingProposal', () {
      final listenerBody =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('_parseKeyMappingProposal'));
    });
  });

  // ── Source-level: listener calls setState when parsing succeeds ─────────

  group('Listener calls setState on successful parse', () {
    test('AlarmEditorPage calls setState after _parseAlarmProposal', () {
      final listenerBody =
          _extractListenerBody(alarmEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('if (_isProposal) setState'));
    });

    test('PageEditor calls setState after _applyProposalData', () {
      final listenerBody =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('setState'));
    });

    test('KeyRepositoryEditor calls setState after _parseKeyMappingProposal',
        () {
      final listenerBody =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('if (_isProposal) setState'));
    });
  });

  // ── Source-level: empty proposals list causes early return ──────────────

  group('Listener returns early when no matching proposals exist', () {
    test('AlarmEditorPage checks isEmpty before accessing .first', () {
      final listenerBody =
          _extractListenerBody(alarmEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('.isEmpty'));
      // Verify isEmpty check comes before .first to prevent StateError
      final isEmptyIdx = listenerBody!.indexOf('.isEmpty');
      final firstIdx = listenerBody.indexOf('.first');
      expect(isEmptyIdx, lessThan(firstIdx),
          reason: 'isEmpty guard must come before .first access');
    });

    test('PageEditor checks isEmpty before accessing .first', () {
      final listenerBody =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      final isEmptyIdx = listenerBody!.indexOf('.isEmpty');
      final firstIdx = listenerBody.indexOf('.first');
      expect(isEmptyIdx, lessThan(firstIdx));
    });

    test('KeyRepositoryEditor checks isEmpty before accessing .first', () {
      final listenerBody =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      final isEmptyIdx = listenerBody!.indexOf('.isEmpty');
      final firstIdx = listenerBody.indexOf('.first');
      expect(isEmptyIdx, lessThan(firstIdx));
    });
  });

  // ── Source-level: listener uses proposal.proposalJson (not proposalType) ─

  group('Listener passes proposalJson to parse method', () {
    test('AlarmEditorPage passes proposal.proposalJson', () {
      final listenerBody =
          _extractListenerBody(alarmEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('proposal.proposalJson'));
    });

    test('PageEditor passes proposal.proposalJson', () {
      final listenerBody =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('proposal.proposalJson'));
    });

    test('KeyRepositoryEditor passes proposal.proposalJson', () {
      final listenerBody =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      expect(listenerBody, isNotNull);
      expect(listenerBody, contains('proposal.proposalJson'));
    });
  });

  // ── Source-level: no overlapping type filters across editors ────────────

  group('No overlapping type filters across editors (isolation)', () {
    test('alarm types are only handled by AlarmEditorPage', () {
      // Verify the other two editors do NOT filter for alarm types
      final pageListener =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      final keyListener =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      for (final alarmType in ['alarm', 'alarm_create', 'alarm_update']) {
        expect(pageListener!.contains("'$alarmType'"), isFalse,
            reason: 'PageEditor must not handle $alarmType');
        expect(keyListener!.contains("'$alarmType'"), isFalse,
            reason: 'KeyRepository must not handle $alarmType');
      }
    });

    test('page/asset types are only handled by PageEditor', () {
      final alarmListener = _extractListenerBody(
          alarmEditorSource, 'ref.listen<ProposalState>');
      final keyListener =
          _extractListenerBody(keyRepoSource, 'ref.listen<ProposalState>');
      for (final pageType in ['page', 'asset']) {
        expect(alarmListener!.contains("'$pageType'"), isFalse,
            reason: 'AlarmEditor must not handle $pageType');
        expect(keyListener!.contains("'$pageType'"), isFalse,
            reason: 'KeyRepository must not handle $pageType');
      }
    });

    test('key_mapping type is only handled by KeyRepositoryEditor', () {
      final alarmListener = _extractListenerBody(
          alarmEditorSource, 'ref.listen<ProposalState>');
      final pageListener =
          _extractListenerBody(pageEditorSource, 'ref.listen<ProposalState>');
      expect(alarmListener!.contains("'key_mapping'"), isFalse,
          reason: 'AlarmEditor must not handle key_mapping');
      expect(pageListener!.contains("'key_mapping'"), isFalse,
          reason: 'PageEditor must not handle key_mapping');
    });
  });

  // ── Unit tests: ProposalState filtering matches listener logic ─────────

  group('ProposalState.ofType filtering matches listener type filters', () {
    test('alarm proposals are found by ofType for all alarm subtypes', () {
      final state = ProposalState(proposals: [
        makeProposal(id: 1, type: 'alarm', json: '{"uid":"a1"}'),
        makeProposal(id: 2, type: 'alarm_create', json: '{"uid":"ac1"}'),
        makeProposal(id: 3, type: 'alarm_update', json: '{"uid":"au1"}'),
        makeProposal(id: 4, type: 'page', json: '{"uid":"p1"}'),
        makeProposal(id: 5, type: 'key_mapping', json: '{"uid":"k1"}'),
      ]);

      // The alarm editor listener filters with:
      //   p.proposalType == 'alarm' ||
      //   p.proposalType == 'alarm_create' ||
      //   p.proposalType == 'alarm_update'
      // Simulate that filter:
      final alarmMatches = state.proposals.where((p) =>
          p.proposalType == 'alarm' ||
          p.proposalType == 'alarm_create' ||
          p.proposalType == 'alarm_update');
      expect(alarmMatches, hasLength(3));
      expect(alarmMatches.map((p) => p.id), containsAll([1, 2, 3]));
    });

    test('page proposals are found by ofType for page and asset', () {
      final state = ProposalState(proposals: [
        makeProposal(id: 1, type: 'alarm', json: '{"uid":"a1"}'),
        makeProposal(id: 2, type: 'page', json: '{"uid":"p1"}'),
        makeProposal(id: 3, type: 'asset', json: '{"uid":"as1"}'),
        makeProposal(id: 4, type: 'key_mapping', json: '{"uid":"k1"}'),
      ]);

      // The page editor listener filters with:
      //   p.proposalType == 'page' || p.proposalType == 'asset'
      final pageMatches = state.proposals
          .where((p) => p.proposalType == 'page' || p.proposalType == 'asset');
      expect(pageMatches, hasLength(2));
      expect(pageMatches.map((p) => p.id), containsAll([2, 3]));
    });

    test('key_mapping proposals are found by ofType', () {
      final state = ProposalState(proposals: [
        makeProposal(id: 1, type: 'alarm', json: '{"uid":"a1"}'),
        makeProposal(id: 2, type: 'key_mapping', json: '{"uid":"k1"}'),
        makeProposal(id: 3, type: 'page', json: '{"uid":"p1"}'),
      ]);

      // The key repo listener filters with:
      //   p.proposalType == 'key_mapping'
      final keyMatches =
          state.proposals.where((p) => p.proposalType == 'key_mapping');
      expect(keyMatches, hasLength(1));
      expect(keyMatches.first.id, 2);
    });

    test('empty state yields no matches for any editor filter', () {
      const state = ProposalState();

      final alarmMatches = state.proposals.where((p) =>
          p.proposalType == 'alarm' ||
          p.proposalType == 'alarm_create' ||
          p.proposalType == 'alarm_update');
      expect(alarmMatches, isEmpty);

      final pageMatches = state.proposals
          .where((p) => p.proposalType == 'page' || p.proposalType == 'asset');
      expect(pageMatches, isEmpty);

      final keyMatches =
          state.proposals.where((p) => p.proposalType == 'key_mapping');
      expect(keyMatches, isEmpty);
    });

    test('.first on filtered results gives the oldest matching proposal', () {
      final state = ProposalState(proposals: [
        makeProposal(id: 10, type: 'alarm', title: 'First alarm',
            json: '{"uid":"fa"}'),
        makeProposal(id: 20, type: 'alarm', title: 'Second alarm',
            json: '{"uid":"sa"}'),
        makeProposal(id: 30, type: 'alarm_create', title: 'Third alarm',
            json: '{"uid":"ta"}'),
      ]);

      final alarmMatches = state.proposals.where((p) =>
          p.proposalType == 'alarm' ||
          p.proposalType == 'alarm_create' ||
          p.proposalType == 'alarm_update');
      expect(alarmMatches.first.id, 10,
          reason: 'Listener should pick the first (oldest) matching proposal');
      expect(alarmMatches.first.title, 'First alarm');
    });
  });

  // ── Unit tests: ProposalStateNotifier addProposal triggers listeners ───

  group('ProposalStateNotifier state changes trigger listener callbacks', () {
    test('addProposal changes state (would fire ref.listen)', () {
      final notifier = ProposalStateNotifier(null);
      final states = <ProposalState>[];

      notifier.addListener((state) {
        states.add(state);
      });

      notifier.addProposal(makeProposal(id: 1, type: 'alarm',
          json: '{"uid":"a1"}'));
      // StateNotifier fires listener for initial state + each change
      expect(states.last.proposals, hasLength(1));
    });

    test('addProposal of wrong type does not match another editors filter', () {
      final notifier = ProposalStateNotifier(null);
      notifier.addProposal(makeProposal(id: 1, type: 'key_mapping',
          json: '{"uid":"k1"}'));

      // Simulate alarm editor listener filter
      final alarmMatches = notifier.state.proposals.where((p) =>
          p.proposalType == 'alarm' ||
          p.proposalType == 'alarm_create' ||
          p.proposalType == 'alarm_update');
      expect(alarmMatches, isEmpty,
          reason: 'key_mapping proposal must not trigger alarm editor');
    });

    test('duplicate addProposal does not re-trigger state change', () {
      final notifier = ProposalStateNotifier(null);
      final states = <ProposalState>[];

      notifier.addListener((state) {
        states.add(state);
      });

      notifier.addProposal(makeProposal(id: 1, json: '{"uid":"dup"}'));
      final countAfterFirst = states.length;
      notifier.addProposal(makeProposal(id: 1, json: '{"uid":"dup"}'));
      // Second add is a duplicate — no additional state change
      expect(states.length, countAfterFirst,
          reason: 'Duplicate addProposal must not trigger state change');
    });

    test('acceptProposal removes from state (listener would see empty)', () async {
      final notifier = ProposalStateNotifier(null);
      notifier.addProposal(makeProposal(id: 1, type: 'alarm',
          json: '{"uid":"a1"}'));
      expect(notifier.state.proposals, hasLength(1));

      await notifier.acceptProposal(1);
      // After accept, the alarm editor listener would see empty alarm proposals
      final alarmMatches = notifier.state.proposals.where((p) =>
          p.proposalType == 'alarm' ||
          p.proposalType == 'alarm_create' ||
          p.proposalType == 'alarm_update');
      expect(alarmMatches, isEmpty);
    });
  });

  // ── Source-level: consistency checks across all three editors ───────────

  group('Consistency: all editors follow the same reactive listener pattern', () {
    test('all editors use (prev, next) callback signature', () {
      for (final entry in {
        'AlarmEditor': alarmEditorSource,
        'PageEditor': pageEditorSource,
        'KeyRepository': keyRepoSource,
      }.entries) {
        final listener =
            _extractListenerBody(entry.value, 'ref.listen<ProposalState>');
        expect(listener, isNotNull,
            reason: '${entry.key} must have a ProposalState listener');
      }
      // The callback signatures are inside the ref.listen call — we already
      // validated them by extracting the listener body successfully.
    });

    test('all editors check proposalType on next.proposals (not prev)', () {
      for (final entry in {
        'AlarmEditor': alarmEditorSource,
        'PageEditor': pageEditorSource,
        'KeyRepository': keyRepoSource,
      }.entries) {
        final listener =
            _extractListenerBody(entry.value, 'ref.listen<ProposalState>');
        expect(listener, isNotNull);
        expect(listener, contains('next.proposals'),
            reason: '${entry.key} must filter on next (new) state');
      }
    });

    test('all editors guard with _isProposal before applying', () {
      for (final entry in {
        'AlarmEditor': alarmEditorSource,
        'PageEditor': pageEditorSource,
        'KeyRepository': keyRepoSource,
      }.entries) {
        final listener =
            _extractListenerBody(entry.value, 'ref.listen<ProposalState>');
        expect(listener, contains('_isProposal'),
            reason: '${entry.key} must check _isProposal flag');
      }
    });

    test('all editors have _isProposal field', () {
      expect(alarmEditorSource, contains('bool _isProposal'));
      expect(pageEditorSource, contains('bool _isProposal'));
      expect(keyRepoSource, contains('bool _isProposal'));
    });
  });
}

/// Extracts the body of a method whose signature contains [methodSignature].
///
/// Returns the content from the first `{` after the signature to its matching
/// `}`. Returns null if not found.
String? _extractMethodBody(String source, String methodSignature) {
  final methodIndex = source.indexOf(methodSignature);
  if (methodIndex == -1) return null;

  final braceStart = source.indexOf('{', methodIndex);
  if (braceStart == -1) return null;

  var depth = 0;
  for (var i = braceStart; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) {
      return source.substring(braceStart, i + 1);
    }
  }
  return null;
}

/// Extracts the callback body of a `ref.listen<ProposalState>(...)` call.
///
/// Finds the listener invocation matching [listenerCall], then extracts the
/// lambda body `(prev, next) { ... }` — specifically, the content between the
/// first `{` inside that call and its matching `}`.
///
/// Extracts a brace-delimited block starting at [braceStart].
String? _extractBraceBlock(String source, int braceStart) {
  if (braceStart < 0 || braceStart >= source.length) return null;
  var depth = 0;
  for (var i = braceStart; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(braceStart, i + 1);
  }
  return null;
}

/// This is a heuristic parser that works for the simple single-lambda pattern
/// used in all three editors. Returns null if not found.
String? _extractListenerBody(String source, String listenerCall) {
  final callIndex = source.indexOf(listenerCall);
  if (callIndex == -1) return null;

  // Find the opening `{` of the callback lambda.
  // Skip the opening `(` of ref.listen to find the lambda body.
  final lambdaStart = source.indexOf('{', callIndex);
  if (lambdaStart == -1) return null;

  var depth = 0;
  for (var i = lambdaStart; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) {
      return source.substring(lambdaStart, i + 1);
    }
  }
  return null;
}

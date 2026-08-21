import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level assertions for key_repository.dart proposal handling.
///
/// KeyRepositoryPage depends on the preferencesProvider, stateManProvider and
/// databaseProvider chains, which is why these are source assertions rather
/// than widget tests.
///
/// The shape they pin changed on 2026-08-18. Proposals used to be staged one
/// at a time and accepted from an inline amber bar inside this page. An MCP
/// client fires create_key_mapping one call per mapping, so a batch of 28
/// arrived as 28 proposals and cost 28 reviews and 28 saves — and the inline
/// bar was a second place to act on a proposal, competing with the black
/// banner. Both are gone: the page stages the whole queue and publishes
/// commit/discard to the banner, which is now the only place to accept.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/pages/key_repository.dart').readAsStringSync();
  });

  group('KeyRepositoryPage proposal support', () {
    test('has proposalData parameter', () {
      expect(source, contains('proposalData'));
    });

    test('passes proposalData down to KeyRepositoryContent', () {
      expect(source, contains('KeyRepositoryContent(proposalData:'));
    });
  });

  group('proposals are staged as a batch, not one at a time', () {
    test('stages every pending key_mapping proposal', () {
      expect(source, contains('_stageKeyMappingProposals'));
    });

    test('keeps a list of staged mappings and their proposal ids', () {
      expect(source, contains('_proposedMappings'));
      expect(source, contains('_proposalIds'));
    });

    test('_isProposal is derived from the batch, not a separate flag', () {
      expect(source, contains('bool get _isProposal => _proposedMappings.isNotEmpty'));
    });

    test('skips ids already staged so re-entry cannot double-apply', () {
      expect(source, contains('_proposalIds.contains(p.id)'));
    });

    test('only accepts key_mapping proposals', () {
      expect(source, contains("p.proposalType != 'key_mapping'"));
      expect(source, contains("decoded['_proposal_type'] != 'key_mapping'"));
    });

    test('tolerates a malformed proposal without dropping the batch', () {
      expect(source, contains('jsonDecode(p.proposalJson)'));
      expect(source, contains('is! Map<String, dynamic>'));
    });
  });

  group('the banner owns accept/reject — nothing inline', () {
    test('publishes commit and discard to the banner', () {
      expect(source, contains('proposalCommitProvider'));
      expect(source, contains('proposalDiscardProvider'));
      expect(source, contains('_commitProposals'));
      expect(source, contains('_discardProposals'));
    });

    test('no inline Accept/Reject buttons remain in this page', () {
      // The amber bar carried an ElevatedButton 'Accept' and an
      // OutlinedButton 'Reject'. Two competing controls meant an operator
      // could accept in one place while the other still showed it pending.
      expect(source, isNot(contains("child: const Text('Accept')")));
      expect(source, isNot(contains("child: const Text('Reject')")));
    });

    test('clears the callbacks once the batch is resolved', () {
      // Cleared through the stored slots rather than `ref.read(...)`: these
      // run from the banner, which outlives this section, and `ref` throws
      // once the widget is disposed. See the disposal group below.
      expect(
        RegExp(r'_commitSlot\?\.state = null')
            .allMatches(source)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'both commit and discard must clear the banner callbacks',
      );
    });
  });

  group('commit applies before it accepts', () {
    test('saves the mappings, then marks the proposals accepted', () {
      final commit = source.substring(source.indexOf('_commitProposals'));
      final save = commit.indexOf('_saveKeyMappings()');
      final accept = commit.indexOf('acceptProposal');
      expect(save, greaterThan(-1));
      expect(accept, greaterThan(-1));
      expect(save, lessThan(accept),
          reason: 'acceptProposal marks the row accepted in the database, so '
              'doing it before the save would lose the mapping if the save '
              'failed');
    });

    test('awaits each accept rather than firing and forgetting', () {
      expect(source, contains('await notifier.acceptProposal(id)'));
    });

    test('applies the proposed opcua node onto a real KeyMappingEntry', () {
      expect(source, contains('OpcUANodeConfig.fromJson(opcuaNode)'));
      expect(source, contains('_keyMappings!.nodes[key] = entry'));
    });
  });

  group('the proposed mappings are still shown inline', () {
    test('highlighted rows remain — that is why you navigate here', () {
      expect(source, contains('proposalDecoration()'));
      expect(source, contains('ProposalBadge()'));
    });

    test('the list is bounded so a large batch cannot fill the page', () {
      expect(source, contains('maxHeight: 160'));
    });
  });

  group('a proposal merges onto the existing entry', () {
    // update_key_mapping used to build a fresh KeyMappingEntry and assign only
    // opcuaNode, so proposing a new node id silently discarded that key's
    // collect settings -- its retention and sample interval -- along with any
    // m2400/modbus/io binding. The 28 sensor fault mappings were written that
    // way. A proposal states what changes; the rest has to survive.
    test('starts from the entry already stored under the key', () {
      expect(source,
          contains('_keyMappings!.nodes[key] ?? KeyMappingEntry()'));
    });

    test('does not construct a bare entry and overwrite the slot', () {
      expect(source, isNot(contains('final entry = KeyMappingEntry();')));
    });

    test('applies a collect block when the proposal carries one', () {
      expect(source, contains('CollectEntry.fromJson(collect)'));
    });

    test('keys the collect entry to the mapping it belongs to', () {
      expect(source, contains('..key = key'));
    });

    test('an explicit null collect turns collection off', () {
      expect(source, contains("m.containsKey('collect')"));
      expect(source, contains('entry.collect = null'));
    });
  });

  group('a delete proposal removes the key', () {
    test('recognises the delete op', () {
      expect(source, contains("m['_op'] == 'delete'"));
    });

    test('removes through _removeKey so derived caches are dropped too', () {
      expect(source, contains('_removeKey(key)'));
    });

    test('a delete carries no fields to merge', () {
      final applyLoop = source.substring(source.indexOf('for (final m in _proposedMappings)'));
      final deleteAt = applyLoop.indexOf("m['_op'] == 'delete'");
      final mergeAt = applyLoop.indexOf('?? KeyMappingEntry()');
      expect(deleteAt, greaterThan(-1));
      expect(mergeAt, greaterThan(deleteAt),
          reason: 'the delete branch must return before any merge');
    });
  });

  // On 2026-08-21 a batch of 16 mappings was accepted. Every mapping was
  // written to preferences, and not one proposal was marked accepted, so the
  // whole batch came back on the next load and could not be cleared.
  //
  // Accepting rebuilds this subtree, so by the time the save returned, the
  // section was deactivated. `mounted` is still true then, but an ancestor
  // lookup is not safe: the success snackbar threw, the catch block threw
  // again on its own snackbar, and that escaped `_saveKeyMappings` --
  // stopping `_commitProposals` before `acceptProposal` ever ran.
  group('a snackbar cannot cost the accept step', () {
    String saveBody() {
      final start = source.indexOf('Future<bool> _saveKeyMappings()');
      expect(start, greaterThan(-1),
          reason: '_saveKeyMappings must report whether the save landed');
      return source.substring(start, source.indexOf('\n  }', start));
    }

    test('the messenger is resolved before the first await', () {
      final body = saveBody();
      final captureAt = body.indexOf('ScaffoldMessenger.maybeOf(context)');
      final awaitAt = body.indexOf('await ');
      expect(captureAt, greaterThan(-1));
      expect(awaitAt, greaterThan(captureAt),
          reason: 'after an await the ancestor lookup can throw');
    });

    test('the save never looks an ancestor up unguarded', () {
      // `.of(context)` throws on a dead element; the handles taken while the
      // section was alive are what the banner path relies on.
      final body = saveBody();
      expect(body, isNot(contains('ScaffoldMessenger.of(context)')));
      expect(body, contains('_messengerHandle ??'));
      expect(body, contains('_errorColourHandle ??'));
    });

    test('the banner path never reaches for ref', () {
      // `ref` throws outright once the widget is disposed, which is what made
      // Reject fail as well as Accept.
      final body = saveBody();
      final prefsAt = body.indexOf('_prefsHandle ??');
      expect(prefsAt, greaterThan(-1),
          reason: 'the save must prefer the captured preferences handle');
      for (final fn in ['_commitProposals', '_discardProposals']) {
        final start = source.indexOf('Future<void> $fn()');
        expect(start, greaterThan(-1));
        final body = source.substring(start, source.indexOf('\n  }', start));
        expect(body, isNot(contains('ref.read')),
            reason: '$fn runs from the banner, after this state may be gone');
      }
    });

    test('the handles are taken where ref and context are known good', () {
      final start = source.indexOf('void _publishProposalCallbacks()');
      final body = source.substring(start, source.indexOf('\n  }', start));
      expect(body, contains('_proposals = ref.read(proposalStateProvider.notifier)'));
      expect(body, contains('_prefsHandle = ref.read(preferencesProvider.future)'));
      expect(body, contains('_messengerHandle = ScaffoldMessenger.maybeOf(context)'));
    });

    test('the save reports success rather than throwing at the caller', () {
      final body = saveBody();
      expect(body, contains('return true'));
      expect(body, contains('return false'));
    });

    test('proposals are only accepted when the mappings actually saved', () {
      expect(source, contains('if (!await _saveKeyMappings()) return;'));
      final commit = source.substring(source.indexOf('_commitProposals'));
      final saveAt = commit.indexOf('_saveKeyMappings()');
      final acceptAt = commit.indexOf('acceptProposal');
      expect(saveAt, greaterThan(-1));
      expect(acceptAt, greaterThan(saveAt),
          reason: 'a proposal must not be marked accepted before its save');
    });
  });
}

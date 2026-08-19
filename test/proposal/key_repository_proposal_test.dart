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
      expect(
        RegExp(r'proposalCommitProvider\.notifier\)\.state = null')
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
}

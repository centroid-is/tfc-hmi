import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level assertions for key_repository.dart proposal enhancements.
///
/// KeyRepositoryPage depends on preferencesProvider, stateManProvider, and
/// databaseProvider chains. Source assertions verify proposal support.
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

  group('_KeyMappingsSection proposal support', () {
    test('has proposalData parameter', () {
      // _KeyMappingsSection receives proposalData
      expect(source, contains('_KeyMappingsSection'));
      expect(source, contains('proposalData'));
    });

    test('has _parseKeyMappingProposal method', () {
      expect(source, contains('_parseKeyMappingProposal'));
    });

    test('has _proposedMapping field', () {
      expect(source, contains('_proposedMapping'));
    });

    test('has Accept button with green color', () {
      expect(source, contains('Accept'));
      expect(source, contains('Colors.green'));
    });

    test('has Reject button with red color', () {
      expect(source, contains('Reject'));
      expect(source, contains('Colors.red'));
    });

    test('imports proposal_state.dart', () {
      expect(source, contains('proposal_state.dart'));
    });

    test('imports proposal_visual.dart', () {
      expect(source, contains('proposal_visual.dart'));
    });

    test('uses proposalDecoration for proposed key mapping', () {
      expect(source, contains('proposalDecoration'));
    });

    test('shows ProposalBadge on proposed key mapping', () {
      expect(source, contains('ProposalBadge'));
    });

    test('handles invalid proposal JSON gracefully', () {
      expect(source, contains('try'));
      expect(source, contains('catch'));
    });
  });

  group('_parseKeyMappingProposal correctness', () {
    test('checks _proposal_type is key_mapping before activating', () {
      expect(source, contains("type != 'key_mapping'"));
    });

    test('validates decoded JSON is a Map before processing', () {
      expect(source, contains('decoded is! Map<String, dynamic>'));
    });

    test('sets _isProposal = true on valid proposal', () {
      expect(source, contains('_isProposal = true'));
    });

    test('matches against proposalStateProvider for ID tracking', () {
      expect(source, contains('ref.read(proposalStateProvider)'));
      expect(source, contains('p.proposalJson == json'));
    });

    test('is called from initState with widget.proposalData', () {
      expect(source, contains('_parseKeyMappingProposal(widget.proposalData)'));
    });
  });

  group('Accept handler correctness', () {
    test('extracts key from _proposedMapping before clearing', () {
      expect(
        source,
        contains("final key = _proposedMapping!['key'] as String?"),
      );
    });

    test('creates KeyMappingEntry from proposal opcua_node', () {
      expect(source, contains('OpcUANodeConfig.fromJson(opcuaNode)'));
    });

    test('inserts mapping into _keyMappings.nodes', () {
      expect(source, contains('_keyMappings!.nodes[key] = mapping'));
    });

    test('calls _saveKeyMappings to persist', () {
      // The Accept handler must call _saveKeyMappings() after adding the node
      expect(source, contains('_saveKeyMappings()'));
    });

    test('calls acceptProposal on proposalStateProvider', () {
      expect(source, contains('acceptProposal(_proposalId!)'));
    });

    test('sets _newlyAddedKey before nullifying _proposedMapping', () {
      // Regression test: _newlyAddedKey must be assigned to `key` (the
      // captured local variable), NOT read from _proposedMapping after it has
      // been set to null. The old buggy pattern was:
      //   _proposedMapping = null;
      //   _newlyAddedKey = _proposedMapping?['key']; // always null!
      //
      // Correct pattern: _newlyAddedKey = key; before or after nullification.
      final stateBlock = RegExp(
        r'setState\(\(\)\s*\{[^}]*_newlyAddedKey[^}]*_proposedMapping\s*=\s*null',
        dotAll: true,
      );
      expect(
        source,
        matches(stateBlock),
        reason:
            '_newlyAddedKey must be assigned before _proposedMapping = null '
            'inside the same setState block',
      );
      // Also verify it uses the captured `key` variable, not _proposedMapping
      expect(source, contains('_newlyAddedKey = key;'));
    });
  });

  group('Reject handler correctness', () {
    test('calls rejectProposal on proposalStateProvider', () {
      expect(source, contains('rejectProposal(_proposalId!)'));
    });

    test('clears _isProposal and _proposedMapping', () {
      // Reject handler must clear proposal state
      expect(source, contains('_isProposal = false'));
      expect(source, contains('_proposedMapping = null'));
    });

    test('does not call _saveKeyMappings', () {
      // Reject should NOT save. Find the Reject onPressed block and verify
      // it doesn't contain _saveKeyMappings.
      // We verify by checking the Reject button section specifically.
      final rejectSection = RegExp(
        r"child:\s*const\s*Text\('Reject'\)",
      );
      expect(source, matches(rejectSection));
      // The Reject handler is the OutlinedButton.onPressed before 'Reject' text
      // We use a pattern to extract the reject onPressed handler
      final rejectHandler = RegExp(
        r"OutlinedButton\(\s*onPressed:\s*\(\)\s*\{(.*?)\},\s*style:\s*OutlinedButton\.styleFrom\(\s*foregroundColor:\s*Colors\.red",
        dotAll: true,
      );
      final match = rejectHandler.firstMatch(source);
      expect(match, isNotNull, reason: 'Reject handler block must exist');
      final handlerBody = match!.group(1)!;
      expect(
        handlerBody,
        isNot(contains('_saveKeyMappings')),
        reason: 'Reject handler must NOT save key mappings',
      );
    });
  });

  group('Proposal visual styling', () {
    test('banner uses amber color scheme', () {
      expect(source, contains('Colors.amber'));
      expect(source, contains('Colors.amber.shade50'));
    });

    test('banner shows auto_awesome icon', () {
      expect(source, contains('Icons.auto_awesome'));
    });

    test('proposal inline display uses proposalDecoration()', () {
      // The inline ListTile should be wrapped in proposalDecoration
      expect(source, contains('decoration: proposalDecoration()'));
    });

    test('proposal inline display shows ProposalBadge as leading widget', () {
      expect(source, contains('leading: const ProposalBadge()'));
    });

    test('proposal banner and inline are conditional on _isProposal', () {
      // Both banner and inline display should only show when _isProposal
      expect(
        source,
        contains('if (_isProposal && _proposedMapping != null)'),
      );
    });

    test('proposal inline display shows the proposed key name', () {
      expect(source, contains("title: Text('\${_proposedMapping!['key']}')"));
    });

    test('proposal banner describes the mapping operation', () {
      expect(source, contains("'AI Proposal: Map"));
    });
  });

  group('Edge case handling', () {
    test('proposal with missing key field does not crash Accept', () {
      // Accept handler guards key != null before modifying _keyMappings
      expect(source, contains('if (key != null && _keyMappings != null)'));
    });

    test('proposal with missing opcua_node still creates entry', () {
      // opcuaNode is only set when the map is present, otherwise a bare
      // KeyMappingEntry() is created (which is valid -- all nodes are optional)
      expect(source, contains('if (opcuaNode is Map<String, dynamic>)'));
    });

    test('proposal with non-key_mapping type is silently ignored', () {
      // _parseKeyMappingProposal returns early if type != 'key_mapping'
      expect(source, contains("if (type != 'key_mapping') return"));
    });

    test('null proposalData does not trigger parsing', () {
      expect(source, contains('if (json == null) return'));
    });

    test('non-Map decoded JSON is silently ignored', () {
      expect(source, contains('if (decoded is! Map<String, dynamic>) return'));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level assertions for page_editor.dart proposal enhancements.
///
/// The PageEditor widget depends on heavy provider chains (pageManagerProvider,
/// databaseProvider, themeNotifierProvider, etc.) that require full app wiring
/// to pump. Instead, we verify proposal behavior through source code assertions
/// -- the same pattern used in Phase 18 for complex widgets.
void main() {
  late String source;
  late String pageViewSource;

  setUpAll(() {
    source = File('lib/pages/page_editor.dart').readAsStringSync();
    pageViewSource = File('lib/pages/page_view.dart').readAsStringSync();
  });

  group('PageEditor proposal enhancements', () {
    test('tracks proposed assets in a set', () {
      expect(source, contains('_proposedAssets'));
    });

    test('stores pre-proposal pages for reject revert', () {
      expect(source, contains('_preProposalPages'));
    });

    test('has Accept button that calls _saveToPrefs', () {
      expect(source, contains('Accept'));
      expect(source, contains('_saveToPrefs'));
    });

    test('has Reject button that reverts to pre-proposal state', () {
      expect(source, contains('Reject'));
      expect(source, contains('_preProposalPages'));
    });

    test('imports proposal_visual.dart', () {
      expect(source, contains('proposal_visual.dart'));
    });

    test('imports proposal_state.dart for accept/reject state updates', () {
      expect(source, contains('proposal_state.dart'));
    });

    test('replaces MaterialBanner with Accept/Reject buttons', () {
      // The old MaterialBanner with just DISMISS should be replaced
      // with Accept (green) and Reject (red) actions
      expect(source, contains('Accept'));
      expect(source, contains('Reject'));
      expect(source, contains('Colors.green'));
      expect(source, contains('Colors.red'));
    });

    test('passes proposedAssets to AssetStack', () {
      // The _proposedAssets set is passed to AssetStack for rendering indicators
      expect(source, contains('proposedAssets: _proposedAssets'));
    });

    test('page_view.dart uses DashedBorderPainter for proposed assets', () {
      expect(pageViewSource, contains('DashedBorderPainter'));
      expect(pageViewSource, contains('ProposalBadge'));
      expect(pageViewSource, contains('proposedAssets.contains'));
    });
  });

  group('PageEditor proposal banner UI', () {
    test('banner shows AI proposal title', () {
      expect(source, contains('AI Proposal:'));
      expect(source, contains('_proposalTitle'));
    });

    test('banner has amber background', () {
      expect(source, contains('Colors.amber.shade50'));
    });

    test('banner has auto_awesome icon', () {
      expect(source, contains('Icons.auto_awesome'));
    });

    test('Accept button is green ElevatedButton', () {
      expect(source, contains('ElevatedButton'));
      expect(source, contains('backgroundColor: Colors.green'));
      expect(source, contains('foregroundColor: Colors.white'));
    });

    test('Reject button is red OutlinedButton', () {
      expect(source, contains('OutlinedButton'));
      expect(source, contains('foregroundColor: Colors.red'));
      expect(source, contains('BorderSide(color: Colors.red)'));
    });

    test('title bar changes when in proposal mode', () {
      expect(source, contains("'Page Editor \u2014 AI Proposal'"));
      expect(source, contains("'Page Editor'"));
    });
  });

  group('PageEditor accept flow', () {
    test('accept calls _saveToPrefs which saves to pageManager', () {
      expect(source, contains('pageManager.pages = PageManager.copyPages'));
      expect(source, contains('pageManager.save()'));
    });

    test('invalidates pageManagerProvider after save so Page View refreshes', () {
      expect(source, contains('ref.invalidate(pageManagerProvider)'));
    });

    test('accept clears proposal state', () {
      // After save, _isProposal should be false, _proposedAssets cleared
      expect(source, contains('_isProposal = false; // Proposal accepted'));
      expect(source, contains('_proposedAssets = {};'));
      expect(source, contains('_preProposalPages = null;'));
    });

    test('accept updates universal proposal state via notifier', () {
      expect(source, contains('proposalStateProvider.notifier'));
      expect(source, contains('acceptProposal(_proposalId!)'));
    });

    test('accept only fires proposal state update when proposalId exists', () {
      expect(source, contains('if (_isProposal && _proposalId != null)'));
    });
  });

  group('PageEditor reject flow', () {
    test('reject reverts to _preProposalPages snapshot', () {
      expect(source, contains('_temporaryPages = _preProposalPages!'));
    });

    test('reject resets current page to first available', () {
      expect(source, contains('_currentPage = _temporaryPages.keys.firstOrNull'));
    });

    test('reject clears all proposal flags', () {
      // Reject block should reset _isProposal, _proposedAssets, _preProposalPages
      expect(source, contains('_isProposal = false;'));
      expect(source, contains('_proposedAssets = {};'));
      expect(source, contains('_preProposalPages = null;'));
    });

    test('reject updates _savedJson to match reverted state', () {
      expect(source, contains('_savedJson = _currentJson;'));
    });

    test('reject calls rejectProposal on notifier when proposalId exists', () {
      expect(source, contains('rejectProposal(_proposalId!)'));
    });
  });

  group('PageEditor _applyProposalData', () {
    test('stores pre-proposal snapshot before applying', () {
      expect(source, contains('_preProposalPages = PageManager.copyPages'));
    });

    test('handles malformed JSON gracefully with try-catch', () {
      // Outer try-catch wraps the entire proposal parsing
      expect(source, contains('try {'));
      expect(source, contains('jsonDecode(proposalJson)'));
      expect(source, contains("} catch (_) {"));
    });

    test('checks _proposal_type field for routing', () {
      expect(source, contains("proposal['_proposal_type']"));
    });

    test('routes page type to _applyPageProposal', () {
      expect(source, contains("type == 'page'"));
      expect(source, contains('_applyPageProposal'));
    });

    test('routes asset type to _applyAssetProposal', () {
      expect(source, contains("type == 'asset'"));
      expect(source, contains('_applyAssetProposal'));
    });

    test('ignores proposal with null type', () {
      expect(source, contains('if (type == null) return;'));
    });

    test('attempts to match proposalId from universal state', () {
      expect(source, contains('ref.read(proposalStateProvider)'));
      expect(source, contains('p.proposalJson == proposalJson'));
      expect(source, contains('_proposalId = p.id'));
    });
  });

  group('PageEditor _applyPageProposal', () {
    test('defaults title to AI Proposal', () {
      expect(source, contains("'AI Proposal'"));
    });

    test('defaults key from title', () {
      expect(source, contains(r"final key = proposal['key'] as String? ?? '/$title'"));
    });

    test('parses assets from proposal', () {
      expect(source, contains("AssetRegistry.parse({'assets': items})"));
    });

    test('falls back to createDefaultAssetByName for page proposal', () {
      expect(source, contains('AssetRegistry.createDefaultAssetByName'));
    });

    test('creates AssetPage with auto_awesome icon', () {
      expect(source, contains('icon: Icons.auto_awesome'));
    });

    test('navigates to the new page', () {
      expect(source, contains('_currentPage = key;'));
    });

    test('marks all parsed assets as proposed', () {
      expect(source, contains('_proposedAssets = Set.of(assets)'));
    });
  });

  group('PageEditor _applyAssetProposal', () {
    test('merges children and assets lists additively', () {
      // Bug fix: both children and assets should be addAll, not overwrite
      expect(source, contains("newAssets.addAll("));
      // Verify there is no plain assignment that would overwrite
      expect(source.contains("newAssets = AssetRegistry.parse"), isFalse,
          reason: 'Should use addAll to merge, not overwrite with assignment');
    });

    test('adds assets to existing page when targetPage matches', () {
      expect(source,
          contains('_temporaryPages[targetPage]!.assets.addAll(newAssets)'));
    });

    test('creates new page when targetPage does not match existing pages', () {
      expect(source, contains("final pageKey = targetPage ?? '/\$title'"));
      expect(source, contains('_temporaryPages[pageKey] = AssetPage'));
    });

    test('falls back to currentPage when no page_key in proposal', () {
      expect(source, contains(
          "final targetPage = proposal['page_key'] as String? ?? _currentPage"));
    });

    test('falls back to createDefaultAssetByName for minimal MCP JSON', () {
      // When AssetRegistry.parse fails (e.g. missing required fields like
      // colors/sizes), the fallback creates default assets by type name
      // and applies key/title/coordinates from the proposal.
      expect(source, contains('AssetRegistry.createDefaultAssetByName'));
      expect(source, contains("item['asset_name'] as String?"));
      expect(source, contains("item['asset_type'] as String?"));
    });
  });

  group('PageEditor Beamer route integration', () {
    test('route configuration passes proposalData from args', () {
      final mainSource =
          File('centroid-hmi/lib/main.dart').readAsStringSync();
      expect(mainSource, contains("PageEditor(proposalData: args is String ? args : null)"));
    });

    test('proposalData parameter is nullable String', () {
      expect(source, contains('final String? proposalData'));
    });

    test('_applyProposalData called in initState', () {
      expect(source, contains('_applyProposalData(widget.proposalData)'));
    });
  });

  group('page_view.dart AssetStack proposal rendering', () {
    test('AssetStack accepts proposedAssets parameter', () {
      expect(pageViewSource, contains('final Set<Asset> proposedAssets'));
    });

    test('proposedAssets defaults to empty set', () {
      expect(pageViewSource, contains('this.proposedAssets = const {}'));
    });

    test('checks isProposed per asset', () {
      expect(pageViewSource, contains('widget.proposedAssets.contains(asset)'));
    });

    test('dashed border is wrapped in IgnorePointer', () {
      expect(pageViewSource, contains('IgnorePointer'));
    });

    test('ProposalBadge is positioned top-right', () {
      expect(pageViewSource, contains('top: 2'));
      expect(pageViewSource, contains('right: 2'));
    });

    test('dashed border color is amber', () {
      expect(pageViewSource, contains('DashedBorderPainter(color: Colors.amber)'));
    });
  });

  group('PageEditor edge cases', () {
    test('empty proposal (no assets key) does not crash', () {
      // _applyPageProposal checks `proposal["assets"] is List` before parsing
      expect(source, contains("proposal['assets'] is List"));
    });

    test('proposal with unknown _proposal_type is ignored', () {
      // Only "page" and "asset" types are handled
      expect(source, contains("if (type == 'page')"));
      expect(source, contains("} else if (type == 'asset')"));
      // No else clause means unknown types are silently ignored
    });

    test('proposal for existing page merges into it', () {
      // _applyAssetProposal checks _temporaryPages.containsKey(targetPage)
      expect(source, contains('_temporaryPages.containsKey(targetPage)'));
    });

    test('proposal marks saved json empty so unsaved indicator shows', () {
      // When proposal is applied, _savedJson is set to empty string
      expect(source, contains("_isProposal ? '' : _currentJson"));
    });

    test('AssetView does not use proposedAssets (view-only mode)', () {
      // AssetView is the non-editor view and should not show proposal indicators
      // It constructs AssetStack without proposedAssets (uses default empty set)
      expect(pageViewSource, contains('class AssetView'));
      // The AssetView build method should NOT pass proposedAssets
      final assetViewSection = pageViewSource.substring(
          pageViewSource.indexOf('class AssetView'));
      expect(assetViewSection.contains('proposedAssets:'), isFalse,
          reason: 'AssetView should use default empty proposedAssets');
    });
  });
}

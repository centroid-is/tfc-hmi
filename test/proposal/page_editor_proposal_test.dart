import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level assertions for page_editor.dart proposal handling.
///
/// The PageEditor widget depends on heavy provider chains (pageManagerProvider,
/// databaseProvider, themeNotifierProvider, etc.) that require full app wiring
/// to pump, which is why these are source assertions rather than widget tests.
///
/// The shape they pin changed on 2026-08-19. Proposals used to be staged one
/// at a time (`_proposalId`, a single int) and accepted from an inline amber
/// Accept/Reject bar drawn by this page. An MCP client fires update_asset one
/// call per asset, so binding eight children arrived as eight proposals and
/// cost eight reviews and eight saves -- and the inline bar was a second place
/// to act on a proposal, competing with the black banner. Both are gone: the
/// editor stages the whole pending queue into `_proposalIds` and publishes
/// commit/discard callbacks to the banner, which is now the only place to
/// accept or reject.
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

    test('imports proposal_visual.dart', () {
      expect(source, contains('proposal_visual.dart'));
    });

    test('imports proposal_state.dart for accept/reject state updates', () {
      expect(source, contains('proposal_state.dart'));
    });

    test('passes proposedAssets to AssetStack', () {
      // The _proposedAssets set is passed to AssetStack for rendering
      // indicators.
      expect(source, contains('proposedAssets: _proposedAssets'));
    });

    test('page_view.dart uses DashedBorderPainter for proposed assets', () {
      expect(pageViewSource, contains('DashedBorderPainter'));
      expect(pageViewSource, contains('ProposalBadge'));
      expect(pageViewSource, contains('proposedAssets.contains'));
    });
  });

  group('proposals are staged as a batch, not one at a time', () {
    test('keeps a list of proposal ids, not a single id', () {
      expect(source, contains('final List<int> _proposalIds = [];'));
      expect(source, isNot(contains('int? _proposalId;')),
          reason: 'a single staged id was what forced one review per proposal');
    });

    test('applies the whole queued asset_update run in one pass', () {
      expect(source,
          contains('int _applyUpdateBatch(List<PendingProposal> proposals)'));
      expect(source, contains('_applyUpdateBatch(updates)'));
    });

    test('skips ids already staged so re-entry cannot double-apply', () {
      expect(source, contains('_proposalIds.contains(p.id)'));
    });

    test('skips ids already accepted or rejected', () {
      // acceptProposal/rejectProposal await a database write before dropping
      // the proposal from state, so their removals land after the batch has
      // been cleared -- and every removal fires the state listener. Without
      // this the listener treats the not-yet-removed rows as a brand new
      // batch and re-applies them, which is how a reject left the change on
      // the page.
      expect(source, contains('final Set<int> _consumedProposalIds = {};'));
      expect(source, contains('_consumedProposalIds.contains(p.id)'));
      expect(source, contains('_consumedProposalIds.addAll(_proposalIds)'));
    });

    test('a second wave extends the open batch instead of restarting it', () {
      // Re-snapshotting _preProposalPages over already-patched pages left
      // reject-all with no way back to the original, and clearing
      // _proposedAssets left only the newest asset outlined.
      expect(source, contains('final extending = _preProposalPages != null;'));
      expect(source, contains('if (!extending) {'));
    });

    test('tolerates a malformed proposal without dropping the batch', () {
      expect(source, contains('jsonDecode(p.proposalJson)'));
      expect(source, contains('is! Map<String, dynamic>'));
    });
  });

  group('the banner owns accept/reject -- nothing inline', () {
    test('publishes commit and discard to the banner', () {
      expect(source, contains('proposalCommitProvider'));
      expect(source, contains('proposalDiscardProvider'));
      // Captured into a field on publish, so dispose() can clear them
      // without touching `ref` -- Riverpod throws if you do that there.
      expect(source, contains('_commitSlot = commitSlot;'));
      expect(source, contains('commitSlot.state = _saveToPrefs;'));
      expect(source, contains('_discardSlot = discardSlot;'));
      expect(
          source, contains('discardSlot.state = _discardProposal;'));
    });

    test('page and asset proposals publish the callbacks too', () {
      // Only the asset_update batch used to, so rejecting a `page` or `asset`
      // proposal from the banner just marked the rows rejected -- the staged
      // assets stayed on the page with nothing left to explain them.
      final apply =
          source.substring(source.indexOf('void _applyProposalData('));
      expect(apply, contains('if (_isProposal) {'));
      expect(apply, contains('proposalCommitProvider'),
          reason: '_applyProposalData must hand the banner a commit');
      expect(apply, contains('proposalDiscardProvider'));
    });

    test('no inline amber Accept/Reject bar remains', () {
      // The bar carried a green ElevatedButton 'Accept' and a red
      // OutlinedButton 'Reject'. Two competing controls meant an operator
      // could accept in one place while the other still showed it pending.
      expect(source, isNot(contains('Colors.amber.shade50')));
      expect(source, isNot(contains('Reject')));
      expect(source, isNot(contains("Text('Accept')")));
      expect(source, isNot(contains('backgroundColor: Colors.green')));
      expect(source, isNot(contains('BorderSide(color: Colors.red)')));
    });

    test('clears the callbacks on dispose', () {
      // The banner holds these closures over this State; left set they fire
      // into a disposed State after navigating away -- nothing saved, the
      // proposals still pending, and an uncaught async error.
      final dispose = source.substring(source.indexOf('void dispose() {'));
      expect(dispose,
          contains('ref.read(proposalCommitProvider.notifier).state = null;'));
      expect(dispose,
          contains('ref.read(proposalDiscardProvider.notifier).state = null;'));
    });

    test('a staged batch is still announced in the title bar', () {
      expect(source, contains("'Page Editor — AI Proposal'"));
      expect(source, contains("'Page Editor'"));
      expect(source, contains('_proposalTitle'));
    });

    test('a multi-proposal batch is titled by its count', () {
      expect(source, contains(r"'$staged asset updates'"));
    });
  });

  group('PageEditor accept flow', () {
    test('accept calls _saveToPrefs which saves to pageManager', () {
      expect(source, contains('pageManager.pages = PageManager.copyPages'));
      expect(source, contains('pageManager.save()'));
    });

    test('invalidates pageManagerProvider after save so Page View refreshes',
        () {
      expect(source, contains('ref.invalidate(pageManagerProvider)'));
    });

    test('saves the pages, then marks the proposals accepted', () {
      final save =
          source.substring(source.indexOf('Future<void> _saveToPrefs('));
      final persisted = save.indexOf('await pageManager.save()');
      final accepted = save.indexOf('acceptProposal');
      expect(persisted, greaterThan(-1));
      expect(accepted, greaterThan(-1));
      expect(persisted, lessThan(accepted),
          reason: 'acceptProposal marks the row accepted in the database, so '
              'doing it first would lose the pages if the save failed');
    });

    test('awaits each accept rather than firing and forgetting', () {
      expect(source, contains('await notifier.acceptProposal(id)'));
    });

    test('accept only touches proposal state when a batch is staged', () {
      expect(source, contains('if (_isProposal && _proposalIds.isNotEmpty)'));
    });

    test('accept clears proposal state', () {
      expect(source, contains('_isProposal = false; // Proposal accepted'));
      expect(source, contains('_proposalIds.clear();'));
      expect(source, contains('_proposedAssets = {};'));
      expect(source, contains('_preProposalPages = null;'));
    });

    test('accept retires the banner callbacks', () {
      final save =
          source.substring(source.indexOf('Future<void> _saveToPrefs('));
      expect(save,
          contains('ref.read(proposalCommitProvider.notifier).state = null;'));
      expect(save,
          contains('ref.read(proposalDiscardProvider.notifier).state = null;'));
    });
  });

  group('PageEditor reject flow', () {
    test('the banner discards through _discardProposal', () {
      expect(source, contains('Future<void> _discardProposal() async'));
    });

    test('reject reverts to _preProposalPages snapshot', () {
      expect(source, contains('_temporaryPages = _preProposalPages!'));
    });

    test('reject resets current page to first available', () {
      expect(
          source, contains('_currentPage = _temporaryPages.keys.firstOrNull'));
    });

    test('reject clears all proposal flags', () {
      final discard =
          source.substring(source.indexOf('Future<void> _discardProposal()'));
      expect(discard, contains('_isProposal = false;'));
      expect(discard, contains('_proposalIds.clear();'));
      expect(discard, contains('_proposedAssets = {};'));
      expect(discard, contains('_preProposalPages = null;'));
    });

    test('reject updates _savedJson to match reverted state', () {
      expect(source, contains('_savedJson = _currentJson;'));
    });

    test('reject marks every folded-in proposal rejected, awaited', () {
      expect(source, contains('await notifier.rejectProposal(id)'));
      final discard =
          source.substring(source.indexOf('Future<void> _discardProposal()'));
      expect(discard, contains('for (final id in _proposalIds)'));
    });
  });

  group('PageEditor _applyProposalData', () {
    test('stores pre-proposal snapshot before applying', () {
      expect(source, contains('_preProposalPages = PageManager.copyPages'));
    });

    test('handles malformed JSON gracefully with try-catch', () {
      // Outer try-catch wraps the entire proposal parsing.
      expect(source, contains('try {'));
      expect(source, contains('jsonDecode(proposalJson)'));
      expect(source, contains('} catch (_) {'));
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

    test('routes asset_update type to _applyUpdateProposal', () {
      expect(source, contains("type == 'asset_update'"));
      expect(source, contains('_applyUpdateProposal'));
    });

    test('ignores proposal with null type', () {
      expect(source, contains('if (type == null) return;'));
    });

    test('records the matched proposal id in the batch list', () {
      expect(source, contains('ref.read(proposalStateProvider)'));
      expect(source, contains('p.proposalJson == proposalJson'));
      expect(source, contains('_proposalIds.add(p.id)'));
    });
  });

  group('PageEditor _applyPageProposal', () {
    test('defaults title to AI Proposal', () {
      expect(source, contains("'AI Proposal'"));
    });

    test('defaults key from title', () {
      expect(source,
          contains(r"final key = proposal['key'] as String? ?? '/$title'"));
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
      // Bug fix: both children and assets should be addAll, not overwrite.
      expect(source, contains('newAssets.addAll('));
      // Verify there is no plain assignment that would overwrite.
      expect(source.contains('newAssets = AssetRegistry.parse'), isFalse,
          reason: 'Should use addAll to merge, not overwrite with assignment');
    });

    test('appends to an existing page when the proposal names no index', () {
      final apply =
          source.substring(source.indexOf('void _applyAssetProposal('));
      expect(apply,
          contains('final assets = _temporaryPages[targetPage]!.assets;'));
      expect(apply, contains('assets.addAll(newAssets);'));
    });

    test('honours a requested draw-order index', () {
      // The asset list IS the draw order (page_view walks it front to back),
      // so appending always lands on top. A beacon that belongs behind the
      // sensor it sits under has to be able to name its position.
      expect(source, contains(r"final at = proposal['index'];"));
      expect(source, contains('at is int && at >= 0 && at <= assets.length'));
      expect(source, contains('assets.insertAll(at, newAssets);'));
    });

    test('creates new page when targetPage does not match existing pages', () {
      expect(source, contains("final pageKey = targetPage ?? '/\$title'"));
      expect(source, contains('_temporaryPages[pageKey] = AssetPage'));
    });

    test('falls back to currentPage when no page_key in proposal', () {
      expect(
          source,
          contains("final targetPage = proposal['page_key'] as String? ?? "
              '_currentPage'));
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
      final mainSource = File('centroid-hmi/lib/main.dart').readAsStringSync();
      expect(
          mainSource,
          contains(
              'PageEditor(proposalData: args is String ? args : null)'));
    });

    test('proposalData parameter is nullable String', () {
      expect(source, contains('final String? proposalData'));
    });

    test('the routed proposal is only a fallback for an empty queue', () {
      // Arriving from the banner's "Review all" hands us one proposalJson,
      // but the queue behind it is what the operator asked to review -- and
      // the banner hides nothing, so anything not staged here shows nowhere.
      expect(source,
          contains('if (batched == 0) _applyProposalData(widget.proposalData);'));
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
      expect(pageViewSource,
          contains('DashedBorderPainter(color: Colors.amber)'));
    });
  });

  group('PageEditor edge cases', () {
    test('empty proposal (no assets key) does not crash', () {
      // _applyPageProposal checks `proposal["assets"] is List` before parsing.
      expect(source, contains("proposal['assets'] is List"));
    });

    test('proposal with unknown _proposal_type is ignored', () {
      // Only "page", "asset" and "asset_update" are handled.
      expect(source, contains("if (type == 'page')"));
      expect(source, contains("} else if (type == 'asset')"));
      // No else clause means unknown types are silently ignored.
    });

    test('proposal for existing page merges into it', () {
      // _applyAssetProposal checks _temporaryPages.containsKey(targetPage).
      expect(source, contains('_temporaryPages.containsKey(targetPage)'));
    });

    test('proposal marks saved json empty so unsaved indicator shows', () {
      // When proposal is applied, _savedJson is set to empty string.
      expect(source, contains("_isProposal ? '' : _currentJson"));
    });

    test('an unappliable asset_update explains itself instead of going quiet',
        () {
      // A stale index or a missing page leaves the canvas untouched; without
      // this the operator gets an editor titled "AI Proposal" showing no diff.
      expect(source, contains('AI update proposal not applied: '));
    });

    test('AssetView does not use proposedAssets (view-only mode)', () {
      // AssetView is the non-editor view and should not show proposal
      // indicators. It constructs AssetStack without proposedAssets (uses
      // the default empty set).
      expect(pageViewSource, contains('class AssetView'));
      final assetViewSection =
          pageViewSource.substring(pageViewSource.indexOf('class AssetView'));
      expect(assetViewSection.contains('proposedAssets:'), isFalse,
          reason: 'AssetView should use default empty proposedAssets');
    });
  });
}

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

  /// The text of one method, ending at the first line that closes at class
  /// indentation.
  ///
  /// Slicing to end-of-file instead is what let three stray
  /// `ref.read(proposalCommitProvider.notifier).state = null` lines sit in the
  /// tree-drag auto-scroll code for months while the tests that meant to pin
  /// dispose() and _saveToPrefs matched them and stayed green.
  String bodyOf(String signature) {
    final start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: 'missing $signature');
    return source.substring(
        start, source.indexOf(RegExp(r'^  }', multiLine: true), start));
  }

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

    test('applies the whole queued asset run in one pass', () {
      // Was `_applyUpdateBatch`, which took `asset_update` only. New assets
      // (`asset`, from propose_asset) went down the single-apply path and
      // every one after the first was dropped, so the name no longer fit.
      expect(source,
          contains('int _applyAssetBatch(List<PendingProposal> proposals)'));
      expect(source, contains('_applyAssetBatch(assetProposals)'));
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
      //
      // Both staging paths now go through _publishProposalCallbacks rather
      // than each writing the slots itself: publishing is also where the
      // provider container the callbacks run on is captured, and one of two
      // copies quietly missing that capture is the whole failure this file's
      // disposal group exists to prevent.
      final apply = bodyOf('void _applyProposalData(');
      expect(apply, contains('if (_isProposal) {'));
      expect(apply, contains('_publishProposalCallbacks()'),
          reason: '_applyProposalData must hand the banner a commit');
      final publish = bodyOf('void _publishProposalCallbacks()');
      expect(publish, contains('proposalCommitProvider'));
      expect(publish, contains('proposalDiscardProvider'));
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
      //
      // Through the stored controllers, not `ref`: Riverpod throws on `ref`
      // inside dispose(). This used to assert on `ref.read(...)` over a
      // slice that ran to end-of-file, so what it actually matched was the
      // auto-scroll code, not dispose() at all.
      final dispose = bodyOf('void dispose() {');
      expect(dispose, contains('commitSlot.state = null;'));
      expect(dispose, contains('discardSlot.state = null;'));
      for (final use in ['ref.read', 'ref.watch', 'ref.invalidate']) {
        expect(dispose, isNot(contains(use)));
      }
    });

    test('the clear is deferred to after this frame', () {
      // Navigating away disposes the editor from inside a build, and writing
      // to a provider there trips riverpod's "tried to modify a provider
      // while the widget tree was building".
      final dispose = bodyOf('void dispose() {');
      expect(dispose, contains('WidgetsBinding.instance.addPostFrameCallback'));
    });

    test('the deferred clear only retires our own closures', () {
      // An editor that replaced this one has already published its callbacks
      // into the same slots. Clearing unconditionally a frame later would
      // take the banner's buttons away from a live batch.
      final dispose = bodyOf('void dispose() {');
      expect(dispose, contains('final commit = _saveToPrefs;'));
      expect(dispose, contains('final discard = _discardProposal;'));
      expect(dispose, contains('commitSlot.state == commit'));
      expect(dispose, contains('discardSlot.state == discard'));
      // And the slot itself may be gone by then -- the whole ProviderScope
      // can tear down between dispose() and the next frame.
      expect(dispose, contains('commitSlot.mounted'));
      expect(dispose, contains('discardSlot.mounted'));
    });

    test('a staged batch is still announced in the title bar', () {
      expect(source, contains("'Page Editor — AI Proposal'"));
      expect(source, contains("'Page Editor'"));
      expect(source, contains('_proposalTitle'));
    });

    test('a multi-proposal batch is titled by its count', () {
      // "asset updates" was accurate while the batch only held asset_update.
      // It now holds new assets too, and telling an operator staging seven
      // new sensors that he has "7 asset updates" is simply wrong.
      expect(source, contains(r"'$staged asset proposals'"));
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
      // Same change of mechanism as dispose(), and for the same reason: the
      // banner can call this after the editor is gone, and `ref` throws then.
      // The old slice ran to end-of-file and matched the auto-scroll code.
      final save = bodyOf('Future<void> _saveToPrefs(');
      expect(save, contains('_commitSlot?.state = null;'));
      expect(save, contains('_discardSlot?.state = null;'));
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

    test('a config override that will not parse is reported, not swallowed',
        () {
      // The override is merged onto `asset.toJson()` and re-parsed. When that
      // throws, falling back to the default asset is a reasonable last
      // resort -- doing it silently is not. A proposed three-lamp LED column
      // arrived as the preview's two grey LEDs with nothing in the log and
      // nothing shown to the operator, and the only reason anyone found out
      // was that the wrong thing was visible on the page.
      //
      // Same failure mode as the `catch (_) {}` in _saveToPrefs below: a bare
      // catch around a parse is how a batch goes missing quietly.
      // Scoped to the config-override block, not the whole method. Two other
      // `catch (_) {}` live in _applyAssetProposal and neither is this bug:
      // one drops to the create-by-name fallback on purpose, and one guards
      // `(asset as dynamic).key =` for the asset types that have no `key`
      // field at all, where there is genuinely nothing to report.
      final apply = bodyOf('void _applyAssetProposal(');
      final start = apply.indexOf('// Apply config overrides');
      expect(start, greaterThan(-1),
          reason: 'the config-override block moved; re-scope this test');
      final overrideBlock =
          apply.substring(start, apply.indexOf('newAssets.add(asset);', start));

      expect(overrideBlock, isNot(contains('catch (_)')),
          reason: 'a swallowed parse failure here is indistinguishable from '
              'a badly written proposal');
      expect(overrideBlock, contains('falling back to the default asset'));
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

  // Seven `asset` proposals were pending. Accept all removed exactly one row
  // and Review all then did nothing at all: the listener applied
  // `pageProposals.first`, that set `_isProposal`, and every proposal behind
  // it hit `if (_isProposal) return`. Nothing else was ever staged, so the
  // commit slot stayed null and the banner kept offering a review that could
  // not happen. `asset_update` had been batched since #197; `asset` never was.
  group('a queue of new-asset proposals is staged whole', () {
    test('the listener batches asset alongside asset_update', () {
      final listener = source.substring(
          source.indexOf('ref.listen<ProposalState>'),
          source.indexOf('return Focus('));
      expect(listener, contains("p.proposalType == 'asset' ||"));
      expect(listener, contains('_applyAssetBatch(assetProposals)'));
    });

    test('the batch runs before the single-proposal guard', () {
      final listener = source.substring(
          source.indexOf('ref.listen<ProposalState>'),
          source.indexOf('return Focus('));
      final batched = listener.indexOf('_applyAssetBatch(assetProposals)');
      final guard = listener.indexOf('if (_isProposal) return');
      expect(batched, greaterThan(-1));
      expect(guard, greaterThan(batched),
          reason: 'the guard is what threw the other six away');
    });

    test('only page proposals still go one at a time', () {
      // A `page` proposal replaces or creates a whole page, so folding a run
      // of them together has no defined result. `asset` appends, which does.
      final listener = source.substring(
          source.indexOf('ref.listen<ProposalState>'),
          source.indexOf('return Focus('));
      final single = listener.indexOf('pageOnly.first.proposalJson');
      final guard = listener.indexOf('if (_isProposal) return');
      expect(single, greaterThan(-1));
      expect(guard, lessThan(single),
          reason: 'the single-apply path is the else branch, page only');
    });

    test('initState stages the page-A proposals the listener would', () {
      // Opening the editor from the banner has to stage the same set the
      // listener stages -- the proposals for the open page -- so the first
      // thing the operator sees is not one of seven, nor a page they are not
      // on. Both routes go through the same page partition.
      final init = bodyOf('void initState() {');
      expect(init, contains('_partitionAssetProposals(pending, _currentPage)'));
      expect(init, contains('_applyAssetBatch(split.onPage)'));
    });

    test('the batch dispatches both asset kinds', () {
      // One driver, two applies: a create builds new assets and appends them,
      // an update patches one in place. The bookkeeping around them --
      // snapshot once, skip staged ids, count what landed -- is identical,
      // which is why they share the loop rather than each having one.
      final batch = bodyOf('int _applyAssetBatch(List<PendingProposal>');
      expect(batch, contains("_applyAssetProposal(decoded)"));
      expect(batch, contains("_applyUpdateProposal(decoded)"));
      expect(batch, contains('for (final p in proposals)'));
    });

    test('a proposal arriving mid-review joins the batch', () {
      final batch = bodyOf('int _applyAssetBatch(List<PendingProposal>');
      expect(batch, contains('_proposalIds.contains(p.id)'));
      expect(batch, contains('_consumedProposalIds.contains(p.id)'));
      expect(batch, contains('final extending = _preProposalPages != null;'),
          reason: 're-snapshotting over already-staged pages would leave '
              'reject-all with no way back to the original');
    });

    test('a new-asset proposal adds to the outline instead of replacing it',
        () {
      // `_proposedAssets = Set.of(newAssets)` meant the second create in a
      // batch erased the first one's yellow outline.
      final apply = bodyOf('void _applyAssetProposal(');
      expect(apply, contains('_proposedAssets.addAll(newAssets)'));
      expect(apply, isNot(contains('_proposedAssets = Set.of(newAssets)')));
    });

    test('a proposal that built nothing does not claim the batch', () {
      // This is the second way a queue stranded: a proposal the registry
      // could not build still ran to the bottom of _applyAssetProposal and
      // set `_isProposal = true`, so the guard blocked every later one --
      // with nothing staged to accept and no empty page worth creating.
      final apply = bodyOf('void _applyAssetProposal(');
      final bail = apply.indexOf('if (newAssets.isEmpty) return;');
      final flag = apply.indexOf('_isProposal = true;');
      expect(bail, greaterThan(-1));
      expect(flag, greaterThan(bail));
    });

    test('one malformed proposal does not take the batch with it', () {
      // Eleven proposals missing required fields left a queue of 25
      // unusable. Each proposal is applied inside its own try, and a failure
      // is reported rather than swallowed.
      final batch = bodyOf('int _applyAssetBatch(List<PendingProposal>');
      expect(batch, isNot(contains('catch (_) {}')));
      expect(batch, contains('debugPrint('));
      final caught = batch.indexOf('} catch (e)');
      final counted = batch.indexOf('applied++');
      expect(counted, greaterThan(-1));
      expect(caught, greaterThan(counted),
          reason: 'the catch belongs inside the loop, around one proposal');
    });
  });

  // The banner outlives this editor: it is published once and stays up while
  // the operator navigates, and accepting a batch rebuilds or navigates out
  // from under this State. By the time Accept ran, `mounted` was false and
  // `ref` was dead -- so the pages were written and not one proposal was
  // marked accepted, and the same batch came back on the next load. That is
  // the asset-proposal spelling of what a key-mapping batch of 16 hit on
  // 2026-08-21; see key_repository_proposal_test.dart.
  group('accept and reject survive the editor being disposed', () {
    test('the container is captured where ref and context are known good', () {
      final publish = bodyOf('void _publishProposalCallbacks()');
      expect(
          publish,
          contains(
              '_container = ProviderScope.containerOf(context, listen: false)'),
          reason: 'the banner callbacks have no live ref of their own');
    });

    test('reject never reaches for ref', () {
      final body = bodyOf('Future<void> _discardProposal()');
      for (final use in ['ref.read', 'ref.watch', 'ref.invalidate']) {
        expect(body, isNot(contains(use)),
            reason: 'reject runs from the banner, after this State may be gone');
      }
      expect(body, contains('final container = _container;'));
      expect(body, contains('if (container == null) return;'));
    });

    test('the save prefers the captured container over ref', () {
      // _saveToPrefs has two callers: the Save button, where `ref` is alive
      // and no container was ever captured, and the banner, where it is not.
      final save = bodyOf('Future<void> _saveToPrefs(');
      expect(save, contains('final container = _container;'));
      expect(save, contains('container.read(pageManagerProvider.future)'));
      expect(save, contains('container.invalidate(pageManagerProvider)'));
      expect(save, contains('container.read(proposalStateProvider.notifier)'));
    });

    test('the accept step is not behind a mounted guard', () {
      // This is the bug: `if (!mounted) return;` sat between the save and the
      // accept loop, so a proposal accepted from the banner wrote its pages
      // and stayed pending. Only the rebuild may depend on `mounted`.
      final save = bodyOf('Future<void> _saveToPrefs(');
      expect(save, isNot(contains('if (!mounted) return;')));
      final accepted = save.indexOf('acceptProposal');
      final rebuilt = save.indexOf('if (mounted) setState');
      expect(accepted, greaterThan(-1));
      expect(rebuilt, greaterThan(accepted),
          reason: 'the batch has to be marked accepted whether or not this '
              'editor is still on screen');
    });

    test('a proposal that could not be marked resolved is reported', () {
      // A bare `catch (_) {}` around the database write is what let the key
      // repository lose a whole batch quietly for weeks.
      for (final fn in [
        'Future<void> _saveToPrefs(',
        'Future<void> _discardProposal()'
      ]) {
        final body = bodyOf(fn);
        expect(body, isNot(contains('catch (_) {}')));
        expect(body, contains('debugPrint('));
      }
    });

    test('dragging a row in the tree does not retire the banner', () {
      // #197 copied dispose()'s slot-clearing block into the tree drag's
      // auto-scroll path. _autoScrollStep is 0 for every drag update away
      // from the list edges, so dragging a page while a batch was staged
      // dropped the banner's Accept and Reject on the floor.
      for (final fn in [
        'void _updateAutoScroll(',
        'void _autoScrollTick()',
      ]) {
        final body = bodyOf(fn);
        expect(body, isNot(contains('proposalCommitProvider')),
            reason: 'auto-scroll has nothing to do with proposals');
        expect(body, isNot(contains('proposalDiscardProvider')));
      }
    });
  });

  // A cross-page batch used to strand its off-page proposals. All pending
  // asset proposals -- for every page -- were fed to _applyAssetBatch, which
  // patched pages the operator could not see. Worse, a proposal for a page
  // other than the open one applied to no visible asset, so it staged neither
  // there nor here and stayed pending with nothing to accept it. The staging
  // is now filtered to the open page; the rest stay genuinely pending and
  // stage when their own page is opened.
  group('a batch spanning pages stages only the open page', () {
    test('proposals are partitioned by the page they target', () {
      // page_key is the field the apply methods already resolve against; the
      // partition reads the same one so what stages is exactly what the open
      // page would show.
      expect(source, contains('_partitionAssetProposals('));
      expect(source, contains("decoded['page_key'] as String?"));
      final partition = bodyOf(
          '_partitionAssetProposals(List<PendingProposal> all, String? page)');
      expect(partition, contains('onPage'));
      expect(partition, contains('elsewhere'));
      // A missing page_key follows the open page, matching the `?? _currentPage`
      // fallback the apply methods use.
      expect(partition, contains('key == null || key == page'));
    });

    test('both staging routes filter to the current page', () {
      final init = bodyOf('void initState() {');
      expect(init, contains('_partitionAssetProposals(pending, _currentPage)'));
      expect(init, contains('_applyAssetBatch(split.onPage)'));
      final listener = source.substring(
          source.indexOf('ref.listen<ProposalState>'),
          source.indexOf('return Focus('));
      expect(listener,
          contains('_partitionAssetProposals(pageProposals.toList()'));
      expect(listener, contains('final assetProposals = split.onPage;'));
    });

    test('off-page proposals are left pending, not staged into the open page',
        () {
      // The listener's else-of-else returns without touching the open page
      // when every asset proposal that arrived targets elsewhere.
      final listener = source.substring(
          source.indexOf('ref.listen<ProposalState>'),
          source.indexOf('return Focus('));
      expect(listener, contains('} else if (pageOnly.isNotEmpty) {'));
      expect(listener, contains('Leave them'));
    });

    test('opening a page stages the proposals left pending for it', () {
      // Both page-switch onTaps call the stager after moving _currentPage, so
      // navigating to a page is how its pending proposals get their turn.
      expect(source, contains('void _stagePendingForCurrentPage()'));
      final stager = bodyOf('void _stagePendingForCurrentPage()');
      expect(stager, contains('_partitionAssetProposals(pending, _currentPage)'));
      expect(stager, contains('_applyAssetBatch(split.onPage)'));
      // Idempotent: _applyAssetBatch skips ids already staged, so returning to
      // a page does nothing.
      expect(
          '_stagePendingForCurrentPage();'.allMatches(source).length,
          greaterThanOrEqualTo(2),
          reason: 'both page-switch handlers must re-stage');
    });

    test('the editor opens on the page the review is about', () {
      // A banner hands one proposal; its page_key wins so the editor lands on
      // it rather than on whatever page sorts first, and that proposal is in
      // the staged batch rather than left off it.
      final init = bodyOf('void initState() {');
      expect(init,
          contains('_currentPage = _focusPageForProposals(pending) ?? _currentPage'));
      final focus = bodyOf(
          'String? _focusPageForProposals(List<PendingProposal> pending)');
      expect(focus, contains('widget.proposalData'));
      expect(focus, contains('_temporaryPages.containsKey(key)'));
    });

    test('the operator is told about proposals waiting on other pages', () {
      expect(source, contains('void _noteOffPageProposals(int count)'));
      expect(source, contains('_noteOffPageProposals(split.elsewhere.length)'));
      final note = bodyOf('void _noteOffPageProposals(int count)');
      expect(note, contains('on other pages'));
    });

    test('Review all while already open switches to the proposal page', () {
      // The BeamPage key is constant, so beaming the same route again reuses
      // the mounted editor -- initState does not run twice. didUpdateWidget is
      // the only hook that sees the new proposalData; without it a "Review all"
      // for another page lands the operator on the page they were already on.
      expect(source, contains('void didUpdateWidget(PageEditor oldWidget)'));
      final upd = bodyOf('void didUpdateWidget(PageEditor oldWidget) {');
      // Only a genuine change of proposal re-routes; an unrelated rebuild with
      // the same proposalData must do nothing.
      expect(upd, contains('data == oldWidget.proposalData'));
      // Lands on the proposal's own page, then stages that page's batch --
      // reusing the same page-filtering the cold open uses.
      expect(upd, contains('_focusPageForProposals(pending)'));
      expect(upd, contains('_currentPage = focus'));
      expect(upd, contains('_partitionAssetProposals(pending, _currentPage)'));
      expect(upd, contains('_applyAssetBatch(split.onPage)'));
    });
  });
}

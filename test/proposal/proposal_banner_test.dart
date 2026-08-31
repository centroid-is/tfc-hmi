import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/proposal_visual.dart';

/// Widget tests for the proposal visuals, plus source-level assertions for
/// the black ProposalBanner.
///
/// The banner's role changed on 2026-08-19. It used to hide any proposal
/// whose editorRoute matched the current route, because each editor drew its
/// own inline amber Accept/Reject bar and showing both at once was
/// duplication. The inline bars are gone, so the banner is now the single
/// place a proposal is accepted or rejected: it stays visible on the editor
/// page, and Accept all / Reject all drive the commit/discard callbacks the
/// editor publishes rather than marking rows accepted behind the editor's
/// back.
void main() {
  // ── DashedBorderPainter ─────────────────────────────────────────────

  group('DashedBorderPainter', () {
    testWidgets('paints without error with default parameters', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: DashedBorderPainter(),
              size: const Size(200, 100),
            ),
          ),
        ),
      );

      // Smoke test: no exception during paint
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('paints without error with custom parameters', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: DashedBorderPainter(
                color: Colors.red,
                strokeWidth: 4.0,
                dashWidth: 10.0,
                dashGap: 8.0,
              ),
              size: const Size(300, 150),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('default color is amber', () {
      final painter = DashedBorderPainter();
      expect(painter.color, Colors.amber);
    });

    test('default strokeWidth is 2.0', () {
      final painter = DashedBorderPainter();
      expect(painter.strokeWidth, 2.0);
    });

    test('default dashWidth is 6.0', () {
      final painter = DashedBorderPainter();
      expect(painter.dashWidth, 6.0);
    });

    test('default dashGap is 4.0', () {
      final painter = DashedBorderPainter();
      expect(painter.dashGap, 4.0);
    });

    test('shouldRepaint returns false for identical painters', () {
      final a = DashedBorderPainter();
      final b = DashedBorderPainter();
      expect(a.shouldRepaint(b), isFalse);
    });

    test('shouldRepaint returns true when color changes', () {
      final a = DashedBorderPainter(color: Colors.amber);
      final b = DashedBorderPainter(color: Colors.red);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when strokeWidth changes', () {
      final a = DashedBorderPainter(strokeWidth: 2.0);
      final b = DashedBorderPainter(strokeWidth: 3.0);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when dashWidth changes', () {
      final a = DashedBorderPainter(dashWidth: 6.0);
      final b = DashedBorderPainter(dashWidth: 10.0);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when dashGap changes', () {
      final a = DashedBorderPainter(dashGap: 4.0);
      final b = DashedBorderPainter(dashGap: 8.0);
      expect(a.shouldRepaint(b), isTrue);
    });

    testWidgets('paints correctly at zero size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: DashedBorderPainter(),
              size: Size.zero,
            ),
          ),
        ),
      );

      // Should not throw even with zero-size canvas
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  // ── ProposalBadge ──────────────────────────────────────────────────

  group('ProposalBadge', () {
    testWidgets('renders sparkle (auto_awesome) icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProposalBadge(),
          ),
        ),
      );

      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('icon color is white', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProposalBadge(),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.auto_awesome));
      expect(icon.color, Colors.white);
    });

    testWidgets('default icon size is 16', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProposalBadge(),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.auto_awesome));
      expect(icon.size, 16);
    });

    testWidgets('respects custom size parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProposalBadge(size: 24),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.auto_awesome));
      expect(icon.size, 24);
    });

    testWidgets('has amber background with partial opacity', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProposalBadge(),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(Icons.auto_awesome),
          matching: find.byType(Container),
        ),
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.amber.withAlpha(200));
    });

    testWidgets('has rounded corners with radius 4', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProposalBadge(),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(Icons.auto_awesome),
          matching: find.byType(Container),
        ),
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(4));
    });

    testWidgets('has padding of 2 on all sides', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProposalBadge(),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(Icons.auto_awesome),
          matching: find.byType(Container),
        ),
      );

      expect(container.padding, const EdgeInsets.all(2));
    });
  });

  // ── proposalDecoration ─────────────────────────────────────────────

  group('proposalDecoration', () {
    test('returns a BoxDecoration', () {
      final decoration = proposalDecoration();
      expect(decoration, isA<BoxDecoration>());
    });

    test('has semi-transparent amber background', () {
      final decoration = proposalDecoration();
      expect(decoration.color, Colors.amber.withAlpha(25));
    });

    test('has amber border', () {
      final decoration = proposalDecoration();
      final border = decoration.border as Border;
      expect(border.top.color, Colors.amber);
      expect(border.bottom.color, Colors.amber);
      expect(border.left.color, Colors.amber);
      expect(border.right.color, Colors.amber);
    });

    test('border width is 1.5', () {
      final decoration = proposalDecoration();
      final border = decoration.border as Border;
      expect(border.top.width, 1.5);
    });

    test('has rounded corners with radius 8', () {
      final decoration = proposalDecoration();
      expect(decoration.borderRadius, BorderRadius.circular(8));
    });

    test('each call returns a new instance', () {
      final a = proposalDecoration();
      final b = proposalDecoration();
      // Should be equal but not identical
      expect(a.color, b.color);
      expect(identical(a, b), isFalse);
    });
  });

  // ── ProposalBanner: the one place a proposal is acted on ─────────────
  //
  // The banner used to hide any proposal whose editorRoute matched the
  // current Beamer route, because the editor drew its own amber
  // Accept/Reject bar and two banners at once was confusing. That inverted
  // once the inline bars were removed: hiding here would leave the operator
  // on a page showing a staged edit with nothing anywhere to accept it. The
  // route filter and its _currentRoutePath helper are gone; the banner now
  // shows every pending proposal and carries Accept all / Reject all.
  //
  // ProposalBanner depends on proposalStateProvider, navigatorKeyProvider
  // and Beamer, so these are source-level assertions (same pattern as
  // alarm_editor_proposal_test.dart and page_editor_proposal_test.dart).

  group('ProposalBanner visibility', () {
    late String bannerSource;

    setUpAll(() {
      bannerSource =
          File('lib/widgets/proposal_banner.dart').readAsStringSync();
    });

    test('returns SizedBox.shrink when no pending proposals', () {
      // First guard: if (!state.hasPending) return const SizedBox.shrink()
      expect(bannerSource, contains('!state.hasPending'));
      expect(bannerSource, contains('SizedBox.shrink()'));
    });

    test('does not filter by the current route any more', () {
      // Hiding a proposal because its editor is open was only safe while that
      // editor drew its own Accept/Reject bar. It no longer does.
      expect(bannerSource, isNot(contains('_currentRoutePath')));
      expect(bannerSource, isNot(contains('currentPath')));
      expect(bannerSource, isNot(contains('routeInformation')));
    });

    test('renders straight from state.proposals', () {
      expect(bannerSource, contains('final proposals = state.proposals;'));
      expect(bannerSource, contains('final count = proposals.length'));
      expect(bannerSource, contains('_buildSingleProposal(proposals.first)'));
      expect(
          bannerSource, contains('_buildMultipleProposals(proposals, count)'));
    });

    test('still bails out when the list is empty', () {
      expect(
          bannerSource,
          contains(
              'if (proposals.isEmpty) return const SizedBox.shrink()'));
    });

    test('watches proposalStateProvider reactively', () {
      // The banner must use ref.watch (not ref.read) so it rebuilds when
      // proposals are added, accepted, or rejected.
      expect(bannerSource, contains('ref.watch(proposalStateProvider)'));
    });

    test('never auto-dismisses on a timer', () {
      expect(bannerSource, isNot(contains('Future.delayed')));
      expect(bannerSource, isNot(contains('Timer(')));
    });
  });

  group('ProposalBanner batch actions', () {
    late String bannerSource;

    setUpAll(() {
      bannerSource =
          File('lib/widgets/proposal_banner.dart').readAsStringSync();
    });

    String acceptAllBody() => bannerSource.substring(
        bannerSource.indexOf('Widget _buildAcceptAllButton('),
        bannerSource.indexOf('Widget _buildRejectAllButton('));

    String rejectAllBody() => bannerSource.substring(
        bannerSource.indexOf('Widget _buildRejectAllButton('),
        bannerSource.indexOf('Widget _buildAcceptButton('));

    test('a multi-proposal batch offers Accept all and Reject all', () {
      // Accepting twenty-one bindings one row at a time is not review, it is
      // data entry -- and the operator has already read the list.
      expect(bannerSource, contains('_buildAcceptAllButton(proposals)'));
      expect(bannerSource, contains('_buildRejectAllButton(proposals)'));
      expect(bannerSource, contains(r"'Reject all (${proposals.length})'"));
    });

    test('accept-all commits a staged batch through the editor', () {
      // Deliberately NOT acceptProposal() per item: that marks a proposal
      // accepted in the database and drops it from state without ever
      // applying the patch, so the edit is silently lost. The editor publishes
      // the save that applies and persists first.
      final body = acceptAllBody();
      expect(body, contains('ref.read(proposalCommitProvider)'));
      expect(body, contains('commit();'));
      expect(body, isNot(contains('acceptProposal')),
          reason: 'accepting without applying loses the staged edit');
    });

    test('accept-all opens the editor when nothing is staged yet', () {
      final body = acceptAllBody();
      final commit = body.indexOf('final commit = ref.read(proposalCommitProvider);');
      // Opening the editor is one shared helper now, not an inline beam:
      // _openEditorTakes hands the proposal to the editor already on screen
      // and beams only when there is none. Beaming to the route you are
      // standing on is a no-op, so "Review all" from inside the editor used
      // to do nothing at all.
      final open = body.indexOf('_openEditorTakes(proposals.first)');
      expect(commit, greaterThan(-1));
      expect(open, greaterThan(-1));
      expect(commit, lessThan(open),
          reason: 'a staged batch must be committed, not re-opened');
    });

    test('the button says what it will do', () {
      // "Review all" until an editor has staged the queue and published its
      // commit; "Accept all" once pressing it would actually save.
      expect(bannerSource, contains('ref.watch(proposalCommitProvider) != null'));
      expect(bannerSource, contains(r"? 'Accept all (${proposals.length})'"));
      expect(bannerSource, contains(r": 'Review all (${proposals.length})'"));
    });

    test('reject-all reverts a staged batch through the editor', () {
      // Mirrors accept-all: once the editor has applied the batch, rejecting
      // has to undo those edits as well as mark the rows rejected, or the
      // operator is left with an unsaved page full of unexplained changes.
      final body = rejectAllBody();
      final discard = body.indexOf('final discard = ref.read(proposalDiscardProvider);');
      final fallback = body.indexOf('notifier.rejectProposal(p.id)');
      expect(discard, greaterThan(-1));
      expect(fallback, greaterThan(-1));
      expect(discard, lessThan(fallback),
          reason: 'plain rejectProposal would leave the staged edits on screen');
      expect(body, contains('discard();'));
    });

    test('reject-all with nothing staged still clears every row', () {
      expect(rejectAllBody(), contains('for (final p in proposals)'));
    });

    test('the expanded drawer is capped so a long queue cannot fill the page',
        () {
      expect(bannerSource, contains('maxHeight: 220'));
      expect(bannerSource, contains('shrinkWrap: true'));
    });
  });

  group('ProposalBanner navigation', () {
    late String bannerSource;

    setUpAll(() {
      bannerSource =
          File('lib/widgets/proposal_banner.dart').readAsStringSync();
    });

    test('editorRoute is used to navigate, not to hide', () {
      expect(bannerSource, contains('proposal.editorRoute'));
      expect(bannerSource, contains('beamToNamed(route, data:'));
    });

    test('every proposal type has an editor route to beam to', () {
      // A type with no route leaves View and Review all dead, so the proposal
      // can only be accepted blind from the banner.
      final routeSource =
          File('lib/providers/proposal.dart').readAsStringSync();

      expect(routeSource, contains("'alarm': '/advanced/alarm-editor'"));
      expect(routeSource, contains("'alarm_create': '/advanced/alarm-editor'"));
      expect(routeSource, contains("'alarm_update': '/advanced/alarm-editor'"));
      expect(
          routeSource, contains("'key_mapping': '/advanced/key-repository'"));
      expect(routeSource, contains("'page': '/advanced/page-editor'"));
      expect(routeSource, contains("'asset': '/advanced/page-editor'"));
      expect(routeSource, contains("'asset_update': '/advanced/page-editor'"));
    });

    test('banner uses navigatorKeyProvider for Beamer context', () {
      // The banner can't use its own context for Beamer.of() because it
      // sits in the MaterialApp.builder Stack above the Navigator. It must
      // use navigatorKeyProvider to get the correct context.
      expect(bannerSource, contains('navigatorKeyProvider'));
      expect(bannerSource, contains('navKey'));
    });

    test('navigation carries the proposal json to the editor', () {
      // Every button opens the editor through the same helper, so the json is
      // threaded in one place -- into the editor already on screen, and into
      // the beam that opens it when it is not.
      expect(bannerSource, contains('entry.enter(proposal.proposalJson)'));
      expect(bannerSource, contains('data: proposal.proposalJson'));
      // ...and the batch buttons reach it by handing over their first
      // proposal, rather than by repeating the beam with their own json.
      expect(bannerSource, contains('_openEditorTakes(proposals.first)'));
    });
  });
}

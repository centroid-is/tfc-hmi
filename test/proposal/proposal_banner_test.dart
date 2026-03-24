import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/proposal_visual.dart';

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

  // ── ProposalBanner route-aware visibility (Bug fix) ──────────────────
  //
  // Regression tests for a bug where both the dark persistent ProposalBanner
  // AND the amber in-editor banner showed simultaneously when the user was
  // already on the correct editor page. The fix filters out proposals whose
  // editorRoute matches the current Beamer route path.
  //
  // ProposalBanner depends on proposalStateProvider, navigatorKeyProvider,
  // and Beamer, so we use source-level assertions (same pattern as
  // alarm_editor_proposal_test.dart and page_editor_proposal_test.dart).

  group('Bug fix: ProposalBanner hides when on matching editor route', () {
    late String bannerSource;

    setUpAll(() {
      bannerSource =
          File('lib/widgets/proposal_banner.dart').readAsStringSync();
    });

    test('has _currentRoutePath helper that reads Beamer route', () {
      // The banner must be able to determine the current route to decide
      // whether to hide proposals whose editor is already visible.
      expect(bannerSource, contains('_currentRoutePath'));
      expect(bannerSource, contains('Beamer.of'));
      expect(bannerSource, contains('routeInformation'));
    });

    test('returns SizedBox.shrink when no pending proposals', () {
      // First guard: if (!state.hasPending) return const SizedBox.shrink()
      expect(bannerSource, contains('!state.hasPending'));
      expect(bannerSource, contains('SizedBox.shrink()'));
    });

    test('filters proposals by comparing editorRoute to current path', () {
      // The core fix: proposals whose editorRoute matches the current path
      // are filtered out, so the dark banner doesn't duplicate the amber
      // in-editor banner.
      expect(bannerSource, contains('currentPath'));
      expect(bannerSource, contains('p.editorRoute'));
      expect(bannerSource, contains('currentPath.contains(p.editorRoute!)'));
    });

    test('only filters when currentPath is available', () {
      // When Beamer context is unavailable (e.g. app startup), currentPath
      // is null and no filtering occurs — all proposals are shown.
      expect(bannerSource, contains('currentPath != null'));
    });

    test('returns SizedBox.shrink when all proposals are filtered out', () {
      // If the user is on the editor page and ALL pending proposals target
      // that editor, the filtered list is empty → SizedBox.shrink().
      expect(bannerSource, contains('if (proposals.isEmpty) return const SizedBox.shrink()'));
    });

    test('filters use where clause that checks editorRoute null OR not matching', () {
      // The filter keeps proposals where editorRoute is null (no known editor)
      // OR the current path does NOT contain the editorRoute. This ensures
      // proposals without a known route are always shown in the dark banner.
      final whereClause = RegExp(
        r'p\.editorRoute\s*==\s*null\s*\|\|\s*!currentPath\.contains\(p\.editorRoute!\)',
      );
      expect(
        bannerSource,
        matches(whereClause),
        reason: 'Filter must keep proposals with null editorRoute or '
            'non-matching editorRoute',
      );
    });

    test('uses filtered list (not state.proposals) for rendering', () {
      // After filtering, the banner must use the filtered `proposals` list
      // (not `state.proposals`) when building single/multi proposal views.
      // The count variable should be derived from the filtered list.
      expect(bannerSource, contains('final count = proposals.length'));
      expect(bannerSource, contains('_buildSingleProposal(proposals.first)'));
      expect(bannerSource, contains('_buildMultipleProposals(proposals, count)'));
    });

    test('watches proposalStateProvider reactively', () {
      // The banner must use ref.watch (not ref.read) so it rebuilds when
      // proposals are added, accepted, or rejected.
      expect(bannerSource, contains('ref.watch(proposalStateProvider)'));
    });

    test('_currentRoutePath catches errors gracefully', () {
      // If Beamer is not available (e.g. during testing or before the router
      // is mounted), _currentRoutePath should return null, not throw.
      expect(bannerSource, contains('catch (_)'));
      expect(bannerSource, contains('return null'));
    });
  });

  group('ProposalBanner multi-proposal route filtering', () {
    late String bannerSource;

    setUpAll(() {
      bannerSource =
          File('lib/widgets/proposal_banner.dart').readAsStringSync();
    });

    test('with mixed proposals, only shows proposals for OTHER editors', () {
      // Scenario: user is on /advanced/alarm-editor. There are 2 alarm
      // proposals and 1 page proposal. The banner should show only the
      // page proposal (alarm ones are handled by the amber in-editor banner).
      //
      // The filter: state.proposals.where((p) =>
      //     p.editorRoute == null || !currentPath.contains(p.editorRoute!))
      //
      // For alarm proposal: editorRoute = '/advanced/alarm-editor'
      //   currentPath.contains('/advanced/alarm-editor') → true → filtered OUT
      // For page proposal: editorRoute = '/advanced/page-editor'
      //   currentPath.contains('/advanced/page-editor') → false → kept
      //
      // This logic is validated by checking the source uses the where clause
      // with contains() comparison on the editorRoute.
      expect(bannerSource, contains('.where((p)'));
      expect(bannerSource, contains('p.editorRoute == null'));
      expect(bannerSource, contains('!currentPath.contains(p.editorRoute!)'));
    });

    test('proposal routes in watcher match banner filter expectations', () {
      // Verify that proposalRoutes in proposal_watcher.dart define the
      // routes that ProposalBanner uses for filtering. Each editor must
      // have a distinct route so proposals for other editors remain visible.
      final watcherSource =
          File('lib/providers/proposal_watcher.dart').readAsStringSync();

      // All known proposal types have routes defined
      expect(watcherSource, contains("'alarm': '/advanced/alarm-editor'"));
      expect(watcherSource, contains("'key_mapping': '/advanced/key-repository'"));
      expect(watcherSource, contains("'page': '/advanced/page-editor'"));
      expect(watcherSource, contains("'asset': '/advanced/page-editor'"));

      // The banner imports or uses editorRoute which reads from these routes
      expect(bannerSource, contains('p.editorRoute'));
    });

    test('banner uses navigatorKeyProvider for Beamer context', () {
      // The banner can't use its own context for Beamer.of() because it
      // sits in the MaterialApp.builder Stack above the Navigator. It must
      // use navigatorKeyProvider to get the correct context.
      expect(bannerSource, contains('navigatorKeyProvider'));
      expect(bannerSource, contains('navKey'));
    });
  });
}

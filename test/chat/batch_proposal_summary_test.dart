import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc/chat/batch_proposal_summary.dart';
import 'package:tfc/providers/proposal_state.dart';
import 'package:tfc/providers/proposal_watcher.dart';

PendingProposal _makeProposal({
  required int id,
  String type = 'alarm',
  String title = 'Test Alarm',
  String? json,
  String operator = 'op1',
}) =>
    PendingProposal(
      id: id,
      proposalType: type,
      title: title,
      proposalJson:
          json ?? '{"_proposal_type":"$type","uid":"$id","title":"$title"}',
      operatorId: operator,
      createdAt: DateTime.now(),
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('BatchProposalSummary', () {
    testWidgets('renders nothing when no proposals', (tester) async {
      await tester.pumpWidget(_wrap(const BatchProposalSummary()));
      await tester.pump();

      expect(find.byType(BatchProposalSummary), findsOneWidget);
      // Should render a SizedBox.shrink, not any visible card
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsNothing);
    });

    testWidgets('renders nothing with only 1 proposal of a type',
        (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(id: 1));

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider
              .overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Only 1 alarm proposal -- batch summary should not appear
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsNothing);
    });

    testWidgets('shows batch card when 2+ proposals of same type',
        (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      for (var i = 1; i <= 5; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          title: 'Motor $i Fault',
          json:
              '{"_proposal_type":"alarm","uid":"m$i","title":"Motor $i Fault"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider
              .overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Batch card should appear for alarm type
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsOneWidget);
      expect(
          find.textContaining('5 Alarm proposals pending'), findsOneWidget);
    });

    testWidgets('shows Accept All and Reject All buttons', (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      for (var i = 1; i <= 3; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          title: 'Alarm $i',
          json:
              '{"_proposal_type":"alarm","uid":"a$i","title":"Alarm $i"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider
              .overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      expect(find.text('Accept All (3)'), findsOneWidget);
      expect(find.text('Reject All'), findsOneWidget);
    });

    testWidgets('shows separate batch cards for different types',
        (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      // 3 alarm proposals
      for (var i = 1; i <= 3; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          type: 'alarm',
          title: 'Alarm $i',
          json:
              '{"_proposal_type":"alarm","uid":"a$i","title":"Alarm $i"}',
        ));
      }
      // 2 page proposals
      for (var i = 4; i <= 5; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          type: 'page',
          title: 'Page ${i - 3}',
          json:
              '{"_proposal_type":"page","uid":"p$i","title":"Page ${i - 3}"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider
              .overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Both batch cards should appear
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('batch-proposal-page')),
          findsOneWidget);
      expect(
          find.textContaining('3 Alarm proposals pending'), findsOneWidget);
      expect(
          find.textContaining('2 Page proposals pending'), findsOneWidget);
    });

    testWidgets('does not show batch card for type with only 1 proposal',
        (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      // 3 alarm proposals
      for (var i = 1; i <= 3; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          type: 'alarm',
          title: 'Alarm $i',
          json:
              '{"_proposal_type":"alarm","uid":"a$i","title":"Alarm $i"}',
        ));
      }
      // Only 1 page proposal -- should NOT get a batch card
      notifier.addProposal(_makeProposal(
        id: 4,
        type: 'page',
        title: 'Page 1',
        json: '{"_proposal_type":"page","uid":"p4","title":"Page 1"}',
      ));

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider
              .overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('batch-proposal-page')),
          findsNothing);
    });

    // ─── Reject All behavior ─────────────────────────────────────────

    testWidgets('Reject All removes proposals and hides batch card',
        (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      for (var i = 1; i <= 3; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          title: 'Alarm $i',
          json:
              '{"_proposal_type":"alarm","uid":"r$i","title":"Alarm $i"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Batch card should be visible
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsOneWidget);
      expect(find.text('Reject All'), findsOneWidget);

      // Tap Reject All
      await tester.tap(
          find.byKey(const ValueKey<String>('batch-reject-all-alarm')));
      await tester.pumpAndSettle();

      // Batch card should disappear
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsNothing);

      // Notifier state should have no proposals
      expect(notifier.state.pendingCount, 0);
    });

    // ─── Accept All behavior (no Beamer) ─────────────────────────────

    testWidgets('Accept All removes proposals from state',
        (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      for (var i = 1; i <= 3; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          title: 'Alarm $i',
          json:
              '{"_proposal_type":"alarm","uid":"aa$i","title":"Alarm $i"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      expect(find.text('Accept All (3)'), findsOneWidget);

      // Tap Accept All (Beamer.of will throw, but onPressed catches it)
      await tester.tap(
          find.byKey(const ValueKey<String>('batch-accept-all-alarm')));
      await tester.pumpAndSettle();

      // Batch card should disappear because all alarm proposals removed
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsNothing);

      // Notifier state should have no proposals
      expect(notifier.state.pendingCount, 0);
    });

    // ─── Mixed batch: Accept All of one type preserves other ─────────

    testWidgets(
        'Accept All of one type preserves proposals of other types',
        (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      // 2 alarm proposals
      for (var i = 1; i <= 2; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          type: 'alarm',
          title: 'Alarm $i',
          json:
              '{"_proposal_type":"alarm","uid":"mix$i","title":"Alarm $i"}',
        ));
      }
      // 2 page proposals
      for (var i = 3; i <= 4; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          type: 'page',
          title: 'Page ${i - 2}',
          json:
              '{"_proposal_type":"page","uid":"mix$i","title":"Page ${i - 2}"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Both batch cards should be visible
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('batch-proposal-page')),
          findsOneWidget);

      // Accept all alarms
      await tester.tap(
          find.byKey(const ValueKey<String>('batch-accept-all-alarm')));
      await tester.pumpAndSettle();

      // Alarm batch card gone, page batch card still present
      expect(find.byKey(const ValueKey<String>('batch-proposal-alarm')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('batch-proposal-page')),
          findsOneWidget);

      // 2 page proposals should remain
      expect(notifier.state.pendingCount, 2);
      expect(notifier.state.ofType('alarm'), isEmpty);
      expect(notifier.state.ofType('page'), hasLength(2));
    });

    // ─── Type label mapping ──────────────────────────────────────────

    testWidgets('maps alarm_create to Alarm label', (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      for (var i = 1; i <= 2; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          type: 'alarm_create',
          title: 'Alarm $i',
          json:
              '{"_proposal_type":"alarm_create","uid":"ac$i","title":"Alarm $i"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('2 Alarm proposals pending'), findsOneWidget);
    });

    testWidgets('maps unknown type to Config label', (tester) async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      for (var i = 1; i <= 2; i++) {
        notifier.addProposal(_makeProposal(
          id: i,
          type: 'custom_thing',
          title: 'Custom $i',
          json:
              '{"_proposal_type":"custom_thing","uid":"ct$i","title":"Custom $i"}',
        ));
      }

      await tester.pumpWidget(_wrap(
        const BatchProposalSummary(),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      expect(
          find.textContaining('2 Config proposals pending'), findsOneWidget);
    });
  });
}

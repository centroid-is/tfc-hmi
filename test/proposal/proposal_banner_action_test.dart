import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/providers/proposal_state.dart';
import 'package:tfc/widgets/proposal_banner.dart';

/// The banner labels every proposal with what accepting it *does* — CREATE,
/// EDIT or DELETE — because the title alone doesn't say: a key-mapping
/// proposal titled "conveyor.speed" reads identically whether the AI wants
/// to add the mapping or remove it.
///
/// The action comes from the `_op` field the MCP server stamps into the
/// proposal JSON; proposals recorded before `_op` existed fall back to the
/// proposal type name.
PendingProposal _proposal({
  int id = 1,
  String type = 'key_mapping',
  String title = 'conveyor.speed',
  String json = '{}',
}) =>
    PendingProposal(
      id: id,
      proposalType: type,
      title: title,
      proposalJson: json,
      operatorId: 'op',
      createdAt: DateTime(2026, 8, 20),
    );

Widget _banner(List<PendingProposal> proposals) {
  return ProviderScope(
    overrides: [
      proposalStateProvider.overrideWith((ref) {
        final notifier = ProposalStateNotifier(null);
        for (final p in proposals) {
          notifier.addProposal(p);
        }
        return notifier;
      }),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Stack(children: [ProposalBanner()]),
      ),
    ),
  );
}

void main() {
  group('PendingProposal.action', () {
    test('reads _op create from the proposal JSON', () {
      expect(_proposal(json: '{"_op":"create","key":"a"}').action,
          ProposalOp.create);
    });

    test('reads _op update from the proposal JSON', () {
      expect(_proposal(json: '{"_op":"update","key":"a"}').action,
          ProposalOp.update);
    });

    test('reads _op delete from the proposal JSON', () {
      expect(_proposal(json: '{"_op":"delete","key":"a"}').action,
          ProposalOp.delete);
    });

    test('falls back to the type name for pre-_op update proposals', () {
      expect(_proposal(type: 'asset_update').action, ProposalOp.update);
      expect(_proposal(type: 'alarm_update').action, ProposalOp.update);
    });

    test('pre-_op proposals of the remaining types were creates', () {
      for (final type in ['alarm', 'page', 'asset', 'key_mapping']) {
        expect(_proposal(type: type).action, ProposalOp.create,
            reason: type);
      }
    });

    test('malformed JSON still yields an action rather than throwing', () {
      expect(_proposal(json: 'not json').action, ProposalOp.create);
      expect(_proposal(json: 'not json', type: 'asset_update').action,
          ProposalOp.update);
    });

    test('an unknown _op value falls back to the type name', () {
      expect(_proposal(json: '{"_op":"replace"}', type: 'asset_update').action,
          ProposalOp.update);
    });
  });

  group('ProposalBanner action labels', () {
    testWidgets('a single delete proposal is labelled DELETE', (tester) async {
      await tester.pumpWidget(_banner([
        _proposal(json: '{"_op":"delete","key":"conveyor.speed"}'),
      ]));

      expect(find.text('DELETE'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('CREATE'), findsNothing);
    });

    testWidgets('the collapsed header says what the batch does',
        (tester) async {
      await tester.pumpWidget(_banner([
        _proposal(id: 1, json: '{"_op":"create","key":"a"}'),
        _proposal(id: 2, json: '{"_op":"create","key":"b"}'),
        _proposal(id: 3, json: '{"_op":"update","key":"c"}'),
        _proposal(id: 4, json: '{"_op":"delete","key":"d"}'),
      ]));

      expect(find.textContaining('4 AI Proposals'), findsOneWidget);
      expect(find.textContaining('2 create · 1 edit · 1 delete'),
          findsOneWidget);
    });

    testWidgets('the summary lists only the actions present', (tester) async {
      await tester.pumpWidget(_banner([
        _proposal(id: 1, json: '{"_op":"delete","key":"a"}'),
        _proposal(id: 2, json: '{"_op":"delete","key":"b"}'),
      ]));

      expect(find.textContaining('2 delete'), findsOneWidget);
    });

    testWidgets('every expanded row carries its own action chip',
        (tester) async {
      await tester.pumpWidget(_banner([
        _proposal(id: 1, json: '{"_op":"create","key":"a"}'),
        _proposal(id: 2, json: '{"_op":"update","key":"b"}'),
        _proposal(id: 3, json: '{"_op":"delete","key":"c"}'),
      ]));

      await tester.tap(find.textContaining('3 AI Proposals'));
      await tester.pumpAndSettle();

      expect(find.text('CREATE'), findsOneWidget);
      expect(find.text('EDIT'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });
  });
}

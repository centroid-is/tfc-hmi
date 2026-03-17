import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc/chat/proposal_action.dart';
import 'package:tfc/providers/proposal_state.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────

PendingProposal _makeProposal({
  required int id,
  String type = 'alarm',
  String title = 'Test Alarm',
  required String json,
  String operator = 'op1',
}) =>
    PendingProposal(
      id: id,
      proposalType: type,
      title: title,
      proposalJson: json,
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
  // ─── Source-level assertions ──────────────────────────────────────────

  group('ProposalAction status integration (source)', () {
    late String source;

    setUpAll(() {
      source = File('lib/chat/proposal_action.dart').readAsStringSync();
    });

    test('imports proposal_state.dart', () {
      expect(source, contains('proposal_state.dart'));
    });

    test('watches proposalStateProvider for status', () {
      expect(source, contains('proposalStateProvider'));
    });

    test('shows status indicator (pending/processed)', () {
      expect(source, contains('Colors.amber'));
    });

    test('shows correct label for each proposal type', () {
      expect(source, contains('Open in Alarm Editor'));
      expect(source, contains('Open in Key Repository'));
      expect(source, contains('Open in Page Editor'));
    });
  });

  // ─── Widget-level tests: status dot color ────────────────────────────

  group('ProposalAction status dot', () {
    testWidgets('shows amber dot when proposal is pending', (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Test Alarm',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(id: 1, json: proposalJson));

      await tester.pumpWidget(_wrap(
        ProposalAction(proposalJson: proposalJson),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Find the 8x8 status dot container
      final dotFinder = find.byWidgetPredicate((widget) {
        if (widget is Container) {
          final decoration = widget.decoration;
          if (decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle) {
            return decoration.color == Colors.amber;
          }
        }
        return false;
      });

      expect(dotFinder, findsOneWidget,
          reason: 'Should show amber dot for pending proposal');
    });

    testWidgets('shows grey dot when proposal is not pending (processed)',
        (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Test Alarm',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      // Empty notifier — no proposals pending (simulates already processed)
      final notifier = ProposalStateNotifier(db);

      await tester.pumpWidget(_wrap(
        ProposalAction(proposalJson: proposalJson),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Find the grey status dot
      final greyDot = find.byWidgetPredicate((widget) {
        if (widget is Container) {
          final decoration = widget.decoration;
          if (decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle) {
            return decoration.color == Colors.grey;
          }
        }
        return false;
      });

      expect(greyDot, findsOneWidget,
          reason: 'Should show grey dot for processed proposal');
    });

    testWidgets('dot transitions from amber to grey after acceptance',
        (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Test Alarm',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(id: 1, json: proposalJson));

      await tester.pumpWidget(_wrap(
        ProposalAction(proposalJson: proposalJson),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Verify amber dot initially
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Container) {
            final decoration = widget.decoration;
            if (decoration is BoxDecoration &&
                decoration.shape == BoxShape.circle) {
              return decoration.color == Colors.amber;
            }
          }
          return false;
        }),
        findsOneWidget,
        reason: 'Should start with amber dot',
      );

      // Accept the proposal
      await notifier.acceptProposal(1);
      await tester.pump();

      // Verify grey dot after acceptance
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Container) {
            final decoration = widget.decoration;
            if (decoration is BoxDecoration &&
                decoration.shape == BoxShape.circle) {
              return decoration.color == Colors.grey;
            }
          }
          return false;
        }),
        findsOneWidget,
        reason: 'Should show grey dot after acceptance',
      );

      // Verify amber dot is gone
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Container) {
            final decoration = widget.decoration;
            if (decoration is BoxDecoration &&
                decoration.shape == BoxShape.circle) {
              return decoration.color == Colors.amber;
            }
          }
          return false;
        }),
        findsNothing,
        reason: 'Amber dot should be gone after acceptance',
      );
    });

    testWidgets('dot transitions from amber to grey after rejection',
        (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'page',
        'uid': 'p1',
        'title': 'Test Page',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(
        id: 2,
        type: 'page',
        json: proposalJson,
        title: 'Test Page',
      ));

      await tester.pumpWidget(_wrap(
        ProposalAction(proposalJson: proposalJson),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Reject the proposal
      await notifier.rejectProposal(2);
      await tester.pump();

      // Verify grey dot after rejection
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Container) {
            final decoration = widget.decoration;
            if (decoration is BoxDecoration &&
                decoration.shape == BoxShape.circle) {
              return decoration.color == Colors.grey;
            }
          }
          return false;
        }),
        findsOneWidget,
        reason: 'Should show grey dot after rejection',
      );
    });

    testWidgets('fallback button has no status dot for unknown types',
        (tester) async {
      final json =
          jsonEncode({'_proposal_type': 'unknown_xyz', 'data': 'stuff'});

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());
      final notifier = ProposalStateNotifier(db);

      await tester.pumpWidget(_wrap(
        ProposalAction(proposalJson: json),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Unknown types use fallback button which has no status dot
      expect(find.text('View Proposal'), findsOneWidget);

      // No circle dot should be present
      final dots = find.byWidgetPredicate((widget) {
        if (widget is Container) {
          final decoration = widget.decoration;
          if (decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle) {
            return true;
          }
        }
        return false;
      });

      expect(dots, findsNothing,
          reason: 'Fallback button should not show a status dot');
    });
  });
}

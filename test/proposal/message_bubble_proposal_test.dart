import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc/chat/message_bubble.dart';
import 'package:tfc/llm/llm_models.dart';
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

  group('MessageBubble proposal status colors (source)', () {
    late String source;

    setUpAll(() {
      source = File('lib/chat/message_bubble.dart').readAsStringSync();
    });

    test('imports proposal_state.dart', () {
      expect(source, contains('proposal_state.dart'));
    });

    test('watches proposalStateProvider for status coloring', () {
      expect(source, contains('proposalStateProvider'));
    });

    test('has amber status for pending proposals', () {
      expect(source, contains('Colors.amber'));
    });

    test('shows proposal status indicator near ProposalAction', () {
      expect(source, contains('ProposalAction'));
      expect(source, contains('proposalStateProvider'));
    });
  });

  // ─── Widget-level tests: assistant bubble amber border ───────────────

  group('MessageBubble assistant bubble amber border', () {
    testWidgets('shows amber border when proposal is pending', (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Test Alarm',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(
        id: 1,
        json: proposalJson,
      ));

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: ChatMessage.assistant(proposalJson),
        ),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Find the assistant bubble container
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bubbleWithBorder = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          final border = decoration.border as Border;
          return border.top.color == Colors.amber;
        }
        return false;
      });

      expect(bubbleWithBorder.isNotEmpty, isTrue,
          reason: 'Should have an amber-bordered container for pending proposal');
    });

    testWidgets('no amber border when proposal is not pending',
        (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Test Alarm',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      // Empty notifier — no proposals pending
      final notifier = ProposalStateNotifier(db);

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: ChatMessage.assistant(proposalJson),
        ),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // No container should have an amber border
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bubbleWithAmberBorder = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          final border = decoration.border as Border;
          return border.top.color == Colors.amber;
        }
        return false;
      });

      expect(bubbleWithAmberBorder.isEmpty, isTrue,
          reason:
              'Should NOT have an amber-bordered container when no pending proposal');
    });

    testWidgets('amber border disappears after proposal is accepted',
        (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Test Alarm',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(
        id: 1,
        json: proposalJson,
      ));

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: ChatMessage.assistant(proposalJson),
        ),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Verify amber border exists initially
      var containers = tester.widgetList<Container>(find.byType(Container));
      var amberBorders = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          final border = decoration.border as Border;
          return border.top.color == Colors.amber;
        }
        return false;
      });
      expect(amberBorders.isNotEmpty, isTrue,
          reason: 'Amber border should exist before accept');

      // Accept the proposal (removes from state)
      await notifier.acceptProposal(1);
      await tester.pump();

      // Verify amber border is gone
      containers = tester.widgetList<Container>(find.byType(Container));
      amberBorders = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          final border = decoration.border as Border;
          return border.top.color == Colors.amber;
        }
        return false;
      });
      expect(amberBorders.isEmpty, isTrue,
          reason: 'Amber border should be gone after accept');
    });
  });

  // ─── Widget-level tests: tool result proposal card amber border ──────

  group('MessageBubble tool result proposal card border', () {
    testWidgets('shows amber border when proposal is pending', (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Pump Fault',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(
        id: 1,
        json: proposalJson,
        title: 'Pump Fault',
      ));

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: ChatMessage.toolResult('tc1', proposalJson),
        ),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Should have an amber-bordered container
      final containers = tester.widgetList<Container>(find.byType(Container));
      final amberBorders = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          final border = decoration.border as Border;
          return border.top.color == Colors.amber;
        }
        return false;
      });

      expect(amberBorders.isNotEmpty, isTrue,
          reason: 'Tool result card should have amber border when pending');
    });

    testWidgets('amber border becomes subtle after proposal is accepted',
        (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Pump Fault',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(
        id: 1,
        json: proposalJson,
        title: 'Pump Fault',
      ));

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: ChatMessage.toolResult('tc1', proposalJson),
        ),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Accept the proposal
      await notifier.acceptProposal(1);
      await tester.pump();

      // Amber border should be gone
      final containers = tester.widgetList<Container>(find.byType(Container));
      final amberBorders = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          final border = decoration.border as Border;
          return border.top.color == Colors.amber;
        }
        return false;
      });

      expect(amberBorders.isEmpty, isTrue,
          reason:
              'Tool result card should NOT have amber border after accept');
    });

    testWidgets('lightbulb icon turns grey after proposal is processed',
        (tester) async {
      final proposalJson = jsonEncode({
        '_proposal_type': 'alarm',
        'uid': 'a1',
        'title': 'Pump Fault',
      });

      final db = AppDatabase.inMemoryForTest();
      addTearDown(() async => await db.close());

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(_makeProposal(
        id: 1,
        json: proposalJson,
        title: 'Pump Fault',
      ));

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: ChatMessage.toolResult('tc1', proposalJson),
        ),
        overrides: [
          proposalStateProvider.overrideWith((ref) => notifier),
        ],
      ));
      await tester.pump();

      // Initially pending: lightbulb should be amber
      var lightbulbs = tester.widgetList<Icon>(find.byIcon(Icons.lightbulb));
      expect(lightbulbs.any((icon) => icon.color == Colors.amber), isTrue,
          reason: 'Lightbulb should be amber when pending');

      // Accept the proposal
      await notifier.acceptProposal(1);
      await tester.pump();

      // After accept: lightbulb should be grey
      lightbulbs = tester.widgetList<Icon>(find.byIcon(Icons.lightbulb));
      expect(lightbulbs.any((icon) => icon.color == Colors.grey), isTrue,
          reason: 'Lightbulb should be grey after accept');
    });
  });
}

/// The "Rows never stored" section of the database pane.
///
/// Before this, `Database.getStats()` reported writes and waits and nothing
/// about discards, and this pane showed neither. A thirty-second outage could
/// take two thirds of a tag's samples — oldest first, so the start of the
/// incident — with nothing anywhere an operator would look.
///
/// The section is rendered from a plain stats map rather than a live Database,
/// so these cases are exact and need no server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/panes/database_stats_pane.dart';

void main() {
  /// A stats map shaped like the one [Database.getStats] returns.
  Map<String, dynamic> stats({
    int dropped = 0,
    int poisoned = 0,
    int queued = 0,
    Map<String, int> droppedByTable = const {},
    Map<String, int> poisonedByTable = const {},
  }) =>
      {
        'total_writes': 10,
        'dropped_rows': dropped,
        'dropped_rows_by_table': droppedByTable,
        'poisoned_rows': poisoned,
        'poisoned_rows_by_table': poisonedByTable,
        'queued_rows': queued,
        'queued_rows_by_table': const <String, int>{},
        'max_queued_rows_per_table': 10000,
        'max_queued_rows_total': 200000,
      };

  Future<void> pump(WidgetTester tester, Map<String, dynamic> s,
      {bool collectsHere = true}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DatabaseWriteQueueView(stats: s, collectsHere: collectsHere),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The value rendered under a tile label.
  String valueUnder(WidgetTester tester, String label) {
    // Each tile renders its label and its value as sibling Texts; the pane's
    // tiles keep them in one subtree, so search from the label's ancestor.
    final tile = find.ancestor(
      of: find.text(label),
      matching: find.byType(Column),
    );
    final texts = tester
        .widgetList<Text>(find.descendant(of: tile.first, matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    return texts.firstWhere((t) => t != label);
  }

  group('the numbers', () {
    testWidgets('a clean pipeline shows zeros and says nothing was lost',
        (tester) async {
      await pump(tester, stats());
      expect(valueUnder(tester, 'Discarded'), '0');
      expect(valueUnder(tester, 'Rejected'), '0');
      expect(find.textContaining('Nothing has been discarded'), findsOneWidget);
    });

    testWidgets('discarded rows are shown, not just logged', (tester) async {
      // The measured case: 300 samples across an outage, 200 gone.
      await pump(
          tester,
          stats(dropped: 200, droppedByTable: {'cn01.motor.speed': 200}));
      expect(valueUnder(tester, 'Discarded'), '200');
      expect(find.textContaining('cn01.motor.speed'), findsOneWidget,
          reason: 'Which tag stopped recording is the actionable part.');
    });

    testWidgets('rejected rows are counted apart from discarded ones',
        (tester) async {
      // Different cause, different remedy: overflow means the outage outlasted
      // the buffer; rejection means a value cannot fit its column.
      await pump(
          tester,
          stats(poisoned: 7, poisonedByTable: {'cn03.counter': 7}));
      expect(valueUnder(tester, 'Rejected'), '7');
      expect(valueUnder(tester, 'Discarded'), '0');
      expect(find.textContaining('BIGINT'), findsOneWidget,
          reason: 'The remedy for a rejected batch is to widen the column, so '
              'the pane should say so.');
    });

    testWidgets('a tag with both kinds of loss shows both', (tester) async {
      await pump(
          tester,
          stats(
            dropped: 5,
            poisoned: 3,
            droppedByTable: {'cn03.counter': 5},
            poisonedByTable: {'cn03.counter': 3},
          ));
      expect(find.textContaining('5 discarded'), findsOneWidget);
      expect(find.textContaining('3 rejected'), findsOneWidget);
    });

    testWidgets('queue depth is shown before anything has been lost',
        (tester) async {
      await pump(tester, stats(queued: 4200));
      expect(valueUnder(tester, 'Waiting'), '4200');
      expect(valueUnder(tester, 'Discarded'), '0');
      expect(find.textContaining('10000'), findsOneWidget,
          reason: 'The depth only means something next to the cap it is '
              'heading for.');
    });
  });

  group('honesty about which process these numbers describe', () {
    testWidgets('says so when this process does not collect', (tester) async {
      await pump(tester, stats(), collectsHere: false);
      expect(find.textContaining('does not collect data'), findsOneWidget,
          reason: 'On an HMI station these read zero because collection runs '
              'in the backend service. A permanent zero that looks like a '
              'health indicator is worse than no indicator: it reads as "no '
              'data has been lost" when it means "this process never wrote".');
      expect(find.textContaining('Nothing has been discarded'), findsNothing,
          reason: 'That reassurance would be unearned here.');
    });

    testWidgets('does not disclaim when this process is the writer',
        (tester) async {
      await pump(tester, stats(), collectsHere: true);
      expect(find.textContaining('does not collect data'), findsNothing);
    });
  });

  group('resilience of the section itself', () {
    testWidgets('a stats map missing the new keys renders as zeros, not a crash',
        (tester) async {
      // An older Database, or a snapshot taken before the counters existed.
      await pump(tester, {'total_writes': 3});
      expect(valueUnder(tester, 'Discarded'), '0');
      expect(tester.takeException(), isNull);
    });
  });
}

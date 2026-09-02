/// The table's Timestamp column must carry the date once the rows cross a
/// calendar-day boundary — HH:mm:ss alone made a multi-day range unreadable
/// (every midnight looked like the trace rewinding).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/database.dart';

import 'package:tfc/providers/collector.dart';
import 'package:tfc/widgets/history_table_pane.dart';
import 'package:tfc/models/history_models.dart';

import '../pages/history_view_harness.dart';

Widget _buildTable({
  required Map<String, List<TimeseriesData<dynamic>>> samples,
  required DateTimeRange range,
}) {
  final keys = samples.keys.toList();
  final fakeDb = FakeHistoryDatabase(inMemoryAppDatabase(), samples);
  return ProviderScope(
    overrides: [
      collectorProvider
          .overrideWith((ref) async => FakeHistoryCollector(fakeDb, samples)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: HistoryTablePane(
          keys: keys,
          realtime: false,
          range: range,
          realtimeDuration: const Duration(minutes: 10),
          graphConfigs: {
            for (final k in keys)
              k: GraphKeyConfig(key: k, alias: k, graphIndex: 0),
          },
          rows: -1,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('rows within one day show time only', (tester) async {
    final day = DateTime(2026, 8, 30);
    await tester.pumpWidget(_buildTable(
      samples: {
        'line1.temperature': [
          TimeseriesData(4.2, day.add(const Duration(hours: 10))),
          TimeseriesData(4.7, day.add(const Duration(hours: 11))),
        ],
      },
      range: DateTimeRange(
          start: day, end: day.add(const Duration(hours: 23))),
    ));
    await settleHistory(tester);

    expect(find.text('10:00:00'), findsOneWidget);
    expect(find.text('11:00:00'), findsOneWidget);
    expect(find.textContaining('2026-08-30'), findsNothing);
  });

  testWidgets('rows spanning days carry the date', (tester) async {
    final day = DateTime(2026, 8, 30);
    await tester.pumpWidget(_buildTable(
      samples: {
        'line1.temperature': [
          TimeseriesData(4.2, day.add(const Duration(hours: 10))),
          TimeseriesData(4.7, day.add(const Duration(hours: 26))),
        ],
      },
      range: DateTimeRange(
          start: day, end: day.add(const Duration(days: 2))),
    ));
    await settleHistory(tester);

    expect(find.text('2026-08-30 10:00:00'), findsOneWidget);
    expect(find.text('2026-08-31 02:00:00'), findsOneWidget);
  });
}

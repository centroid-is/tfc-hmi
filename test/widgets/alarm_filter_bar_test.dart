/// The Alarm View's search + Active/History bar has to survive a narrow
/// column.
///
/// The alarm list is 2/5 of the page, so on a small window the bar itself
/// drops below ~250 px — narrower than the labelled toggle alone. The search
/// field is `Expanded`, so the toggle wins the layout and the row overflows to
/// the right; the operator loses the search field and gets a yellow-and-black
/// stripe instead.
///
/// The bar therefore drops the segment labels below 360 px and names each
/// segment in a tooltip. These tests pin both halves of that: the labels are
/// there when there is room, and there is no overflow when there is not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/providers/alarm.dart';
import 'package:tfc/widgets/alarm.dart';
import 'package:tfc/widgets/fuzzy_search_bar.dart';
import 'package:tfc_dart/core/alarm.dart';

/// An alarm manager with nothing active and no history.
///
/// `implements AlarmMan` rather than a subclass: the real one has a private
/// constructor and opens an OPC UA evaluation stream per alarm. The bar is
/// built on the empty-list branch too, so two empty streams are the whole
/// fixture. Anything else the widget reaches for falls through to
/// [noSuchMethod] and throws loudly.
class _EmptyAlarmMan implements AlarmMan {
  @override
  Stream<Set<AlarmActive>> activeAlarms() => Stream.value(const {});

  @override
  Stream<List<AlarmActive?>> history() => Stream.value(const []);

  @override
  List<AlarmActive> filterAlarms(List<AlarmActive> alarms, String query) =>
      alarms;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pumps the alarm list into a column exactly [width] wide, the way the Alarm
/// View page hands it 2/5 of the window.
Future<void> _pumpBar(WidgetTester tester, double width) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        alarmManProvider.overrideWith((ref) async => _EmptyAlarmMan()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 600,
              child: const ListActiveAlarms(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The label inside a segment, if the segment kept one.
Finder _segmentLabel(String text) => find.descendant(
      of: find.byType(SegmentedButton<AlarmViewMode>),
      matching: find.text(text),
    );

List<ButtonSegment<AlarmViewMode>> _segments(WidgetTester tester) =>
    tester.widget<SegmentedButton<AlarmViewMode>>(find.byType(SegmentedButton<AlarmViewMode>))
        .segments
        .toList();

void main() {
  group('Alarm filter bar', () {
    testWidgets('a wide bar labels the Active and History segments',
        (tester) async {
      await _pumpBar(tester, 600);

      expect(_segmentLabel('Active'), findsOneWidget);
      expect(_segmentLabel('History'), findsOneWidget);
      expect(_segments(tester).map((s) => s.tooltip), everyElement(isNull),
          reason: 'a visible label needs no tooltip to repeat it');
    });

    testWidgets('a narrow bar drops the labels and keeps the icons',
        (tester) async {
      await _pumpBar(tester, 240);

      expect(_segmentLabel('Active'), findsNothing);
      expect(_segmentLabel('History'), findsNothing);

      final segments = _segments(tester);
      expect(segments.map((s) => s.icon), everyElement(isNotNull),
          reason: 'without a label the icon is the only thing left to aim at');
    });

    testWidgets('a narrow bar names each segment in a tooltip',
        (tester) async {
      await _pumpBar(tester, 240);

      expect(_segments(tester).map((s) => s.tooltip), ['Active', 'History'],
          reason: 'an unlabelled icon must still be identifiable');
    });

    testWidgets('a narrow bar does not overflow', (tester) async {
      await _pumpBar(tester, 240);

      expect(tester.takeException(), isNull,
          reason: 'the labelled toggle alone was wider than the bar, and the '
              'Expanded search field overflowed to the right');
      expect(find.byType(FuzzySearchBar), findsOneWidget,
          reason: 'the search field must survive the narrow layout');
    });

    testWidgets('the search field keeps a positive width at 240 px',
        (tester) async {
      await _pumpBar(tester, 240);

      final searchWidth = tester.getSize(find.byType(FuzzySearchBar)).width;
      expect(searchWidth, greaterThan(0),
          reason: 'an overflowing Row leaves Expanded at zero or negative — '
              'the field is on screen but unusable');
    });
  });
}

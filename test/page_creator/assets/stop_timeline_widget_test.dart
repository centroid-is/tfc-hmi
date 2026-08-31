import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/stop_timeline.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/alarm_interval.dart';
import 'package:tfc_dart/core/alarm_tree.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import 'package:tfc_dart/core/stop_interval_source.dart';

final now = DateTime(2026, 8, 29, 14, 22);
DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

AlarmConfig alarm(
  String title, {
  required List<String> group,
  bool bindToGroup = false,
  AlarmLevel level = AlarmLevel.error,
}) =>
    AlarmConfig(
      uid: title.toLowerCase().replaceAll(' ', '-'),
      title: title,
      description: title,
      group: group,
      bindToGroup: bindToGroup,
      rules: [
        AlarmRule(
          level: level,
          expression: ExpressionConfig(value: Expression(formula: 'a')),
          acknowledgeRequired: false,
        )
      ],
    );

final alarms = [
  alarm('Multivac stopped', group: ['Line 3', 'Multivac'], bindToGroup: true),
  alarm('Film reel empty', group: ['Line 3', 'Multivac']),
  alarm('Seal temperature out of band', group: ['Line 3', 'Multivac']),
  alarm('Link error', group: ['Infrastructure'], level: AlarmLevel.warning),
];

StopIntervalSource source() => StopIntervalSource(
      closed: [
        StopActivation(
          alarmUid: 'film-reel-empty',
          interval: AlarmInterval(
              start: ago(90), end: ago(70), level: AlarmLevel.error),
        ),
        StopActivation(
          alarmUid: 'multivac-stopped',
          interval: AlarmInterval(
              start: ago(150), end: ago(140), level: AlarmLevel.error),
        ),
        StopActivation(
          alarmUid: 'link-error',
          interval: AlarmInterval(
              start: ago(60), end: ago(50), level: AlarmLevel.warning),
        ),
      ],
      open: [
        StopActivation(
          alarmUid: 'seal-temperature-out-of-band',
          interval: AlarmInterval(
              start: ago(10), end: null, level: AlarmLevel.error),
        ),
      ],
    );

Future<void> pumpTimeline(
  WidgetTester tester, {
  StopTimelineConfig? config,
  List<AlarmConfig>? configs,
  Size size = const Size(900, 420),
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: StopTimelineView(
            config: config ?? StopTimelineConfig(),
            tree: AlarmTree.fromConfigs(configs ?? alarms),
            source: source(),
            clock: now,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('StopTimelineView', () {
    testWidgets('starts collapsed, showing only the top-level groups',
        (tester) async {
      await pumpTimeline(tester);
      expect(find.text('Line 3'), findsOneWidget);
      expect(find.text('Infrastructure'), findsOneWidget);
      expect(find.text('Multivac'), findsNothing);
      expect(find.text('Film reel empty'), findsNothing);
    });

    testWidgets('expanding a group reveals what is inside it', (tester) async {
      await pumpTimeline(tester);
      await tester
          .tap(find.byKey(const ValueKey('stop-timeline-row-g:Line 3')));
      await tester.pumpAndSettle();

      expect(find.text('Multivac'), findsOneWidget);
      // still collapsed one level down
      expect(find.text('Film reel empty'), findsNothing);
    });

    testWidgets('drilling into a machine reaches the diagnosis',
        (tester) async {
      await pumpTimeline(tester);
      await tester
          .tap(find.byKey(const ValueKey('stop-timeline-row-g:Line 3')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey('stop-timeline-row-g:Line 3/Multivac')));
      await tester.pumpAndSettle();

      expect(find.text('Film reel empty'), findsOneWidget);
      expect(find.text('Seal temperature out of band'), findsOneWidget);
    });

    testWidgets('a group with its own alarm lists it as well as its members',
        (tester) async {
      await pumpTimeline(tester);
      await tester
          .tap(find.byKey(const ValueKey('stop-timeline-row-g:Line 3')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey('stop-timeline-row-g:Line 3/Multivac')));
      await tester.pumpAndSettle();

      // otherwise Multivac's lane would show intervals nothing under it
      // explains
      expect(find.text('Multivac stopped'), findsOneWidget);
    });

    testWidgets('collapsing again hides the subtree', (tester) async {
      await pumpTimeline(tester);
      final line3 =
          find.byKey(const ValueKey('stop-timeline-row-g:Line 3'));
      await tester.tap(line3);
      await tester.pumpAndSettle();
      expect(find.text('Multivac'), findsOneWidget);

      await tester.tap(line3);
      await tester.pumpAndSettle();
      expect(find.text('Multivac'), findsNothing);
    });

    testWidgets('the header counts only the alarms in scope', (tester) async {
      await pumpTimeline(tester,
          config: StopTimelineConfig(groups: [
            ['Infrastructure']
          ]));
      // one warning activation lives under Infrastructure; the three errors
      // are all in Line 3
      expect(find.text('Warning 1'), findsOneWidget);
      expect(find.text('Error 0'), findsOneWidget);
    });

    testWidgets('a scoped group is re-indented to the top level',
        (tester) async {
      await pumpTimeline(tester,
          config: StopTimelineConfig(groups: [
            ['Line 3', 'Multivac']
          ]));
      expect(find.text('Multivac'), findsOneWidget);
      expect(find.text('Line 3'), findsNothing);
      expect(find.text('Infrastructure'), findsNothing);
    });

    testWidgets('a group that no longer exists says so rather than drawing '
        'a convincing empty chart', (tester) async {
      await pumpTimeline(tester,
          config: StopTimelineConfig(groups: [
            ['Line 9']
          ]));
      expect(
          find.textContaining('No alarms are defined under'), findsOneWidget);
    });

    testWidgets('with no alarms configured at all it says that instead',
        (tester) async {
      await pumpTimeline(tester, configs: const []);
      expect(find.text('No alarms are configured yet.'), findsOneWidget);
    });

    testWidgets('a standing alarm is announced in the header', (tester) async {
      await pumpTimeline(tester);
      expect(find.text('1 standing'), findsOneWidget);
    });

    testWidgets('turning a severity off removes it from the lanes',
        (tester) async {
      await pumpTimeline(tester);
      // Infrastructure holds only the warning, so hiding warnings empties it
      expect(find.textContaining('10m · 1×'), findsWidgets);

      await tester.tap(
          find.byKey(const ValueKey('stop-timeline-level-warning')));
      await tester.pumpAndSettle();

      final infra = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data);
      expect(infra.where((t) => t != null && t.contains('10m · 1×')), isEmpty);
    });

    testWidgets('the custom header text is used when set', (tester) async {
      await pumpTimeline(tester,
          config: StopTimelineConfig(headerText: 'Packing hall stops'));
      expect(find.text('Packing hall stops'), findsOneWidget);
      expect(find.text('Stop analysis'), findsNothing);
    });

    testWidgets('at strip height the brush and detail row are dropped',
        (tester) async {
      await pumpTimeline(tester, size: const Size(620, 150));
      expect(find.text('Select an activation to inspect it.'), findsNothing);
      // the lanes themselves survive
      expect(find.text('Line 3'), findsOneWidget);
    });

    testWidgets('at full height the detail row invites a selection',
        (tester) async {
      await pumpTimeline(tester);
      expect(
          find.text('Select an activation to inspect it.'), findsOneWidget);
    });
  });

  group('the Pareto table', () {
    Future<void> openTable(WidgetTester tester) async {
      await tester
          .tap(find.byKey(const ValueKey('stop-timeline-view-table')));
      await tester.pumpAndSettle();
    }

    testWidgets('switching to it replaces the lanes', (tester) async {
      await pumpTimeline(tester);
      await openTable(tester);
      expect(find.byKey(const ValueKey('stop-timeline-pareto')),
          findsOneWidget);
      // the detail row belongs to the timeline, not the table
      expect(find.text('Select an activation to inspect it.'), findsNothing);
    });

    testWidgets('ranks the most expensive alarm first', (tester) async {
      await pumpTimeline(tester);
      await openTable(tester);
      // film reel empty ran 20m; seal temperature has been standing 10m;
      // multivac stopped ran 10m; link error ran 10m
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(labels, contains('Film reel empty'));
      expect(labels.indexOf('Film reel empty'),
          lessThan(labels.indexOf('Link error')));
    });

    testWidgets('grouping by group collapses a machine into one line',
        (tester) async {
      await pumpTimeline(tester);
      await openTable(tester);
      await tester
          .tap(find.byKey(const ValueKey('stop-timeline-pareto-group')));
      await tester.pumpAndSettle();

      expect(find.text('Line 3 › Multivac'), findsOneWidget);
      expect(find.text('Film reel empty'), findsNothing);
    });

    testWidgets('grouping by severity collapses to the three levels',
        (tester) async {
      await pumpTimeline(tester);
      await openTable(tester);
      await tester
          .tap(find.byKey(const ValueKey('stop-timeline-pareto-severity')));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
    });

    testWidgets('ranking by count asks a different question than by time',
        (tester) async {
      await pumpTimeline(tester);
      await openTable(tester);
      await tester
          .tap(find.byKey(const ValueKey('stop-timeline-rank-count')));
      await tester.pumpAndSettle();
      // still a table, now ordered by frequency
      expect(find.byKey(const ValueKey('stop-timeline-pareto')),
          findsOneWidget);
    });

    testWidgets('an alarm that did not fire in the window is not listed',
        (tester) async {
      await pumpTimeline(tester,
          config: StopTimelineConfig(groups: [
            ['Infrastructure']
          ]));
      await openTable(tester);
      expect(find.text('Link error'), findsOneWidget);
      expect(find.text('Film reel empty'), findsNothing);
    });

    testWidgets('a severity turned off drops out of the ranking',
        (tester) async {
      await pumpTimeline(tester);
      await openTable(tester);
      expect(find.text('Link error'), findsOneWidget);

      await tester.tap(
          find.byKey(const ValueKey('stop-timeline-level-warning')));
      await tester.pumpAndSettle();
      expect(find.text('Link error'), findsNothing);
    });

    testWidgets('an empty window says so rather than showing a blank table',
        (tester) async {
      await pumpTimeline(tester, configs: const []);
      // no alarms at all, so the lanes say so and there is no table to open
      expect(find.text('No alarms are configured yet.'), findsOneWidget);
    });
  });

  group('StopTimelineConfigForm', () {
    testWidgets('adding a group gives the asset another one to show',
        (tester) async {
      final config = StopTimelineConfig();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StopTimelineConfigForm(config: config)),
      ));
      await tester.tap(
          find.byKey(const ValueKey('stop-timeline-add-group')));
      await tester.pumpAndSettle();

      expect(config.groups, hasLength(1));

      await tester.enterText(
          find.byKey(const ValueKey('stop-timeline-group-0')),
          'Line 3 / Multivac');
      expect(config.groups.single, ['Line 3', 'Multivac']);
    });

    testWidgets('the period only takes a sensible number', (tester) async {
      final config = StopTimelineConfig();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StopTimelineConfigForm(config: config)),
      ));

      await tester.enterText(
          find.byKey(const ValueKey('stop-timeline-period')), '24');
      expect(config.periodHours, 24);

      // a half-typed or nonsense value must not blank the setting
      await tester.enterText(
          find.byKey(const ValueKey('stop-timeline-period')), '');
      expect(config.periodHours, 24);
      await tester.enterText(
          find.byKey(const ValueKey('stop-timeline-period')), '0');
      expect(config.periodHours, 24);
    });

    testWidgets('clearing the header text falls back to the default',
        (tester) async {
      final config = StopTimelineConfig(headerText: 'Something');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StopTimelineConfigForm(config: config)),
      ));
      await tester.enterText(
          find.byKey(const ValueKey('stop-timeline-header')), '');
      expect(config.headerText, isNull);
    });

    testWidgets('the timeline can be sized from the form', (tester) async {
      final config = StopTimelineConfig();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StopTimelineConfigForm(config: config)),
      ));

      Finder field(String label) => find.ancestor(
          of: find.text(label), matching: find.byType(TextFormField));

      await tester.enterText(field('Width %'), '55');
      await tester.enterText(field('Height %'), '40');

      expect(config.size.width, closeTo(0.55, 1e-9));
      expect(config.size.height, closeTo(0.40, 1e-9));
    });

    testWidgets('the timeline can be positioned from the form',
        (tester) async {
      final config = StopTimelineConfig();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StopTimelineConfigForm(config: config)),
      ));

      Finder field(String label) => find.ancestor(
          of: find.text(label), matching: find.byType(TextFormField));

      await tester.enterText(field('X 0-100%'), '25');
      await tester.enterText(field('Y 0-100%'), '60');

      expect(config.coordinates.x, closeTo(0.25, 1e-9));
      expect(config.coordinates.y, closeTo(0.60, 1e-9));
    });
  });
}

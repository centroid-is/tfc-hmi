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
  });
}

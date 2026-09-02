/// The alarm page's two readings: the alarm lists, and Stops — the stop
/// analysis that used to be a page-creator asset nobody could find. The
/// Alarms/Stops control is the page's own header row, deliberately not a
/// third segment of the list's Active/History toggle (that one picks which
/// *list* is shown and lives in the list's search bar). This pins the
/// round-trip (list → timeline → list) and that the loader drops alarms the
/// editor marked `countsAsStop: false`.
library;

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/pages/alarm_view.dart';
import 'package:tfc/providers/alarm.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc/widgets/alarm.dart';
import 'package:tfc/widgets/stop_timeline.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

AlarmConfig _config(String uid, {bool countsAsStop = true}) => AlarmConfig(
      uid: uid,
      title: uid,
      description: '',
      countsAsStop: countsAsStop,
      rules: [
        AlarmRule(
          level: AlarmLevel.error,
          expression: ExpressionConfig(value: Expression(formula: 'x')),
          acknowledgeRequired: false,
        ),
      ],
    );

AlarmActive _active(AlarmConfig config, DateTime at, {DateTime? ended}) =>
    AlarmActive(
      alarm: Alarm(config: config),
      notification: AlarmNotification(
        uid: config.uid,
        active: ended == null,
        expression: 'x',
        rule: config.rules.first,
        timestamp: at,
      ),
      deactivated: ended,
    );

/// The slice of [AlarmMan] the page reads: the list's two streams, and the
/// config + history the stop timeline loads.
class _FakeAlarmMan implements AlarmMan {
  _FakeAlarmMan({required this.config, this.active = const {}});

  @override
  final AlarmManConfig config;
  final Set<AlarmActive> active;

  @override
  Stream<Set<AlarmActive>> activeAlarms() => Stream.value(active);

  @override
  Stream<List<AlarmActive?>> history() => Stream.value(const []);

  @override
  List<AlarmActive> filterAlarms(List<AlarmActive> alarms, String query) =>
      alarms;

  @override
  Future<List<AlarmActive>> getRecentAlarms({
    int limit = 1000,
    DateTime? from,
    DateTime? to,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPage(WidgetTester tester, _FakeAlarmMan alarmMan) async {
  final delegate = BeamerDelegate(
    locationBuilder: RoutesLocationBuilder(routes: {
      // A fixed clock, so the timeline never starts its once-a-second live
      // repaint and the tests can pumpAndSettle.
      '/': (context, state, data) => BeamPage(
            key: const ValueKey('/'),
            title: 'Alarm View',
            child: AlarmViewPage(debugClock: DateTime(2026, 9, 1, 12)),
          ),
    }).call,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [alarmManProvider.overrideWith((ref) async => alarmMan)],
    child: BeamerProvider(
      routerDelegate: delegate,
      child: MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: BeamerParser(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // BaseScaffold's navigation bar asserts on at least two destinations.
    final registry = RouteRegistry();
    registry.menuItems.clear();
    registry.addMenuItem(
        const MenuItem(label: 'Home', path: '/', icon: Icons.home));
    registry.addMenuItem(const MenuItem(
        label: 'Alarm View', path: '/alarm-view', icon: Icons.alarm));
  });
  tearDown(() => RouteRegistry().menuItems.clear());

  final stop = _config('conveyor-jam');
  final advisory = _config('door-open', countsAsStop: false);

  testWidgets('Stops replaces the list, and the toggle leads back',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final man = _FakeAlarmMan(
      config: AlarmManConfig(alarms: [stop]),
      active: {_active(stop, DateTime(2026, 9, 1, 8))},
    );
    await _pumpPage(tester, man);

    expect(find.byType(ListActiveAlarms), findsOneWidget);
    expect(find.byType(StopTimelineView), findsNothing);

    await tester.tap(find.text('Stops'));
    await tester.pumpAndSettle();

    expect(find.byType(StopTimelineView), findsOneWidget);
    expect(find.byType(ListActiveAlarms), findsNothing,
        reason: 'the timeline is the whole page, not a third pane');

    // The list is gone, but the page's own header row is not — the way
    // back never unmounts with the list.
    await tester.tap(find.text('Alarms'));
    await tester.pumpAndSettle();

    expect(find.byType(ListActiveAlarms), findsOneWidget);
    expect(find.byType(StopTimelineView), findsNothing);
  });

  testWidgets('an alarm the editor excluded from stops draws no lane',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final man = _FakeAlarmMan(
      config: AlarmManConfig(alarms: [stop, advisory]),
      active: {
        _active(stop, DateTime(2026, 9, 1, 8)),
        _active(advisory, DateTime(2026, 9, 1, 9)),
      },
    );
    await _pumpPage(tester, man);

    await tester.tap(find.text('Stops'));
    await tester.pumpAndSettle();

    expect(find.text('conveyor-jam'), findsOneWidget);
    expect(find.text('door-open'), findsNothing,
        reason: 'countsAsStop: false keeps the advisory out of the '
            'stop analysis at the source');
  });
}

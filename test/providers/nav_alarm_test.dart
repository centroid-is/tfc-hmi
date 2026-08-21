import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/assets/alarm_visibility.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/providers/nav_alarm.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

/// An active alarm, [navigationIndicator] on unless said otherwise — every
/// case here is about what the navigation bar does with one.
AlarmActive activeFx({
  String uid = 'a1',
  AlarmLevel level = AlarmLevel.error,
  bool navigationIndicator = true,
  DateTime? timestamp,
}) {
  final rule = AlarmRule(
    level: level,
    expression: ExpressionConfig(value: Expression(formula: 'x')),
    acknowledgeRequired: false,
  );
  return AlarmActive(
    alarm: Alarm(
      config: AlarmConfig(
        uid: uid,
        title: 'Alarm $uid',
        description: 'desc',
        rules: [rule],
        navigationIndicator: navigationIndicator,
      ),
    ),
    notification: AlarmNotification(
      uid: uid,
      active: true,
      expression: 'x',
      rule: rule,
      timestamp: timestamp ?? DateTime(2026, 1, 1),
    ),
  );
}

AssetPage pageFx(String path, List<Asset> assets) => AssetPage(
      menuItem: MenuItem(label: path, path: path, icon: Icons.abc),
      assets: assets,
      mirroringDisabled: false,
    );

AlarmVisibilityConfig beacon(List<String> uids) =>
    AlarmVisibilityConfig(alarmUids: uids);

void main() {
  group('navigationAlarmLevels', () {
    test('a page with a beacon bound to an active alarm announces it', () {
      final levels = navigationAlarmLevels(
        pages: {
          '/freezer': pageFx('/freezer', [beacon(['a1'])]),
        },
        active: [activeFx(uid: 'a1', level: AlarmLevel.warning)],
      );

      expect(levels, {'/freezer': AlarmLevel.warning});
    });

    test('an alarm without the navigation flag stays out of the bar', () {
      final levels = navigationAlarmLevels(
        pages: {
          '/freezer': pageFx('/freezer', [beacon(['a1'])]),
        },
        active: [activeFx(uid: 'a1', navigationIndicator: false)],
      );

      expect(levels, isEmpty,
          reason: 'The switch in the alarm editor is the whole gate.');
    });

    test('a page with no beacon for the alarm stays quiet', () {
      final levels = navigationAlarmLevels(
        pages: {
          '/freezer': pageFx('/freezer', [beacon(['other'])]),
          '/packing': pageFx('/packing', []),
        },
        active: [activeFx(uid: 'a1')],
      );

      expect(levels, isEmpty);
    });

    test('a beacon with no uids watches every alarm, so its page announces '
        'any of them', () {
      final levels = navigationAlarmLevels(
        pages: {
          '/overview': pageFx('/overview', [beacon([])]),
        },
        active: [activeFx(uid: 'whatever', level: AlarmLevel.info)],
      );

      expect(levels, {'/overview': AlarmLevel.info});
    });

    test('the worst alarm on a page wins, across beacons', () {
      final levels = navigationAlarmLevels(
        pages: {
          '/freezer': pageFx('/freezer', [
            beacon(['a1']),
            beacon(['a2']),
          ]),
        },
        active: [
          activeFx(uid: 'a1', level: AlarmLevel.info),
          activeFx(uid: 'a2', level: AlarmLevel.error),
        ],
      );

      expect(levels, {'/freezer': AlarmLevel.error});
    });

    test('one alarm announces on every page that beacons it', () {
      final levels = navigationAlarmLevels(
        pages: {
          '/freezer': pageFx('/freezer', [beacon(['a1'])]),
          '/packing': pageFx('/packing', [beacon(['a1'])]),
          '/idle': pageFx('/idle', [beacon(['a2'])]),
        },
        active: [activeFx(uid: 'a1')],
      );

      expect(levels.keys, unorderedEquals(['/freezer', '/packing']));
    });

    test('an alarm waiting on acknowledgement still announces', () {
      // AlarmMan clears notification.active but keeps the entry in the active
      // set until it is acked — same as the beacon asset, the signal ends when
      // the alarm is dealt with, not when the condition clears.
      final alarm = activeFx(uid: 'a1', level: AlarmLevel.error);
      alarm.notification.active = false;
      alarm.pendingAck = true;

      final levels = navigationAlarmLevels(
        pages: {
          '/freezer': pageFx('/freezer', [beacon(['a1'])]),
        },
        active: [alarm],
      );

      expect(levels, {'/freezer': AlarmLevel.error});
    });

    test('no active alarms is an empty map, not a map of nulls', () {
      final levels = navigationAlarmLevels(
        pages: {
          '/freezer': pageFx('/freezer', [beacon(['a1'])]),
        },
        active: const [],
      );

      expect(levels, isEmpty);
    });
  });

  group('navigationAlarmLevelFor', () {
    MenuItem item(String label, {String? path, List<MenuItem>? children}) =>
        MenuItem(
            label: label,
            path: path,
            icon: Icons.abc,
            children: children ?? const []);

    test('a leaf takes its own level', () {
      expect(
        navigationAlarmLevelFor(
          item('Freezer', path: '/freezer'),
          {'/freezer': AlarmLevel.warning},
        ),
        AlarmLevel.warning,
      );
    });

    test('the page on screen never pulses — it already shows its own alarms',
        () {
      expect(
        navigationAlarmLevelFor(
          item('Freezer', path: '/freezer'),
          {'/freezer': AlarmLevel.error},
          currentPath: '/freezer',
        ),
        isNull,
      );
    });

    test('a section carries the worst alarm from anywhere beneath it', () {
      final section = item('Lines', children: [
        item('One', path: '/one'),
        item('Two', path: '/two', children: [
          item('Deep', path: '/deep'),
        ]),
      ]);

      expect(
        navigationAlarmLevelFor(section, {
          '/one': AlarmLevel.info,
          '/deep': AlarmLevel.error,
        }),
        AlarmLevel.error,
      );
    });

    test('inside a section only the open child goes quiet; a sibling still '
        'lights the section', () {
      final section = item('Lines', children: [
        item('One', path: '/one'),
        item('Two', path: '/two'),
      ]);

      expect(
        navigationAlarmLevelFor(
          section,
          {'/one': AlarmLevel.error, '/two': AlarmLevel.warning},
          currentPath: '/one',
        ),
        AlarmLevel.warning,
      );
    });

    test('a section whose only alarming page is the open one goes quiet', () {
      final section = item('Lines', children: [item('One', path: '/one')]);

      expect(
        navigationAlarmLevelFor(
          section,
          {'/one': AlarmLevel.error},
          currentPath: '/one',
        ),
        isNull,
      );
    });

    test('a menu item pointing back at an ancestor does not hang the bar', () {
      // Page menu trees are resolved from a flat path map, which permits it.
      final children = <MenuItem>[];
      final section = item('Loop', path: '/loop', children: children);
      children.add(section);

      expect(
        navigationAlarmLevelFor(section, {'/loop': AlarmLevel.info}),
        AlarmLevel.info,
      );
    });

    test('two distinct entries that compare equal are both visited', () {
      // MenuItem's == is label+path+icon, so the cycle guard has to be by
      // identity or a real second entry would be skipped.
      final section = item('Lines', children: [
        item('Same', path: '/quiet'),
        item('Same', path: '/quiet'),
        item('Loud', path: '/loud'),
      ]);

      expect(
        navigationAlarmLevelFor(section, {'/loud': AlarmLevel.error}),
        AlarmLevel.error,
      );
    });

    test('nothing alarming anywhere is null', () {
      expect(
        navigationAlarmLevelFor(item('Freezer', path: '/freezer'), const {}),
        isNull,
      );
    });
  });
}

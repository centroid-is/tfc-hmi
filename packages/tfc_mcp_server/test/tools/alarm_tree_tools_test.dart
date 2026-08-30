import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/tools/alarm_tree_tools.dart';

Map<String, dynamic> alarm(
  String title, {
  List<String>? group,
  bool? bindToGroup,
}) =>
    {
      'uid': title.toLowerCase().replaceAll(' ', '-'),
      'title': title,
      'description': '$title description',
      'rules': const [],
      if (group != null) 'group': group,
      if (bindToGroup != null) 'bindToGroup': bindToGroup,
    };

final packingHall = [
  alarm('Multivac stopped', group: ['Line 3', 'Multivac'], bindToGroup: true),
  alarm('Film reel empty', group: ['Line 3', 'Multivac']),
  alarm('Seal temperature out of band', group: ['Line 3', 'Multivac']),
  alarm('Blank magazine empty', group: ['Line 3', 'Box erector']),
  alarm('Line stopped from panel', group: ['Line 3']),
  alarm('Link error', group: ['Infrastructure', 'EtherCAT']),
  alarm('Something ungrouped'),
];

void main() {
  group('buildAlarmGroupTree', () {
    test('nests groups by their address', () {
      final root = buildAlarmGroupTree(packingHall);
      expect(root.children.keys, ['Line 3', 'Infrastructure']);
      expect(root.children['Line 3']!.children.keys,
          ['Multivac', 'Box erector']);
    });

    test('a bound alarm becomes the group rather than a member', () {
      final multivac =
          buildAlarmGroupTree(packingHall).children['Line 3']!.children['Multivac']!;
      expect(multivac.bound, 'Multivac stopped');
      expect(multivac.alarms,
          ['Film reel empty', 'Seal temperature out of band']);
    });

    test('an alarm with no group stays at the root', () {
      expect(buildAlarmGroupTree(packingHall).alarms, ['Something ungrouped']);
    });

    test('a bound alarm at the root is an ordinary member', () {
      final root = buildAlarmGroupTree([alarm('Odd', bindToGroup: true)]);
      expect(root.bound, isNull);
      expect(root.alarms, ['Odd']);
    });

    test('a second bound alarm on one group stays a member', () {
      final root = buildAlarmGroupTree([
        alarm('First', group: ['N'], bindToGroup: true),
        alarm('Second', group: ['N'], bindToGroup: true),
      ]);
      expect(root.children['N']!.bound, 'First');
      expect(root.children['N']!.alarms, ['Second']);
    });

    test('total counts everything nested inside', () {
      final root = buildAlarmGroupTree(packingHall);
      // 1 bound + 2 members + 1 erector + 1 own leaf
      expect(root.children['Line 3']!.total, 5);
      expect(root.children['Infrastructure']!.total, 1);
    });

    test('a missing title falls back to the uid', () {
      final root = buildAlarmGroupTree([
        {'uid': 'no-title', 'group': <String>['G']}
      ]);
      expect(root.children['G']!.alarms, ['no-title']);
    });
  });

  group('renderAlarmGroupTree', () {
    test('renders the whole tree with counts and the bound marker', () {
      final text = renderAlarmGroupTree(buildAlarmGroupTree(packingHall));
      expect(text, '''
Line 3  (5)
  Multivac  (3)
    * Multivac stopped   <- this alarm IS the group
    - Film reel empty
    - Seal temperature out of band
  Box erector  (1)
    - Blank magazine empty
  - Line stopped from panel
Infrastructure  (1)
  EtherCAT  (1)
    - Link error
- Something ungrouped  (ungrouped)''');
    });

    test('scoping renders only that subtree', () {
      final text = renderAlarmGroupTree(buildAlarmGroupTree(packingHall),
          scope: ['Line 3', 'Multivac']);
      expect(text, '''
Multivac  (3)
  * Multivac stopped   <- this alarm IS the group
  - Film reel empty
  - Seal temperature out of band''');
    });

    test('an address that matches nothing renders empty', () {
      expect(
          renderAlarmGroupTree(buildAlarmGroupTree(packingHall),
              scope: ['Line 9']),
          isEmpty);
    });

    test('no alarms at all renders empty', () {
      expect(renderAlarmGroupTree(buildAlarmGroupTree(const [])), isEmpty);
    });
  });
}

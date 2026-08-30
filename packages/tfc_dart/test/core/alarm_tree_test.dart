import 'dart:convert';

import 'package:test/test.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/alarm_tree.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

AlarmConfig alarm(
  String title, {
  List<String> path = const [],
  bool bindToPath = false,
  AlarmLevel level = AlarmLevel.error,
}) =>
    AlarmConfig(
      uid: title.toLowerCase().replaceAll(' ', '-'),
      title: title,
      description: '$title description',
      path: path,
      bindToPath: bindToPath,
      rules: [
        AlarmRule(
          level: level,
          expression: ExpressionConfig(value: Expression(formula: 'A')),
          acknowledgeRequired: false,
        )
      ],
    );

/// The packing-hall shape the design settled on: a branch with both its own
/// alarm and diagnoses under it, a branch with only diagnoses, and a branch
/// with only its own alarm.
final packingHall = [
  alarm('Multivac stopped', path: ['Line 3', 'Multivac'], bindToPath: true),
  alarm('Film reel empty', path: ['Line 3', 'Multivac']),
  alarm('Seal temperature out of band', path: ['Line 3', 'Multivac']),
  alarm('Blank magazine empty', path: ['Line 3', 'Box erector']),
  alarm('Glue temperature low', path: ['Line 3', 'Box erector']),
  alarm('Strapper stopped', path: ['Line 3', 'Afak'], bindToPath: true),
  alarm('Line stopped from panel', path: ['Line 3']),
  alarm('Link error', path: ['Infrastructure', 'EtherCAT']),
];

void main() {
  group('AlarmConfig path fields', () {
    test('default to root and unbound', () {
      final a = AlarmConfig(
          uid: 'u', title: 't', description: 'd', rules: const []);
      expect(a.path, isEmpty);
      expect(a.bindToPath, isFalse);
    });

    test('survive a JSON round trip', () {
      final a = alarm('Film reel empty', path: ['Line 3', 'Multivac']);
      // AlarmConfig has no explicitToJson, so a round trip has to go through
      // an encode — which is how `alarm_man_config` is persisted anyway
      final back = AlarmConfig.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(back.path, ['Line 3', 'Multivac']);
      expect(back.bindToPath, isFalse);
    });

    test('bindToPath survives a JSON round trip', () {
      final a =
          alarm('Multivac stopped', path: ['Line 3'], bindToPath: true);
      final back = AlarmConfig.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(back.bindToPath, isTrue);
      expect(back.path, ['Line 3']);
    });

    test('stored configs written before the fields existed still load', () {
      // exactly what `alarm_man_config` holds today — no path, no bindToPath
      final legacy = {
        'uid': 'u',
        'key': null,
        'title': 'Old alarm',
        'description': 'from before the tree',
        'rules': <dynamic>[],
      };
      final a = AlarmConfig.fromJson(legacy);
      expect(a.path, isEmpty);
      expect(a.bindToPath, isFalse);
      expect(a.title, 'Old alarm');
    });

    test('AlarmConfig.from copies the path rather than sharing it', () {
      final original = alarm('x', path: ['A', 'B']);
      final copy = AlarmConfig.from(original);
      expect(copy.path, ['A', 'B']);
      expect(identical(copy.path, original.path), isFalse);
    });
  });

  group('AlarmTree.fromConfigs', () {
    final tree = AlarmTree.fromConfigs(packingHall);

    test('builds a node per distinct path segment', () {
      expect(tree.root.children.map((e) => e.name), ['Line 3', 'Infrastructure']);
      final line3 = tree.nodeAt(['Line 3'])!;
      expect(line3.children.map((e) => e.name),
          ['Multivac', 'Box erector', 'Afak']);
    });

    test('keeps first-appearance order, so the alarm list controls it', () {
      final reordered = AlarmTree.fromConfigs(packingHall.reversed);
      expect(reordered.root.children.map((e) => e.name),
          ['Infrastructure', 'Line 3']);
    });

    test('attaches a bound alarm to the node itself', () {
      final multivac = tree.nodeAt(['Line 3', 'Multivac'])!;
      expect(multivac.bound?.title, 'Multivac stopped');
      expect(multivac.alarms.map((e) => e.title),
          ['Film reel empty', 'Seal temperature out of band']);
    });

    test('a node with no bound alarm has none', () {
      expect(tree.nodeAt(['Line 3', 'Box erector'])!.bound, isNull);
    });

    test('a node can have a bound alarm and no children at all', () {
      final afak = tree.nodeAt(['Line 3', 'Afak'])!;
      expect(afak.bound?.title, 'Strapper stopped');
      expect(afak.alarms, isEmpty);
      expect(afak.children, isEmpty);
      expect(afak.hasChildren, isFalse);
    });

    test('an alarm can hang directly off an intermediate node', () {
      expect(tree.nodeAt(['Line 3'])!.alarms.map((e) => e.title),
          ['Line stopped from panel']);
    });

    test('nodeAt returns null for a path that is not there', () {
      expect(tree.nodeAt(['Line 9']), isNull);
      expect(tree.nodeAt(['Line 3', 'Nope']), isNull);
    });

    test('an alarm with an empty path lands at the root', () {
      final t = AlarmTree.fromConfigs([alarm('Plant wide')]);
      expect(t.root.alarms.map((e) => e.title), ['Plant wide']);
      expect(t.root.children, isEmpty);
    });

    test('a bound alarm with an empty path is treated as a root leaf', () {
      // there is no node to bind to, so it must not vanish
      final t = AlarmTree.fromConfigs([alarm('Odd', bindToPath: true)]);
      expect(t.root.bound, isNull);
      expect(t.root.alarms.map((e) => e.title), ['Odd']);
    });

    test('a second bound alarm on one node keeps the first and demotes the '
        'rest to leaves', () {
      final t = AlarmTree.fromConfigs([
        alarm('First', path: ['N'], bindToPath: true),
        alarm('Second', path: ['N'], bindToPath: true),
      ]);
      final n = t.nodeAt(['N'])!;
      expect(n.bound?.title, 'First');
      expect(n.alarms.map((e) => e.title), ['Second']);
    });

    test('subtreeAlarms gathers the bound alarm, the leaves and descendants',
        () {
      final line3 = tree.nodeAt(['Line 3'])!;
      expect(
          line3.subtreeAlarms.map((e) => e.title).toSet(),
          {
            'Line stopped from panel',
            'Multivac stopped',
            'Film reel empty',
            'Seal temperature out of band',
            'Blank magazine empty',
            'Glue temperature low',
            'Strapper stopped',
          });
    });

    test('depth counts path segments', () {
      expect(tree.root.depth, -1);
      expect(tree.nodeAt(['Line 3'])!.depth, 0);
      expect(tree.nodeAt(['Line 3', 'Multivac'])!.depth, 1);
    });
  });

  group('AlarmTree.rows', () {
    final tree = AlarmTree.fromConfigs(packingHall);

    test('lists a node, its own alarm, its subgroups, then its own leaves', () {
      final rows = tree.rows();
      expect(rows.map((r) => '${'  ' * r.depth}${r.label}').toList(), [
        'Line 3',
        '  Multivac',
        '    Multivac stopped',
        '    Film reel empty',
        '    Seal temperature out of band',
        '  Box erector',
        '    Blank magazine empty',
        '    Glue temperature low',
        '  Afak',
        '  Line stopped from panel',
        'Infrastructure',
        '  EtherCAT',
        '    Link error',
      ]);
    });

    test('a branch with a bound alarm AND children also lists it as a row', () {
      final rows = tree.rows();
      final bound = rows.firstWhere((r) => r.label == 'Multivac stopped');
      expect(bound.isBound, isTrue);
      expect(bound.alarm, isNotNull);
    });

    test('a branch whose only alarm is the bound one does not repeat it', () {
      // Afak has no children, so its row already is that alarm
      expect(tree.rows().where((r) => r.label == 'Strapper stopped'), isEmpty);
    });

    test('group rows carry the node, alarm rows carry the alarm', () {
      final rows = tree.rows();
      final group = rows.firstWhere((r) => r.label == 'Multivac');
      expect(group.node, isNotNull);
      expect(group.alarm, isNull);
      final leaf = rows.firstWhere((r) => r.label == 'Film reel empty');
      expect(leaf.alarm?.uid, 'film-reel-empty');
      expect(leaf.isBound, isFalse);
    });
  });

  group('AlarmTree.rows scoped to a path — the asset\'s whole config', () {
    final tree = AlarmTree.fromConfigs(packingHall);

    test('an empty scope is the whole tree', () {
      expect(tree.rows(scope: const []).length, tree.rows().length);
    });

    test('scoping to a branch re-indents it to the top level', () {
      final rows = tree.rows(scope: [
        ['Line 3', 'Multivac']
      ]);
      expect(rows.map((r) => '${'  ' * r.depth}${r.label}').toList(), [
        'Multivac',
        '  Multivac stopped',
        '  Film reel empty',
        '  Seal temperature out of band',
      ]);
    });

    test('scoping to an intermediate node keeps its whole subtree', () {
      final rows = tree.rows(scope: [
        ['Line 3']
      ]);
      expect(rows.first.label, 'Line 3');
      expect(rows.first.depth, 0);
      expect(rows.map((r) => r.label), contains('Film reel empty'));
      expect(rows.map((r) => r.label), isNot(contains('EtherCAT')));
    });

    test('several paths can be shown side by side', () {
      final rows = tree.rows(scope: [
        ['Line 3', 'Box erector'],
        ['Infrastructure', 'EtherCAT'],
      ]);
      expect(rows.map((r) => '${'  ' * r.depth}${r.label}').toList(), [
        'Box erector',
        '  Blank magazine empty',
        '  Glue temperature low',
        'EtherCAT',
        '  Link error',
      ]);
    });

    test('a path that matches nothing yields no rows rather than throwing', () {
      expect(tree.rows(scope: [
        ['Line 9']
      ]), isEmpty);
    });

    test('a path that no longer exists does not hide the ones that do', () {
      final rows = tree.rows(scope: [
        ['Line 9'],
        ['Infrastructure'],
      ]);
      expect(rows.first.label, 'Infrastructure');
    });

    test('scoping does not duplicate a node covered by two overlapping paths',
        () {
      final rows = tree.rows(scope: [
        ['Line 3'],
        ['Line 3', 'Multivac'],
      ]);
      expect(rows.where((r) => r.label == 'Multivac'), hasLength(1));
    });
  });
}

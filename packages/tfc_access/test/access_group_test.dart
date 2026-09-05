import 'package:tfc_access/tfc_access.dart';
import 'package:test/test.dart';

void main() {
  group('AccessGroup', () {
    test('has exactly seven values', () {
      // Exact, not `greaterThan`. An eighth group is a decision — it changes
      // what every role in the field can be granted — so it must fail here and
      // be taken deliberately, not merged as an edit.
      expect(AccessGroup.values, hasLength(7));
    });

    test('values are in spec order', () {
      expect(AccessGroup.values, [
        AccessGroup.operate,
        AccessGroup.setpoints,
        AccessGroup.device,
        AccessGroup.force,
        AccessGroup.configure,
        AccessGroup.administer,
        AccessGroup.users,
      ]);
    });

    test('names match the spec strings stored in the database', () {
      // The enum name is what lands in AppRole.groups, so renaming a value is
      // a data migration, not a refactor.
      expect(AccessGroup.values.map((g) => g.name), [
        'operate',
        'setpoints',
        'device',
        'force',
        'configure',
        'administer',
        'users',
      ]);
    });

    test('byName resolves a known name', () {
      expect(AccessGroup.byName('setpoints'), AccessGroup.setpoints);
      expect(AccessGroup.byName('users'), AccessGroup.users);
    });

    test('byName returns null for an unknown name rather than throwing', () {
      // A newer station may write a group this build has never heard of. That
      // must degrade to "not granted", not to an exception on read.
      expect(AccessGroup.byName('nope'), isNull);
    });

    test('byName is exact — no case folding, no trimming', () {
      expect(AccessGroup.byName('Setpoints'), isNull);
      expect(AccessGroup.byName(' setpoints'), isNull);
      expect(AccessGroup.byName(''), isNull);
    });
  });

  group('AccessGroupInfo', () {
    test('every group has a non-empty label', () {
      for (final group in AccessGroup.values) {
        expect(group.label, isNotEmpty,
            reason: 'the roles screen is seven checkboxes and each one needs '
                'something to say for itself');
      }
    });

    test('every group has a non-empty description', () {
      for (final group in AccessGroup.values) {
        expect(group.description, isNotEmpty,
            reason: 'the description is the checkbox subtitle');
      }
    });

    test('the seven labels are distinct', () {
      final labels = AccessGroup.values.map((g) => g.label).toSet();
      expect(labels, hasLength(AccessGroup.values.length),
          reason: 'two checkboxes reading the same is worse than the bare '
              'enum names');
    });

    test('the seven descriptions are distinct', () {
      final descriptions =
          AccessGroup.values.map((g) => g.description).toSet();
      expect(descriptions, hasLength(AccessGroup.values.length));
    });

    test('device and force do not resolve to their bare enum names', () {
      // CONTEXT: `device` versus `force` is not a distinction a commissioning
      // engineer can make from those two words. Today AccessGroup.name is used
      // raw in access_denied_prompt.dart, whose doc already says it is "the
      // same word the roles screen shows". These two labels are the whole
      // reason this extension exists.
      expect(AccessGroup.device.label, isNot('device'),
          reason: 'the raw name tells a commissioning engineer nothing about '
              'device versus force');
      expect(AccessGroup.force.label, isNot('force'),
          reason: 'the raw name tells a commissioning engineer nothing about '
              'device versus force');
    });

    test('every description ends in a full stop', () {
      // The description is rendered as a subtitle under the label, so it has
      // to read as a sentence rather than as a fragment.
      for (final group in AccessGroup.values) {
        expect(group.description, endsWith('.'),
            reason: '${group.name} reads as a subtitle sentence');
      }
    });

    test('descriptions are the enum doc comments verbatim', () {
      // One wording, shared by the roles screen and the MCP tools. A paraphrase
      // here would be a second vocabulary for the same seven things.
      expect(AccessGroup.operate.description,
          'Start/stop/jog, gates, alarm acknowledge.');
      expect(AccessGroup.setpoints.description, 'Targets, limits, recipes.');
      expect(AccessGroup.device.description,
          'Drive parameters, calibration, scaling.');
      expect(AccessGroup.force.description, 'Forced I/O and overrides.');
      expect(AccessGroup.configure.description,
          'Page editor, alarm rules, key mappings.');
      expect(AccessGroup.administer.description,
          'Server config, database, network, updates.');
      expect(AccessGroup.users.description, 'Managing roles and users.');
    });

    test('a label never becomes what is stored', () {
      // AccessRole.encodeGroups writes AccessGroup.name into app_role.groups on
      // every deployed station. The label lives outside the enum precisely so
      // that changing it cannot reach that column.
      for (final group in AccessGroup.values) {
        expect(AccessGroup.byName(group.name), group);
        expect(AccessGroup.byName(group.label), isNull,
            reason: 'the label is display text and must not resolve as a '
                'stored identifier');
      }
    });
  });
}

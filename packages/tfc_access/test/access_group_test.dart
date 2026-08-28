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
}

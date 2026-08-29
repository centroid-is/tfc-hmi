// Reducing one whole-struct write to the members that actually changed.
//
// Every input here is a real `DynamicValue`, never a fake, because the trap
// this file exists to close only exists in the real type: `DynamicValue`
// carries no equality of its own, so two separately built wrappers holding the
// same scalar are never equal. A fake with a sensible equality would make the
// whole suite pass against an implementation that reports thirty changes for a
// jog.

import 'dart:collection' show LinkedHashMap;

import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:test/test.dart';
import 'package:tfc_dart/core/access/dynamic_value_diff.dart';

/// A struct built the way the assets build one: a fresh [DynamicValue] with
/// members assigned by name, so member order is insertion order.
DynamicValue struct(Map<String, Object?> members) {
  final v = DynamicValue();
  members.forEach((key, value) {
    v[key] = value is DynamicValue ? value : DynamicValue(value: value);
  });
  return v;
}

/// A `DynamicValue` that is an object by [DynamicValue.type] but whose
/// [DynamicValue.entries] throws — the shape the real getter takes off a
/// non-object, reproduced so the diff can be shown not to propagate it.
class _UnreadableObject extends DynamicValue {
  _UnreadableObject(LinkedHashMap<String, DynamicValue> members)
      : super(value: members);

  @override
  Iterable<MapEntry<String, DynamicValue>> get entries =>
      throw StateError('DynamicValue is not an object');
}

LinkedHashMap<String, DynamicValue> _members(Map<String, DynamicValue> from) =>
    LinkedHashMap<String, DynamicValue>.from(from);

void main() {
  group('diffDynamicValue', () {
    test(
        'the identity trap: an unchanged member yields no change even though '
        'the two wrappers are distinct instances', () {
      // Built separately, so nothing is shared between the two sides. Compared
      // as wrappers these are three changes; compared at the scalar leaves
      // they are none.
      final before = struct({
        'p_cmd_JogFwd': false,
        'p_cfg_Frequency': 42.5,
        'p_cfg_Name': 'CN04',
      });
      final after = struct({
        'p_cmd_JogFwd': false,
        'p_cfg_Frequency': 42.5,
        'p_cfg_Name': 'CN04',
      });

      expect(diffDynamicValue(before, after), isEmpty);
    });

    test(
        'null against the empty string is a change in both directions, and the '
        'two renderings differ', () {
      final absentToEmpty = diffDynamicValue(
        struct({'reason': DynamicValue(value: null)}),
        struct({'reason': ''}),
      );
      expect(absentToEmpty, hasLength(1));
      expect(absentToEmpty.single.member, 'reason');
      expect(absentToEmpty.single.oldValue, isNull);
      expect(absentToEmpty.single.newValue, '');
      expect(absentToEmpty.single.oldValue,
          isNot(equals(absentToEmpty.single.newValue)),
          reason: 'absent and empty must not render the same, or the trail '
              'shows the transition as no change at all');

      final emptyToAbsent = diffDynamicValue(
        struct({'reason': ''}),
        struct({'reason': DynamicValue(value: null)}),
      );
      expect(emptyToAbsent, hasLength(1));
      expect(emptyToAbsent.single.oldValue, '');
      expect(emptyToAbsent.single.newValue, isNull);
    });

    test('null to a value, and back, renders the absent side as null', () {
      final appearing = diffDynamicValue(
        struct({'p_cfg_Frequency': DynamicValue(value: null)}),
        struct({'p_cfg_Frequency': 42}),
      );
      expect(appearing, hasLength(1));
      expect(appearing.single.member, 'p_cfg_Frequency');
      expect(appearing.single.oldValue, isNull);
      expect(appearing.single.newValue, '42');

      final vanishing = diffDynamicValue(
        struct({'p_cfg_Frequency': 42}),
        struct({'p_cfg_Frequency': DynamicValue(value: null)}),
      );
      expect(vanishing, hasLength(1));
      expect(vanishing.single.oldValue, '42');
      expect(vanishing.single.newValue, isNull);
    });

    test('two bare scalars produce one change with a null member path', () {
      final changes = diffDynamicValue(
        DynamicValue(value: false),
        DynamicValue(value: true),
      );
      expect(changes, hasLength(1));
      expect(changes.single.member, isNull);
      expect(changes.single.oldValue, 'false');
      expect(changes.single.newValue, 'true');
      expect(changes.single.noBaseline, isFalse);
    });

    test('a jog: one changed member yields exactly one change naming it', () {
      final before = struct({
        'p_cmd_JogFwd': false,
        'p_cmd_JogBwd': false,
        'p_stat_Frequency': 42.5,
      });
      final after = struct({
        'p_cmd_JogFwd': true,
        'p_cmd_JogBwd': false,
        'p_stat_Frequency': 42.5,
      });

      final changes = diffDynamicValue(before, after);
      expect(changes, hasLength(1));
      expect(changes.single.member, 'p_cmd_JogFwd');
      expect(changes.single.oldValue, 'false');
      expect(changes.single.newValue, 'true');
    });

    test("three changed members yield three changes in the struct's own order",
        () {
      final before = struct({'a': 1, 'b': 2, 'c': 3, 'd': 4});
      final after = struct({'a': 9, 'b': 8, 'c': 7, 'd': 4});

      final changes = diffDynamicValue(before, after);
      expect(changes.map((c) => c.member).toList(), ['a', 'b', 'c']);
      expect(changes.map((c) => c.oldValue).toList(), ['1', '2', '3']);
      expect(changes.map((c) => c.newValue).toList(), ['9', '8', '7']);
    });

    test('a struct in which nothing changed yields no changes', () {
      final before = struct({
        'p_cfg': struct({'Freq': 42.5, 'Ramp': 3}),
        'p_cmd_JogFwd': false,
      });
      final after = struct({
        'p_cfg': struct({'Freq': 42.5, 'Ramp': 3}),
        'p_cmd_JogFwd': false,
      });

      expect(diffDynamicValue(before, after), isEmpty);
    });

    test('a nested member is named by its dotted path, to arbitrary depth', () {
      final before = struct({
        'p_cfg': struct({
          'Freq': 42.5,
          'Limits': struct({'Max': 50.0}),
        }),
      });
      final after = struct({
        'p_cfg': struct({
          'Freq': 47.5,
          'Limits': struct({'Max': 60.0}),
        }),
      });

      final changes = diffDynamicValue(before, after);
      expect(changes.map((c) => c.member).toList(),
          ['p_cfg.Freq', 'p_cfg.Limits.Max']);
      expect(changes.first.oldValue, '42.5');
      expect(changes.first.newValue, '47.5');
    });

    test('a member present only in the new value renders a null old side', () {
      final changes = diffDynamicValue(
        struct({'a': 1}),
        struct({'a': 1, 'b': 2}),
      );
      expect(changes, hasLength(1));
      expect(changes.single.member, 'b');
      expect(changes.single.oldValue, isNull);
      expect(changes.single.newValue, '2');
    });

    test('a member present only in the old value renders a null new side', () {
      final changes = diffDynamicValue(
        struct({'a': 1, 'b': 2}),
        struct({'a': 1}),
      );
      expect(changes, hasLength(1));
      expect(changes.single.member, 'b');
      expect(changes.single.oldValue, '2');
      expect(changes.single.newValue, isNull);
    });

    test('an array member is reported whole and never index by index', () {
      final before = struct({
        'p_cfg_Recipe': DynamicValue.fromList([1, 2, 3]),
        'p_cmd_JogFwd': false,
      });
      final after = struct({
        'p_cfg_Recipe': DynamicValue.fromList([1, 5, 3]),
        'p_cmd_JogFwd': false,
      });

      final changes = diffDynamicValue(before, after);
      expect(changes, hasLength(1));
      expect(changes.single.member, 'p_cfg_Recipe');
      expect(changes.single.member, isNot(contains('[')));
      expect(changes.single.oldValue, '[1, 2, 3]');
      expect(changes.single.newValue, '[1, 5, 3]');
    });

    test('an unchanged array member yields no change', () {
      final before = struct({
        'p_cfg_Recipe': DynamicValue.fromList([1, 2, 3]),
      });
      final after = struct({
        'p_cfg_Recipe': DynamicValue.fromList([1, 2, 3]),
      });

      expect(diffDynamicValue(before, after), isEmpty);
    });

    test(
        'a member changing between scalar and object yields one change and no '
        'descent', () {
      final toObject = diffDynamicValue(
        struct({'p_cfg': 3}),
        struct({
          'p_cfg': struct({'Freq': 42.5}),
        }),
      );
      expect(toObject, hasLength(1));
      expect(toObject.single.member, 'p_cfg');
      expect(toObject.single.oldValue, '3');
      expect(toObject.single.newValue, '{Freq: 42.5}');

      final toScalar = diffDynamicValue(
        struct({
          'p_cfg': struct({'Freq': 42.5}),
        }),
        struct({'p_cfg': 3}),
      );
      expect(toScalar, hasLength(1));
      expect(toScalar.single.member, 'p_cfg');
      expect(toScalar.single.oldValue, '{Freq: 42.5}');
      expect(toScalar.single.newValue, '3');
    });

    test('no baseline yields exactly one change marked as having none', () {
      final changes = diffDynamicValue(
        null,
        struct({'p_cmd_JogFwd': true, 'p_cfg_Frequency': 42.5}),
      );
      expect(changes, hasLength(1));
      expect(changes.single.noBaseline, isTrue);
      expect(changes.single.member, isNull);
      expect(changes.single.oldValue, isNull);
      expect(changes.single.newValue,
          '{p_cmd_JogFwd: true, p_cfg_Frequency: 42.5}');
    });

    test('a value whose entries throws is treated as an opaque scalar', () {
      final unreadable =
          _UnreadableObject(_members({'a': DynamicValue(value: 1)}));

      late List<MemberChange> changes;
      expect(() => changes = diffDynamicValue(unreadable, struct({'a': 2})),
          returnsNormally);
      expect(changes, hasLength(1));
      expect(changes.single.member, isNull,
          reason: 'an unreadable object cannot name its members, so the change '
              'is the whole value');
      expect(changes.single.oldValue, '{a: 1}');
      expect(changes.single.newValue, '{a: 2}');
    });

    test('a rendering longer than the cap is truncated with a visible marker',
        () {
      final long = 'x' * (kMaxRenderedValueLength * 2);
      final changes = diffDynamicValue(
        struct({'note': 'short'}),
        struct({'note': long}),
      );

      expect(changes, hasLength(1));
      final rendered = changes.single.newValue!;
      expect(rendered, endsWith(kRenderTruncationMarker));
      expect(rendered.length,
          kMaxRenderedValueLength + kRenderTruncationMarker.length);
      expect(changes.single.oldValue, 'short',
          reason: 'a short rendering carries no marker, so a reader can tell '
              'the two apart');
    });
  });
}

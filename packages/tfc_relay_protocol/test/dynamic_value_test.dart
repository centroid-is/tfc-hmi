/// The pure-Dart DynamicValue — the type every later component passes around.
///
/// Each group states the operational consequence of the property it pins, not
/// the mechanics: these are the guarantees widgets, the value store and the
/// wire all lean on. No clock, no I/O, no FFI anywhere in this file.
library;

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/src/dynamic_value.dart';
import 'package:tfc_relay_protocol/src/quality.dart';

void main() {
  group('coercions never return null and never throw', () {
    test('a double answers every scalar question', () {
      final v = DynamicValue(value: 3.5);
      expect(v.asDouble, 3.5);
      expect(v.asInt, 3, reason: 'truncation, not a throw, on a gauge reading');
      expect(v.asString, '3.5');
      expect(v.asBool, isTrue, reason: 'non-zero is on, as operators read it');
    });

    test('a null value coerces to zeroes, never null and never a throw', () {
      final v = DynamicValue(value: null);
      expect(v.asDouble, 0.0);
      expect(v.asInt, 0);
      expect(v.asString, '');
      expect(v.asBool, isFalse,
          reason: '44 asDouble and 43 asInt call sites index the result '
              'directly; a null here is a crashed mimic page');
    });

    test('booleans parse from the strings and numbers a PLC actually sends',
        () {
      expect(DynamicValue(value: 'true').asBool, isTrue);
      expect(DynamicValue(value: '  TRUE ').asBool, isTrue,
          reason: 'whitespace and case from a text tag must not flip a state');
      expect(DynamicValue(value: '1').asBool, isTrue);
      expect(DynamicValue(value: 1).asBool, isTrue);
      expect(DynamicValue(value: 0).asBool, isFalse);
      expect(DynamicValue(value: 'no').asBool, isFalse);
      expect(DynamicValue(value: true).asBool, isTrue);
    });

    test('numeric strings coerce rather than reading as zero', () {
      expect(DynamicValue(value: '42').asInt, 42);
      expect(DynamicValue(value: '42.5').asDouble, 42.5);
      expect(DynamicValue(value: '42.5').asInt, 42);
      expect(DynamicValue(value: 'not a number').asDouble, 0.0,
          reason: 'garbage degrades to zero, it does not throw mid-build');
    });

    test('a collection still answers the scalar getters without throwing', () {
      final v = DynamicValue(value: const {'a': 1});
      expect(v.asDouble, 0.0);
      expect(v.asInt, 0);
      expect(v.asBool, isFalse);
      expect(v.asString, isNotEmpty);
    });
  });

  group('type tests each recognise exactly their own shape', () {
    test('every shape reports itself and nothing else', () {
      expect(DynamicValue(value: null).isNull, isTrue);
      expect(DynamicValue(value: true).isBoolean, isTrue);
      expect(DynamicValue(value: 7).isInteger, isTrue);
      expect(DynamicValue(value: 7.5).isDouble, isTrue);
      expect(DynamicValue(value: 'x').isString, isTrue);
      expect(DynamicValue(value: const [1, 2]).isArray, isTrue);
      expect(DynamicValue(value: const {'a': 1}).isObject, isTrue);
    });

    test('an integer is not a double and an array is not an object', () {
      final i = DynamicValue(value: 7);
      expect(i.isDouble, isFalse,
          reason: 'the JSON type tag is derived from this, so a widened int '
              'would change the wire shape');
      expect(DynamicValue(value: 7.5).isInteger, isFalse);
      expect(DynamicValue(value: const [1]).isObject, isFalse);
      expect(DynamicValue(value: const {'a': 1}).isArray, isFalse);
      expect(DynamicValue(value: null).isString, isFalse);
    });
  });

  group('membership and indexing (the sensor.dart guard idiom)', () {
    final obj = DynamicValue(value: const {
      'run': true,
      'speed': 12.5,
      'nested': {'deep': 1},
    });

    test('contains answers for a missing member instead of throwing', () {
      expect(obj.contains('run'), isTrue);
      expect(obj.contains('missing'), isFalse,
          reason: 'an older PLC library revision missing a member must '
              'degrade, not crash the mimic');
    });

    test('operator[] throws on a missing member', () {
      expect(obj['run'].asBool, isTrue);
      expect(() => obj['missing'], throwsStateError,
          reason: 'sensor.dart:125-132 guards every read precisely because '
              'this throws — silently returning null would hide bad configs');
    });

    test('arrays index by int and object members by String', () {
      final arr = DynamicValue(value: const [10, 20, 30]);
      expect(arr[1].asInt, 20);
      expect(arr.length, 3);
      expect(() => arr[9], throwsStateError);
      expect(arr.contains(9), isFalse);
      expect(obj['nested']['deep'].asInt, 1,
          reason: 'nested members index without unwrapping by hand');
    });

    test('entries iterate object children in insertion order', () {
      expect(obj.entries.map((e) => e.key).toList(), ['run', 'speed', 'nested'],
          reason: 'diagnostic tables render fields in the order the server '
              'declared them');
    });

    test('asObject and asArray throw on the wrong shape', () {
      expect(() => DynamicValue(value: 1).asObject, throwsStateError);
      expect(() => DynamicValue(value: 1).asArray, throwsStateError);
      expect(obj.asObject.keys, contains('speed'));
      expect(DynamicValue(value: const [1]).asArray, hasLength(1));
    });
  });

  group('value equality is what makes zero-rebuild possible (CLI-06)', () {
    test('two values built from equal nested maps are == and share a hashCode',
        () {
      final a = DynamicValue(value: {
        'a': 1,
        'b': {
          'c': [1, 2, 3],
        },
      });
      final b = DynamicValue(value: {
        'a': 1,
        'b': {
          'c': [1, 2, 3],
        },
      });
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode,
          reason: 'the store skips the notification on ==; an identity-based '
              'comparison would rebuild all 1500 keys every batch');
    });

    test('changing one nested leaf makes them unequal', () {
      final a = DynamicValue(value: {
        'b': {'c': 1},
      });
      final b = DynamicValue(value: {
        'b': {'c': 2},
      });
      expect(a, isNot(equals(b)),
          reason: 'a deep change the store missed is a stale screen');
    });

    test('quality and sourceTime participate in equality', () {
      final t = DateTime.utc(2026, 8, 13, 12);
      expect(DynamicValue(value: 1, quality: Quality.badStale),
          isNot(equals(DynamicValue(value: 1))),
          reason: 'a value going stale must notify even when the number is '
              'unchanged — that is the whole freshness promise');
      expect(DynamicValue(value: 1, sourceTime: t),
          isNot(equals(DynamicValue(value: 1))));
      expect(DynamicValue(value: 1, sourceTime: t),
          equals(DynamicValue(value: 1, sourceTime: t)));
    });

    test('copyWith returns a new instance and leaves the original untouched',
        () {
      final original = DynamicValue(value: 1, displayName: const LocalizedText('Speed'));
      final changed = original.copyWith(value: 2);
      expect(original.asInt, 1, reason: 'immutability is the store contract');
      expect(changed.asInt, 2);
      expect(changed.displayName?.value, 'Speed',
          reason: 'metadata survives the six ..value= call sites being ported '
              'to copyWith');
    });

    test('copyWith can clear an optional field', () {
      final original = DynamicValue(
        value: 1,
        displayName: const LocalizedText('Speed'),
        description: const LocalizedText('belt speed'),
      );
      final cleared = original.copyWith(displayName: null, description: null);
      expect(cleared.displayName, isNull);
      expect(cleared.description, isNull);
      expect(original.displayName, isNotNull);
    });

    test('DynamicValue.from is a deep copy that is == to its source', () {
      final source = DynamicValue(value: {
        'b': {'c': 1},
      });
      final copy = DynamicValue.from(source);
      expect(copy, equals(source));
      expect(identical(copy['b'], source['b']), isFalse,
          reason: 'a shared child would let a mutation of one tree leak into '
              'the other during encode-once fan-out');
    });
  });

  group('quality composition — a parent never looks healthier than its child',
      () {
    test('an object inherits the worst quality among its children', () {
      final v = DynamicValue(value: {
        'ok': DynamicValue(value: 1),
        'broken': DynamicValue(value: 2, quality: Quality.badCommFault),
      });
      expect(v.quality, Quality.badCommFault,
          reason: 'a green header over a dead member is exactly the lie the '
              'pipe exists to prevent');
    });

    test('an array inherits the worst quality among its elements', () {
      final v = DynamicValue(value: [
        DynamicValue(value: 1),
        DynamicValue(value: 2, quality: Quality.errorConfig),
      ]);
      expect(v.quality, Quality.errorConfig);
    });

    test('a good-band quality of its own survives healthy children', () {
      final v = DynamicValue(
        value: {'ok': DynamicValue(value: 1)},
        quality: Quality.goodWritePending,
      );
      expect(v.quality, Quality.goodWritePending,
          reason: 'the write-pending badge must not be laundered back to '
              'plain good by composition');
    });

    test('a non-finite leaf becomes null with badNonFinite quality', () {
      final v = DynamicValue(value: double.infinity);
      expect(v.value, isNull);
      expect(v.quality, Quality.badNonFinite,
          reason: 'jsonEncode throws on Infinity — one open-circuit 4-20 mA '
              'input would otherwise fail the batch for every client');

      final nested = DynamicValue(value: {'rate': double.nan});
      expect(nested['rate'].value, isNull);
      expect(nested.quality, Quality.badNonFinite);
    });
  });

  group('toString renders what diagnostic pages print', () {
    test('a value with enumFields renders name(value)', () {
      final v = DynamicValue(
        value: 2,
        enumFields: const {
          1: EnumField(value: 1, name: 'Stopped'),
          2: EnumField(value: 2, name: 'Running'),
        },
      );
      expect(v.toString(), 'Running(2)');
    });

    test('a null value renders null', () {
      expect(DynamicValue(value: null).toString(), 'null');
      expect(
          DynamicValue(
            value: null,
            enumFields: const {1: EnumField(value: 1, name: 'Stopped')},
          ).toString(),
          'null');
    });
  });

  group('companion types carry their own equality', () {
    test('LocalizedText and EnumField compare by content', () {
      expect(const LocalizedText('Hraði', locale: 'is'),
          equals(const LocalizedText('Hraði', locale: 'is')));
      expect(const LocalizedText('Hraði', locale: 'is'),
          isNot(equals(const LocalizedText('Hraði'))));
      expect(const EnumField(value: 1, name: 'Stopped'),
          equals(const EnumField(value: 1, name: 'Stopped')));
    });
  });
}

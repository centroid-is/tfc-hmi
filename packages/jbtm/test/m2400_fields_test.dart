import 'package:jbtm/src/m2400.dart';
import 'package:jbtm/src/m2400_fields.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // M2400Field enum
  // ---------------------------------------------------------------------------
  group('M2400Field', () {
    group('fromId - confirmed device fields', () {
      test('fromId(1) returns weight', () {
        expect(M2400Field.fromId(1), equals(M2400Field.weight));
      });

      test('fromId(2) returns unit', () {
        expect(M2400Field.fromId(2), equals(M2400Field.unit));
      });

      test('fromId(77) returns siWeight', () {
        expect(M2400Field.fromId(77), equals(M2400Field.siWeight));
      });
    });

    group('fromId - device-observed provisional fields', () {
      test('fromId(6) returns a provisional field', () {
        final field = M2400Field.fromId(6);
        expect(field, isNotNull);
        expect(field!.id, equals(6));
      });

      test('fromId(11) returns a provisional field', () {
        final field = M2400Field.fromId(11);
        expect(field, isNotNull);
        expect(field!.id, equals(11));
      });

      test('fromId(59) returns a provisional field', () {
        final field = M2400Field.fromId(59);
        expect(field, isNotNull);
        expect(field!.id, equals(59));
      });

      test('fromId(78) returns a provisional field', () {
        final field = M2400Field.fromId(78);
        expect(field, isNotNull);
        expect(field!.id, equals(78));
      });

      test('fromId(79) returns a provisional field', () {
        final field = M2400Field.fromId(79);
        expect(field, isNotNull);
        expect(field!.id, equals(79));
      });

      test('fromId(80) returns a provisional field', () {
        final field = M2400Field.fromId(80);
        expect(field, isNotNull);
        expect(field!.id, equals(80));
      });

      test('fromId(81) returns a provisional field', () {
        final field = M2400Field.fromId(81);
        expect(field, isNotNull);
        expect(field!.id, equals(81));
      });
    });

    group('fromId - unresolvable IDs', () {
      test('fromId(0) returns null (placeholder IDs not matchable)', () {
        expect(M2400Field.fromId(0), isNull);
      });

      test('fromId(999) returns null (unknown ID)', () {
        expect(M2400Field.fromId(999), isNull);
      });

      test('fromId(-1) returns null (negative ID)', () {
        expect(M2400Field.fromId(-1), isNull);
      });
    });

    group('fieldType metadata', () {
      test('weight.fieldType == FieldType.decimal', () {
        expect(M2400Field.weight.fieldType, equals(FieldType.decimal));
      });

      test('unit.fieldType == FieldType.string', () {
        expect(M2400Field.unit.fieldType, equals(FieldType.string));
      });

      test('siWeight.fieldType == FieldType.string (display-ready)', () {
        expect(M2400Field.siWeight.fieldType, equals(FieldType.string));
      });
    });

    group('enum completeness', () {
      test('has 50+ enum values defined', () {
        expect(M2400Field.values.length, greaterThanOrEqualTo(50));
      });

      test('spot-check confirmed fields exist', () {
        expect(M2400Field.values, contains(M2400Field.weight));
        expect(M2400Field.values, contains(M2400Field.unit));
        expect(M2400Field.values, contains(M2400Field.siWeight));
      });

      test('spot-check unconfirmed fields exist (id == 0)', () {
        // These are requirement-defined fields without confirmed IDs
        expect(M2400Field.values.where((f) => f.id == 0).length,
            greaterThanOrEqualTo(30),
            reason: 'Should have many unconfirmed fields with placeholder ID 0');
      });
    });
  });

  // ---------------------------------------------------------------------------
  // FieldType enum
  // ---------------------------------------------------------------------------
  group('FieldType', () {
    test('has all expected values', () {
      expect(FieldType.values, containsAll([
        FieldType.decimal,
        FieldType.integer,
        FieldType.string,
        FieldType.percentage,
        FieldType.date,
        FieldType.time,
        FieldType.timeMs,
      ]));
    });
  });

  // ---------------------------------------------------------------------------
  // WeigherStatus enum
  // ---------------------------------------------------------------------------
  group('WeigherStatus', () {
    group('fromCode - defined codes', () {
      test('fromCode(0) returns bad', () {
        expect(WeigherStatus.fromCode(0), equals(WeigherStatus.bad));
      });

      test('fromCode(1) returns r1', () {
        expect(WeigherStatus.fromCode(1), equals(WeigherStatus.r1));
      });

      test('fromCode(2) returns r2', () {
        expect(WeigherStatus.fromCode(2), equals(WeigherStatus.r2));
      });

      test('fromCode(10) returns badDeny', () {
        expect(WeigherStatus.fromCode(10), equals(WeigherStatus.badDeny));
      });

      test('fromCode(11) returns badStddev', () {
        expect(WeigherStatus.fromCode(11), equals(WeigherStatus.badStddev));
      });

      test('fromCode(12) returns badAlibi', () {
        expect(WeigherStatus.fromCode(12), equals(WeigherStatus.badAlibi));
      });

      test('fromCode(13) returns badUnexpect', () {
        expect(WeigherStatus.fromCode(13), equals(WeigherStatus.badUnexpect));
      });

      test('fromCode(14) returns badUnder', () {
        expect(WeigherStatus.fromCode(14), equals(WeigherStatus.badUnder));
      });

      test('fromCode(15) returns badOver', () {
        expect(WeigherStatus.fromCode(15), equals(WeigherStatus.badOver));
      });
    });

    group('fromCode - undefined codes', () {
      test('fromCode(5) returns unknown (undefined code)', () {
        expect(WeigherStatus.fromCode(5), equals(WeigherStatus.unknown));
      });

      test('fromCode(-1) returns unknown (negative code)', () {
        expect(WeigherStatus.fromCode(-1), equals(WeigherStatus.unknown));
      });

      test('fromCode(100) returns unknown (out of range)', () {
        expect(WeigherStatus.fromCode(100), equals(WeigherStatus.unknown));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // expectedFields map
  // ---------------------------------------------------------------------------
  group('expectedFields', () {
    test('contains recStat with weight and unit', () {
      expect(expectedFields[M2400RecordType.recStat],
          containsAll([M2400Field.weight, M2400Field.unit]));
    });

    test('contains recBatch with all 10 observed fields', () {
      final batchFields = expectedFields[M2400RecordType.recBatch]!;
      expect(batchFields, contains(M2400Field.weight));
      expect(batchFields, contains(M2400Field.unit));
      expect(batchFields, contains(M2400Field.siWeight));
      expect(batchFields, contains(M2400Field.fromId(6)));
      expect(batchFields, contains(M2400Field.fromId(11)));
      expect(batchFields, contains(M2400Field.fromId(59)));
      expect(batchFields, contains(M2400Field.fromId(78)));
      expect(batchFields, contains(M2400Field.fromId(79)));
      expect(batchFields, contains(M2400Field.fromId(80)));
      expect(batchFields, contains(M2400Field.fromId(81)));
    });
  });
}

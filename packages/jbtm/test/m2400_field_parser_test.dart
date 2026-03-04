import 'package:jbtm/src/m2400.dart';
import 'package:jbtm/src/m2400_fields.dart';
import 'package:jbtm/src/m2400_field_parser.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // parseFieldValue
  // ---------------------------------------------------------------------------
  group('parseFieldValue', () {
    test('decimal parses to double', () {
      expect(parseFieldValue('12.52', FieldType.decimal), equals(12.52));
      expect(parseFieldValue('12.52', FieldType.decimal), isA<double>());
    });

    test('integer parses to int', () {
      expect(parseFieldValue('47', FieldType.integer), equals(47));
      expect(parseFieldValue('47', FieldType.integer), isA<int>());
    });

    test('string passes through as String', () {
      expect(parseFieldValue('kg', FieldType.string), equals('kg'));
      expect(parseFieldValue('kg', FieldType.string), isA<String>());
    });

    test('percentage parses to double', () {
      expect(parseFieldValue('85.5', FieldType.percentage), equals(85.5));
      expect(parseFieldValue('85.5', FieldType.percentage), isA<double>());
    });

    test('decimal parse failure returns null', () {
      expect(parseFieldValue('not_a_number', FieldType.decimal), isNull);
    });

    test('integer parse failure returns null', () {
      expect(parseFieldValue('not_a_number', FieldType.integer), isNull);
    });

    test('date stores as string', () {
      expect(
          parseFieldValue('2026-03-04', FieldType.date), equals('2026-03-04'));
    });

    test('time stores as string', () {
      expect(parseFieldValue('14:30:00', FieldType.time), equals('14:30:00'));
    });

    test('timeMs stores as string', () {
      expect(parseFieldValue('500', FieldType.timeMs), equals('500'));
    });
  });

  // ---------------------------------------------------------------------------
  // parseTypedRecord - real WGT record
  // ---------------------------------------------------------------------------
  group('parseTypedRecord - WGT record', () {
    late M2400ParsedRecord parsed;

    setUp(() {
      final raw = M2400Record(
        type: M2400RecordType.recBatch,
        fields: {
          '1': '12.52',
          '2': 'kg',
          '77': '11.00kg',
          '6': '47',
          '11': '0',
          '59': '0.38',
          '81': 'auto',
          '79': '1.3',
          '80': '0',
          '78': '12.3',
        },
      );
      parsed = parseTypedRecord(raw);
    });

    test('weight is double 12.52', () {
      expect(parsed.weight, equals(12.52));
      expect(parsed.weight, isA<double>());
    });

    test('unit is String kg', () {
      expect(parsed.unitString, equals('kg'));
    });

    test('siWeight is String 11.00kg (no suffix stripping)', () {
      expect(parsed.siWeight, equals('11.00kg'));
    });

    test('field6 is int 47', () {
      expect(parsed.getField<int>(M2400Field.field6), equals(47));
    });

    test('field59 is double 0.38', () {
      expect(parsed.getField<double>(M2400Field.field59), equals(0.38));
    });

    test('field81 is String auto', () {
      expect(parsed.getField<String>(M2400Field.field81), equals('auto'));
    });

    test('type is recBatch', () {
      expect(parsed.type, equals(M2400RecordType.recBatch));
    });

    test('rawFields preserved as original map', () {
      expect(parsed.rawFields['1'], equals('12.52'));
      expect(parsed.rawFields['2'], equals('kg'));
      expect(parsed.rawFields['77'], equals('11.00kg'));
    });

    test('unknownFields is empty (all fields are in enum)', () {
      expect(parsed.unknownFields, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // parseTypedRecord - STAT record
  // ---------------------------------------------------------------------------
  group('parseTypedRecord - STAT record', () {
    test('STAT record produces weight and unit', () {
      final raw = M2400Record(
        type: M2400RecordType.recStat,
        fields: {'1': '12.37', '2': 'kg'},
      );
      final parsed = parseTypedRecord(raw);

      expect(parsed.weight, equals(12.37));
      expect(parsed.unitString, equals('kg'));
      expect(parsed.type, equals(M2400RecordType.recStat));
    });
  });

  // ---------------------------------------------------------------------------
  // parseTypedRecord - unknown fields
  // ---------------------------------------------------------------------------
  group('parseTypedRecord - unknown fields', () {
    test('unknown field ID stored in unknownFields', () {
      final raw = M2400Record(
        type: M2400RecordType.recBatch,
        fields: {'1': '10.0', '999': 'mystery'},
      );
      final parsed = parseTypedRecord(raw);

      expect(parsed.unknownFields[999], equals('mystery'));
      expect(parsed.weight, equals(10.0));
    });
  });

  // ---------------------------------------------------------------------------
  // parseTypedRecord - parse failure isolation
  // ---------------------------------------------------------------------------
  group('parseTypedRecord - parse failure isolation', () {
    test('parse failure on one field does not affect other fields', () {
      final raw = M2400Record(
        type: M2400RecordType.recBatch,
        fields: {
          '1': 'not_a_number', // weight parse fails
          '2': 'kg', // unit should still work
        },
      );
      final parsed = parseTypedRecord(raw);

      expect(parsed.weight, isNull);
      expect(parsed.unitString, equals('kg'));
    });
  });

  // ---------------------------------------------------------------------------
  // M2400ParsedRecord convenience getters
  // ---------------------------------------------------------------------------
  group('M2400ParsedRecord convenience getters', () {
    test('weight returns typed double', () {
      final raw = M2400Record(
        type: M2400RecordType.recStat,
        fields: {'1': '55.5'},
      );
      final parsed = parseTypedRecord(raw);
      expect(parsed.weight, isA<double>());
      expect(parsed.weight, equals(55.5));
    });

    test('unitString returns typed String', () {
      final raw = M2400Record(
        type: M2400RecordType.recStat,
        fields: {'2': 'lb'},
      );
      final parsed = parseTypedRecord(raw);
      expect(parsed.unitString, equals('lb'));
    });

    test('siWeight returns typed String', () {
      final raw = M2400Record(
        type: M2400RecordType.recBatch,
        fields: {'77': '22.50kg'},
      );
      final parsed = parseTypedRecord(raw);
      expect(parsed.siWeight, equals('22.50kg'));
    });

    test('weigherStatus returns null when status field absent', () {
      final raw = M2400Record(
        type: M2400RecordType.recBatch,
        fields: {'1': '10.0'},
      );
      final parsed = parseTypedRecord(raw);
      expect(parsed.weigherStatus, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // LUA record handling
  // ---------------------------------------------------------------------------
  group('LUA record handling', () {
    test('LUA record with known and unknown fields', () {
      final raw = M2400Record(
        type: M2400RecordType.recLua,
        fields: {
          '1': '5.0', // known field (weight)
          '200': 'luaData1', // unknown
          '201': 'luaData2', // unknown
        },
      );
      final parsed = parseTypedRecord(raw);

      // Known field is typed
      expect(parsed.weight, equals(5.0));

      // Unknown fields retained as raw strings
      expect(parsed.unknownFields[200], equals('luaData1'));
      expect(parsed.unknownFields[201], equals('luaData2'));
    });
  });

  // ---------------------------------------------------------------------------
  // extractTimestamp
  // ---------------------------------------------------------------------------
  group('extractTimestamp', () {
    test('returns null when date/time fields absent', () {
      final fields = <M2400Field, Object>{
        M2400Field.weight: 12.5,
      };
      expect(extractTimestamp(fields), isNull);
    });

    test('returns DateTime with valid ISO date and time', () {
      final fields = <M2400Field, Object>{
        M2400Field.date: '2026-03-04',
        M2400Field.time: '14:30:00',
      };
      final ts = extractTimestamp(fields);
      expect(ts, isNotNull);
      expect(ts!.year, equals(2026));
      expect(ts.month, equals(3));
      expect(ts.day, equals(4));
      expect(ts.hour, equals(14));
      expect(ts.minute, equals(30));
      expect(ts.second, equals(0));
    });

    test('includes milliseconds when timeMs present', () {
      final fields = <M2400Field, Object>{
        M2400Field.date: '2026-03-04',
        M2400Field.time: '14:30:00',
        M2400Field.timeMs: '500',
      };
      final ts = extractTimestamp(fields);
      expect(ts, isNotNull);
      expect(ts!.millisecond, equals(500));
    });

    test('returns null when date present but time absent', () {
      final fields = <M2400Field, Object>{
        M2400Field.date: '2026-03-04',
      };
      expect(extractTimestamp(fields), isNull);
    });

    test('returns null when time present but date absent', () {
      final fields = <M2400Field, Object>{
        M2400Field.time: '14:30:00',
      };
      expect(extractTimestamp(fields), isNull);
    });
  });
}

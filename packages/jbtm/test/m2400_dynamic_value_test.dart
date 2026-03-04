import 'package:jbtm/src/m2400.dart';
import 'package:jbtm/src/m2400_dynamic_value.dart';
import 'package:jbtm/src/m2400_field_parser.dart';
import 'package:jbtm/src/m2400_fields.dart';
import 'package:open62541/open62541.dart' show DynamicValue, EnumField;
import 'package:test/test.dart';

void main() {
  group('convertRecordToDynamicValue', () {
    test('WGT record converts to parent DynamicValue with typed children', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {
          M2400Field.weight: 12.5,
          M2400Field.unit: 'kg',
          M2400Field.siWeight: '11.00kg',
        },
        unknownFields: {},
        rawFields: {'1': '12.50', '2': 'kg', '77': '11.00kg'},
        receivedAt: DateTime.utc(2026, 3, 4, 12, 0, 0),
      );

      final dv = convertRecordToDynamicValue(record);

      expect(dv['weight'].asDouble, 12.5);
      expect(dv['unit'].asString, 'kg');
      expect(dv['siWeight'].asString, '11.00kg');
    });

    test('parent DynamicValue name is the record type name', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {},
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv.name, 'recBatch');
    });

    test('integer fields produce int-valued child DynamicValues', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {
          M2400Field.field6: 7,
          M2400Field.field11: 3,
          M2400Field.field80: 42,
        },
        unknownFields: {},
        rawFields: {'6': '7', '11': '3', '80': '42'},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv['field6'].asInt, 7);
      expect(dv['field11'].asInt, 3);
      expect(dv['field80'].asInt, 42);
    });

    test('unknown fields included as string children keyed by numeric ID', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {},
        unknownFields: {99: 'mystery'},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv['99'].asString, 'mystery');
    });

    test('empty record produces parent DynamicValue that isObject', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {},
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      // Should be an object (has receivedAt at minimum)
      expect(dv.isObject, true);
    });

    test('WeigherStatus field produces child DynamicValue with enumFields', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {
          M2400Field.status: 1,
        },
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      final statusDv = dv['status'];
      expect(statusDv.asInt, 1);
      expect(statusDv.enumFields, isNotNull);
      expect(statusDv.enumFields, isA<Map<int, EnumField>>());
      expect(statusDv.enumFields![1]!.name, 'r1');
      expect(statusDv.enumFields![0]!.name, 'bad');
    });

    test('WeigherStatus on weighingStatus field also gets enumFields', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {
          M2400Field.weighingStatus: 10,
        },
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      final statusDv = dv['weighingStatus'];
      expect(statusDv.asInt, 10);
      expect(statusDv.enumFields, isNotNull);
      expect(statusDv.enumFields![10]!.name, 'badDeny');
    });

    test('deviceTimestamp stored as ISO 8601 string child', () {
      final ts = DateTime.utc(2026, 3, 4, 10, 30, 45);
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {},
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
        deviceTimestamp: ts,
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv['deviceTimestamp'].asString, ts.toIso8601String());
    });

    test('null deviceTimestamp means no deviceTimestamp child', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {},
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
        deviceTimestamp: null,
      );

      final dv = convertRecordToDynamicValue(record);
      // DynamicValue [] throws on missing key, so check the map directly
      final map = dv.value as Map<String, DynamicValue>;
      expect(map.containsKey('deviceTimestamp'), isFalse);
    });

    test('receivedAt stored as ISO 8601 string child', () {
      final ra = DateTime.utc(2026, 3, 4, 12, 0, 0);
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {},
        unknownFields: {},
        rawFields: {},
        receivedAt: ra,
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv['receivedAt'].asString, ra.toIso8601String());
    });

    test('round-trip: double in -> asDouble out matches', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {M2400Field.weight: 99.75},
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv['weight'].asDouble, 99.75);
    });

    test('round-trip: int in -> asInt out matches', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {M2400Field.field6: 42},
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv['field6'].asInt, 42);
    });

    test('round-trip: String in -> asString out matches', () {
      final record = M2400ParsedRecord(
        type: M2400RecordType.recBatch,
        typedFields: {M2400Field.unit: 'lb'},
        unknownFields: {},
        rawFields: {},
        receivedAt: DateTime.utc(2026, 3, 4),
      );

      final dv = convertRecordToDynamicValue(record);
      expect(dv['unit'].asString, 'lb');
    });
  });

  group('pipeline round-trip', () {
    test('raw wire -> parseTypedRecord -> convertRecordToDynamicValue', () {
      final raw = M2400Record(
        type: M2400RecordType.recBatch,
        fields: {
          '1': '12.50',
          '2': 'kg',
          '77': '11.00kg',
          '6': '7',
          '11': '3',
        },
      );

      final parsed = parseTypedRecord(raw);
      final dv = convertRecordToDynamicValue(parsed);

      expect(dv.name, 'recBatch');
      expect(dv['weight'].asDouble, 12.5);
      expect(dv['unit'].asString, 'kg');
      expect(dv['siWeight'].asString, '11.00kg');
      expect(dv['field6'].asInt, 7);
      expect(dv['field11'].asInt, 3);
      expect(dv.isObject, true);
    });

    test('unknown fields survive full pipeline', () {
      final raw = M2400Record(
        type: M2400RecordType.recBatch,
        fields: {
          '1': '5.0',
          '999': 'mystery',
        },
      );

      final parsed = parseTypedRecord(raw);
      final dv = convertRecordToDynamicValue(parsed);

      expect(dv['weight'].asDouble, 5.0);
      expect(dv['999'].asString, 'mystery');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/dynamic_value_converter.dart';
import 'package:open62541/open62541.dart'
    show DynamicValue, NodeId, LocalizedText;
import 'dart:collection';

void main() {
  group('DynamicValueConverter', () {
    late DynamicValueConverter converter;

    setUp(() {
      converter = const DynamicValueConverter();
    });

    group('fromJson', () {
      test('converts null value', () {
        final json = {'type': 'null', 'value': null};
        final result = converter.fromJson(json);
        expect(result.isNull, true);
      });

      test('converts string value', () {
        final json = {'type': 'string', 'value': 'test'};
        final result = converter.fromJson(json);
        expect(result.isString, true);
        expect(result.asString, 'test');
      });

      test('converts integer value', () {
        final json = {'type': 'integer', 'value': 42};
        final result = converter.fromJson(json);
        expect(result.isInteger, true);
        expect(result.asInt, 42);
      });

      test('converts double value', () {
        final json = {'type': 'double', 'value': 3.14};
        final result = converter.fromJson(json);
        expect(result.isDouble, true);
        expect(result.asDouble, 3.14);
      });

      test('converts boolean value', () {
        final json = {'type': 'boolean', 'value': true};
        final result = converter.fromJson(json);
        expect(result.isBoolean, true);
        expect(result.asBool, true);
      });

      test('converts object value', () {
        final json = {
          'type': 'object',
          'value': {
            'key1': {'type': 'string', 'value': 'value1'},
            'key2': {'type': 'integer', 'value': 42}
          }
        };
        final result = converter.fromJson(json);
        expect(result.isObject, true);
        expect(result.asObject['key1']?.asString, 'value1');
        expect(result.asObject['key2']?.asInt, 42);
      });

      test('converts array value', () {
        final json = {
          'type': 'array',
          'value': [
            {'type': 'string', 'value': 'item1'},
            {'type': 'integer', 'value': 42}
          ]
        };
        final result = converter.fromJson(json);
        expect(result.isArray, true);
        expect(result.asArray[0].asString, 'item1');
        expect(result.asArray[1].asInt, 42);
      });

      test('handles metadata fields', () {
        final json = {
          'type': 'string',
          'value': 'test',
          'typeId': 'ns=1;s=SomeType',
          'displayName': {'value': 'Display Name', 'locale': 'en'},
          'description': {'value': 'Description', 'locale': 'en'}
        };
        final result = converter.fromJson(json);
        expect(result.typeId.toString(), 'ns=1;s=SomeType');
        expect(result.displayName?.value, 'Display Name');
        expect(result.displayName?.locale, 'en');
        expect(result.description?.value, 'Description');
        expect(result.description?.locale, 'en');
      });
    });

    group('toJson', () {
      test('converts null value', () {
        final value = DynamicValue();
        final result = converter.toJson(value);
        expect(result['type'], 'null');
        expect(result['value'], null);
      });

      test('converts string value', () {
        final value = DynamicValue(value: 'test');
        final result = converter.toJson(value);
        expect(result['type'], 'string');
        expect(result['value'], 'test');
      });

      test('converts integer value', () {
        final value = DynamicValue(value: 42);
        final result = converter.toJson(value);
        expect(result['type'], 'integer');
        expect(result['value'], 42);
      });

      test('converts double value', () {
        final value = DynamicValue(value: 3.14);
        final result = converter.toJson(value);
        expect(result['type'], 'double');
        expect(result['value'], 3.14);
      });

      test('converts boolean value', () {
        final value = DynamicValue(value: true);
        final result = converter.toJson(value);
        expect(result['type'], 'boolean');
        expect(result['value'], true);
      });

      test('converts object value', () {
        final value = DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
          'key1': DynamicValue(value: 'value1'),
          'key2': DynamicValue(value: 42)
        }));
        final result = converter.toJson(value);
        expect(result['type'], 'object');
        expect(result['value']['key1']['value'], 'value1');
        expect(result['value']['key2']['value'], 42);
      });

      test('converts array value', () {
        final value = DynamicValue.fromList(
            [DynamicValue(value: 'item1'), DynamicValue(value: 42)]);
        final result = converter.toJson(value);
        expect(result['type'], 'array');
        expect(result['value'][0]['value'], 'item1');
        expect(result['value'][1]['value'], 42);
      });

      test('handles metadata fields', () {
        final value = DynamicValue(value: 'test')
          ..typeId = NodeId.fromString(1, 'SomeType')
          ..displayName = LocalizedText('Display Name', 'en')
          ..description = LocalizedText('Description', 'en');

        final result = converter.toJson(value);
        expect(result['typeId'], 'ns=1;s=SomeType');
        expect(result['displayName']['value'], 'Display Name');
        expect(result['displayName']['locale'], 'en');
        expect(result['description']['value'], 'Description');
        expect(result['description']['locale'], 'en');
      });
    });

    group('roundtrip tests', () {
      test('string value roundtrip', () {
        final original = DynamicValue(value: 'test');
        final json = converter.toJson(original);
        final result = converter.fromJson(json);
        expect(result.asString, 'test');
      });

      test('nested object roundtrip', () {
        final original =
            DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
          'key1': DynamicValue(value: 'value1'),
          'key2': DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from(
              {'nested': DynamicValue(value: 42)}))
        }));
        final json = converter.toJson(original);
        final result = converter.fromJson(json);
        expect(result.asObject['key1']?.asString, 'value1');
        expect(result.asObject['key2']?.asObject['nested']?.asInt, 42);
      });

      test('array with mixed types roundtrip', () {
        final original = DynamicValue.fromList([
          DynamicValue(value: 'string'),
          DynamicValue(value: 42),
          DynamicValue(value: true),
          DynamicValue.fromList([DynamicValue(value: 'nested')])
        ]);
        final json = converter.toJson(original);
        final result = converter.fromJson(json);
        expect(result.asArray[0].asString, 'string');
        expect(result.asArray[1].asInt, 42);
        expect(result.asArray[2].asBool, true);
        expect(result.asArray[3].asArray[0].asString, 'nested');
      });
    });
  });
}

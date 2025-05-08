import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/alarm.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

void main() {
  group('Alarm expression', () {
    test('Alarm expression simple AND', () {
      final expression = Expression(formula: 'A AND B');
      expect(
          expression.evaluate(
              {'A': DynamicValue(value: true), 'B': DynamicValue(value: true)}),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: true),
            'B': DynamicValue(value: false)
          }),
          isFalse);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: true)
          }),
          isFalse);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: false)
          }),
          isFalse);
    });
    test('Alarm expression simple OR', () {
      final expression = Expression(formula: 'A OR B');
      expect(
          expression.evaluate(
              {'A': DynamicValue(value: true), 'B': DynamicValue(value: true)}),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: true),
            'B': DynamicValue(value: false)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: true)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: false)
          }),
          isFalse);
    });
    test('Alarm expression simple AND OR', () {
      final expression = Expression(formula: 'A AND B OR C');
      expect(
          expression.evaluate({
            'A': DynamicValue(value: true),
            'B': DynamicValue(value: true),
            'C': DynamicValue(value: true)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: true),
            'B': DynamicValue(value: false),
            'C': DynamicValue(value: true)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: true),
            'B': DynamicValue(value: false),
            'C': DynamicValue(value: false)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: true),
            'C': DynamicValue(value: true)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: true),
            'C': DynamicValue(value: false)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: false),
            'C': DynamicValue(value: true)
          }),
          isTrue);
      expect(
          expression.evaluate({
            'A': DynamicValue(value: false),
            'B': DynamicValue(value: false),
            'C': DynamicValue(value: false)
          }),
          isFalse);
    });
  });
}

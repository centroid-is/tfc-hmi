import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/expression/expression_validator.dart';

void main() {
  late ExpressionValidator validator;

  setUp(() {
    validator = ExpressionValidator();
  });

  group('ExpressionValidator', () {
    group('isValid', () {
      test('returns true for variable > literal', () {
        expect(validator.isValid('pump3.current > 15'), isTrue);
      });

      test('returns true for compound AND expression', () {
        expect(
          validator.isValid('pump3.current > 15 AND pump3.temp < 80'),
          isTrue,
        );
      });

      test('returns true for parenthesized groups with OR', () {
        expect(validator.isValid('(a > 1) OR (b < 2)'), isTrue);
      });

      test('returns true for equality operator', () {
        expect(validator.isValid('pump3.speed == 1450'), isTrue);
      });

      test('returns true for inequality operator', () {
        expect(validator.isValid('pump3.speed != 0'), isTrue);
      });

      test('returns true for >= and <= operators', () {
        expect(validator.isValid('a >= 10 AND b <= 20'), isTrue);
      });

      test('returns true for string literal comparison', () {
        expect(validator.isValid('status == "running"'), isTrue);
      });

      test('returns true for boolean literal comparison', () {
        expect(validator.isValid('flag == true'), isTrue);
      });

      test('returns false for empty string', () {
        expect(validator.isValid(''), isFalse);
      });

      test('returns false for missing left operand', () {
        expect(validator.isValid('> 15'), isFalse);
      });

      test('returns false for missing right operand', () {
        expect(validator.isValid('a >'), isFalse);
      });

      test('returns false for trailing operator', () {
        expect(validator.isValid('a > b AND'), isFalse);
      });

      test('returns false for unbalanced parentheses', () {
        expect(validator.isValid('((a > 1)'), isFalse);
      });

      test('returns false for whitespace in variable name', () {
        expect(validator.isValid('a b > 1'), isFalse);
      });
    });

    group('extractVariables', () {
      test('extracts variables from compound expression', () {
        expect(
          validator.extractVariables('pump3.current > 15 AND pump3.temp < 80'),
          equals(['pump3.current', 'pump3.temp']),
        );
      });

      test('extracts single variable and does NOT include literal', () {
        expect(
          validator.extractVariables('a > 1'),
          equals(['a']),
        );
      });
    });

    group('round-trip parse/serialize', () {
      test('simple expression round-trips', () {
        const formula = 'pump3.current > 15';
        final tokens = validator.parse(formula);
        final serialized = validator.serialize(tokens);
        expect(serialized, equals(formula));
      });

      test('parenthesized expression preserves parens and spacing', () {
        const formula = '(a > 1) OR (b < 2)';
        final tokens = validator.parse(formula);
        final serialized = validator.serialize(tokens);
        expect(serialized, equals(formula));
      });

      test('complex expression with multiple operators round-trips', () {
        const formula = 'a > 10 AND b <= 20 OR c == true';
        final tokens = validator.parse(formula);
        final serialized = validator.serialize(tokens);
        expect(serialized, equals(formula));
      });
    });
  });
}

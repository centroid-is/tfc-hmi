import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/compiler.dart';
import 'package:tfc_mcp_server/src/compiler/st_parser.dart';

void main() {
  late StParser parser;

  setUp(() {
    parser = StParser();
  });

  // ================================================================
  // 1. Literals
  // ================================================================
  group('literals', () {
    test('integer literal', () {
      final expr = parser.parseExpression('42');
      expect(expr, isA<IntLiteral>().having((e) => e.value, 'value', 42));
    });

    test('zero literal', () {
      final expr = parser.parseExpression('0');
      expect(expr, isA<IntLiteral>().having((e) => e.value, 'value', 0));
    });

    test('large integer literal', () {
      final expr = parser.parseExpression('123456');
      expect(
          expr, isA<IntLiteral>().having((e) => e.value, 'value', 123456));
    });

    test('negative integer as unary negate', () {
      final expr = parser.parseExpression('-7');
      expect(
          expr,
          isA<UnaryExpression>()
              .having((e) => e.operator, 'op', UnaryOp.negate)
              .having((e) => e.operand, 'operand',
                  isA<IntLiteral>().having((e) => e.value, 'value', 7)));
    });

    test('real literal', () {
      final expr = parser.parseExpression('3.14');
      expect(expr, isA<RealLiteral>().having((e) => e.value, 'value', 3.14));
    });

    test('real literal with leading zero', () {
      final expr = parser.parseExpression('0.5');
      expect(expr, isA<RealLiteral>().having((e) => e.value, 'value', 0.5));
    });

    test('real literal with exponent', () {
      final expr = parser.parseExpression('1.5E3');
      expect(
          expr, isA<RealLiteral>().having((e) => e.value, 'value', 1500.0));
    });

    test('real literal with negative exponent', () {
      final expr = parser.parseExpression('2.5E-2');
      expect(
          expr, isA<RealLiteral>().having((e) => e.value, 'value', 0.025));
    });

    test('boolean TRUE', () {
      final expr = parser.parseExpression('TRUE');
      expect(expr, isA<BoolLiteral>().having((e) => e.value, 'value', true));
    });

    test('boolean FALSE', () {
      final expr = parser.parseExpression('FALSE');
      expect(
          expr, isA<BoolLiteral>().having((e) => e.value, 'value', false));
    });

    test('boolean true lowercase', () {
      final expr = parser.parseExpression('true');
      expect(expr, isA<BoolLiteral>().having((e) => e.value, 'value', true));
    });

    test('boolean false lowercase', () {
      final expr = parser.parseExpression('false');
      expect(
          expr, isA<BoolLiteral>().having((e) => e.value, 'value', false));
    });

    test('string literal single quotes', () {
      final expr = parser.parseExpression("'hello world'");
      expect(expr,
          isA<StringLiteral>().having((e) => e.value, 'value', 'hello world'));
    });

    test('empty string literal', () {
      final expr = parser.parseExpression("''");
      expect(
          expr, isA<StringLiteral>().having((e) => e.value, 'value', ''));
    });

    test('typed literal INT#42', () {
      final expr = parser.parseExpression('INT#42');
      expect(
          expr,
          isA<IntLiteral>()
              .having((e) => e.value, 'value', 42)
              .having((e) => e.typePrefix, 'typePrefix', 'INT'));
    });

    test('typed literal DINT#1000', () {
      final expr = parser.parseExpression('DINT#1000');
      expect(
          expr,
          isA<IntLiteral>()
              .having((e) => e.value, 'value', 1000)
              .having((e) => e.typePrefix, 'typePrefix', 'DINT'));
    });

    test('typed literal REAL#3.14', () {
      final expr = parser.parseExpression('REAL#3.14');
      expect(
          expr,
          isA<RealLiteral>()
              .having((e) => e.value, 'value', 3.14)
              .having((e) => e.typePrefix, 'typePrefix', 'REAL'));
    });

    test('typed literal LREAL#1.0E10', () {
      final expr = parser.parseExpression('LREAL#1.0E10');
      expect(
          expr,
          isA<RealLiteral>()
              .having((e) => e.value, 'value', 1.0e10)
              .having((e) => e.typePrefix, 'typePrefix', 'LREAL'));
    });

    test('hex literal 16#FF', () {
      final expr = parser.parseExpression('16#FF');
      expect(expr, isA<IntLiteral>().having((e) => e.value, 'value', 255));
    });

    test('hex literal 16#0A', () {
      final expr = parser.parseExpression('16#0A');
      expect(expr, isA<IntLiteral>().having((e) => e.value, 'value', 10));
    });

    test('binary literal 2#1010', () {
      final expr = parser.parseExpression('2#1010');
      expect(expr, isA<IntLiteral>().having((e) => e.value, 'value', 10));
    });

    test('octal literal 8#77', () {
      final expr = parser.parseExpression('8#77');
      expect(expr, isA<IntLiteral>().having((e) => e.value, 'value', 63));
    });

    test('time literal T#5s', () {
      final expr = parser.parseExpression('T#5s');
      expect(
          expr,
          isA<TimeLiteral>()
              .having((e) => e.value, 'value', Duration(seconds: 5)));
    });

    test('time literal T#1h30m', () {
      final expr = parser.parseExpression('T#1h30m');
      expect(
          expr,
          isA<TimeLiteral>().having(
              (e) => e.value, 'value', Duration(hours: 1, minutes: 30)));
    });

    test('time literal T#100ms', () {
      final expr = parser.parseExpression('T#100ms');
      expect(
          expr,
          isA<TimeLiteral>()
              .having((e) => e.value, 'value', Duration(milliseconds: 100)));
    });

    test('time literal T#2h15m30s500ms', () {
      final expr = parser.parseExpression('T#2h15m30s500ms');
      expect(
          expr,
          isA<TimeLiteral>().having(
              (e) => e.value,
              'value',
              Duration(
                  hours: 2, minutes: 15, seconds: 30, milliseconds: 500)));
    });

    test('time literal lowercase t#10s', () {
      final expr = parser.parseExpression('t#10s');
      expect(
          expr,
          isA<TimeLiteral>()
              .having((e) => e.value, 'value', Duration(seconds: 10)));
    });

    test('time literal TIME#500ms', () {
      final expr = parser.parseExpression('TIME#500ms');
      expect(
          expr,
          isA<TimeLiteral>()
              .having((e) => e.value, 'value', Duration(milliseconds: 500)));
    });

    test('date literal D#2024-01-15', () {
      final expr = parser.parseExpression('D#2024-01-15');
      expect(expr, isA<DateLiteral>());
    });

    test('date literal DATE#2024-01-15', () {
      final expr = parser.parseExpression('DATE#2024-01-15');
      expect(expr, isA<DateLiteral>());
    });

    test('date and time literal DT#2024-01-15-12:30:00', () {
      final expr = parser.parseExpression('DT#2024-01-15-12:30:00');
      expect(expr, isA<DateTimeLiteral>());
    });

    test('date and time literal DATE_AND_TIME#2024-01-15-12:30:00', () {
      final expr =
          parser.parseExpression('DATE_AND_TIME#2024-01-15-12:30:00');
      expect(expr, isA<DateTimeLiteral>());
    });

    test('time of day literal TOD#12:30:00', () {
      final expr = parser.parseExpression('TOD#12:30:00');
      expect(expr, isA<TimeOfDayLiteral>());
    });

    test('time of day literal TIME_OF_DAY#08:00:00', () {
      final expr = parser.parseExpression('TIME_OF_DAY#08:00:00');
      expect(expr, isA<TimeOfDayLiteral>());
    });
  });

  // ================================================================
  // 2. Identifiers and Access
  // ================================================================
  group('identifiers and access', () {
    test('simple identifier', () {
      final expr = parser.parseExpression('myVar');
      expect(expr,
          isA<IdentifierExpression>().having((e) => e.name, 'name', 'myVar'));
    });

    test('identifier with underscores', () {
      final expr = parser.parseExpression('my_var_1');
      expect(
          expr,
          isA<IdentifierExpression>()
              .having((e) => e.name, 'name', 'my_var_1'));
    });

    test('member access a.b', () {
      final expr = parser.parseExpression('a.b');
      expect(
          expr,
          isA<MemberAccessExpression>()
              .having((e) => e.member, 'member', 'b')
              .having((e) => e.target, 'target',
                  isA<IdentifierExpression>().having((e) => e.name, 'name', 'a')));
    });

    test('chained member access a.b.c', () {
      final expr = parser.parseExpression('a.b.c');
      expect(
          expr,
          isA<MemberAccessExpression>()
              .having((e) => e.member, 'member', 'c')
              .having(
                  (e) => e.target,
                  'target',
                  isA<MemberAccessExpression>()
                      .having((e) => e.member, 'member', 'b')
                      .having((e) => e.target, 'target',
                          isA<IdentifierExpression>())));
    });

    test('array access arr[1]', () {
      final expr = parser.parseExpression('arr[1]');
      expect(
          expr,
          isA<ArrayAccessExpression>()
              .having((e) => e.target, 'target', isA<IdentifierExpression>())
              .having((e) => e.indices.length, 'index count', 1)
              .having((e) => e.indices[0], 'index',
                  isA<IntLiteral>().having((e) => e.value, 'value', 1)));
    });

    test('array access with expression index arr[i+1]', () {
      final expr = parser.parseExpression('arr[i+1]');
      expect(
          expr,
          isA<ArrayAccessExpression>()
              .having((e) => e.target, 'target', isA<IdentifierExpression>())
              .having(
                  (e) => e.indices[0], 'index', isA<BinaryExpression>()));
    });

    test('multi-dimensional array access arr[1,2]', () {
      final expr = parser.parseExpression('arr[1,2]');
      expect(
          expr,
          isA<ArrayAccessExpression>()
              .having((e) => e.indices.length, 'index count', 2)
              .having((e) => e.indices[0], 'first index',
                  isA<IntLiteral>().having((e) => e.value, 'value', 1))
              .having((e) => e.indices[1], 'second index',
                  isA<IntLiteral>().having((e) => e.value, 'value', 2)));
    });

    test('member then array access motor.speeds[0]', () {
      final expr = parser.parseExpression('motor.speeds[0]');
      expect(
          expr,
          isA<ArrayAccessExpression>()
              .having(
                  (e) => e.target,
                  'target',
                  isA<MemberAccessExpression>()
                      .having((e) => e.member, 'member', 'speeds'))
              .having((e) => e.indices[0], 'index',
                  isA<IntLiteral>().having((e) => e.value, 'value', 0)));
    });

    test('Schneider direct address %MW100', () {
      final expr = parser.parseExpression('%MW100');
      expect(
          expr,
          isA<DirectAddressExpression>()
              .having((e) => e.address, 'address', '%MW100'));
    });

    test('Schneider direct address %I0.3.5', () {
      final expr = parser.parseExpression('%I0.3.5');
      expect(
          expr,
          isA<DirectAddressExpression>()
              .having((e) => e.address, 'address', '%I0.3.5'));
    });

    test('Schneider direct address %QX0.0', () {
      final expr = parser.parseExpression('%QX0.0');
      expect(
          expr,
          isA<DirectAddressExpression>()
              .having((e) => e.address, 'address', '%QX0.0'));
    });

    test('Beckhoff THIS^', () {
      // THIS^ parses as DerefExpression(ThisExpression)
      final expr = parser.parseExpression('THIS^');
      expect(
          expr,
          isA<DerefExpression>()
              .having((e) => e.target, 'target', isA<ThisExpression>()));
    });

    test('Beckhoff SUPER^', () {
      final expr = parser.parseExpression('SUPER^');
      expect(
          expr,
          isA<DerefExpression>()
              .having((e) => e.target, 'target', isA<SuperExpression>()));
    });

    test('Beckhoff pointer dereference ptr^', () {
      final expr = parser.parseExpression('ptr^');
      expect(
          expr,
          isA<DerefExpression>().having((e) => e.target, 'target',
              isA<IdentifierExpression>().having((e) => e.name, 'name', 'ptr')));
    });

    test('Beckhoff chained dereference ptr^.field', () {
      final expr = parser.parseExpression('ptr^.field');
      expect(
          expr,
          isA<MemberAccessExpression>()
              .having((e) => e.member, 'member', 'field')
              .having((e) => e.target, 'target', isA<DerefExpression>()));
    });

    test('bit access on WORD: q_xState.0', () {
      final expr = parser.parseExpression('q_xState.0');
      expect(
          expr,
          isA<MemberAccessExpression>()
              .having((e) => e.member, 'member', '0')
              .having((e) => e.target, 'target',
                  isA<IdentifierExpression>()
                      .having((e) => e.name, 'name', 'q_xState')));
    });

    test('bit access on WORD: someVar.15', () {
      final expr = parser.parseExpression('someVar.15');
      expect(
          expr,
          isA<MemberAccessExpression>()
              .having((e) => e.member, 'member', '15')
              .having((e) => e.target, 'target',
                  isA<IdentifierExpression>()
                      .having((e) => e.name, 'name', 'someVar')));
    });

    test('bit access with chained member: GVL_IO.Input1.q_xState.1', () {
      final expr = parser.parseExpression('GVL_IO.Input1.q_xState.1');
      expect(expr, isA<MemberAccessExpression>());
      final outer = expr as MemberAccessExpression;
      expect(outer.member, '1');
      // inner should be GVL_IO.Input1.q_xState
      expect(outer.target, isA<MemberAccessExpression>());
      final mid = outer.target as MemberAccessExpression;
      expect(mid.member, 'q_xState');
    });

    test('bit access .0 through .7 all parse', () {
      for (var i = 0; i <= 7; i++) {
        final expr = parser.parseExpression('myByte.$i');
        expect(
            expr,
            isA<MemberAccessExpression>()
                .having((e) => e.member, 'member', '$i'));
      }
    });
  });

  // ================================================================
  // 3. Arithmetic Operators (with precedence)
  // ================================================================
  group('arithmetic', () {
    test('addition', () {
      final expr = parser.parseExpression('1 + 2');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add)
              .having((e) => e.left, 'left',
                  isA<IntLiteral>().having((e) => e.value, 'value', 1))
              .having((e) => e.right, 'right',
                  isA<IntLiteral>().having((e) => e.value, 'value', 2)));
    });

    test('subtraction', () {
      final expr = parser.parseExpression('10 - 3');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.subtract));
    });

    test('multiplication', () {
      final expr = parser.parseExpression('4 * 5');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.multiply));
    });

    test('division', () {
      final expr = parser.parseExpression('10 / 2');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.divide));
    });

    test('MOD', () {
      final expr = parser.parseExpression('10 MOD 3');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.modulo));
    });

    test('MOD lowercase', () {
      final expr = parser.parseExpression('10 mod 3');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.modulo));
    });

    test('Beckhoff power operator **', () {
      final expr = parser.parseExpression('2 ** 3');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.power));
    });

    test('precedence: * before +', () {
      // 1 + 2 * 3 should parse as 1 + (2 * 3)
      final expr = parser.parseExpression('1 + 2 * 3');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add)
              .having((e) => e.left, 'left',
                  isA<IntLiteral>().having((e) => e.value, 'value', 1))
              .having(
                  (e) => e.right,
                  'right',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.multiply)));
    });

    test('precedence: * before -', () {
      // a - b * c should parse as a - (b * c)
      final expr = parser.parseExpression('a - b * c');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.subtract)
              .having(
                  (e) => e.right,
                  'right',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.multiply)));
    });

    test('precedence: / same level as *', () {
      // a * b / c should parse as (a * b) / c (left associative)
      final expr = parser.parseExpression('a * b / c');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.divide)
              .having(
                  (e) => e.left,
                  'left',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.multiply)));
    });

    test('precedence: parentheses override', () {
      // (1 + 2) * 3 should have multiply at the top
      final expr = parser.parseExpression('(1 + 2) * 3');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.multiply)
              .having((e) => e.left, 'left', isA<ParenExpression>()));
    });

    test('left associativity: a - b - c = (a - b) - c', () {
      final expr = parser.parseExpression('a - b - c');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.subtract)
              .having(
                  (e) => e.left,
                  'left',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.subtract))
              .having((e) => e.right, 'right',
                  isA<IdentifierExpression>()));
    });

    test('left associativity: a + b + c = (a + b) + c', () {
      final expr = parser.parseExpression('a + b + c');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add)
              .having(
                  (e) => e.left,
                  'left',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.add))
              .having((e) => e.right, 'right',
                  isA<IdentifierExpression>()));
    });

    test('unary negation: -x', () {
      final expr = parser.parseExpression('-x');
      expect(
          expr,
          isA<UnaryExpression>()
              .having((e) => e.operator, 'op', UnaryOp.negate)
              .having((e) => e.operand, 'operand',
                  isA<IdentifierExpression>()));
    });

    test('double negation: --x', () {
      final expr = parser.parseExpression('--x');
      expect(
          expr,
          isA<UnaryExpression>()
              .having((e) => e.operator, 'op', UnaryOp.negate)
              .having((e) => e.operand, 'operand',
                  isA<UnaryExpression>()
                      .having((e) => e.operator, 'op', UnaryOp.negate)));
    });

    test('negation in expression: a + -b', () {
      final expr = parser.parseExpression('a + -b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add)
              .having((e) => e.right, 'right', isA<UnaryExpression>()
                  .having((e) => e.operator, 'op', UnaryOp.negate)));
    });
  });

  // ================================================================
  // 4. Comparison Operators
  // ================================================================
  group('comparison', () {
    test('equal =', () {
      final expr = parser.parseExpression('a = b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.equal));
    });

    test('not equal <>', () {
      final expr = parser.parseExpression('a <> b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.notEqual));
    });

    test('less than', () {
      final expr = parser.parseExpression('a < b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.lessThan));
    });

    test('greater than', () {
      final expr = parser.parseExpression('a > b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.greaterThan));
    });

    test('less or equal', () {
      final expr = parser.parseExpression('a <= b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.lessOrEqual));
    });

    test('greater or equal', () {
      final expr = parser.parseExpression('a >= b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.greaterOrEqual));
    });

    test('comparison lower precedence than arithmetic: a + 1 > b', () {
      // a + 1 > b should parse as (a + 1) > b
      final expr = parser.parseExpression('a + 1 > b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.greaterThan)
              .having(
                  (e) => e.left,
                  'left',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.add))
              .having((e) => e.right, 'right',
                  isA<IdentifierExpression>()));
    });

    test('comparison lower precedence than subtraction: x - 1 < y', () {
      final expr = parser.parseExpression('x - 1 < y');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.lessThan)
              .having((e) => e.left, 'left', isA<BinaryExpression>()));
    });

    test('chained comparison with AND: a > 0 AND b < 10', () {
      // This should parse as (a > 0) AND (b < 10)
      // AND is lower precedence than comparison
      final expr = parser.parseExpression('a > 0 AND b < 10');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.and_)
              .having((e) => e.left, 'left',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.greaterThan))
              .having((e) => e.right, 'right',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.lessThan)));
    });
  });

  // ================================================================
  // 5. Boolean Operators
  // ================================================================
  group('boolean', () {
    test('AND', () {
      final expr = parser.parseExpression('a AND b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.and_));
    });

    test('OR', () {
      final expr = parser.parseExpression('a OR b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.or_));
    });

    test('XOR', () {
      final expr = parser.parseExpression('a XOR b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.xor_));
    });

    test('NOT', () {
      final expr = parser.parseExpression('NOT a');
      expect(
          expr,
          isA<UnaryExpression>()
              .having((e) => e.operator, 'op', UnaryOp.not_)
              .having((e) => e.operand, 'operand',
                  isA<IdentifierExpression>()));
    });

    test('NOT lowercase', () {
      final expr = parser.parseExpression('not a');
      expect(
          expr,
          isA<UnaryExpression>()
              .having((e) => e.operator, 'op', UnaryOp.not_));
    });

    test('AND lowercase', () {
      final expr = parser.parseExpression('a and b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.and_));
    });

    test('OR lowercase', () {
      final expr = parser.parseExpression('a or b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.or_));
    });

    test('precedence: AND before OR', () {
      // a OR b AND c should parse as a OR (b AND c)
      final expr = parser.parseExpression('a OR b AND c');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.or_)
              .having(
                  (e) => e.left, 'left', isA<IdentifierExpression>())
              .having(
                  (e) => e.right,
                  'right',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.and_)));
    });

    test('precedence: NOT before AND', () {
      // NOT a AND b should parse as (NOT a) AND b
      final expr = parser.parseExpression('NOT a AND b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.and_)
              .having((e) => e.left, 'left', isA<UnaryExpression>()
                  .having((e) => e.operator, 'op', UnaryOp.not_)));
    });

    test('precedence: XOR between AND and OR', () {
      // a OR b XOR c AND d should parse as a OR ((b XOR (c AND d)))
      // Actually: AND > XOR > OR, so:
      // a OR (b XOR (c AND d))
      final expr = parser.parseExpression('a OR b XOR c AND d');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.or_)
              .having((e) => e.left, 'left', isA<IdentifierExpression>())
              .having(
                  (e) => e.right,
                  'right',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.xor_)));
    });

    test('complex: (a > 0) AND (b < 10) OR (c = 5)', () {
      // Should parse as ((a > 0) AND (b < 10)) OR (c = 5)
      // because AND has higher precedence than OR
      final expr =
          parser.parseExpression('(a > 0) AND (b < 10) OR (c = 5)');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.or_)
              .having(
                  (e) => e.left,
                  'left',
                  isA<BinaryExpression>()
                      .having((e) => e.operator, 'op', BinaryOp.and_))
              .having(
                  (e) => e.right, 'right', isA<ParenExpression>()));
    });

    test('double NOT: NOT NOT flag', () {
      final expr = parser.parseExpression('NOT NOT flag');
      expect(
          expr,
          isA<UnaryExpression>()
              .having((e) => e.operator, 'op', UnaryOp.not_)
              .having(
                  (e) => e.operand,
                  'operand',
                  isA<UnaryExpression>()
                      .having((e) => e.operator, 'op', UnaryOp.not_)));
    });
  });

  // ================================================================
  // 6. Function Calls
  // ================================================================
  group('function calls', () {
    test('no-arg function call', () {
      final expr = parser.parseExpression('GET_TIME()');
      expect(
          expr,
          isA<FunctionCallExpression>()
              .having((e) => e.name, 'name', 'GET_TIME')
              .having((e) => e.arguments.length, 'arg count', 0));
    });

    test('single positional arg: ABS(-42.0)', () {
      final expr = parser.parseExpression('ABS(-42.0)');
      expect(
          expr,
          isA<FunctionCallExpression>()
              .having((e) => e.name, 'name', 'ABS')
              .having((e) => e.arguments.length, 'arg count', 1)
              .having((e) => e.arguments[0].name, 'arg name', isNull));
    });

    test('multiple positional args: MAX(a, b)', () {
      final expr = parser.parseExpression('MAX(a, b)');
      expect(
          expr,
          isA<FunctionCallExpression>()
              .having((e) => e.name, 'name', 'MAX')
              .having((e) => e.arguments.length, 'arg count', 2));
    });

    test('named args: LIMIT(MN := 0.0, IN := x, MX := 100.0)', () {
      final expr =
          parser.parseExpression('LIMIT(MN := 0.0, IN := x, MX := 100.0)');
      expect(
          expr,
          isA<FunctionCallExpression>()
              .having((e) => e.name, 'name', 'LIMIT')
              .having((e) => e.arguments.length, 'arg count', 3)
              .having((e) => e.arguments[0].name, 'first arg name', 'MN')
              .having((e) => e.arguments[1].name, 'second arg name', 'IN')
              .having(
                  (e) => e.arguments[2].name, 'third arg name', 'MX'));
    });

    test('output capture arg: FB(x := 1, y => result)', () {
      final expr = parser.parseExpression('FB(x := 1, y => result)');
      expect(
          expr,
          isA<FunctionCallExpression>()
              .having((e) => e.name, 'name', 'FB')
              .having((e) => e.arguments.length, 'arg count', 2)
              .having((e) => e.arguments[0].isOutput, 'first is output', false)
              .having((e) => e.arguments[1].isOutput, 'second is output', true)
              .having(
                  (e) => e.arguments[1].name, 'output arg name', 'y'));
    });

    test('nested function call: ABS(SIN(x))', () {
      final expr = parser.parseExpression('ABS(SIN(x))');
      expect(
          expr,
          isA<FunctionCallExpression>()
              .having((e) => e.name, 'name', 'ABS')
              .having((e) => e.arguments.length, 'arg count', 1)
              .having((e) => e.arguments[0].value, 'inner call',
                  isA<FunctionCallExpression>()
                      .having((e) => e.name, 'name', 'SIN')));
    });

    test('function call in expression: a + ABS(b)', () {
      final expr = parser.parseExpression('a + ABS(b)');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add)
              .having((e) => e.right, 'right',
                  isA<FunctionCallExpression>()));
    });

    test('function call result member access: FUNC().value', () {
      // This depends on whether the parser allows it; many ST parsers
      // treat function call + member access as a valid chain.
      // If the parser supports it, the result should be MemberAccess
      // with a FunctionCallExpression as target.
      final expr = parser.parseExpression('FUNC().value');
      expect(
          expr,
          isA<MemberAccessExpression>()
              .having((e) => e.member, 'member', 'value')
              .having((e) => e.target, 'target',
                  isA<FunctionCallExpression>()));
    });
  });

  // ================================================================
  // 7. Edge Cases
  // ================================================================
  group('edge cases', () {
    test('deeply nested parentheses: ((((x))))', () {
      final expr = parser.parseExpression('((((x))))');
      // Should be ParenExpression wrapping ParenExpression wrapping ...
      expect(expr, isA<ParenExpression>());
      final inner1 = (expr as ParenExpression).inner;
      expect(inner1, isA<ParenExpression>());
      final inner2 = (inner1 as ParenExpression).inner;
      expect(inner2, isA<ParenExpression>());
      final inner3 = (inner2 as ParenExpression).inner;
      expect(inner3, isA<ParenExpression>());
      final inner4 = (inner3 as ParenExpression).inner;
      expect(inner4, isA<IdentifierExpression>()
          .having((e) => e.name, 'name', 'x'));
    });

    test('complex nested expression', () {
      // (a + b) * (c - d) / (e MOD f)
      final expr =
          parser.parseExpression('(a + b) * (c - d) / (e MOD f)');
      // Top level should be divide (left-assoc with multiply)
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.divide));
    });

    test('whitespace variations - extra spaces', () {
      final expr = parser.parseExpression('  a   +   b  ');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add));
    });

    test('whitespace variations - no spaces around operators', () {
      final expr = parser.parseExpression('a+b');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add));
    });

    test('whitespace variations - tabs', () {
      final expr = parser.parseExpression('a\t+\tb');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.add));
    });

    test('case insensitive keywords: and vs AND', () {
      final lower = parser.parseExpression('a and b');
      final upper = parser.parseExpression('a AND b');
      expect(lower, isA<BinaryExpression>()
          .having((e) => e.operator, 'op', BinaryOp.and_));
      expect(upper, isA<BinaryExpression>()
          .having((e) => e.operator, 'op', BinaryOp.and_));
    });

    test('case insensitive keywords: or vs OR', () {
      final lower = parser.parseExpression('a or b');
      final upper = parser.parseExpression('a OR b');
      expect(lower, isA<BinaryExpression>()
          .having((e) => e.operator, 'op', BinaryOp.or_));
      expect(upper, isA<BinaryExpression>()
          .having((e) => e.operator, 'op', BinaryOp.or_));
    });

    test('case insensitive keywords: xor vs XOR', () {
      final lower = parser.parseExpression('a xor b');
      final upper = parser.parseExpression('a XOR b');
      expect(lower, isA<BinaryExpression>()
          .having((e) => e.operator, 'op', BinaryOp.xor_));
      expect(upper, isA<BinaryExpression>()
          .having((e) => e.operator, 'op', BinaryOp.xor_));
    });

    test('case insensitive TRUE/true/True', () {
      expect(parser.parseExpression('TRUE'),
          isA<BoolLiteral>().having((e) => e.value, 'value', true));
      expect(parser.parseExpression('true'),
          isA<BoolLiteral>().having((e) => e.value, 'value', true));
      expect(parser.parseExpression('True'),
          isA<BoolLiteral>().having((e) => e.value, 'value', true));
    });

    test('case insensitive FALSE/false/False', () {
      expect(parser.parseExpression('FALSE'),
          isA<BoolLiteral>().having((e) => e.value, 'value', false));
      expect(parser.parseExpression('false'),
          isA<BoolLiteral>().having((e) => e.value, 'value', false));
      expect(parser.parseExpression('False'),
          isA<BoolLiteral>().having((e) => e.value, 'value', false));
    });

    test('empty input throws FormatException', () {
      expect(
          () => parser.parseExpression(''), throwsA(isA<FormatException>()));
    });

    test('whitespace-only input throws FormatException', () {
      expect(() => parser.parseExpression('   '),
          throwsA(isA<FormatException>()));
    });

    test('unbalanced parentheses throws FormatException', () {
      expect(() => parser.parseExpression('(a + b'),
          throwsA(isA<FormatException>()));
    });

    test('trailing operator throws FormatException', () {
      expect(() => parser.parseExpression('a +'),
          throwsA(isA<FormatException>()));
    });

    test('double operator throws FormatException', () {
      expect(() => parser.parseExpression('a + + b'),
          throwsA(isA<FormatException>()));
    });

    test('expression with real and int mixed: 1 + 2.5', () {
      final expr = parser.parseExpression('1 + 2.5');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.left, 'left', isA<IntLiteral>())
              .having((e) => e.right, 'right', isA<RealLiteral>()));
    });

    test('full precedence chain: NOT a OR b AND c XOR d > e + f * g', () {
      // Precedence (highest to lowest):
      // *, / → +, - → >, <, =, <>, >=, <= → NOT → AND → XOR → OR
      // So this should parse as:
      // (NOT a) OR ((b AND (c XOR (d > (e + (f * g))))))
      // Actually IEC precedence: *, / > +, - > comparisons > NOT > AND > XOR > OR
      // Let's just check the top-level is OR
      final expr =
          parser.parseExpression('NOT a OR b AND c XOR d > e + f * g');
      expect(
          expr,
          isA<BinaryExpression>()
              .having((e) => e.operator, 'op', BinaryOp.or_));
    });
  });
}

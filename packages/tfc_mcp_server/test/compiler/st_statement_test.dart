import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/compiler.dart';
import 'package:tfc_mcp_server/src/compiler/st_parser.dart';

void main() {
  late StParser parser;

  setUp(() {
    parser = StParser();
  });

  // ==================================================================
  // 1. Assignment Statements
  // ==================================================================
  group('assignment', () {
    test('simple assignment: x := 42;', () {
      final stmt = parser.parseStatement('x := 42;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.operator, AssignmentOp.assign);
      expect(assign.target, isA<IdentifierExpression>());
      expect(
        (assign.target as IdentifierExpression).name,
        'x',
      );
      expect(assign.value, isA<IntLiteral>());
      expect((assign.value as IntLiteral).value, 42);
    });

    test('expression assignment: x := a + b * c;', () {
      final stmt = parser.parseStatement('x := a + b * c;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      // RHS should be a + (b * c) due to precedence
      expect(assign.value, isA<BinaryExpression>());
      final add = assign.value as BinaryExpression;
      expect(add.operator, BinaryOp.add);
      expect(add.left, isA<IdentifierExpression>());
      expect(add.right, isA<BinaryExpression>());
      final mul = add.right as BinaryExpression;
      expect(mul.operator, BinaryOp.multiply);
    });

    test('member access target: motor.speed := 100.0;', () {
      final stmt = parser.parseStatement('motor.speed := 100.0;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.target, isA<MemberAccessExpression>());
      final member = assign.target as MemberAccessExpression;
      expect(member.member, 'speed');
      expect(member.target, isA<IdentifierExpression>());
      expect(
        (member.target as IdentifierExpression).name,
        'motor',
      );
      expect(assign.value, isA<RealLiteral>());
      expect((assign.value as RealLiteral).value, 100.0);
    });

    test('array access target: arr[i] := 42;', () {
      final stmt = parser.parseStatement('arr[i] := 42;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.target, isA<ArrayAccessExpression>());
      final arr = assign.target as ArrayAccessExpression;
      expect(arr.target, isA<IdentifierExpression>());
      expect((arr.target as IdentifierExpression).name, 'arr');
      expect(arr.indices, hasLength(1));
      expect(arr.indices[0], isA<IdentifierExpression>());
    });

    test('Beckhoff S= (set/latch): flag S= trigger;', () {
      final stmt = parser.parseStatement('flag S= trigger;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.operator, AssignmentOp.set_);
      expect(assign.target, isA<IdentifierExpression>());
      expect(
        (assign.target as IdentifierExpression).name,
        'flag',
      );
      expect(assign.value, isA<IdentifierExpression>());
      expect(
        (assign.value as IdentifierExpression).name,
        'trigger',
      );
    });

    test('Beckhoff R= (reset): flag R= resetSignal;', () {
      final stmt = parser.parseStatement('flag R= resetSignal;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.operator, AssignmentOp.reset);
      expect(
        (assign.target as IdentifierExpression).name,
        'flag',
      );
      expect(
        (assign.value as IdentifierExpression).name,
        'resetSignal',
      );
    });

    test('Beckhoff REF= : ref REF= source;', () {
      final stmt = parser.parseStatement('ref REF= source;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.operator, AssignmentOp.refAssign);
    });

    test('Schneider direct address target: %MW100 := 42;', () {
      final stmt = parser.parseStatement('%MW100 := 42;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.target, isA<DirectAddressExpression>());
      expect(
        (assign.target as DirectAddressExpression).address,
        '%MW100',
      );
      expect(assign.value, isA<IntLiteral>());
      expect((assign.value as IntLiteral).value, 42);
    });
  });

  // ==================================================================
  // 2. IF Statements
  // ==================================================================
  group('if statement', () {
    test('simple IF/THEN/END_IF', () {
      final stmt = parser.parseStatement('''
        IF running THEN
          speed := 100.0;
        END_IF;
      ''');
      expect(stmt, isA<IfStatement>());
      final ifStmt = stmt as IfStatement;
      expect(ifStmt.condition, isA<IdentifierExpression>());
      expect(
        (ifStmt.condition as IdentifierExpression).name,
        'running',
      );
      expect(ifStmt.thenBody, hasLength(1));
      expect(ifStmt.thenBody[0], isA<AssignmentStatement>());
      expect(ifStmt.elsifClauses, isEmpty);
      expect(ifStmt.elseBody, isNull);
    });

    test('IF/ELSE', () {
      final stmt = parser.parseStatement('''
        IF active THEN
          x := 1;
        ELSE
          x := 0;
        END_IF;
      ''');
      expect(stmt, isA<IfStatement>());
      final ifStmt = stmt as IfStatement;
      expect(ifStmt.thenBody, hasLength(1));
      expect(ifStmt.elsifClauses, isEmpty);
      expect(ifStmt.elseBody, isNotNull);
      expect(ifStmt.elseBody, hasLength(1));
    });

    test('IF/ELSIF/ELSE', () {
      final stmt = parser.parseStatement('''
        IF x > 10 THEN
          y := 1;
        ELSIF x > 5 THEN
          y := 2;
        ELSE
          y := 3;
        END_IF;
      ''');
      expect(stmt, isA<IfStatement>());
      final ifStmt = stmt as IfStatement;
      expect(ifStmt.thenBody, hasLength(1));
      expect(ifStmt.elsifClauses, hasLength(1));
      expect(ifStmt.elsifClauses[0].condition, isA<BinaryExpression>());
      expect(ifStmt.elsifClauses[0].body, hasLength(1));
      expect(ifStmt.elseBody, isNotNull);
      expect(ifStmt.elseBody, hasLength(1));
    });

    test('multiple ELSIF clauses', () {
      final stmt = parser.parseStatement('''
        IF state = 0 THEN
          mode := 0;
        ELSIF state = 1 THEN
          mode := 1;
        ELSIF state = 2 THEN
          mode := 2;
        ELSIF state = 3 THEN
          mode := 3;
        ELSE
          mode := -1;
        END_IF;
      ''');
      expect(stmt, isA<IfStatement>());
      final ifStmt = stmt as IfStatement;
      expect(ifStmt.elsifClauses, hasLength(3));
      expect(ifStmt.elseBody, isNotNull);
    });

    test('nested IF', () {
      final stmt = parser.parseStatement('''
        IF a THEN
          IF b THEN
            x := 1;
          END_IF;
        END_IF;
      ''');
      expect(stmt, isA<IfStatement>());
      final outer = stmt as IfStatement;
      expect(outer.thenBody, hasLength(1));
      expect(outer.thenBody[0], isA<IfStatement>());
      final inner = outer.thenBody[0] as IfStatement;
      expect(inner.thenBody, hasLength(1));
    });

    test('empty THEN body', () {
      final stmt = parser.parseStatement('''
        IF flag THEN
        END_IF;
      ''');
      expect(stmt, isA<IfStatement>());
      final ifStmt = stmt as IfStatement;
      expect(ifStmt.thenBody, isEmpty);
    });
  });

  // ==================================================================
  // 3. CASE Statements
  // ==================================================================
  group('case statement', () {
    test('simple CASE with single values', () {
      final stmt = parser.parseStatement('''
        CASE state OF
          0: speed := 0.0;
          1: speed := 50.0;
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.expression, isA<IdentifierExpression>());
      expect(
        (caseStmt.expression as IdentifierExpression).name,
        'state',
      );
      expect(caseStmt.clauses, hasLength(2));
      expect(caseStmt.clauses[0].matches, hasLength(1));
      expect(caseStmt.clauses[0].matches[0], isA<CaseValueMatch>());
      expect(caseStmt.clauses[0].body, hasLength(1));
      expect(caseStmt.elseBody, isNull);
    });

    test('CASE with comma-separated values: 2, 3:', () {
      final stmt = parser.parseStatement('''
        CASE mode OF
          2, 3: result := TRUE;
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.clauses, hasLength(1));
      expect(caseStmt.clauses[0].matches, hasLength(2));
      expect(caseStmt.clauses[0].matches[0], isA<CaseValueMatch>());
      expect(caseStmt.clauses[0].matches[1], isA<CaseValueMatch>());
    });

    test('CASE with range: 4..10:', () {
      final stmt = parser.parseStatement('''
        CASE idx OF
          4..10: inRange := TRUE;
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.clauses, hasLength(1));
      expect(caseStmt.clauses[0].matches, hasLength(1));
      expect(caseStmt.clauses[0].matches[0], isA<CaseRangeMatch>());
      final range = caseStmt.clauses[0].matches[0] as CaseRangeMatch;
      expect(range.lower, isA<IntLiteral>());
      expect((range.lower as IntLiteral).value, 4);
      expect(range.upper, isA<IntLiteral>());
      expect((range.upper as IntLiteral).value, 10);
    });

    test('CASE with ELSE', () {
      final stmt = parser.parseStatement('''
        CASE cmd OF
          1: doStart();
          2: doStop();
        ELSE
          doDefault();
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.clauses, hasLength(2));
      expect(caseStmt.elseBody, isNotNull);
      expect(caseStmt.elseBody, hasLength(1));
    });

    test('CASE with multiple statements per clause', () {
      final stmt = parser.parseStatement('''
        CASE step OF
          0:
            x := 0;
            y := 0;
            z := 0;
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.clauses, hasLength(1));
      expect(caseStmt.clauses[0].body, hasLength(3));
    });
  });

  // ==================================================================
  // 4. FOR Loop
  // ==================================================================
  group('for loop', () {
    test('simple FOR', () {
      final stmt = parser.parseStatement('''
        FOR i := 0 TO 9 DO
          j := j + i;
        END_FOR;
      ''');
      expect(stmt, isA<ForStatement>());
      final forStmt = stmt as ForStatement;
      expect(forStmt.variable, 'i');
      expect(forStmt.start, isA<IntLiteral>());
      expect((forStmt.start as IntLiteral).value, 0);
      expect(forStmt.end, isA<IntLiteral>());
      expect((forStmt.end as IntLiteral).value, 9);
      expect(forStmt.step, isNull);
      expect(forStmt.body, hasLength(1));
      expect(forStmt.body[0], isA<AssignmentStatement>());
    });

    test('FOR with BY step', () {
      final stmt = parser.parseStatement('''
        FOR i := 0 TO 100 BY 10 DO
          sum := sum + i;
        END_FOR;
      ''');
      expect(stmt, isA<ForStatement>());
      final forStmt = stmt as ForStatement;
      expect(forStmt.variable, 'i');
      expect(forStmt.step, isNotNull);
      expect(forStmt.step, isA<IntLiteral>());
      expect((forStmt.step as IntLiteral).value, 10);
    });

    test('FOR with negative BY step', () {
      final stmt = parser.parseStatement('''
        FOR i := 10 TO 0 BY -1 DO
          arr[i] := 0;
        END_FOR;
      ''');
      expect(stmt, isA<ForStatement>());
      final forStmt = stmt as ForStatement;
      expect(forStmt.step, isNotNull);
      // Negative step could be a UnaryExpression(negate, IntLiteral(1))
      // or an IntLiteral(-1) depending on parser implementation.
      // We accept either representation.
      final step = forStmt.step!;
      if (step is IntLiteral) {
        expect(step.value, -1);
      } else {
        expect(step, isA<UnaryExpression>());
        final unary = step as UnaryExpression;
        expect(unary.operator, UnaryOp.negate);
        expect(unary.operand, isA<IntLiteral>());
      }
    });

    test('FOR with expression bounds', () {
      final stmt = parser.parseStatement('''
        FOR i := start TO start + count DO
          process(i);
        END_FOR;
      ''');
      expect(stmt, isA<ForStatement>());
      final forStmt = stmt as ForStatement;
      expect(forStmt.variable, 'i');
      expect(forStmt.start, isA<IdentifierExpression>());
      expect(forStmt.end, isA<BinaryExpression>());
    });

    test('nested FOR loops', () {
      final stmt = parser.parseStatement('''
        FOR i := 0 TO 3 DO
          FOR j := 0 TO 3 DO
            matrix[i, j] := 0;
          END_FOR;
        END_FOR;
      ''');
      expect(stmt, isA<ForStatement>());
      final outer = stmt as ForStatement;
      expect(outer.variable, 'i');
      expect(outer.body, hasLength(1));
      expect(outer.body[0], isA<ForStatement>());
      final inner = outer.body[0] as ForStatement;
      expect(inner.variable, 'j');
      expect(inner.body, hasLength(1));
    });
  });

  // ==================================================================
  // 5. WHILE Loop
  // ==================================================================
  group('while loop', () {
    test('simple WHILE', () {
      final stmt = parser.parseStatement('''
        WHILE running DO
          counter := counter + 1;
        END_WHILE;
      ''');
      expect(stmt, isA<WhileStatement>());
      final whileStmt = stmt as WhileStatement;
      expect(whileStmt.condition, isA<IdentifierExpression>());
      expect(
        (whileStmt.condition as IdentifierExpression).name,
        'running',
      );
      expect(whileStmt.body, hasLength(1));
    });

    test('WHILE with complex condition', () {
      final stmt = parser.parseStatement('''
        WHILE x > 0 AND y < 100 DO
          x := x - 1;
          y := y + 1;
        END_WHILE;
      ''');
      expect(stmt, isA<WhileStatement>());
      final whileStmt = stmt as WhileStatement;
      expect(whileStmt.condition, isA<BinaryExpression>());
      final cond = whileStmt.condition as BinaryExpression;
      expect(cond.operator, BinaryOp.and_);
      expect(whileStmt.body, hasLength(2));
    });

    test('nested WHILE', () {
      final stmt = parser.parseStatement('''
        WHILE a DO
          WHILE b DO
            c := c + 1;
          END_WHILE;
        END_WHILE;
      ''');
      expect(stmt, isA<WhileStatement>());
      final outer = stmt as WhileStatement;
      expect(outer.body, hasLength(1));
      expect(outer.body[0], isA<WhileStatement>());
    });
  });

  // ==================================================================
  // 6. REPEAT Loop
  // ==================================================================
  group('repeat loop', () {
    test('simple REPEAT/UNTIL', () {
      final stmt = parser.parseStatement('''
        REPEAT
          i := i - 1;
        UNTIL i <= 0
        END_REPEAT;
      ''');
      expect(stmt, isA<RepeatStatement>());
      final repeat = stmt as RepeatStatement;
      expect(repeat.body, hasLength(1));
      expect(repeat.body[0], isA<AssignmentStatement>());
      expect(repeat.condition, isA<BinaryExpression>());
      final cond = repeat.condition as BinaryExpression;
      expect(cond.operator, BinaryOp.lessOrEqual);
    });

    test('REPEAT with multiple body statements', () {
      final stmt = parser.parseStatement('''
        REPEAT
          x := x + 1;
          y := y * 2;
        UNTIL x >= 10
        END_REPEAT;
      ''');
      expect(stmt, isA<RepeatStatement>());
      final repeat = stmt as RepeatStatement;
      expect(repeat.body, hasLength(2));
    });

    test('nested REPEAT', () {
      final stmt = parser.parseStatement('''
        REPEAT
          REPEAT
            j := j + 1;
          UNTIL j >= 5
          END_REPEAT;
          i := i + 1;
        UNTIL i >= 3
        END_REPEAT;
      ''');
      expect(stmt, isA<RepeatStatement>());
      final outer = stmt as RepeatStatement;
      expect(outer.body, hasLength(2));
      expect(outer.body[0], isA<RepeatStatement>());
    });
  });

  // ==================================================================
  // 7. FB Call Statements
  // ==================================================================
  group('fb call', () {
    test('simple FB call: timer1(IN := TRUE, PT := T#5s);', () {
      final stmt = parser.parseStatement('timer1(IN := TRUE, PT := T#5s);');
      expect(stmt, isA<FbCallStatement>());
      final fb = stmt as FbCallStatement;
      expect(fb.target, isA<IdentifierExpression>());
      expect(
        (fb.target as IdentifierExpression).name,
        'timer1',
      );
      expect(fb.arguments, hasLength(2));
      expect(fb.arguments[0].name, 'IN');
      expect(fb.arguments[0].value, isA<BoolLiteral>());
      expect((fb.arguments[0].value as BoolLiteral).value, true);
      expect(fb.arguments[0].isOutput, false);
      expect(fb.arguments[1].name, 'PT');
      expect(fb.arguments[1].value, isA<TimeLiteral>());
    });

    test('FB call with output capture: motor(x := 1, y => result);', () {
      final stmt = parser.parseStatement('motor(x := 1, y => result);');
      expect(stmt, isA<FbCallStatement>());
      final fb = stmt as FbCallStatement;
      expect(fb.arguments, hasLength(2));
      // First arg: input assignment
      expect(fb.arguments[0].name, 'x');
      expect(fb.arguments[0].isOutput, false);
      // Second arg: output capture
      expect(fb.arguments[1].name, 'y');
      expect(fb.arguments[1].isOutput, true);
    });

    test('FB call via member access: obj.method(param := 42);', () {
      final stmt = parser.parseStatement('obj.method(param := 42);');
      expect(stmt, isA<FbCallStatement>());
      final fb = stmt as FbCallStatement;
      expect(fb.target, isA<MemberAccessExpression>());
      final target = fb.target as MemberAccessExpression;
      expect(target.member, 'method');
      expect(target.target, isA<IdentifierExpression>());
      expect(
        (target.target as IdentifierExpression).name,
        'obj',
      );
      expect(fb.arguments, hasLength(1));
      expect(fb.arguments[0].name, 'param');
    });

    test('FB call with no arguments: myFb();', () {
      final stmt = parser.parseStatement('myFb();');
      expect(stmt, isA<FbCallStatement>());
      final fb = stmt as FbCallStatement;
      expect(fb.target, isA<IdentifierExpression>());
      expect(fb.arguments, isEmpty);
    });
  });

  // ==================================================================
  // 8. Control Flow
  // ==================================================================
  group('control flow', () {
    test('EXIT;', () {
      final stmt = parser.parseStatement('EXIT;');
      expect(stmt, isA<ExitStatement>());
    });

    test('RETURN;', () {
      final stmt = parser.parseStatement('RETURN;');
      expect(stmt, isA<ReturnStatement>());
    });

    test('CONTINUE; (Beckhoff)', () {
      final stmt = parser.parseStatement('CONTINUE;');
      expect(stmt, isA<ContinueStatement>());
    });

    test('empty statement ;;', () {
      final stmts = parser.parseStatements(';;');
      // At least one empty statement should be parsed
      expect(stmts, isNotEmpty);
      expect(stmts.every((s) => s is EmptyStatement), isTrue);
    });
  });

  // ==================================================================
  // 8b. Expression Statement (bare expression as statement)
  // ==================================================================
  group('expression statement', () {
    test('bare dotted expression as statement: GVL_IO.Input1.q_xState.1;', () {
      final stmt = parser.parseStatement('GVL_IO.Input1.q_xState.1;');
      expect(stmt, isA<ExpressionStatement>());
      final exprStmt = stmt as ExpressionStatement;
      expect(exprStmt.expression, isA<MemberAccessExpression>());
    });

    test('bare identifier as statement: myVar;', () {
      final stmt = parser.parseStatement('myVar;');
      expect(stmt, isA<ExpressionStatement>());
      final exprStmt = stmt as ExpressionStatement;
      expect(exprStmt.expression, isA<IdentifierExpression>());
      expect(
        (exprStmt.expression as IdentifierExpression).name,
        'myVar',
      );
    });

    test('bare member access as statement: obj.field;', () {
      final stmt = parser.parseStatement('obj.field;');
      expect(stmt, isA<ExpressionStatement>());
      final exprStmt = stmt as ExpressionStatement;
      expect(exprStmt.expression, isA<MemberAccessExpression>());
    });
  });

  // ==================================================================
  // 8c. CASE with dotted (namespaced) labels
  // ==================================================================
  group('case with dotted labels', () {
    test('CASE with enum dotted label', () {
      final stmt = parser.parseStatement('''
        CASE eOutputState OF
          ET_FORCE_STATE.NORMAL:
            out_signal := i_xSignal;
          ET_FORCE_STATE.FORCED_LOW:
            out_signal := FALSE;
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.clauses, hasLength(2));
      // First clause label should be ET_FORCE_STATE.NORMAL
      final firstMatch = caseStmt.clauses[0].matches[0];
      expect(firstMatch, isA<CaseValueMatch>());
      final firstValue = (firstMatch as CaseValueMatch).value;
      expect(firstValue, isA<MemberAccessExpression>());
      final memberAccess = firstValue as MemberAccessExpression;
      expect(memberAccess.member, 'NORMAL');
      expect(memberAccess.target, isA<IdentifierExpression>());
      expect(
        (memberAccess.target as IdentifierExpression).name,
        'ET_FORCE_STATE',
      );
    });

    test('CASE with mix of dotted and integer labels', () {
      final stmt = parser.parseStatement('''
        CASE state OF
          MyEnum.VALUE_A:
            x := 1;
          0:
            x := 0;
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.clauses, hasLength(2));
      // First clause: dotted label
      final firstMatch = caseStmt.clauses[0].matches[0];
      expect(firstMatch, isA<CaseValueMatch>());
      expect((firstMatch as CaseValueMatch).value,
          isA<MemberAccessExpression>());
      // Second clause: integer label
      final secondMatch = caseStmt.clauses[1].matches[0];
      expect(secondMatch, isA<CaseValueMatch>());
      expect((secondMatch as CaseValueMatch).value, isA<IntLiteral>());
    });

    test('CASE with deeply dotted label: Ns.SubNs.VALUE', () {
      final stmt = parser.parseStatement('''
        CASE x OF
          Ns.SubNs.VALUE:
            y := 1;
        END_CASE;
      ''');
      expect(stmt, isA<CaseStatement>());
      final caseStmt = stmt as CaseStatement;
      expect(caseStmt.clauses, hasLength(1));
      final match = caseStmt.clauses[0].matches[0];
      expect(match, isA<CaseValueMatch>());
      final value = (match as CaseValueMatch).value;
      expect(value, isA<MemberAccessExpression>());
      final outer = value as MemberAccessExpression;
      expect(outer.member, 'VALUE');
      expect(outer.target, isA<MemberAccessExpression>());
    });
  });

  // ==================================================================
  // 8d. Bit access in assignments
  // ==================================================================
  group('bit access assignment', () {
    test('assign to bit: q_xState.0 := TRUE;', () {
      final stmt = parser.parseStatement('q_xState.0 := TRUE;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.target, isA<MemberAccessExpression>());
      final member = assign.target as MemberAccessExpression;
      expect(member.member, '0');
      expect(member.target, isA<IdentifierExpression>());
      expect(
        (member.target as IdentifierExpression).name,
        'q_xState',
      );
      expect(assign.value, isA<BoolLiteral>());
    });

    test('assign to bit: q_xState.1 := FALSE;', () {
      final stmt = parser.parseStatement('q_xState.1 := FALSE;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.target, isA<MemberAccessExpression>());
      final member = assign.target as MemberAccessExpression;
      expect(member.member, '1');
    });

    test('assign to chained bit: GVL.output.3 := x;', () {
      final stmt = parser.parseStatement('GVL.output.3 := x;');
      expect(stmt, isA<AssignmentStatement>());
      final assign = stmt as AssignmentStatement;
      expect(assign.target, isA<MemberAccessExpression>());
      final member = assign.target as MemberAccessExpression;
      expect(member.member, '3');
      expect(member.target, isA<MemberAccessExpression>());
    });
  });

  // ==================================================================
  // 9. Multiple Statements
  // ==================================================================
  group('multiple statements', () {
    test('parseStatements returns list', () {
      final stmts = parser.parseStatements('''
        x := 1;
        y := 2;
        z := x + y;
      ''');
      expect(stmts, hasLength(3));
      expect(stmts[0], isA<AssignmentStatement>());
      expect(stmts[1], isA<AssignmentStatement>());
      expect(stmts[2], isA<AssignmentStatement>());
    });

    test('mixed statement types', () {
      final stmts = parser.parseStatements('''
        x := 0;
        IF x > 0 THEN
          y := 1;
        END_IF;
        FOR i := 0 TO 5 DO
          x := x + i;
        END_FOR;
        RETURN;
      ''');
      expect(stmts, hasLength(4));
      expect(stmts[0], isA<AssignmentStatement>());
      expect(stmts[1], isA<IfStatement>());
      expect(stmts[2], isA<ForStatement>());
      expect(stmts[3], isA<ReturnStatement>());
    });

    test('empty input returns empty list', () {
      final stmts = parser.parseStatements('');
      expect(stmts, isEmpty);
    });

    test('whitespace-only input returns empty list', () {
      final stmts = parser.parseStatements('   \n\n  ');
      expect(stmts, isEmpty);
    });
  });

  // ==================================================================
  // 10. Case Insensitivity
  // ==================================================================
  group('case insensitivity', () {
    test('IF/if/If all parse the same', () {
      final upper = parser.parseStatement('IF x THEN y := 1; END_IF;');
      final lower = parser.parseStatement('if x then y := 1; end_if;');
      final mixed = parser.parseStatement('If x Then y := 1; End_If;');

      expect(upper, isA<IfStatement>());
      expect(lower, isA<IfStatement>());
      expect(mixed, isA<IfStatement>());
    });

    test('END_IF/end_if/End_If all work', () {
      // Already covered above, but also test ELSIF/elsif
      final upper = parser.parseStatement(
        'IF a THEN x := 1; ELSIF b THEN x := 2; END_IF;',
      );
      final lower = parser.parseStatement(
        'if a then x := 1; elsif b then x := 2; end_if;',
      );

      expect(upper, isA<IfStatement>());
      expect(lower, isA<IfStatement>());
      expect(
        (upper as IfStatement).elsifClauses,
        hasLength(1),
      );
      expect(
        (lower as IfStatement).elsifClauses,
        hasLength(1),
      );
    });

    test('FOR/for/For all work', () {
      final upper = parser.parseStatement(
        'FOR i := 0 TO 5 DO x := i; END_FOR;',
      );
      final lower = parser.parseStatement(
        'for i := 0 to 5 do x := i; end_for;',
      );
      final mixed = parser.parseStatement(
        'For i := 0 To 5 Do x := i; End_For;',
      );

      expect(upper, isA<ForStatement>());
      expect(lower, isA<ForStatement>());
      expect(mixed, isA<ForStatement>());
    });

    test('WHILE/while work', () {
      final upper = parser.parseStatement(
        'WHILE x DO y := 1; END_WHILE;',
      );
      final lower = parser.parseStatement(
        'while x do y := 1; end_while;',
      );

      expect(upper, isA<WhileStatement>());
      expect(lower, isA<WhileStatement>());
    });

    test('CASE/case work', () {
      final upper = parser.parseStatement(
        'CASE x OF 1: y := 1; END_CASE;',
      );
      final lower = parser.parseStatement(
        'case x of 1: y := 1; end_case;',
      );

      expect(upper, isA<CaseStatement>());
      expect(lower, isA<CaseStatement>());
    });

    test('REPEAT/repeat work', () {
      final upper = parser.parseStatement(
        'REPEAT x := x + 1; UNTIL x > 5 END_REPEAT;',
      );
      final lower = parser.parseStatement(
        'repeat x := x + 1; until x > 5 end_repeat;',
      );

      expect(upper, isA<RepeatStatement>());
      expect(lower, isA<RepeatStatement>());
    });

    test('EXIT/exit, RETURN/return, CONTINUE/continue work', () {
      expect(parser.parseStatement('EXIT;'), isA<ExitStatement>());
      expect(parser.parseStatement('exit;'), isA<ExitStatement>());
      expect(parser.parseStatement('RETURN;'), isA<ReturnStatement>());
      expect(parser.parseStatement('return;'), isA<ReturnStatement>());
      expect(parser.parseStatement('CONTINUE;'), isA<ContinueStatement>());
      expect(parser.parseStatement('continue;'), isA<ContinueStatement>());
    });

    test('TRUE/true/True and FALSE/false/False in assignments', () {
      final stmt1 = parser.parseStatement('x := TRUE;');
      final stmt2 = parser.parseStatement('x := true;');
      final stmt3 = parser.parseStatement('x := True;');

      for (final stmt in [stmt1, stmt2, stmt3]) {
        expect(stmt, isA<AssignmentStatement>());
        final assign = stmt as AssignmentStatement;
        expect(assign.value, isA<BoolLiteral>());
        expect((assign.value as BoolLiteral).value, true);
      }
    });
  });
}

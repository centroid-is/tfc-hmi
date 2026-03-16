import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/compiler.dart';

void main() {
  late StParser parser;

  setUp(() {
    parser = StParser();
  });

  // ==================================================================
  // 1. Variable Declarations
  // ==================================================================
  group('variable declarations', () {
    test('simple var block', () {
      final block = parser.parseVarBlock('''
        VAR
          x : INT;
          y : REAL;
        END_VAR
      ''');
      expect(block.section, VarSection.var_);
      expect(block.declarations, hasLength(2));
      expect(block.declarations[0].name, 'x');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'INT'),
      );
      expect(block.declarations[1].name, 'y');
      expect(
        block.declarations[1].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'REAL'),
      );
    });

    test('VAR_INPUT', () {
      final block = parser.parseVarBlock('''
        VAR_INPUT
          enable : BOOL;
          setpoint : REAL;
        END_VAR
      ''');
      expect(block.section, VarSection.varInput);
      expect(block.declarations, hasLength(2));
      expect(block.declarations[0].name, 'enable');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'BOOL'),
      );
    });

    test('VAR_OUTPUT', () {
      final block = parser.parseVarBlock('''
        VAR_OUTPUT
          done : BOOL;
          value : REAL;
        END_VAR
      ''');
      expect(block.section, VarSection.varOutput);
      expect(block.declarations, hasLength(2));
    });

    test('VAR_IN_OUT', () {
      final block = parser.parseVarBlock('''
        VAR_IN_OUT
          counter : INT;
        END_VAR
      ''');
      expect(block.section, VarSection.varInOut);
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'counter');
    });

    test('VAR_GLOBAL', () {
      final block = parser.parseVarBlock('''
        VAR_GLOBAL
          globalCounter : DINT;
        END_VAR
      ''');
      expect(block.section, VarSection.varGlobal);
      expect(block.declarations, hasLength(1));
    });

    test('VAR_TEMP', () {
      final block = parser.parseVarBlock('''
        VAR_TEMP
          tmp : INT;
        END_VAR
      ''');
      expect(block.section, VarSection.varTemp);
      expect(block.declarations, hasLength(1));
    });

    test('VAR_INST (Beckhoff)', () {
      final block = parser.parseVarBlock('''
        VAR_INST
          fbInstance : INT;
        END_VAR
      ''');
      expect(block.section, VarSection.varInst);
      expect(block.declarations, hasLength(1));
    });

    test('VAR_STAT (Beckhoff)', () {
      final block = parser.parseVarBlock('''
        VAR_STAT
          callCount : DINT;
        END_VAR
      ''');
      expect(block.section, VarSection.varStat);
      expect(block.declarations, hasLength(1));
    });

    test('VAR RETAIN qualifier', () {
      final block = parser.parseVarBlock('''
        VAR RETAIN
          count : DINT;
        END_VAR
      ''');
      expect(block.section, VarSection.var_);
      expect(block.qualifiers, contains(VarQualifier.retain));
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'count');
    });

    test('VAR PERSISTENT qualifier', () {
      final block = parser.parseVarBlock('''
        VAR PERSISTENT
          savedValue : REAL;
        END_VAR
      ''');
      expect(block.section, VarSection.var_);
      expect(block.qualifiers, contains(VarQualifier.persistent));
    });

    test('VAR CONSTANT qualifier', () {
      final block = parser.parseVarBlock('''
        VAR CONSTANT
          MAX_VALUE : REAL := 100.0;
          MIN_VALUE : REAL := 0.0;
        END_VAR
      ''');
      expect(block.section, VarSection.var_);
      expect(block.qualifiers, contains(VarQualifier.constant));
      expect(block.declarations, hasLength(2));
    });

    test('variable with initializer', () {
      final block = parser.parseVarBlock('''
        VAR
          x : INT := 42;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'x');
      expect(block.declarations[0].initialValue, isNotNull);
      expect(
        block.declarations[0].initialValue,
        isA<IntLiteral>().having((l) => l.value, 'value', 42),
      );
    });

    test('variable with AT address (I/O)', () {
      final block = parser.parseVarBlock('''
        VAR
          motorStart AT %I0.3.5 : BOOL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'motorStart');
      expect(block.declarations[0].atAddress, '%I0.3.5');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'BOOL'),
      );
    });

    test('variable with AT memory address', () {
      final block = parser.parseVarBlock('''
        VAR
          word AT %MW100 : INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'word');
      expect(block.declarations[0].atAddress, '%MW100');
    });

    test('variable with comment', () {
      final block = parser.parseVarBlock('''
        VAR
          x : INT; // this is x
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'x');
      expect(block.declarations[0].comment, 'this is x');
    });

    test('STRING type with length (brackets)', () {
      final block = parser.parseVarBlock('''
        VAR
          s : STRING[80];
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(
        block.declarations[0].typeSpec,
        isA<StringType>()
            .having((t) => t.isWide, 'isWide', false)
            .having((t) => t.maxLength, 'maxLength', 80),
      );
    });

    test('STRING type with length (parens)', () {
      final block = parser.parseVarBlock('''
        VAR
          s : STRING(80);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(
        block.declarations[0].typeSpec,
        isA<StringType>()
            .having((t) => t.isWide, 'isWide', false)
            .having((t) => t.maxLength, 'maxLength', 80),
      );
    });

    test('WSTRING type', () {
      final block = parser.parseVarBlock('''
        VAR
          ws : WSTRING[255];
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(
        block.declarations[0].typeSpec,
        isA<StringType>()
            .having((t) => t.isWide, 'isWide', true)
            .having((t) => t.maxLength, 'maxLength', 255),
      );
    });

    test('ARRAY type', () {
      final block = parser.parseVarBlock('''
        VAR
          arr : ARRAY[1..10] OF INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].typeSpec, isA<ArrayType>());
      final arrType = block.declarations[0].typeSpec as ArrayType;
      expect(arrType.ranges, hasLength(1));
      expect(
        arrType.ranges[0].lower,
        isA<IntLiteral>().having((l) => l.value, 'value', 1),
      );
      expect(
        arrType.ranges[0].upper,
        isA<IntLiteral>().having((l) => l.value, 'value', 10),
      );
      expect(
        arrType.elementType,
        isA<SimpleType>().having((t) => t.name, 'name', 'INT'),
      );
    });

    test('multi-dimensional array', () {
      final block = parser.parseVarBlock('''
        VAR
          arr : ARRAY[1..5, 1..3] OF REAL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      final arrType = block.declarations[0].typeSpec as ArrayType;
      expect(arrType.ranges, hasLength(2));
      expect(
        arrType.ranges[0].lower,
        isA<IntLiteral>().having((l) => l.value, 'value', 1),
      );
      expect(
        arrType.ranges[0].upper,
        isA<IntLiteral>().having((l) => l.value, 'value', 5),
      );
      expect(
        arrType.ranges[1].lower,
        isA<IntLiteral>().having((l) => l.value, 'value', 1),
      );
      expect(
        arrType.ranges[1].upper,
        isA<IntLiteral>().having((l) => l.value, 'value', 3),
      );
      expect(
        arrType.elementType,
        isA<SimpleType>().having((t) => t.name, 'name', 'REAL'),
      );
    });

    test('POINTER TO (Beckhoff)', () {
      final block = parser.parseVarBlock('''
        VAR
          p : POINTER TO INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].typeSpec, isA<PointerType>());
      final ptrType = block.declarations[0].typeSpec as PointerType;
      expect(
        ptrType.targetType,
        isA<SimpleType>().having((t) => t.name, 'name', 'INT'),
      );
    });

    test('REFERENCE TO (Beckhoff)', () {
      final block = parser.parseVarBlock('''
        VAR
          r : REFERENCE TO REAL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].typeSpec, isA<ReferenceType>());
      final refType = block.declarations[0].typeSpec as ReferenceType;
      expect(
        refType.targetType,
        isA<SimpleType>().having((t) => t.name, 'name', 'REAL'),
      );
    });

    test('ARRAY OF POINTER TO', () {
      final block = parser.parseVarBlock('''
        VAR
          arr : ARRAY[0..9] OF POINTER TO REAL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      final arrType = block.declarations[0].typeSpec as ArrayType;
      expect(arrType.ranges, hasLength(1));
      expect(arrType.elementType, isA<PointerType>());
      final ptrType = arrType.elementType as PointerType;
      expect(
        ptrType.targetType,
        isA<SimpleType>().having((t) => t.name, 'name', 'REAL'),
      );
    });

    test('Schneider EBOOL type', () {
      final block = parser.parseVarBlock('''
        VAR
          sig : EBOOL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'sig');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'EBOOL'),
      );
    });

    test('multiple vars same line', () {
      final block = parser.parseVarBlock('''
        VAR
          a, b, c : INT;
        END_VAR
      ''');
      // IEC 61131-3 allows "a, b, c : INT;" to declare multiple vars
      expect(block.declarations, hasLength(3));
      expect(block.declarations[0].name, 'a');
      expect(block.declarations[1].name, 'b');
      expect(block.declarations[2].name, 'c');
      for (final decl in block.declarations) {
        expect(
          decl.typeSpec,
          isA<SimpleType>().having((t) => t.name, 'name', 'INT'),
        );
      }
    });

    test('FB instance', () {
      final block = parser.parseVarBlock('''
        VAR
          timer1 : TON;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'timer1');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'TON'),
      );
    });

    test('string initializer', () {
      final block = parser.parseVarBlock('''
        VAR
          s : STRING[32] := 'Hello';
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 's');
      expect(
        block.declarations[0].typeSpec,
        isA<StringType>().having((t) => t.maxLength, 'maxLength', 32),
      );
      expect(block.declarations[0].initialValue, isNotNull);
      expect(
        block.declarations[0].initialValue,
        isA<StringLiteral>().having((l) => l.value, 'value', 'Hello'),
      );
    });

    test('REAL initializer', () {
      final block = parser.parseVarBlock('''
        VAR
          rate : REAL := 10.0;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].initialValue, isNotNull);
      expect(
        block.declarations[0].initialValue,
        isA<RealLiteral>().having((l) => l.value, 'value', 10.0),
      );
    });

    test('BOOL initializer TRUE', () {
      final block = parser.parseVarBlock('''
        VAR
          flag : BOOL := TRUE;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(
        block.declarations[0].initialValue,
        isA<BoolLiteral>().having((l) => l.value, 'value', true),
      );
    });

    test('STRING without length', () {
      final block = parser.parseVarBlock('''
        VAR
          s : STRING;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(
        block.declarations[0].typeSpec,
        isA<StringType>()
            .having((t) => t.isWide, 'isWide', false)
            .having((t) => t.maxLength, 'maxLength', isNull),
      );
    });

    test('empty var block', () {
      final block = parser.parseVarBlock('''
        VAR
        END_VAR
      ''');
      expect(block.section, VarSection.var_);
      expect(block.declarations, isEmpty);
    });
  });

  // ==================================================================
  // 2. POU Declarations -- PROGRAM
  // ==================================================================
  group('PROGRAM', () {
    test('minimal program', () {
      final pou = parser.parsePou('''
        PROGRAM Main
        VAR
          x : INT;
        END_VAR
          x := 42;
        END_PROGRAM
      ''');
      expect(pou.pouType, PouType.program);
      expect(pou.name, 'Main');
      expect(pou.varBlocks, hasLength(1));
      expect(pou.varBlocks[0].section, VarSection.var_);
      expect(pou.body, hasLength(1));
      expect(pou.body[0], isA<AssignmentStatement>());
    });

    test('program with multiple var blocks', () {
      final pou = parser.parsePou('''
        PROGRAM MultiVars
        VAR_INPUT
          enable : BOOL;
        END_VAR
        VAR_OUTPUT
          done : BOOL;
        END_VAR
        VAR
          state : INT;
        END_VAR
          state := 1;
        END_PROGRAM
      ''');
      expect(pou.pouType, PouType.program);
      expect(pou.name, 'MultiVars');
      expect(pou.varBlocks, hasLength(3));
      expect(pou.varBlocks[0].section, VarSection.varInput);
      expect(pou.varBlocks[1].section, VarSection.varOutput);
      expect(pou.varBlocks[2].section, VarSection.var_);
    });

    test('program with no vars', () {
      final pou = parser.parsePou('''
        PROGRAM EmptyVars
          ; // empty body with semicolons
        END_PROGRAM
      ''');
      expect(pou.pouType, PouType.program);
      expect(pou.name, 'EmptyVars');
      expect(pou.varBlocks, isEmpty);
    });

    test('program with no body', () {
      final pou = parser.parsePou('''
        PROGRAM NoBody
        VAR
          x : INT;
        END_VAR
        END_PROGRAM
      ''');
      expect(pou.pouType, PouType.program);
      expect(pou.name, 'NoBody');
      expect(pou.varBlocks, hasLength(1));
      expect(pou.body, isEmpty);
    });
  });

  // ==================================================================
  // 3. POU Declarations -- FUNCTION_BLOCK
  // ==================================================================
  group('FUNCTION_BLOCK', () {
    test('simple function block', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Simple
        VAR
          x : INT;
        END_VAR
          x := x + 1;
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_Simple');
      expect(pou.varBlocks, hasLength(1));
      expect(pou.body, isNotEmpty);
    });

    test('FB with VAR_INPUT and VAR_OUTPUT', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_IO
        VAR_INPUT
          enable : BOOL;
          setpoint : REAL;
        END_VAR
        VAR_OUTPUT
          done : BOOL;
          value : REAL;
        END_VAR
          IF enable THEN
            value := setpoint;
            done := TRUE;
          END_IF;
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_IO');
      expect(pou.varBlocks, hasLength(2));
      expect(pou.varBlocks[0].section, VarSection.varInput);
      expect(pou.varBlocks[0].declarations, hasLength(2));
      expect(pou.varBlocks[1].section, VarSection.varOutput);
      expect(pou.varBlocks[1].declarations, hasLength(2));
    });

    test('Beckhoff FB with EXTENDS', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Child EXTENDS FB_Parent
        VAR
          x : INT;
        END_VAR
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_Child');
      expect(pou.extendsFrom, 'FB_Parent');
    });

    test('Beckhoff FB with IMPLEMENTS', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Motor IMPLEMENTS ITF_Drive
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_Motor');
      expect(pou.implementsList, ['ITF_Drive']);
    });

    test('Beckhoff FB with EXTENDS and IMPLEMENTS', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_AdvMotor EXTENDS FB_Motor IMPLEMENTS ITF_Drive, ITF_Diag
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_AdvMotor');
      expect(pou.extendsFrom, 'FB_Motor');
      expect(pou.implementsList, ['ITF_Drive', 'ITF_Diag']);
    });

    test('Beckhoff FB with access modifier', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK PUBLIC FB_Visible
        VAR
          x : INT;
        END_VAR
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_Visible');
      expect(pou.accessModifier, AccessModifier.public_);
    });

    test('Beckhoff ABSTRACT FB', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK ABSTRACT FB_Base
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_Base');
      expect(pou.isAbstract, isTrue);
    });

    test('FB with no vars and no body', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Empty
        END_FUNCTION_BLOCK
      ''');
      expect(pou.pouType, PouType.functionBlock);
      expect(pou.name, 'FB_Empty');
      expect(pou.varBlocks, isEmpty);
      expect(pou.body, isEmpty);
    });
  });

  // ==================================================================
  // 4. POU Declarations -- FUNCTION
  // ==================================================================
  group('FUNCTION', () {
    test('function with return type INT', () {
      final pou = parser.parsePou('''
        FUNCTION FC_Add : INT
        VAR_INPUT
          a : INT;
          b : INT;
        END_VAR
          FC_Add := a + b;
        END_FUNCTION
      ''');
      expect(pou.pouType, PouType.function_);
      expect(pou.returnType, 'INT');
      expect(pou.name, 'FC_Add');
      expect(pou.varBlocks, hasLength(1));
      expect(pou.varBlocks[0].section, VarSection.varInput);
      expect(pou.varBlocks[0].declarations, hasLength(2));
      expect(pou.body, hasLength(1));
    });

    test('function with REAL return type', () {
      final pou = parser.parsePou('''
        FUNCTION FC_Scale : REAL
        VAR_INPUT
          value : REAL;
          factor : REAL;
        END_VAR
          FC_Scale := value * factor;
        END_FUNCTION
      ''');
      expect(pou.pouType, PouType.function_);
      expect(pou.returnType, 'REAL');
      expect(pou.name, 'FC_Scale');
    });

    test('function with complex body', () {
      final pou = parser.parsePou('''
        FUNCTION FC_Clamp : REAL
        VAR_INPUT
          value : REAL;
          minVal : REAL;
          maxVal : REAL;
        END_VAR
          IF value < minVal THEN
            FC_Clamp := minVal;
          ELSIF value > maxVal THEN
            FC_Clamp := maxVal;
          ELSE
            FC_Clamp := value;
          END_IF;
        END_FUNCTION
      ''');
      expect(pou.pouType, PouType.function_);
      expect(pou.name, 'FC_Clamp');
      expect(pou.returnType, 'REAL');
      expect(pou.varBlocks, hasLength(1));
      expect(pou.varBlocks[0].declarations, hasLength(3));
      expect(pou.body, hasLength(1));
      expect(pou.body[0], isA<IfStatement>());
    });

    test('function with BOOL return type', () {
      final pou = parser.parsePou('''
        FUNCTION FC_InRange : BOOL
        VAR_INPUT
          val : INT;
          lo : INT;
          hi : INT;
        END_VAR
          FC_InRange := (val >= lo) AND (val <= hi);
        END_FUNCTION
      ''');
      expect(pou.pouType, PouType.function_);
      expect(pou.returnType, 'BOOL');
    });

    test('function with no var blocks', () {
      final pou = parser.parsePou('''
        FUNCTION FC_ReturnZero : INT
          FC_ReturnZero := 0;
        END_FUNCTION
      ''');
      expect(pou.pouType, PouType.function_);
      expect(pou.name, 'FC_ReturnZero');
      expect(pou.returnType, 'INT');
      expect(pou.varBlocks, isEmpty);
      expect(pou.body, hasLength(1));
    });
  });

  // ==================================================================
  // 5. Method Declarations (Beckhoff)
  // ==================================================================
  group('METHOD (Beckhoff)', () {
    test('simple method', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test
        VAR
          _value : INT;
        END_VAR

        METHOD DoWork
          _value := _value + 1;
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.methods, hasLength(1));
      expect(pou.methods[0].name, 'DoWork');
      expect(pou.methods[0].returnType, isNull);
      expect(pou.methods[0].body, isNotEmpty);
    });

    test('method with return type', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test
        VAR
          _value : INT;
        END_VAR

        METHOD GetValue : INT
          GetValue := _value;
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.methods, hasLength(1));
      expect(pou.methods[0].name, 'GetValue');
      expect(pou.methods[0].returnType, 'INT');
    });

    test('method with access modifier', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test
        VAR
          _value : INT;
        END_VAR

        METHOD PUBLIC Start : BOOL
        VAR_INPUT
          initialValue : REAL;
        END_VAR
          Start := TRUE;
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.methods, hasLength(1));
      expect(pou.methods[0].name, 'Start');
      expect(pou.methods[0].accessModifier, AccessModifier.public_);
      expect(pou.methods[0].returnType, 'BOOL');
      expect(pou.methods[0].varBlocks, hasLength(1));
      expect(pou.methods[0].varBlocks[0].section, VarSection.varInput);
    });

    test('method with VAR_INST', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test

        METHOD DoWork
        VAR_INST
          callCount : DINT;
        END_VAR
          callCount := callCount + 1;
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.methods, hasLength(1));
      expect(pou.methods[0].varBlocks, hasLength(1));
      expect(pou.methods[0].varBlocks[0].section, VarSection.varInst);
    });

    test('ABSTRACT method', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK ABSTRACT FB_Base

        METHOD ABSTRACT Execute : BOOL
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.isAbstract, isTrue);
      expect(pou.methods, hasLength(1));
      expect(pou.methods[0].name, 'Execute');
      expect(pou.methods[0].isAbstract, isTrue);
      expect(pou.methods[0].returnType, 'BOOL');
    });

    test('multiple methods', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test

        METHOD PUBLIC Start : BOOL
          Start := TRUE;
        END_METHOD

        METHOD PUBLIC Stop : BOOL
          Stop := TRUE;
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.methods, hasLength(2));
      expect(pou.methods[0].name, 'Start');
      expect(pou.methods[1].name, 'Stop');
    });

    test('PRIVATE method', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test

        METHOD PRIVATE InternalCalc : REAL
          InternalCalc := 0.0;
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.methods, hasLength(1));
      expect(pou.methods[0].accessModifier, AccessModifier.private_);
    });
  });

  // ==================================================================
  // 6. Property Declarations (Beckhoff)
  // ==================================================================
  group('PROPERTY (Beckhoff)', () {
    test('property with GET only', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test
        VAR
          _temp : REAL;
        END_VAR

        PROPERTY Temperature : REAL
        GET
          Temperature := _temp;
        END_GET
        END_PROPERTY

        END_FUNCTION_BLOCK
      ''');
      expect(pou.properties, hasLength(1));
      expect(pou.properties[0].name, 'Temperature');
      expect(pou.properties[0].typeName, 'REAL');
      expect(pou.properties[0].getter, isNotNull);
      expect(pou.properties[0].setter, isNull);
    });

    test('property with SET only', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test
        VAR
          _setpoint : REAL;
        END_VAR

        PROPERTY Setpoint : REAL
        SET
          _setpoint := Setpoint;
        END_SET
        END_PROPERTY

        END_FUNCTION_BLOCK
      ''');
      expect(pou.properties, hasLength(1));
      expect(pou.properties[0].name, 'Setpoint');
      expect(pou.properties[0].getter, isNull);
      expect(pou.properties[0].setter, isNotNull);
    });

    test('property with GET and SET', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test
        VAR
          _temperature : REAL;
        END_VAR

        PROPERTY PUBLIC Temperature : REAL
        GET
        VAR
        END_VAR
          Temperature := _temperature;
        END_GET
        SET
        VAR
        END_VAR
          _temperature := Temperature;
        END_SET
        END_PROPERTY

        END_FUNCTION_BLOCK
      ''');
      expect(pou.properties, hasLength(1));
      expect(pou.properties[0].name, 'Temperature');
      expect(pou.properties[0].typeName, 'REAL');
      expect(pou.properties[0].getter, isNotNull);
      expect(pou.properties[0].setter, isNotNull);
      expect(pou.properties[0].getter!.body, isNotEmpty);
      expect(pou.properties[0].setter!.body, isNotEmpty);
    });

    test('property with access modifier', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test
        VAR
          _speed : REAL;
        END_VAR

        PROPERTY PUBLIC Speed : REAL
        GET
          Speed := _speed;
        END_GET
        END_PROPERTY

        END_FUNCTION_BLOCK
      ''');
      expect(pou.properties, hasLength(1));
      expect(pou.properties[0].accessModifier, AccessModifier.public_);
    });
  });

  // ==================================================================
  // 7. Interface Declarations (Beckhoff)
  // ==================================================================
  group('INTERFACE (Beckhoff)', () {
    test('interface with methods', () {
      final unit = parser.parse('''
        INTERFACE ITF_Drive
          METHOD Start : BOOL
          END_METHOD
          METHOD Stop : BOOL
          END_METHOD
        END_INTERFACE
      ''');
      expect(unit.declarations, hasLength(1));
      expect(unit.declarations[0], isA<InterfaceDeclaration>());
      final iface = unit.declarations[0] as InterfaceDeclaration;
      expect(iface.name, 'ITF_Drive');
      expect(iface.methods, hasLength(2));
      expect(iface.methods[0].name, 'Start');
      expect(iface.methods[0].returnType, 'BOOL');
      expect(iface.methods[1].name, 'Stop');
      expect(iface.methods[1].returnType, 'BOOL');
    });

    test('interface with properties', () {
      final unit = parser.parse('''
        INTERFACE ITF_Sensor
          PROPERTY Value : REAL
          END_PROPERTY
        END_INTERFACE
      ''');
      expect(unit.declarations, hasLength(1));
      final iface = unit.declarations[0] as InterfaceDeclaration;
      expect(iface.name, 'ITF_Sensor');
      expect(iface.properties, hasLength(1));
      expect(iface.properties[0].name, 'Value');
      expect(iface.properties[0].typeName, 'REAL');
    });

    test('interface extending another interface', () {
      final unit = parser.parse('''
        INTERFACE ITF_AdvDrive EXTENDS ITF_Drive
          METHOD Diagnostic : BOOL
          END_METHOD
        END_INTERFACE
      ''');
      expect(unit.declarations, hasLength(1));
      final iface = unit.declarations[0] as InterfaceDeclaration;
      expect(iface.name, 'ITF_AdvDrive');
      expect(iface.extendsFrom, 'ITF_Drive');
      expect(iface.methods, hasLength(1));
    });

    test('empty interface', () {
      final unit = parser.parse('''
        INTERFACE ITF_Empty
        END_INTERFACE
      ''');
      expect(unit.declarations, hasLength(1));
      final iface = unit.declarations[0] as InterfaceDeclaration;
      expect(iface.name, 'ITF_Empty');
      expect(iface.methods, isEmpty);
      expect(iface.properties, isEmpty);
    });
  });

  // ==================================================================
  // 8. Type Declarations
  // ==================================================================
  group('TYPE declarations', () {
    test('enum type with explicit values', () {
      final typeDecl = parser.parseTypeDeclaration('''
        TYPE MotorState :
        (
          Idle := 0,
          Starting := 1,
          Running := 2
        );
        END_TYPE
      ''');
      expect(typeDecl.name, 'MotorState');
      expect(typeDecl.definition, isA<EnumDefinition>());
      final enumDef = typeDecl.definition as EnumDefinition;
      expect(enumDef.values, hasLength(3));
      expect(enumDef.values[0].name, 'Idle');
      expect(
        enumDef.values[0].value,
        isA<IntLiteral>().having((l) => l.value, 'value', 0),
      );
      expect(enumDef.values[1].name, 'Starting');
      expect(
        enumDef.values[1].value,
        isA<IntLiteral>().having((l) => l.value, 'value', 1),
      );
      expect(enumDef.values[2].name, 'Running');
      expect(
        enumDef.values[2].value,
        isA<IntLiteral>().having((l) => l.value, 'value', 2),
      );
    });

    test('enum type without explicit values', () {
      final typeDecl = parser.parseTypeDeclaration('''
        TYPE Color :
        (
          Red,
          Green,
          Blue
        );
        END_TYPE
      ''');
      expect(typeDecl.name, 'Color');
      expect(typeDecl.definition, isA<EnumDefinition>());
      final enumDef = typeDecl.definition as EnumDefinition;
      expect(enumDef.values, hasLength(3));
      expect(enumDef.values[0].name, 'Red');
      expect(enumDef.values[0].value, isNull);
      expect(enumDef.values[1].name, 'Green');
      expect(enumDef.values[2].name, 'Blue');
    });

    test('struct type', () {
      final typeDecl = parser.parseTypeDeclaration('''
        TYPE ST_Data :
        STRUCT
          speed : REAL;
          count : INT;
        END_STRUCT
        END_TYPE
      ''');
      expect(typeDecl.name, 'ST_Data');
      expect(typeDecl.definition, isA<StructDefinition>());
      final structDef = typeDecl.definition as StructDefinition;
      expect(structDef.fields, hasLength(2));
      expect(structDef.fields[0].name, 'speed');
      expect(
        structDef.fields[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'REAL'),
      );
      expect(structDef.fields[1].name, 'count');
      expect(
        structDef.fields[1].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'INT'),
      );
    });

    test('alias type', () {
      final typeDecl = parser.parseTypeDeclaration('''
        TYPE Percentage : REAL;
        END_TYPE
      ''');
      expect(typeDecl.name, 'Percentage');
      expect(typeDecl.definition, isA<AliasDefinition>());
      final aliasDef = typeDecl.definition as AliasDefinition;
      expect(
        aliasDef.aliasedType,
        isA<SimpleType>().having((t) => t.name, 'name', 'REAL'),
      );
    });

    test('struct with string fields', () {
      final typeDecl = parser.parseTypeDeclaration('''
        TYPE ST_MotorData :
        STRUCT
          speed : REAL;
          current : REAL;
          temperature : REAL;
          state : MotorState;
          faultCode : DINT;
          name : STRING[32];
        END_STRUCT
        END_TYPE
      ''');
      expect(typeDecl.name, 'ST_MotorData');
      final structDef = typeDecl.definition as StructDefinition;
      expect(structDef.fields, hasLength(6));
      expect(structDef.fields[5].name, 'name');
      expect(
        structDef.fields[5].typeSpec,
        isA<StringType>().having((t) => t.maxLength, 'maxLength', 32),
      );
    });

    test('struct with initializers', () {
      final typeDecl = parser.parseTypeDeclaration('''
        TYPE ST_Config :
        STRUCT
          maxSpeed : REAL := 100.0;
          enabled : BOOL := FALSE;
          label : STRING[16] := 'default';
        END_STRUCT
        END_TYPE
      ''');
      expect(typeDecl.name, 'ST_Config');
      final structDef = typeDecl.definition as StructDefinition;
      expect(structDef.fields, hasLength(3));
      expect(structDef.fields[0].initialValue, isNotNull);
      expect(
        structDef.fields[0].initialValue,
        isA<RealLiteral>().having((l) => l.value, 'value', 100.0),
      );
      expect(
        structDef.fields[1].initialValue,
        isA<BoolLiteral>().having((l) => l.value, 'value', false),
      );
      expect(
        structDef.fields[2].initialValue,
        isA<StringLiteral>().having((l) => l.value, 'value', 'default'),
      );
    });

    test('enum with 5 values matching fixture', () {
      final typeDecl = parser.parseTypeDeclaration('''
        TYPE MotorState :
        (
          Idle := 0,
          Starting := 1,
          Running := 2,
          Stopping := 3,
          Faulted := 4
        );
        END_TYPE
      ''');
      expect(typeDecl.name, 'MotorState');
      final enumDef = typeDecl.definition as EnumDefinition;
      expect(enumDef.values, hasLength(5));
      expect(enumDef.values[3].name, 'Stopping');
      expect(enumDef.values[4].name, 'Faulted');
    });
  });

  // ==================================================================
  // 9. Complete File Parsing
  // ==================================================================
  group('complete file parsing', () {
    test('parse compilation unit with multiple POUs', () {
      final unit = parser.parse('''
        PROGRAM Main
        VAR
          x : INT;
        END_VAR
          x := 1;
        END_PROGRAM

        FUNCTION_BLOCK FB_Helper
        END_FUNCTION_BLOCK
      ''');
      expect(unit.declarations, hasLength(2));
      expect(unit.declarations[0], isA<PouDeclaration>());
      expect(
        (unit.declarations[0] as PouDeclaration).pouType,
        PouType.program,
      );
      expect(unit.declarations[1], isA<PouDeclaration>());
      expect(
        (unit.declarations[1] as PouDeclaration).pouType,
        PouType.functionBlock,
      );
    });

    test('parse compilation unit with types and POUs', () {
      final unit = parser.parse('''
        TYPE MotorState :
        (
          Idle := 0,
          Running := 1
        );
        END_TYPE

        FUNCTION_BLOCK FB_Motor
        VAR
          state : MotorState;
        END_VAR
        END_FUNCTION_BLOCK
      ''');
      expect(unit.declarations, hasLength(2));
      expect(unit.declarations[0], isA<TypeDeclaration>());
      expect(unit.declarations[1], isA<PouDeclaration>());
    });

    test('parse compilation unit with interface and FB', () {
      final unit = parser.parse('''
        INTERFACE ITF_Drive
          METHOD Start : BOOL
          END_METHOD
          METHOD Stop : BOOL
          END_METHOD
        END_INTERFACE

        FUNCTION_BLOCK FB_Motor IMPLEMENTS ITF_Drive
        VAR
          _running : BOOL;
        END_VAR
        END_FUNCTION_BLOCK
      ''');
      expect(unit.declarations, hasLength(2));
      expect(unit.declarations[0], isA<InterfaceDeclaration>());
      expect(unit.declarations[1], isA<PouDeclaration>());
      final fb = unit.declarations[1] as PouDeclaration;
      expect(fb.implementsList, ['ITF_Drive']);
    });

    test('parse empty source returns empty compilation unit', () {
      final unit = parser.parse('');
      expect(unit.declarations, isEmpty);
    });

    test('parse whitespace-only source returns empty compilation unit', () {
      final unit = parser.parse('   \n  \n  ');
      expect(unit.declarations, isEmpty);
    });

    test('parse fixture: common/var_blocks.st', () {
      final source = File(
        'test/compiler/fixtures/common/var_blocks.st',
      ).readAsStringSync();
      final unit = parser.parse(source);
      expect(unit.declarations, isNotEmpty);
      expect(unit.declarations[0], isA<PouDeclaration>());
      final pou = unit.declarations[0] as PouDeclaration;
      expect(pou.name, 'FB_VarTest');
      expect(pou.pouType, PouType.functionBlock);
      // The fixture has 6 var blocks: VAR_INPUT, VAR_OUTPUT, VAR_IN_OUT,
      // VAR, VAR RETAIN, VAR CONSTANT
      expect(pou.varBlocks, hasLength(6));
    });

    test('parse fixture: common/function_example.st', () {
      final source = File(
        'test/compiler/fixtures/common/function_example.st',
      ).readAsStringSync();
      final unit = parser.parse(source);
      expect(unit.declarations, hasLength(1));
      final pou = unit.declarations[0] as PouDeclaration;
      expect(pou.pouType, PouType.function_);
      expect(pou.name, 'FC_Clamp');
      expect(pou.returnType, 'REAL');
      expect(pou.varBlocks, hasLength(1));
      expect(pou.varBlocks[0].declarations, hasLength(3));
    });

    test('parse fixture: schneider/ebool_types.st', () {
      final source = File(
        'test/compiler/fixtures/schneider/ebool_types.st',
      ).readAsStringSync();
      final unit = parser.parse(source);
      expect(unit.declarations, isNotEmpty);
      final pou = unit.declarations[0] as PouDeclaration;
      expect(pou.pouType, PouType.program);
      expect(pou.name, 'SchneiderTypes');
      // Should have EBOOL variables
      final varBlock = pou.varBlocks[0];
      final eboolVars = varBlock.declarations
          .where(
            (d) => d.typeSpec is SimpleType && (d.typeSpec as SimpleType).name == 'EBOOL',
          )
          .toList();
      expect(eboolVars, hasLength(3)); // startButton, stopButton, motorStatus
    });

    test('parse fixture: beckhoff/oop_motor.st', () {
      final source = File(
        'test/compiler/fixtures/beckhoff/oop_motor.st',
      ).readAsStringSync();
      final unit = parser.parse(source);
      expect(unit.declarations, isNotEmpty);
      // Should contain ITF_Drive interface and FB_Motor
      final iface = unit.declarations.whereType<InterfaceDeclaration>();
      expect(iface, isNotEmpty);
      expect(iface.first.name, 'ITF_Drive');

      final fb = unit.declarations.whereType<PouDeclaration>();
      expect(fb, isNotEmpty);
      final motor = fb.first;
      expect(motor.name, 'FB_Motor');
      expect(motor.extendsFrom, 'FB_Base');
      expect(motor.implementsList, contains('ITF_Drive'));
    });

    test('parse fixture: common/type_declarations.st', () {
      final source = File(
        'test/compiler/fixtures/common/type_declarations.st',
      ).readAsStringSync();
      final unit = parser.parse(source);
      expect(unit.declarations, isNotEmpty);
      // Should contain MotorState enum, ST_MotorData struct, AliasType alias
      final types = unit.declarations.whereType<TypeDeclaration>().toList();
      expect(types, hasLength(3));
      expect(types[0].name, 'MotorState');
      expect(types[0].definition, isA<EnumDefinition>());
      expect(types[1].name, 'ST_MotorData');
      expect(types[1].definition, isA<StructDefinition>());
      expect(types[2].name, 'AliasType');
      expect(types[2].definition, isA<AliasDefinition>());
    });
  });

  // ==================================================================
  // 10. Pragmas (Beckhoff)
  // ==================================================================
  group('pragmas', () {
    test('pragma on var block (qualified_only on GVL)', () {
      final unit = parser.parse('''
        {attribute 'qualified_only'}
        VAR_GLOBAL
          GVL_Main : INT;
          GVL_Counter : DINT;
        END_VAR
      ''');
      expect(unit.declarations, isNotEmpty);
      expect(unit.declarations[0], isA<GlobalVarDeclaration>());
      final gvl = unit.declarations[0] as GlobalVarDeclaration;
      expect(gvl.qualifiedOnly, isTrue);
      expect(gvl.varBlocks, hasLength(1));
      expect(gvl.varBlocks[0].declarations, hasLength(2));
    });

    test('pragma with value (pack_mode)', () {
      final unit = parser.parse('''
        {attribute 'pack_mode' := '1'}
        TYPE ST_Packed :
        STRUCT
          field1 : BYTE;
          field2 : DWORD;
          field3 : BOOL;
        END_STRUCT
        END_TYPE
      ''');
      expect(unit.declarations, isNotEmpty);
      // The pack_mode pragma should be preserved; implementation may attach
      // it to the TYPE or to a wrapper. We only verify the struct parsed.
      final typeDecl = unit.declarations.whereType<TypeDeclaration>().first;
      expect(typeDecl.name, 'ST_Packed');
      final structDef = typeDecl.definition as StructDefinition;
      expect(structDef.fields, hasLength(3));
    });

    test('pragma on variable', () {
      final block = parser.parseVarBlock('''
        VAR
          {attribute 'OPC.UA.DA' := '1'}
          exposedValue : REAL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'exposedValue');
      expect(block.declarations[0].pragmas, hasLength(1));
      expect(block.declarations[0].pragmas[0].name, 'OPC.UA.DA');
      expect(block.declarations[0].pragmas[0].value, '1');
    });

    test('pragma without value', () {
      final block = parser.parseVarBlock('''
        VAR
          {attribute 'hide'}
          hiddenVar : INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].pragmas, hasLength(1));
      expect(block.declarations[0].pragmas[0].name, 'hide');
      expect(block.declarations[0].pragmas[0].value, isNull);
    });

    test('multiple pragmas on same variable', () {
      final block = parser.parseVarBlock('''
        VAR
          {attribute 'OPC.UA.DA' := '1'}
          {attribute 'hide'}
          multiPragmaVar : REAL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].pragmas, hasLength(2));
    });

    test('parse fixture: beckhoff/pragmas.st', () {
      final source = File(
        'test/compiler/fixtures/beckhoff/pragmas.st',
      ).readAsStringSync();
      final unit = parser.parse(source);
      expect(unit.declarations, isNotEmpty);
    });
  });

  // ==================================================================
  // 11. Case sensitivity
  // ==================================================================
  group('case insensitivity', () {
    test('keywords are case insensitive', () {
      final block = parser.parseVarBlock('''
        var
          x : int;
        end_var
      ''');
      expect(block.section, VarSection.var_);
      expect(block.declarations, hasLength(1));
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'INT'),
      );
    });

    test('mixed case keywords', () {
      final pou = parser.parsePou('''
        Program Main
        Var
          x : Int;
        End_Var
          x := 1;
        End_Program
      ''');
      expect(pou.pouType, PouType.program);
      expect(pou.name, 'Main');
    });
  });

  // ==================================================================
  // 12. Edge cases and error handling
  // ==================================================================
  group('edge cases', () {
    test('consecutive semicolons in body', () {
      final pou = parser.parsePou('''
        PROGRAM Main
        VAR
          x : INT;
        END_VAR
          x := 1;;;
        END_PROGRAM
      ''');
      expect(pou.pouType, PouType.program);
      expect(pou.name, 'Main');
    });

    test('comments in var block', () {
      final block = parser.parseVarBlock('''
        VAR
          // this is a comment
          x : INT; // inline comment
          (* block comment *)
          y : REAL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(2));
      expect(block.declarations[0].name, 'x');
      expect(block.declarations[1].name, 'y');
    });

    test('DINT, LINT, SINT, USINT, UINT, UDINT, ULINT types', () {
      final block = parser.parseVarBlock('''
        VAR
          a : DINT;
          b : LINT;
          c : SINT;
          d : USINT;
          e : UINT;
          f : UDINT;
          g : ULINT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(7));
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'DINT'),
      );
      expect(
        block.declarations[6].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'ULINT'),
      );
    });

    test('BYTE, WORD, DWORD, LWORD types', () {
      final block = parser.parseVarBlock('''
        VAR
          a : BYTE;
          b : WORD;
          c : DWORD;
          d : LWORD;
        END_VAR
      ''');
      expect(block.declarations, hasLength(4));
    });

    test('LREAL type', () {
      final block = parser.parseVarBlock('''
        VAR
          x : LREAL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'LREAL'),
      );
    });

    test('negative initializer', () {
      final block = parser.parseVarBlock('''
        VAR
          offset : INT := -10;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].initialValue, isNotNull);
      // Could be UnaryExpression(negate, IntLiteral(10)) or IntLiteral(-10)
      // depending on parser design; just verify it is present.
    });

    test('user-defined type as variable type', () {
      final block = parser.parseVarBlock('''
        VAR
          state : MotorState;
          data : ST_MotorData;
        END_VAR
      ''');
      expect(block.declarations, hasLength(2));
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'MotorState'),
      );
      expect(
        block.declarations[1].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'ST_MotorData'),
      );
    });
  });

  // ==================================================================
  // 13. Beckhoff FINAL modifier
  // ==================================================================
  group('FINAL modifier (Beckhoff)', () {
    test('FINAL function block', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FINAL FB_Sealed
        VAR
          x : INT;
        END_VAR
        END_FUNCTION_BLOCK
      ''');
      expect(pou.isFinal, isTrue);
      expect(pou.name, 'FB_Sealed');
    });

    test('FINAL method', () {
      final pou = parser.parsePou('''
        FUNCTION_BLOCK FB_Test

        METHOD FINAL DoWork : BOOL
          DoWork := TRUE;
        END_METHOD

        END_FUNCTION_BLOCK
      ''');
      expect(pou.methods, hasLength(1));
      expect(pou.methods[0].isFinal, isTrue);
    });
  });

  // ==================================================================
  // 14. Action Declarations
  // ==================================================================
  group('ACTION declarations', () {
    test('simple action', () {
      final pou = parser.parsePou('''
        PROGRAM Main
        VAR
          x : INT;
        END_VAR

        ACTION Reset
          x := 0;
        END_ACTION

        END_PROGRAM
      ''');
      expect(pou.actions, hasLength(1));
      expect(pou.actions[0].name, 'Reset');
      expect(pou.actions[0].body, isNotEmpty);
    });
  });

  // ==================================================================
  // 15. Global Variable Declarations (GVL)
  // ==================================================================
  group('GlobalVarDeclaration', () {
    test('standalone VAR_GLOBAL block', () {
      final unit = parser.parse('''
        VAR_GLOBAL
          g_counter : DINT;
          g_flag : BOOL;
        END_VAR
      ''');
      expect(unit.declarations, isNotEmpty);
      expect(unit.declarations[0], isA<GlobalVarDeclaration>());
      final gvl = unit.declarations[0] as GlobalVarDeclaration;
      expect(gvl.varBlocks, hasLength(1));
      expect(gvl.varBlocks[0].section, VarSection.varGlobal);
      expect(gvl.varBlocks[0].declarations, hasLength(2));
    });
  });

  // ==================================================================
  // 16. Struct/FB Initialization in VAR Blocks
  // ==================================================================
  group('struct-style initialization in VAR blocks', () {
    test('single field struct initializer', () {
      final block = parser.parseVarBlock('''
        VAR
          config : ST_Config := (mode := 1);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'config');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'ST_Config'),
      );
      expect(block.declarations[0].initialValue, isNotNull);
      expect(
        block.declarations[0].initialValue,
        isA<AggregateInitializer>(),
      );
      final init =
          block.declarations[0].initialValue! as AggregateInitializer;
      expect(init.fieldInits, hasLength(1));
      expect(init.fieldInits[0].name, 'mode');
      expect(
        init.fieldInits[0].value,
        isA<IntLiteral>().having((l) => l.value, 'value', 1),
      );
    });

    test('multi-field struct initializer with mixed types', () {
      final block = parser.parseVarBlock('''
        VAR
          fbTime : FB_LocalSystemTime := (bEnable := TRUE, dwCycle := 1);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'fbTime');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having(
            (t) => t.name, 'name', 'FB_LocalSystemTime'),
      );
      final init =
          block.declarations[0].initialValue! as AggregateInitializer;
      expect(init.fieldInits, hasLength(2));
      expect(init.fieldInits[0].name, 'bEnable');
      expect(init.fieldInits[0].value, isA<BoolLiteral>());
      expect(init.fieldInits[1].name, 'dwCycle');
      expect(
        init.fieldInits[1].value,
        isA<IntLiteral>().having((l) => l.value, 'value', 1),
      );
    });

    test('struct init coexists with simple init in same block', () {
      final block = parser.parseVarBlock('''
        VAR
          simple : INT := 42;
          config : ST_Config := (mode := 1, active := TRUE);
          other : REAL := 3.14;
        END_VAR
      ''');
      expect(block.declarations, hasLength(3));
      expect(block.declarations[0].name, 'simple');
      expect(
        block.declarations[0].initialValue,
        isA<IntLiteral>().having((l) => l.value, 'value', 42),
      );
      expect(block.declarations[1].name, 'config');
      expect(block.declarations[1].initialValue, isA<AggregateInitializer>());
      expect(block.declarations[2].name, 'other');
      expect(block.declarations[2].initialValue, isA<RealLiteral>());
    });

    test('struct init with string field values', () {
      final block = parser.parseVarBlock('''
        VAR
          cfg : ST_Cfg := (name := 'hello', count := 5);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      final init =
          block.declarations[0].initialValue! as AggregateInitializer;
      expect(init.fieldInits, hasLength(2));
      expect(init.fieldInits[0].name, 'name');
      expect(
        init.fieldInits[0].value,
        isA<StringLiteral>().having((l) => l.value, 'value', 'hello'),
      );
    });

    test('struct init in full POU', () {
      final pou = parser.parsePou('''
        PROGRAM Main
        VAR
          fbTime : FB_LocalSystemTime := (bEnable := TRUE, dwCycle := 1);
          counter : INT := 0;
        END_VAR
          counter := counter + 1;
        END_PROGRAM
      ''');
      expect(pou.varBlocks, hasLength(1));
      expect(pou.varBlocks[0].declarations, hasLength(2));
      expect(
        pou.varBlocks[0].declarations[0].initialValue,
        isA<AggregateInitializer>(),
      );
      expect(pou.body, hasLength(1));
    });
  });

  // ==================================================================
  // 17. FB Constructor Arguments in VAR Declarations
  // ==================================================================
  group('FB constructor arguments in VAR declarations', () {
    test('FB with positional string constructor args', () {
      final block = parser.parseVarBlock('''
        VAR_GLOBAL
          Input1 : FB_EL1008('Switch1', 'Switch2', 'Switch3');
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'Input1');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'FB_EL1008'),
      );
      expect(block.declarations[0].initialValue, isNotNull);
      expect(
        block.declarations[0].initialValue,
        isA<FbConstructorInit>(),
      );
      final init =
          block.declarations[0].initialValue! as FbConstructorInit;
      expect(init.arguments, hasLength(3));
      expect(init.arguments[0].name, isNull); // positional
      expect(
        init.arguments[0].value,
        isA<StringLiteral>().having((l) => l.value, 'value', 'Switch1'),
      );
      expect(
        init.arguments[1].value,
        isA<StringLiteral>().having((l) => l.value, 'value', 'Switch2'),
      );
    });

    test('FB with no constructor args (just type)', () {
      final block = parser.parseVarBlock('''
        VAR
          Timer1 : TON;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'Timer1');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'TON'),
      );
      expect(block.declarations[0].initialValue, isNull);
    });

    test('FB with numeric constructor args', () {
      final block = parser.parseVarBlock('''
        VAR_GLOBAL
          Motor1 : FB_Motor(100, 200);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'Motor1');
      final init =
          block.declarations[0].initialValue! as FbConstructorInit;
      expect(init.arguments, hasLength(2));
      expect(
        init.arguments[0].value,
        isA<IntLiteral>().having((l) => l.value, 'value', 100),
      );
    });

    test('FB constructor with named args', () {
      final block = parser.parseVarBlock('''
        VAR
          fb1 : FB_Axis(name := 'X_Axis', speed := 100);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      final init =
          block.declarations[0].initialValue! as FbConstructorInit;
      expect(init.arguments, hasLength(2));
      expect(init.arguments[0].name, 'name');
      expect(
        init.arguments[0].value,
        isA<StringLiteral>().having((l) => l.value, 'value', 'X_Axis'),
      );
      expect(init.arguments[1].name, 'speed');
    });

    test('FB constructor mixed with regular decls in same block', () {
      final block = parser.parseVarBlock('''
        VAR_GLOBAL
          Input1 : FB_EL1008('Switch1', 'Switch2');
          Timer1 : TON;
          Counter : INT := 0;
        END_VAR
      ''');
      expect(block.declarations, hasLength(3));
      expect(block.declarations[0].initialValue, isA<FbConstructorInit>());
      expect(block.declarations[1].initialValue, isNull);
      expect(
        block.declarations[2].initialValue,
        isA<IntLiteral>().having((l) => l.value, 'value', 0),
      );
    });
  });

  // ==================================================================
  // 18. Semicolons after END_IF / END_CASE (tolerance)
  // ==================================================================
  group('semicolons after END_IF / END_CASE', () {
    test('END_IF with semicolon in standalone statement', () {
      final stmts = parser.parseStatements('''
        IF x THEN
          y := 1;
        END_IF;
      ''');
      expect(stmts, hasLength(1));
      expect(stmts[0], isA<IfStatement>());
    });

    test('END_CASE with semicolon', () {
      final stmts = parser.parseStatements('''
        CASE mode OF
          1: x := 10;
          2: x := 20;
        END_CASE;
      ''');
      expect(stmts, hasLength(1));
      expect(stmts[0], isA<CaseStatement>());
    });

    test('END_IF with semicolon inside POU body', () {
      final pou = parser.parsePou('''
        PROGRAM Main
        VAR
          x : INT;
          y : INT;
        END_VAR
          IF x > 0 THEN
            y := 1;
          END_IF;
          y := y + 1;
        END_PROGRAM
      ''');
      expect(pou.body, hasLength(2));
      expect(pou.body[0], isA<IfStatement>());
      expect(pou.body[1], isA<AssignmentStatement>());
    });

    test('nested END_IF with semicolons', () {
      final stmts = parser.parseStatements('''
        IF a THEN
          IF b THEN
            c := 1;
          END_IF;
        END_IF;
      ''');
      expect(stmts, hasLength(1));
      final outer = stmts[0] as IfStatement;
      expect(outer.thenBody, hasLength(1));
      expect(outer.thenBody[0], isA<IfStatement>());
    });

    test('END_FOR with semicolon', () {
      final stmts = parser.parseStatements('''
        FOR i := 1 TO 10 DO
          x := x + i;
        END_FOR;
      ''');
      expect(stmts, hasLength(1));
      expect(stmts[0], isA<ForStatement>());
    });

    test('END_WHILE with semicolon', () {
      final stmts = parser.parseStatements('''
        WHILE x > 0 DO
          x := x - 1;
        END_WHILE;
      ''');
      expect(stmts, hasLength(1));
      expect(stmts[0], isA<WhileStatement>());
    });
  });

  // ==================================================================
  // Inline enum types in VAR declarations (Issue #1)
  // ==================================================================
  group('inline enum types in VAR', () {
    test('simple inline enum without values', () {
      final block = parser.parseVarBlock('''
        VAR
          state : (IDLE, RUNNING, DONE);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'state');
      expect(block.declarations[0].typeSpec, isA<InlineEnumType>());
      final enumType = block.declarations[0].typeSpec as InlineEnumType;
      expect(enumType.values, hasLength(3));
      expect(enumType.values[0].name, 'IDLE');
      expect(enumType.values[1].name, 'RUNNING');
      expect(enumType.values[2].name, 'DONE');
      expect(enumType.baseType, isNull);
    });

    test('inline enum with initializer values', () {
      final block = parser.parseVarBlock('''
        VAR
          state : (A := 0, B := 1, C := 2);
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'state');
      expect(block.declarations[0].typeSpec, isA<InlineEnumType>());
      final enumType = block.declarations[0].typeSpec as InlineEnumType;
      expect(enumType.values, hasLength(3));
      expect(enumType.values[0].name, 'A');
      expect(enumType.values[0].value,
          isA<IntLiteral>().having((l) => l.value, 'value', 0));
      expect(enumType.values[1].name, 'B');
      expect(enumType.values[1].value,
          isA<IntLiteral>().having((l) => l.value, 'value', 1));
      expect(enumType.values[2].name, 'C');
      expect(enumType.values[2].value,
          isA<IntLiteral>().having((l) => l.value, 'value', 2));
      expect(enumType.baseType, isNull);
    });

    test('inline enum with base type', () {
      final block = parser.parseVarBlock('''
        VAR
          state : (A := 0, B := 1) UINT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'state');
      expect(block.declarations[0].typeSpec, isA<InlineEnumType>());
      final enumType = block.declarations[0].typeSpec as InlineEnumType;
      expect(enumType.values, hasLength(2));
      expect(enumType.values[0].name, 'A');
      expect(enumType.values[1].name, 'B');
      expect(enumType.baseType, 'UINT');
    });

    test('inline enum with INT base type', () {
      final block = parser.parseVarBlock('''
        VAR
          mode : (OFF := 0, MANUAL := 1, AUTO := 2) INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      final enumType = block.declarations[0].typeSpec as InlineEnumType;
      expect(enumType.values, hasLength(3));
      expect(enumType.baseType, 'INT');
    });
  });

  // ==================================================================
  // Pragmas before TYPE declarations (Issue #2)
  // ==================================================================
  group('pragmas before TYPE declarations', () {
    test('single pragma before TYPE enum', () {
      final unit = parser.parse('''
        {attribute 'qualified_only'}
        TYPE ET_State :
        (
          NORMAL := 0,
          FORCED_LOW := 1
        );
        END_TYPE
      ''');
      expect(unit.declarations, hasLength(1));
      expect(unit.declarations[0], isA<TypeDeclaration>());
      final td = unit.declarations[0] as TypeDeclaration;
      expect(td.name, 'ET_State');
      expect(td.definition, isA<EnumDefinition>());
    });

    test('multiple pragmas before TYPE struct', () {
      final unit = parser.parse('''
        {attribute 'qualified_only'}
        {attribute 'pack_mode' := '1'}
        TYPE ST_Test :
        STRUCT
          x : BOOL;
          y : INT;
        END_STRUCT
        END_TYPE
      ''');
      expect(unit.declarations, hasLength(1));
      expect(unit.declarations[0], isA<TypeDeclaration>());
      final td = unit.declarations[0] as TypeDeclaration;
      expect(td.name, 'ST_Test');
      expect(td.definition, isA<StructDefinition>());
    });

    test('pragma before TYPE in compilation unit with POU', () {
      final unit = parser.parse('''
        {attribute 'qualified_only'}
        TYPE ET_Mode :
        (
          OFF := 0,
          ON := 1
        );
        END_TYPE

        PROGRAM Main
        VAR
          x : INT;
        END_VAR
          x := 1;
        END_PROGRAM
      ''');
      expect(unit.declarations, hasLength(2));
      expect(unit.declarations[0], isA<TypeDeclaration>());
      expect(unit.declarations[1], isA<PouDeclaration>());
    });
  });

  // ==================================================================
  // Pragmas inside struct fields (Issue #3)
  // ==================================================================
  group('pragmas inside struct fields', () {
    test('pragma before struct field', () {
      final td = parser.parseTypeDeclaration('''
        TYPE ST_Test :
        STRUCT
          {attribute 'OPC.UA.DA' := '1'}
          x : BOOL;
          y : INT;
        END_STRUCT
        END_TYPE
      ''');
      expect(td.name, 'ST_Test');
      expect(td.definition, isA<StructDefinition>());
      final structDef = td.definition as StructDefinition;
      expect(structDef.fields, hasLength(2));
      expect(structDef.fields[0].name, 'x');
      expect(structDef.fields[1].name, 'y');
    });

    test('multiple pragmas on multiple fields', () {
      final td = parser.parseTypeDeclaration('''
        TYPE ST_Data :
        STRUCT
          {attribute 'OPC.UA.DA' := '1'}
          x : BOOL;
          {attribute 'monitoring' := 'variable'}
          y : INT;
          {attribute 'OPC.UA.DA' := '1'}
          {attribute 'monitoring' := 'variable'}
          z : REAL;
        END_STRUCT
        END_TYPE
      ''');
      expect(td.name, 'ST_Data');
      final structDef = td.definition as StructDefinition;
      expect(structDef.fields, hasLength(3));
      expect(structDef.fields[0].name, 'x');
      expect(structDef.fields[1].name, 'y');
      expect(structDef.fields[2].name, 'z');
    });

    test('struct with pragmas and initializers', () {
      final td = parser.parseTypeDeclaration('''
        TYPE ST_Config :
        STRUCT
          {attribute 'OPC.UA.DA' := '1'}
          enabled : BOOL := TRUE;
          {attribute 'monitoring' := 'variable'}
          timeout : INT := 1000;
        END_STRUCT
        END_TYPE
      ''');
      expect(td.name, 'ST_Config');
      final structDef = td.definition as StructDefinition;
      expect(structDef.fields, hasLength(2));
      expect(structDef.fields[0].name, 'enabled');
      expect(structDef.fields[0].initialValue, isNotNull);
      expect(structDef.fields[1].name, 'timeout');
      expect(structDef.fields[1].initialValue, isNotNull);
    });
  });

  // ==================================================================
  // TYPE enum with base type (Issue #4)
  // ==================================================================
  group('TYPE enum with base type', () {
    test('enum with UINT base type', () {
      final td = parser.parseTypeDeclaration('''
        TYPE ET_State :
        (
          NORMAL := 0,
          FORCED_LOW := 1
        ) UINT;
        END_TYPE
      ''');
      expect(td.name, 'ET_State');
      expect(td.definition, isA<EnumDefinition>());
      final enumDef = td.definition as EnumDefinition;
      expect(enumDef.values, hasLength(2));
      expect(enumDef.values[0].name, 'NORMAL');
      expect(enumDef.values[1].name, 'FORCED_LOW');
      expect(enumDef.baseType, 'UINT');
    });

    test('enum with INT base type', () {
      final td = parser.parseTypeDeclaration('''
        TYPE ET_Mode :
        (
          OFF := 0,
          MANUAL := 1,
          AUTO := 2
        ) INT;
        END_TYPE
      ''');
      expect(td.name, 'ET_Mode');
      final enumDef = td.definition as EnumDefinition;
      expect(enumDef.values, hasLength(3));
      expect(enumDef.baseType, 'INT');
    });

    test('enum without base type still works', () {
      final td = parser.parseTypeDeclaration('''
        TYPE ET_Simple :
        (
          A := 0,
          B := 1
        );
        END_TYPE
      ''');
      expect(td.name, 'ET_Simple');
      final enumDef = td.definition as EnumDefinition;
      expect(enumDef.values, hasLength(2));
      expect(enumDef.baseType, isNull);
    });

    test('enum with DINT base type and pragma', () {
      final td = parser.parseTypeDeclaration('''
        {attribute 'qualified_only'}
        TYPE ET_ErrorCode :
        (
          OK := 0,
          WARN := 1,
          ERROR := 2,
          CRITICAL := 3
        ) DINT;
        END_TYPE
      ''');
      expect(td.name, 'ET_ErrorCode');
      final enumDef = td.definition as EnumDefinition;
      expect(enumDef.values, hasLength(4));
      expect(enumDef.baseType, 'DINT');
    });
  });

  // ==================================================================
  // AT %I* / %Q* wildcard I/O addressing (Issue #5)
  // ==================================================================
  group('AT wildcard I/O addressing', () {
    test('AT %I* wildcard input', () {
      final block = parser.parseVarBlock('''
        VAR
          x AT %I* : BOOL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'x');
      expect(block.declarations[0].atAddress, '%I*');
      expect(
        block.declarations[0].typeSpec,
        isA<SimpleType>().having((t) => t.name, 'name', 'BOOL'),
      );
    });

    test('AT %Q* wildcard output', () {
      final block = parser.parseVarBlock('''
        VAR
          y AT %Q* : BOOL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'y');
      expect(block.declarations[0].atAddress, '%Q*');
    });

    test('AT %IW* wildcard word input', () {
      final block = parser.parseVarBlock('''
        VAR
          z AT %IW* : INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'z');
      expect(block.declarations[0].atAddress, '%IW*');
    });

    test('AT %QW* wildcard word output', () {
      final block = parser.parseVarBlock('''
        VAR
          w AT %QW* : INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'w');
      expect(block.declarations[0].atAddress, '%QW*');
    });

    test('AT %MW100 concrete address still works', () {
      final block = parser.parseVarBlock('''
        VAR
          v AT %MW100 : INT;
        END_VAR
      ''');
      expect(block.declarations, hasLength(1));
      expect(block.declarations[0].name, 'v');
      expect(block.declarations[0].atAddress, '%MW100');
    });

    test('mixed wildcard and concrete AT addresses', () {
      final block = parser.parseVarBlock('''
        VAR
          a AT %I* : BOOL;
          b AT %MW100 : INT;
          c AT %Q* : BOOL;
        END_VAR
      ''');
      expect(block.declarations, hasLength(3));
      expect(block.declarations[0].atAddress, '%I*');
      expect(block.declarations[1].atAddress, '%MW100');
      expect(block.declarations[2].atAddress, '%Q*');
    });
  });
}

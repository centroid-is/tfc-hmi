import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/compiler.dart';

void main() {
  late StParser parser;

  setUp(() {
    parser = StParser();
  });

  group('error recovery', () {
    test('recovers from unknown syntax between valid POUs', () {
      final result = parser.parseResilient('''
        PROGRAM Good1
        VAR x : INT; END_VAR
          x := 1;
        END_PROGRAM

        GOBBLEDYGOOK UNKNOWN STUFF HERE;

        PROGRAM Good2
        VAR y : INT; END_VAR
          y := 2;
        END_PROGRAM
      ''');
      expect(
        result.unit.declarations.whereType<PouDeclaration>(),
        hasLength(2),
      );
      expect(result.errors, hasLength(1));
      expect(result.errors.first.skippedText, contains('GOBBLEDYGOOK'));
    });

    test('handles completely unparseable input', () {
      final result = parser.parseResilient('!!!@@@ NOT VALID ST CODE');
      // Everything should be error nodes or empty
      expect(
        result.unit.declarations,
        everyElement(isA<ErrorNode>()),
      );
      expect(result.hasErrors, isTrue);
    });

    test('valid input produces no errors', () {
      final result = parser.parseResilient('''
        PROGRAM Main
        VAR x : INT; END_VAR
          x := 42;
        END_PROGRAM
      ''');
      expect(result.isSuccess, isTrue);
      expect(result.errors, isEmpty);
    });

    test('recovers from bad variable declaration', () {
      final result = parser.parseResilient('''
        PROGRAM Main
        VAR
          x : INT;
          @@@ BAD VAR @@@;
          y : REAL;
        END_VAR
          x := 42;
        END_PROGRAM
      ''');
      // Should still parse x, y (bad var skipped), and the body
      final pou = result.unit.declarations.first as PouDeclaration;
      // x and y should be parsed; @@@ BAD VAR @@@ is silently skipped
      // by the resilient var declaration parser
      expect(pou.varBlocks.first.declarations.length, greaterThanOrEqualTo(1));
      // The POU itself should parse successfully (error is inside var block)
      expect(result.unit.declarations.whereType<PouDeclaration>(), hasLength(1));
    });

    test('recovers from bad statement in body', () {
      final result = parser.parseResilient('''
        PROGRAM Main
        VAR x : INT; END_VAR
          x := 1;
          BANANA PHONE;
          x := 2;
        END_PROGRAM
      ''');
      // The POU should still be parsed (body parsing is best-effort)
      final pous = result.unit.declarations.whereType<PouDeclaration>();
      expect(pous, hasLength(1));
      final pou = pous.first;
      // At least some statements should be recovered
      expect(pou.body.length, greaterThanOrEqualTo(1));
    });

    test('multiple errors collected', () {
      final result = parser.parseResilient('''
        BAD STUFF;
        PROGRAM Main END_PROGRAM
        MORE BAD STUFF;
        FUNCTION_BLOCK FB1 END_FUNCTION_BLOCK
      ''');
      expect(result.errors.length, greaterThanOrEqualTo(2));
      expect(
        result.unit.declarations.whereType<PouDeclaration>(),
        hasLength(2),
      );
    });

    test('error includes line number', () {
      final result = parser.parseResilient(
        'line1\nline2\nBAD SYNTAX\nPROGRAM X END_PROGRAM',
      );
      expect(result.errors, isNotEmpty);
      expect(result.errors.first.line, isNotNull);
    });

    test('vendor-specific syntax gracefully skipped', () {
      // Simulate unknown Schneider SECTION keyword
      final result = parser.parseResilient('''
        SECTION MySection
          SOMETHING VENDOR SPECIFIC
        END_SECTION

        PROGRAM Main
        VAR x : INT; END_VAR
          x := 1;
        END_PROGRAM
      ''');
      expect(
        result.unit.declarations.whereType<PouDeclaration>(),
        hasLength(1),
      );
      expect(result.hasErrors, isTrue);
    });

    test('empty input is valid', () {
      final result = parser.parseResilient('');
      expect(result.isSuccess, isTrue);
      expect(result.unit.declarations, isEmpty);
    });

    test('whitespace-only input is valid', () {
      final result = parser.parseResilient('   \n\n  ');
      expect(result.isSuccess, isTrue);
    });

    test('POU names are correctly extracted', () {
      final result = parser.parseResilient('''
        PROGRAM MyProg END_PROGRAM
        FUNCTION_BLOCK MyFB END_FUNCTION_BLOCK
      ''');
      expect(result.isSuccess, isTrue);
      final pous = result.unit.declarations.whereType<PouDeclaration>().toList();
      expect(pous, hasLength(2));
      expect(pous[0].name, 'MyProg');
      expect(pous[0].pouType, PouType.program);
      expect(pous[1].name, 'MyFB');
      expect(pous[1].pouType, PouType.functionBlock);
    });

    test('VAR blocks are parsed inside POUs', () {
      final result = parser.parseResilient('''
        PROGRAM Test
        VAR
          count : INT;
          speed : REAL;
        END_VAR
        END_PROGRAM
      ''');
      expect(result.isSuccess, isTrue);
      final pou = result.unit.declarations.first as PouDeclaration;
      expect(pou.varBlocks, hasLength(1));
      expect(pou.varBlocks.first.declarations, hasLength(2));
      expect(pou.varBlocks.first.declarations[0].name, 'count');
      expect(pou.varBlocks.first.declarations[1].name, 'speed');
    });

    test('body statements are parsed inside POUs', () {
      final result = parser.parseResilient('''
        PROGRAM Test
        VAR x : INT; END_VAR
          x := 42;
        END_PROGRAM
      ''');
      expect(result.isSuccess, isTrue);
      final pou = result.unit.declarations.first as PouDeclaration;
      expect(pou.body, hasLength(1));
      expect(pou.body.first, isA<AssignmentStatement>());
    });

    test('multiple VAR sections in one POU', () {
      final result = parser.parseResilient('''
        PROGRAM Test
        VAR_INPUT
          enable : BOOL;
        END_VAR
        VAR_OUTPUT
          done : BOOL;
        END_VAR
        VAR
          count : INT;
        END_VAR
        END_PROGRAM
      ''');
      expect(result.isSuccess, isTrue);
      final pou = result.unit.declarations.first as PouDeclaration;
      expect(pou.varBlocks, hasLength(3));
      expect(pou.varBlocks[0].section, VarSection.varInput);
      expect(pou.varBlocks[1].section, VarSection.varOutput);
      expect(pou.varBlocks[2].section, VarSection.var_);
    });

    test('error node contains the skipped text', () {
      final result = parser.parseResilient('''
        JUNK HERE
        PROGRAM X END_PROGRAM
      ''');
      expect(result.hasErrors, isTrue);
      final errorNodes = result.unit.declarations.whereType<ErrorNode>();
      expect(errorNodes, hasLength(1));
      expect(errorNodes.first.skippedText, contains('JUNK'));
    });

    test('ParseResult toString on errors is informative', () {
      final error = ParseError(
        message: 'test error',
        position: 10,
        line: 3,
        column: 5,
      );
      expect(error.toString(), contains('line 3'));
      expect(error.toString(), contains('test error'));
    });

    test('ParseError without line info uses position', () {
      final error = ParseError(
        message: 'test error',
        position: 42,
      );
      expect(error.toString(), contains('position 42'));
    });

    test('FUNCTION POU type is recognized', () {
      final result = parser.parseResilient('''
        FUNCTION Add END_FUNCTION
      ''');
      expect(result.isSuccess, isTrue);
      final pou = result.unit.declarations.first as PouDeclaration;
      expect(pou.pouType, PouType.function_);
      expect(pou.name, 'Add');
    });
  });
}

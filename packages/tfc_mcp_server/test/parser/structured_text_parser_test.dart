import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/parser/structured_text_parser.dart';

import '../helpers/sample_twincat_files.dart';

void main() {
  group('parseVariables', () {
    test('parses VAR block with simple declarations', () {
      const declaration = '''
VAR
    bFlag : BOOL;
    nCount : INT;
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(2));
      expect(vars[0].name, equals('bFlag'));
      expect(vars[0].type, equals('BOOL'));
      expect(vars[0].section, equals('VAR'));
      expect(vars[1].name, equals('nCount'));
      expect(vars[1].type, equals('INT'));
      expect(vars[1].section, equals('VAR'));
    });

    test('parses VAR_INPUT, VAR_OUTPUT, VAR_IN_OUT sections separately', () {
      const declaration = '''
VAR_INPUT
    nInput : INT;
END_VAR
VAR_OUTPUT
    bOutput : BOOL;
END_VAR
VAR_IN_OUT
    fInOut : REAL;
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(3));
      expect(vars[0].section, equals('VAR_INPUT'));
      expect(vars[1].section, equals('VAR_OUTPUT'));
      expect(vars[2].section, equals('VAR_IN_OUT'));
    });

    test('parses VAR_GLOBAL section (for GVLs)', () {
      const declaration = '''
VAR_GLOBAL
    pump3_speed : REAL;
    pump3_running : BOOL;
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(2));
      expect(vars[0].section, equals('VAR_GLOBAL'));
      expect(vars[0].name, equals('pump3_speed'));
      expect(vars[0].type, equals('REAL'));
    });

    test('handles AT directives', () {
      const declaration = '''
VAR
    byByte AT %MB0 : ARRAY [0..1027] OF BYTE;
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(1));
      expect(vars[0].name, equals('byByte'));
      expect(vars[0].type, equals('ARRAY [0..1027] OF BYTE'));
    });

    test('handles initial values', () {
      const declaration = '''
VAR
    bStartTest : BOOL := FALSE;
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(1));
      expect(vars[0].name, equals('bStartTest'));
      expect(vars[0].type, equals('BOOL'));
    });

    test('handles multiple VAR blocks in same declaration', () {
      const declaration = '''
VAR
    a : INT;
END_VAR
VAR_INPUT
    b : BOOL;
END_VAR
VAR
    c : REAL;
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(3));
      expect(vars[0].section, equals('VAR'));
      expect(vars[1].section, equals('VAR_INPUT'));
      expect(vars[2].section, equals('VAR'));
    });

    test('extracts inline line comments', () {
      const declaration = '''
VAR
    nSpeed : INT; // Motor speed in RPM
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(1));
      expect(vars[0].comment, equals('Motor speed in RPM'));
    });

    test('extracts inline block comments', () {
      const declaration = '''
VAR
    bActive : BOOL; (* Currently running *)
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(1));
      expect(vars[0].comment, equals('Currently running'));
    });

    test('returns empty list for text with no VAR blocks', () {
      const declaration = 'PROGRAM Main\nEND_PROGRAM';
      final vars = parseVariables(declaration);
      expect(vars, isEmpty);
    });

    test('case-insensitive keyword matching', () {
      const declaration = '''
var
    x : int;
end_var
Var_Input
    y : Bool;
End_Var
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(2));
      expect(vars[0].section, equals('VAR'));
      expect(vars[1].section, equals('VAR_INPUT'));
    });

    test('handles VAR_TEMP and VAR_STAT sections', () {
      const declaration = '''
VAR_TEMP
    tTemp : INT;
END_VAR
VAR_STAT
    sStat : BOOL;
END_VAR
''';
      final vars = parseVariables(declaration);

      expect(vars, hasLength(2));
      expect(vars[0].section, equals('VAR_TEMP'));
      expect(vars[0].name, equals('tTemp'));
      expect(vars[1].section, equals('VAR_STAT'));
      expect(vars[1].name, equals('sStat'));
    });
  });

  group('parseStFile', () {
    test('parses raw .st file with PROGRAM header', () {
      final result = parseStFile(sampleStFile, 'programs/main.st');

      expect(result, isNotNull);
      expect(result!.name, equals('MainProgram'));
      expect(result.type, equals('Program'));
      expect(result.filePath, equals('programs/main.st'));
    });

    test('parses raw .st file with FUNCTION_BLOCK header', () {
      const fbContent = '''FUNCTION_BLOCK FB_Motor
VAR
    bRunning : BOOL;
END_VAR
bRunning := TRUE;
END_FUNCTION_BLOCK
''';
      final result = parseStFile(fbContent, 'blocks/motor.st');

      expect(result, isNotNull);
      expect(result!.name, equals('FB_Motor'));
      expect(result.type, equals('FunctionBlock'));
    });

    test('extracts variables from raw .st VAR block', () {
      final result = parseStFile(sampleStFile, 'test.st');

      expect(result, isNotNull);
      expect(result!.variables, hasLength(3));
      final varNames = result.variables.map((v) => v.name).toSet();
      expect(varNames, equals({'bRunning', 'nSpeed', 'fTemperature'}));
    });

    test('extracts implementation between END_VAR and END_PROGRAM', () {
      final result = parseStFile(sampleStFile, 'test.st');

      expect(result, isNotNull);
      expect(result!.implementation, isNotNull);
      expect(result.implementation, contains('nSpeed := nSpeed + 1'));
      expect(result.implementation, contains('IF bRunning THEN'));
    });

    test('returns null for empty or unparseable content', () {
      expect(parseStFile('', 'test.st'), isNull);
      expect(parseStFile('   ', 'test.st'), isNull);
      expect(parseStFile('random text', 'test.st'), isNull);
    });
  });
}

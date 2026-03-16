import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/parser/twincat_xml_parser.dart';

import '../helpers/sample_twincat_files.dart';

void main() {
  group('parseTcPou', () {
    test('parses sampleTcPouXml with correct name, type, declaration, and implementation', () {
      final result = parseTcPou(sampleTcPouXml, 'POUs/FB_TestBlock.TcPOU');

      expect(result, isNotNull);
      expect(result!.name, equals('FB_TestBlock'));
      expect(result.type, equals('FunctionBlock'));
      expect(result.declaration, contains('FUNCTION_BLOCK'));
      expect(result.declaration, contains('bStartTest'));
      expect(result.implementation, contains('nCounter'));
      expect(result.filePath, equals('POUs/FB_TestBlock.TcPOU'));
    });

    test('extracts variables from Declaration CDATA', () {
      final result = parseTcPou(sampleTcPouXml, 'test.TcPOU');

      expect(result, isNotNull);
      final varNames = result!.variables.map((v) => v.name).toList();
      expect(varNames, contains('bStartTest'));
      expect(varNames, contains('nCounter'));
      expect(varNames, contains('nInput'));
      expect(varNames, contains('bResult'));

      final bStart = result.variables.firstWhere((v) => v.name == 'bStartTest');
      expect(bStart.type, equals('BOOL'));
      expect(bStart.section, equals('VAR'));

      final nInput = result.variables.firstWhere((v) => v.name == 'nInput');
      expect(nInput.section, equals('VAR_INPUT'));
    });

    test('extracts children: Method, Action, Property', () {
      final result = parseTcPou(sampleTcPouWithMethodsXml, 'test.TcPOU');

      expect(result, isNotNull);
      expect(result!.children, hasLength(3));

      final method = result.children.firstWhere((c) => c.childType == 'Method');
      expect(method.name, equals('DoSomething'));
      expect(method.declaration, contains('METHOD'));
      expect(method.implementation, contains('param1 > 0'));

      final action = result.children.firstWhere((c) => c.childType == 'Action');
      expect(action.name, equals('Reset'));
      expect(action.implementation, contains('bStartTest := FALSE'));

      final property = result.children.firstWhere((c) => c.childType == 'Property');
      expect(property.name, equals('IsRunning'));
      expect(property.declaration, contains('PROPERTY'));
    });

    test('preserves both comment styles in fullSource', () {
      final result = parseTcPou(sampleTcPouWithCommentsXml, 'test.TcPOU');

      expect(result, isNotNull);
      expect(result!.fullSource, contains('(* This block controls the motor speed.'));
      expect(result.fullSource, contains('// Check if motor is active'));
      expect(result.fullSource, contains('// Ramp up by 10 RPM'));
    });

    test('returns null for XML with no POU element', () {
      final result = parseTcPou('<Root><Other/></Root>', 'test.TcPOU');
      expect(result, isNull);
    });

    test('detects FUNCTION_BLOCK type', () {
      final result = parseTcPou(sampleTcPouXml, 'test.TcPOU');
      expect(result!.type, equals('FunctionBlock'));
    });

    test('detects PROGRAM type', () {
      final result = parseTcPou(sampleTcPouWithMethodsXml, 'test.TcPOU');
      expect(result!.type, equals('Program'));
    });

    test('detects FUNCTION type', () {
      const functionXml = '''<?xml version="1.0" encoding="utf-8"?>
<TcPlcObject Version="1.1.0.1" ProductVersion="3.1.4024.5">
  <POU Name="FC_Add" Id="{12345678-1234-1234-1234-123456789abc}" SpecialFunc="None">
    <Declaration><![CDATA[FUNCTION FC_Add : INT
VAR_INPUT
    a : INT;
    b : INT;
END_VAR]]></Declaration>
    <Implementation>
      <ST><![CDATA[FC_Add := a + b;]]></ST>
    </Implementation>
  </POU>
</TcPlcObject>''';

      final result = parseTcPou(functionXml, 'test.TcPOU');
      expect(result!.type, equals('Function'));
    });
  });

  group('parseTcGvl', () {
    test('parses sampleTcGvlXml with correct name, type, and declaration', () {
      final result = parseTcGvl(sampleTcGvlXml, 'GVLs/GVL_Main.TcGVL');

      expect(result, isNotNull);
      expect(result!.name, equals('GVL_Main'));
      expect(result.type, equals('GVL'));
      expect(result.implementation, isNull);
      expect(result.filePath, equals('GVLs/GVL_Main.TcGVL'));
    });

    test('extracts 3 variables: pump3_speed, pump3_running, tank_level', () {
      final result = parseTcGvl(sampleTcGvlXml, 'test.TcGVL');

      expect(result, isNotNull);
      expect(result!.variables, hasLength(3));

      final varNames = result.variables.map((v) => v.name).toSet();
      expect(varNames, equals({'pump3_speed', 'pump3_running', 'tank_level'}));

      final pumpSpeed = result.variables.firstWhere((v) => v.name == 'pump3_speed');
      expect(pumpSpeed.type, equals('REAL'));
      expect(pumpSpeed.section, equals('VAR_GLOBAL'));
    });

    test('returns null for XML with no GVL element', () {
      final result = parseTcGvl('<Root><Other/></Root>', 'test.TcGVL');
      expect(result, isNull);
    });
  });
}

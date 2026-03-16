import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/parser/schneider_xml_parser.dart';

import '../helpers/sample_schneider_files.dart';

void main() {
  group('detectSchneiderFormat', () {
    test('detects Control Expert FBSource format', () {
      expect(
        detectSchneiderFormat(sampleControlExpertFB),
        equals(SchneiderFormat.controlExpert),
      );
    });

    test('detects Control Expert STSource format', () {
      expect(
        detectSchneiderFormat(sampleControlExpertST),
        equals(SchneiderFormat.controlExpert),
      );
    });

    test('detects PLCopen XML format by namespace', () {
      expect(
        detectSchneiderFormat(samplePlcopenFB),
        equals(SchneiderFormat.plcopenXml),
      );
    });

    test('detects PLCopen XML format for global vars', () {
      expect(
        detectSchneiderFormat(samplePlcopenGlobalVars),
        equals(SchneiderFormat.plcopenXml),
      );
    });

    test('returns null for TwinCAT XML', () {
      const twincatXml = '''<?xml version="1.0" encoding="utf-8"?>
<TcPlcObject Version="1.1.0.1" ProductVersion="3.1.4024.5">
  <POU Name="FB_Test" SpecialFunc="None">
    <Declaration><![CDATA[FUNCTION_BLOCK FB_Test]]></Declaration>
  </POU>
</TcPlcObject>''';
      expect(detectSchneiderFormat(twincatXml), isNull);
    });

    test('returns null for arbitrary XML', () {
      expect(detectSchneiderFormat('<root><child/></root>'), isNull);
    });
  });

  group('parseSchneiderXml - Control Expert', () {
    test('parses FBSource with correct name and type', () {
      final blocks = parseSchneiderXml(
          sampleControlExpertFB, 'exports/FB_PumpControl.xef');

      expect(blocks, hasLength(1));
      final block = blocks.first;
      expect(block.name, equals('FB_PumpControl'));
      expect(block.type, equals('FunctionBlock'));
      expect(block.filePath, equals('exports/FB_PumpControl.xef'));
    });

    test('extracts variables from Control Expert FBSource', () {
      final blocks =
          parseSchneiderXml(sampleControlExpertFB, 'test.xef');

      expect(blocks, hasLength(1));
      final block = blocks.first;

      // Should have variables from XML declarations and/or ST parsing
      expect(block.variables, isNotEmpty);

      final varNames = block.variables.map((v) => v.name).toSet();
      expect(varNames, contains('bEnable'));
      expect(varNames, contains('rSetpoint'));
      expect(varNames, contains('rActualSpeed'));
      expect(varNames, contains('bRunning'));
      expect(varNames, contains('nErrorCode'));
    });

    test('extracts variable sections correctly', () {
      final blocks =
          parseSchneiderXml(sampleControlExpertFB, 'test.xef');
      final block = blocks.first;

      final bEnable =
          block.variables.firstWhere((v) => v.name == 'bEnable');
      expect(bEnable.section, equals('VAR_INPUT'));
      expect(bEnable.type, equals('BOOL'));

      final rActualSpeed =
          block.variables.firstWhere((v) => v.name == 'rActualSpeed');
      expect(rActualSpeed.section, equals('VAR_OUTPUT'));
      expect(rActualSpeed.type, equals('REAL'));
    });

    test('extracts declaration and implementation from FBSource', () {
      final blocks =
          parseSchneiderXml(sampleControlExpertFB, 'test.xef');
      final block = blocks.first;

      expect(block.declaration, contains('FUNCTION_BLOCK'));
      expect(block.declaration, contains('END_VAR'));
      expect(block.implementation, contains('bEnable'));
      expect(block.implementation, contains('rActualSpeed'));
    });

    test('parses STSource as Program', () {
      final blocks =
          parseSchneiderXml(sampleControlExpertST, 'test.xef');

      expect(blocks, hasLength(1));
      final block = blocks.first;
      expect(block.name, equals('MainTask'));
      expect(block.type, equals('Program'));
    });

    test('parses STSource variables', () {
      final blocks =
          parseSchneiderXml(sampleControlExpertST, 'test.xef');
      final block = blocks.first;

      final varNames = block.variables.map((v) => v.name).toSet();
      expect(varNames, contains('bAutoMode'));
      expect(varNames, contains('rTemperature'));
      expect(varNames, contains('nCycleCount'));
    });

    test('parses multiple blocks from single export file', () {
      final blocks = parseSchneiderXml(
          sampleControlExpertMultiBlock, 'test.xef');

      expect(blocks, hasLength(2));

      final fbMotor = blocks.firstWhere((b) => b.name == 'FB_Motor');
      expect(fbMotor.type, equals('FunctionBlock'));
      expect(fbMotor.variables.map((v) => v.name), contains('bStart'));

      final stLogic = blocks.firstWhere((b) => b.name == 'ST_Logic');
      expect(stLogic.type, equals('Program'));
      expect(stLogic.variables.map((v) => v.name), contains('fbMotor1'));
    });
  });

  group('parseSchneiderXml - PLCopen XML', () {
    test('parses PLCopen function block with correct name and type', () {
      final blocks =
          parseSchneiderXml(samplePlcopenFB, 'exports/project.xml');

      expect(blocks, hasLength(1));
      final block = blocks.first;
      expect(block.name, equals('FB_ValveControl'));
      expect(block.type, equals('FunctionBlock'));
    });

    test('extracts PLCopen input, output, and local variables', () {
      final blocks =
          parseSchneiderXml(samplePlcopenFB, 'test.xml');
      final block = blocks.first;

      expect(block.variables, hasLength(6)); // 2 input + 2 output + 2 local

      final bOpen =
          block.variables.firstWhere((v) => v.name == 'bOpen');
      expect(bOpen.section, equals('VAR_INPUT'));
      expect(bOpen.type, equals('BOOL'));
      expect(bOpen.comment, equals('Command to open valve'));

      final bIsOpen =
          block.variables.firstWhere((v) => v.name == 'bIsOpen');
      expect(bIsOpen.section, equals('VAR_OUTPUT'));

      final nState =
          block.variables.firstWhere((v) => v.name == 'nState');
      expect(nState.section, equals('VAR'));
      expect(nState.type, equals('INT'));
    });

    test('extracts PLCopen ST implementation', () {
      final blocks =
          parseSchneiderXml(samplePlcopenFB, 'test.xml');
      final block = blocks.first;

      expect(block.implementation, isNotNull);
      expect(block.implementation, contains('bOpen'));
      expect(block.implementation, contains('nState := 1'));
    });

    test('extracts PLCopen action children', () {
      final blocks =
          parseSchneiderXml(samplePlcopenFB, 'test.xml');
      final block = blocks.first;

      expect(block.children, hasLength(1));
      final action = block.children.first;
      expect(action.name, equals('Reset'));
      expect(action.childType, equals('Action'));
      expect(action.implementation, contains('nState := 0'));
    });

    test('parses PLCopen program type', () {
      final blocks =
          parseSchneiderXml(samplePlcopenProgram, 'test.xml');

      expect(blocks, hasLength(1));
      final block = blocks.first;
      expect(block.name, equals('PLC_PRG'));
      expect(block.type, equals('Program'));
    });

    test('handles PLCopen string type with length', () {
      final blocks =
          parseSchneiderXml(samplePlcopenProgram, 'test.xml');
      final block = blocks.first;

      final sMessage =
          block.variables.firstWhere((v) => v.name == 'sMessage');
      expect(sMessage.type, equals('STRING(80)'));
    });

    test('parses PLCopen global variables as GVL', () {
      final blocks =
          parseSchneiderXml(samplePlcopenGlobalVars, 'test.xml');

      // Should have at least the GVL block
      final gvlBlocks = blocks.where((b) => b.type == 'GVL').toList();
      expect(gvlBlocks, hasLength(1));

      final gvl = gvlBlocks.first;
      expect(gvl.name, equals('GVL_Process'));
      expect(gvl.variables, hasLength(3));

      final rTankLevel =
          gvl.variables.firstWhere((v) => v.name == 'rTankLevel');
      expect(rTankLevel.type, equals('REAL'));
      expect(rTankLevel.section, equals('VAR_GLOBAL'));
      expect(rTankLevel.comment, equals('Tank level in percent'));
    });

    test('handles PLCopen derived types', () {
      final blocks =
          parseSchneiderXml(samplePlcopenComplexTypes, 'test.xml');

      expect(blocks, hasLength(1));
      final block = blocks.first;

      final stConfig =
          block.variables.firstWhere((v) => v.name == 'stConfig');
      expect(stConfig.type, equals('ST_LoggerConfig'));
    });

    test('handles PLCopen array types', () {
      final blocks =
          parseSchneiderXml(samplePlcopenComplexTypes, 'test.xml');
      final block = blocks.first;

      final aValues =
          block.variables.firstWhere((v) => v.name == 'aValues');
      expect(aValues.type, equals('ARRAY[0..9] OF REAL'));
    });
  });

  group('parseSchneiderXml - edge cases', () {
    test('returns empty list for non-Schneider XML', () {
      final blocks = parseSchneiderXml(
          '<TcPlcObject><POU Name="Test"/></TcPlcObject>', 'test.xml');
      expect(blocks, isEmpty);
    });

    test('returns empty list for invalid XML', () {
      final blocks =
          parseSchneiderXml('not xml at all &&&', 'test.xml');
      expect(blocks, isEmpty);
    });

    test('returns empty list for empty string', () {
      final blocks = parseSchneiderXml('', 'test.xml');
      expect(blocks, isEmpty);
    });

    test('fullSource contains both declaration and implementation', () {
      final blocks =
          parseSchneiderXml(sampleControlExpertFB, 'test.xef');
      final block = blocks.first;

      expect(block.fullSource, contains('FUNCTION_BLOCK'));
      expect(block.fullSource, contains('rActualSpeed'));
    });

    test('builds declaration text for PLCopen blocks', () {
      final blocks =
          parseSchneiderXml(samplePlcopenFB, 'test.xml');
      final block = blocks.first;

      expect(block.declaration, contains('VAR_INPUT'));
      expect(block.declaration, contains('bOpen'));
      expect(block.declaration, contains('END_VAR'));
    });
  });
}

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/services/plc_code_service.dart';
import 'package:tfc_mcp_server/src/services/plc_context_service.dart';

import '../helpers/mock_plc_code_index.dart';

// ---------------------------------------------------------------------------
// Stub KeyMappingLookup for E2E tests.
// ---------------------------------------------------------------------------
class _StubKeyMappingLookup implements KeyMappingLookup {
  _StubKeyMappingLookup(this._mappings);

  final List<Map<String, dynamic>> _mappings;

  @override
  Future<List<Map<String, dynamic>>> listKeyMappings({
    String? filter,
    int limit = 50,
  }) async {
    if (filter == null || filter.isEmpty) {
      return _mappings.take(limit).toList();
    }
    final q = filter.toLowerCase();
    return _mappings
        .where((m) => (m['key'] as String).toLowerCase().contains(q))
        .take(limit)
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Real PLC code fixtures (minimal but realistic ST code).
// ---------------------------------------------------------------------------

const _gvlBlock = ParsedCodeBlock(
  name: 'GVL',
  type: 'GVL',
  declaration: '''VAR_GLOBAL
  pump3_speed : REAL;
  pump3_running : BOOL;
  startCmd : BOOL;
  alarm : BOOL;
END_VAR''',
  implementation: null,
  fullSource: '''VAR_GLOBAL
  pump3_speed : REAL;
  pump3_running : BOOL;
  startCmd : BOOL;
  alarm : BOOL;
END_VAR''',
  filePath: 'GVLs/GVL.TcGVL',
  variables: [
    ParsedVariable(name: 'pump3_speed', type: 'REAL', section: 'VAR_GLOBAL'),
    ParsedVariable(
        name: 'pump3_running', type: 'BOOL', section: 'VAR_GLOBAL'),
    ParsedVariable(name: 'startCmd', type: 'BOOL', section: 'VAR_GLOBAL'),
    ParsedVariable(name: 'alarm', type: 'BOOL', section: 'VAR_GLOBAL'),
  ],
  children: [],
);

const _fbPumpBlock = ParsedCodeBlock(
  name: 'FB_PumpControl',
  type: 'FunctionBlock',
  declaration: '''FUNCTION_BLOCK FB_PumpControl
VAR_INPUT
  enable : BOOL;
END_VAR
VAR_OUTPUT
  speed : REAL;
  running : BOOL;
END_VAR
VAR
  actualRpm : REAL;
END_VAR''',
  implementation: '''speed := actualRpm * 0.1;
running := enable AND (actualRpm > 0.0);''',
  fullSource: '''FUNCTION_BLOCK FB_PumpControl
VAR_INPUT
  enable : BOOL;
END_VAR
VAR_OUTPUT
  speed : REAL;
  running : BOOL;
END_VAR
VAR
  actualRpm : REAL;
END_VAR
speed := actualRpm * 0.1;
running := enable AND (actualRpm > 0.0);''',
  filePath: 'POUs/FB_PumpControl.TcPOU',
  variables: [
    ParsedVariable(name: 'enable', type: 'BOOL', section: 'VAR_INPUT'),
    ParsedVariable(name: 'speed', type: 'REAL', section: 'VAR_OUTPUT'),
    ParsedVariable(name: 'running', type: 'BOOL', section: 'VAR_OUTPUT'),
    ParsedVariable(name: 'actualRpm', type: 'REAL', section: 'VAR'),
  ],
  children: [],
);

const _mainBlock = ParsedCodeBlock(
  name: 'MAIN',
  type: 'Program',
  declaration: '''PROGRAM MAIN
VAR
  pump3 : FB_PumpControl;
END_VAR''',
  implementation: '''pump3(enable := GVL.startCmd);
GVL.pump3_speed := pump3.speed;
GVL.pump3_running := pump3.running;
IF GVL.pump3_speed > 1500.0 THEN
  GVL.alarm := TRUE;
END_IF''',
  fullSource: '''PROGRAM MAIN
VAR
  pump3 : FB_PumpControl;
END_VAR
pump3(enable := GVL.startCmd);
GVL.pump3_speed := pump3.speed;
GVL.pump3_running := pump3.running;
IF GVL.pump3_speed > 1500.0 THEN
  GVL.alarm := TRUE;
END_IF''',
  filePath: 'POUs/MAIN.TcPOU',
  variables: [
    ParsedVariable(name: 'pump3', type: 'FB_PumpControl', section: 'VAR'),
  ],
  children: [],
);

void main() {
  late MockPlcCodeIndex index;
  late _StubKeyMappingLookup keyMapping;
  late PlcCodeService plcCodeService;
  late PlcContextService contextService;

  setUp(() async {
    index = MockPlcCodeIndex();

    // Index all three blocks as one PLC asset
    await index.indexAsset(
      'twincat_project_1',
      [_gvlBlock, _fbPumpBlock, _mainBlock],
      serverAlias: 'TwinCAT_PLC1',
    );

    // Set up key mappings: two OPC-UA keys, one Modbus key
    keyMapping = _StubKeyMappingLookup([
      {
        'key': 'pump3.speed',
        'protocol': 'opcua',
        'identifier': 'ns=4;s=GVL.pump3_speed',
        'server_alias': 'TwinCAT_PLC1',
      },
      {
        'key': 'pump3.running',
        'protocol': 'opcua',
        'identifier': 'ns=4;s=GVL.pump3_running',
        'server_alias': 'TwinCAT_PLC1',
      },
      {
        'key': 'pump3.power',
        'protocol': 'modbus',
        'register_type': 'holding',
        'address': 100,
      },
    ]);

    plcCodeService = PlcCodeService(index, keyMapping);
    contextService = PlcContextService(plcCodeService, keyMapping);
  });

  // ====================================================================
  // Full E2E: key -> mapping -> variable -> call graph -> formatted output
  // ====================================================================
  group('E2E: full resolution chain', () {
    test('resolves pump3.speed through complete chain', () async {
      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      expect(result.unresolvedKeys, isEmpty);

      final resolved = result.resolvedKeys.first;
      expect(resolved.hmiKey, 'pump3.speed');
      expect(resolved.serverAlias, 'TwinCAT_PLC1');
      expect(resolved.plcVariablePath, 'GVL.pump3_speed');
      expect(resolved.declaringBlock, 'GVL');
      expect(resolved.declaringBlockType, 'GVL');
      expect(resolved.variableType, 'REAL');

      // GVL.pump3_speed is written by MAIN (GVL.pump3_speed := pump3.speed)
      expect(resolved.writers, isNotEmpty);
      expect(
        resolved.writers.any((w) => w.blockName == 'MAIN'),
        isTrue,
        reason: 'MAIN should be a writer of GVL.pump3_speed',
      );

      // GVL.pump3_speed is read by MAIN (IF GVL.pump3_speed > 1500.0)
      expect(resolved.readers, isNotEmpty);
      expect(
        resolved.readers.any((r) => r.blockName == 'MAIN'),
        isTrue,
        reason: 'MAIN should read GVL.pump3_speed in the IF condition',
      );
    });

    test('resolves multiple keys at once', () async {
      final result = await contextService.resolveKeys([
        'pump3.speed',
        'pump3.running',
        'pump3.power',
      ]);

      // Two resolved (OPC-UA), one unresolved (Modbus)
      expect(result.resolvedKeys, hasLength(2));
      expect(result.unresolvedKeys, hasLength(1));

      final speedKey =
          result.resolvedKeys.firstWhere((r) => r.hmiKey == 'pump3.speed');
      final runningKey =
          result.resolvedKeys.firstWhere((r) => r.hmiKey == 'pump3.running');

      expect(speedKey.plcVariablePath, 'GVL.pump3_speed');
      expect(speedKey.variableType, 'REAL');

      expect(runningKey.plcVariablePath, 'GVL.pump3_running');
      expect(runningKey.variableType, 'BOOL');

      // Both should be on same PLC
      expect(speedKey.serverAlias, runningKey.serverAlias);

      // pump3.power is Modbus
      expect(result.unresolvedKeys.first.hmiKey, 'pump3.power');
      expect(result.unresolvedKeys.first.protocol, 'modbus');
    });

    test('produces complete formatted output', () async {
      final result = await contextService.resolveKeys([
        'pump3.speed',
        'pump3.running',
        'pump3.power',
      ]);

      final output = contextService.formatForLlm(result);

      // Should have a PLC context section for TwinCAT_PLC1
      expect(output, contains('[PLC CONTEXT'));
      expect(output, contains('TwinCAT_PLC1'));

      // Should list both resolved keys
      expect(output, contains('pump3.speed'));
      expect(output, contains('pump3.running'));
      expect(output, contains('GVL.pump3_speed'));
      expect(output, contains('GVL.pump3_running'));
      expect(output, contains('REAL'));
      expect(output, contains('BOOL'));

      // Should have NON-PLC KEYS section
      expect(output, contains('[NON-PLC KEYS]'));
      expect(output, contains('pump3.power'));
      expect(output, contains('Modbus'));

      // The output should be non-empty and meaningful
      expect(output.length, greaterThan(50));
    });

    test('pump3_running has writer from MAIN', () async {
      final result = await contextService.resolveKeys(['pump3.running']);

      expect(result.resolvedKeys, hasLength(1));
      final resolved = result.resolvedKeys.first;

      // GVL.pump3_running is written by MAIN
      expect(resolved.writers, isNotEmpty);
      expect(
        resolved.writers.any((w) => w.blockName == 'MAIN'),
        isTrue,
        reason: 'MAIN writes GVL.pump3_running',
      );
    });
  });

  // ====================================================================
  // E2E: call graph integration
  // ====================================================================
  group('E2E: call graph integration', () {
    test('call graph correctly identifies readers and writers', () async {
      // Build the call graph directly to verify the plumbing
      final callGraph =
          await plcCodeService.buildCallGraph('twincat_project_1');

      // GVL.pump3_speed should have references from MAIN
      final speedRefs = callGraph.getReferences('GVL.pump3_speed');
      expect(speedRefs, isNotEmpty,
          reason: 'GVL.pump3_speed should have references');

      // Check that context resolution uses the call graph correctly
      final context = callGraph.getVariableContext('GVL.pump3_speed');
      expect(context, isNotNull,
          reason: 'GVL.pump3_speed should be in variable index');
      expect(context!['declaringBlock'], 'GVL');
      expect(context['variableType'], 'REAL');
    });

    test('FB instance pump3 is recognized', () async {
      final callGraph =
          await plcCodeService.buildCallGraph('twincat_project_1');

      final instances = callGraph.getInstances('FB_PumpControl');
      expect(instances, isNotEmpty);
      expect(instances.first.instanceName, 'pump3');
      expect(instances.first.declaringBlock, 'MAIN');
    });
  });

  // ====================================================================
  // E2E: formatted output quality
  // ====================================================================
  group('E2E: output quality', () {
    test('formatted output is structured and readable', () async {
      final result = await contextService.resolveKeys([
        'pump3.speed',
        'pump3.running',
        'pump3.power',
      ]);

      final output = contextService.formatForLlm(result);

      // Verify structure: sections, indentation, key-value pairs
      final lines = output.split('\n');

      // Should start with a section header
      expect(lines.first, startsWith('['));

      // Should not have excessive blank lines (no triple newlines)
      expect(output, isNot(contains('\n\n\n\n')));
    });

    test('key-only resolution (no call graph data) still produces output',
        () async {
      // Create a simple index with just a GVL (no implementation code)
      final simpleIndex = MockPlcCodeIndex();
      await simpleIndex.indexAsset('simple', [
        const ParsedCodeBlock(
          name: 'GVL_Simple',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  temp : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  temp : REAL;\nEND_VAR',
          filePath: 'GVL_Simple.TcGVL',
          variables: [
            ParsedVariable(
                name: 'temp', type: 'REAL', section: 'VAR_GLOBAL'),
          ],
          children: [],
        ),
      ], serverAlias: 'PLC_Simple');

      final simpleKeyMapping = _StubKeyMappingLookup([
        {
          'key': 'temperature',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Simple.temp',
          'server_alias': 'PLC_Simple',
        },
      ]);

      final simplePlcService = PlcCodeService(simpleIndex, simpleKeyMapping);
      final simpleCtxService =
          PlcContextService(simplePlcService, simpleKeyMapping);

      final result = await simpleCtxService.resolveKeys(['temperature']);

      expect(result.resolvedKeys, hasLength(1));
      final resolved = result.resolvedKeys.first;
      expect(resolved.declaringBlock, 'GVL_Simple');
      expect(resolved.variableType, 'REAL');
      // No readers/writers since GVL has no implementation
      expect(resolved.readers, isEmpty);
      expect(resolved.writers, isEmpty);

      final output = simpleCtxService.formatForLlm(result);
      expect(output, contains('GVL_Simple.temp'));
      expect(output, contains('REAL'));
    });
  });
}

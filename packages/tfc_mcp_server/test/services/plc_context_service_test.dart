import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/call_graph_builder.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/interfaces/server_alias_provider.dart';
import 'package:tfc_mcp_server/src/services/plc_code_service.dart';
import 'package:tfc_mcp_server/src/services/plc_context_service.dart';

import '../helpers/mock_plc_code_index.dart';

// ---------------------------------------------------------------------------
// Stub KeyMappingLookup that returns canned key mappings.
// ---------------------------------------------------------------------------
class _StubKeyMappingLookup implements KeyMappingLookup {
  _StubKeyMappingLookup([this._mappings = const []]);

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

void main() {
  // ====================================================================
  // 1. resolveKeys — single key, single PLC
  // ====================================================================
  group('resolveKeys - single key', () {
    test('resolves a single OPC-UA key to PLC code context', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          'server_alias': 'TwinCAT_PLC1',
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\nEND_VAR',
          implementation: 'GVL_Main.pump3_speed := 100.0;',
          fullSource:
              'PROGRAM MAIN\nVAR\nEND_VAR\nGVL_Main.pump3_speed := 100.0;',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ], serverAlias: 'TwinCAT_PLC1');

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      expect(result.unresolvedKeys, isEmpty);

      final resolved = result.resolvedKeys.first;
      expect(resolved.hmiKey, 'pump3.speed');
      expect(resolved.serverAlias, 'TwinCAT_PLC1');
      expect(resolved.plcVariablePath, 'GVL_Main.pump3_speed');
      expect(resolved.declaringBlock, 'GVL_Main');
      expect(resolved.declaringBlockType, 'GVL');
      expect(resolved.variableType, 'REAL');

      // Declaration line should be present.
      expect(resolved.declarationLine, isNotNull);
      expect(resolved.declarationLine, contains('pump3_speed'));
    });
  });

  // ====================================================================
  // 2. resolveKeys — multiple keys, same PLC
  // ====================================================================
  group('resolveKeys - multiple keys same PLC', () {
    test('groups multiple keys under one server alias', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          'server_alias': 'TwinCAT_PLC1',
        },
        {
          'key': 'pump3.running',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_running',
          'server_alias': 'TwinCAT_PLC1',
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration:
              'VAR_GLOBAL\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR',
          implementation: null,
          fullSource:
              'VAR_GLOBAL\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
            ParsedVariable(
              name: 'pump3_running',
              type: 'BOOL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
      ], serverAlias: 'TwinCAT_PLC1');

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys([
        'pump3.speed',
        'pump3.running',
      ]);

      expect(result.resolvedKeys, hasLength(2));
      expect(result.unresolvedKeys, isEmpty);

      // Both should have the same server alias
      expect(
        result.resolvedKeys.every((r) => r.serverAlias == 'TwinCAT_PLC1'),
        isTrue,
      );
    });
  });

  // ====================================================================
  // 3. resolveKeys — multiple keys, different PLCs
  // ====================================================================
  group('resolveKeys - multiple keys different PLCs', () {
    test('groups keys by server alias', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL.pump3_speed',
          'server_alias': 'PLC_A',
        },
        {
          'key': 'tank.level',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL.tank_level',
          'server_alias': 'PLC_B',
        },
      ]);

      await index.indexAsset('plcA', [
        const ParsedCodeBlock(
          name: 'GVL',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
      ], serverAlias: 'PLC_A');

      await index.indexAsset('plcB', [
        const ParsedCodeBlock(
          name: 'GVL',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  tank_level : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  tank_level : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL.TcGVL',
          variables: [
            ParsedVariable(
              name: 'tank_level',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
      ], serverAlias: 'PLC_B');

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys([
        'pump3.speed',
        'tank.level',
      ]);

      expect(result.resolvedKeys, hasLength(2));

      final plcAKeys =
          result.resolvedKeys.where((r) => r.serverAlias == 'PLC_A');
      final plcBKeys =
          result.resolvedKeys.where((r) => r.serverAlias == 'PLC_B');

      expect(plcAKeys, hasLength(1));
      expect(plcBKeys, hasLength(1));
      expect(plcAKeys.first.hmiKey, 'pump3.speed');
      expect(plcBKeys.first.hmiKey, 'tank.level');
    });
  });

  // ====================================================================
  // 4. resolveKeys — Modbus key goes to unresolvedKeys
  // ====================================================================
  group('resolveKeys - unresolved keys', () {
    test('Modbus key goes to unresolvedKeys', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.power',
          'protocol': 'modbus',
          'register_type': 'holding',
          'address': 100,
        },
      ]);

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['pump3.power']);

      expect(result.resolvedKeys, isEmpty);
      expect(result.unresolvedKeys, hasLength(1));
      expect(result.unresolvedKeys.first.hmiKey, 'pump3.power');
      expect(result.unresolvedKeys.first.protocol, 'modbus');
    });

    test('key with no mapping goes to unresolvedKeys', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([]); // No mappings

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['nonexistent.key']);

      expect(result.resolvedKeys, isEmpty);
      expect(result.unresolvedKeys, hasLength(1));
      expect(result.unresolvedKeys.first.hmiKey, 'nonexistent.key');
      expect(result.unresolvedKeys.first.reason, contains('no'));
    });

    test('numeric OPC-UA identifier (i=) goes to unresolvedKeys', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'numeric.tag',
          'protocol': 'opcua',
          'identifier': 'ns=2;i=847',
          'server_alias': 'PLC1',
        },
      ]);

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['numeric.tag']);

      expect(result.resolvedKeys, isEmpty);
      expect(result.unresolvedKeys, hasLength(1));
      expect(result.unresolvedKeys.first.hmiKey, 'numeric.tag');
      expect(result.unresolvedKeys.first.protocol, 'opcua');
      expect(result.unresolvedKeys.first.reason, contains('numeric'));
    });

    test('M2400 key goes to unresolvedKeys', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'meter.energy',
          'protocol': 'm2400',
          'record_type': 'energy',
        },
      ]);

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['meter.energy']);

      expect(result.resolvedKeys, isEmpty);
      expect(result.unresolvedKeys, hasLength(1));
      expect(result.unresolvedKeys.first.protocol, 'm2400');
    });
  });

  // ====================================================================
  // 5. resolveKeys — empty keys
  // ====================================================================
  group('resolveKeys - empty keys', () {
    test('returns empty result for empty keys list', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup();

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys([]);

      expect(result.resolvedKeys, isEmpty);
      expect(result.unresolvedKeys, isEmpty);
    });
  });

  // ====================================================================
  // 6. resolveKeys — FB instance member resolution
  // ====================================================================
  group('resolveKeys - FB instance member', () {
    test('resolves FB instance member with type info', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          'server_alias': 'PLC1',
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration:
              'VAR_GLOBAL\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR',
          implementation: null,
          fullSource:
              'VAR_GLOBAL\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
            ParsedVariable(
              name: 'pump3_running',
              type: 'BOOL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'FB_PumpControl',
          type: 'FunctionBlock',
          declaration:
              'FUNCTION_BLOCK FB_PumpControl\nVAR_INPUT\n  enable : BOOL;\nEND_VAR\nVAR_OUTPUT\n  speed : REAL;\n  running : BOOL;\nEND_VAR',
          implementation:
              'speed := actualRpm * 0.1;\nrunning := enable AND (actualRpm > 0.0);',
          fullSource:
              'FUNCTION_BLOCK FB_PumpControl\nVAR_INPUT\n  enable : BOOL;\nEND_VAR\nVAR_OUTPUT\n  speed : REAL;\n  running : BOOL;\nEND_VAR\nspeed := actualRpm * 0.1;\nrunning := enable AND (actualRpm > 0.0);',
          filePath: 'POUs/FB_PumpControl.st',
          variables: [
            ParsedVariable(
              name: 'enable',
              type: 'BOOL',
              section: 'VAR_INPUT',
            ),
            ParsedVariable(
              name: 'speed',
              type: 'REAL',
              section: 'VAR_OUTPUT',
            ),
            ParsedVariable(
              name: 'running',
              type: 'BOOL',
              section: 'VAR_OUTPUT',
            ),
            ParsedVariable(
              name: 'actualRpm',
              type: 'REAL',
              section: 'VAR',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration:
              'PROGRAM MAIN\nVAR\n  pump3 : FB_PumpControl;\nEND_VAR',
          implementation:
              'pump3(enable := TRUE);\nGVL_Main.pump3_speed := pump3.speed;\nGVL_Main.pump3_running := pump3.running;',
          fullSource:
              'PROGRAM MAIN\nVAR\n  pump3 : FB_PumpControl;\nEND_VAR\npump3(enable := TRUE);\nGVL_Main.pump3_speed := pump3.speed;\nGVL_Main.pump3_running := pump3.running;',
          filePath: 'POUs/MAIN.st',
          variables: [
            ParsedVariable(
              name: 'pump3',
              type: 'FB_PumpControl',
              section: 'VAR',
            ),
          ],
          children: [],
        ),
      ], serverAlias: 'PLC1');

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      final resolved = result.resolvedKeys.first;
      expect(resolved.hmiKey, 'pump3.speed');
      expect(resolved.plcVariablePath, 'GVL_Main.pump3_speed');
      expect(resolved.declaringBlock, 'GVL_Main');
      expect(resolved.variableType, 'REAL');

      // Should have writers (MAIN writes GVL_Main.pump3_speed)
      expect(resolved.writers, isNotEmpty);

      // Writers should have line numbers and source lines.
      final mainWriter = resolved.writers
          .where((w) => w.blockName == 'MAIN')
          .firstOrNull;
      if (mainWriter != null) {
        expect(mainWriter.lineNumber, isNotNull);
        expect(mainWriter.sourceLine, isNotNull);
        expect(mainWriter.sourceLine, contains('pump3_speed'));
      }
    });
  });

  // ====================================================================
  // 7. resolveKeys — mixed resolved and unresolved
  // ====================================================================
  group('resolveKeys - mixed', () {
    test('handles mix of resolved and unresolved keys', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL.pump3_speed',
          'server_alias': 'PLC1',
        },
        {
          'key': 'pump3.power',
          'protocol': 'modbus',
          'register_type': 'holding',
          'address': 100,
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
      ], serverAlias: 'PLC1');

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys([
        'pump3.speed',
        'pump3.power',
        'nonexistent.key',
      ]);

      expect(result.resolvedKeys, hasLength(1));
      expect(result.resolvedKeys.first.hmiKey, 'pump3.speed');

      // pump3.power (modbus) + nonexistent.key (no mapping)
      expect(result.unresolvedKeys, hasLength(2));
      final modbusKey =
          result.unresolvedKeys.firstWhere((u) => u.hmiKey == 'pump3.power');
      expect(modbusKey.protocol, 'modbus');
    });
  });

  // ====================================================================
  // 7b. resolveKeys — enriched references with line numbers
  // ====================================================================
  group('resolveKeys - enriched references', () {
    test('writers have line numbers and source lines', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          'server_alias': 'PLC1',
        },
      ]);

      const gvlDecl = 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR';
      const mainDecl = 'PROGRAM MAIN\nVAR\nEND_VAR';
      const mainImpl = 'GVL_Main.pump3_speed := 100.0;';

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: gvlDecl,
          implementation: null,
          fullSource: gvlDecl,
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: mainDecl,
          implementation: mainImpl,
          fullSource: '$mainDecl\n$mainImpl',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ], serverAlias: 'PLC1');

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      final resolved = result.resolvedKeys.first;

      // MAIN writes GVL_Main.pump3_speed
      expect(resolved.writers, isNotEmpty);
      final writer = resolved.writers.first;
      expect(writer.lineNumber, isNotNull);
      expect(writer.sourceLine, 'GVL_Main.pump3_speed := 100.0;');

      // Declaration line should be found.
      expect(resolved.declarationLine, isNotNull);
      expect(resolved.declarationLine, contains('pump3_speed : REAL'));
    });

    test('readers have line numbers and source lines', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL.pump3_speed',
          'server_alias': 'PLC1',
        },
      ]);

      const gvlDecl = 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR';
      const mainDecl = 'PROGRAM MAIN\nVAR\nEND_VAR';
      const mainImpl =
          'GVL.pump3_speed := 100.0;\nIF GVL.pump3_speed > 1500.0 THEN\n  alarm := TRUE;\nEND_IF';

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL',
          type: 'GVL',
          declaration: gvlDecl,
          implementation: null,
          fullSource: gvlDecl,
          filePath: 'GVLs/GVL.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: mainDecl,
          implementation: mainImpl,
          fullSource: '$mainDecl\n$mainImpl',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ], serverAlias: 'PLC1');

      final plcCodeService = PlcCodeService(index, keyMapping);
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      final resolved = result.resolvedKeys.first;

      // MAIN reads GVL.pump3_speed in the IF condition
      expect(resolved.readers, isNotEmpty);
      final reader = resolved.readers.first;
      expect(reader.lineNumber, isNotNull);
      expect(reader.sourceLine, isNotNull);
      expect(reader.sourceLine, contains('pump3_speed'));
    });
  });

  // ====================================================================
  // 8. formatForLlm — output format tests
  // ====================================================================
  group('formatForLlm', () {
    test('produces compact call graph output', () {
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'pump3.speed',
            serverAlias: 'TwinCAT_PLC1',
            plcVariablePath: 'GVL_Main.pump3_speed',
            declaringBlock: 'GVL_Main',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            declarationLine: 'pump3_speed : REAL;',
            readers: [
              const VariableReference(
                variablePath: 'GVL_Main.pump3_speed',
                kind: ReferenceKind.read,
                blockName: 'FB_AlarmHandler',
                blockType: 'FunctionBlock',
                lineNumber: 12,
                sourceLine: 'IF GVL_Main.pump3_speed > 1500.0 THEN',
              ),
            ],
            writers: [
              const VariableReference(
                variablePath: 'GVL_Main.pump3_speed',
                kind: ReferenceKind.write,
                blockName: 'MAIN',
                blockType: 'Program',
                lineNumber: 45,
                sourceLine: 'GVL_Main.pump3_speed := pump3.speed;',
              ),
            ],
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      // Section header
      expect(output, contains('[PLC CONTEXT'));
      expect(output, contains('TwinCAT_PLC1'));

      // Variable header with declaration
      expect(output, contains('pump3.speed'));
      expect(output, contains('GVL_Main.pump3_speed'));
      expect(output, contains('REAL'));
      expect(output, contains('declared @ GVL_Main'));
      expect(output, contains('pump3_speed : REAL;'));

      // Compact writer edge
      expect(output, contains('MAIN:45 writes'));
      expect(output, contains('GVL_Main.pump3_speed := pump3.speed;'));

      // Compact reader edge
      expect(output, contains('FB_AlarmHandler:12 reads'));
      expect(output, contains('IF GVL_Main.pump3_speed > 1500.0 THEN'));

      // Footer hint
      expect(output, contains('get_plc_code_block'));

      // Should NOT contain old-style sections
      expect(output, isNot(contains('Source Code:')));
      expect(output, isNot(contains('--- GVL_Main ---')));
      expect(output, isNot(contains('Declaring block:')));
      expect(output, isNot(contains('Writers:')));
      expect(output, isNot(contains('Readers:')));
    });

    test('groups by server alias', () {
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'pump3.speed',
            serverAlias: 'PLC_A',
            plcVariablePath: 'GVL.pump3_speed',
            declaringBlock: 'GVL',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            readers: [],
            writers: [],
          ),
          ResolvedKey(
            hmiKey: 'tank.level',
            serverAlias: 'PLC_B',
            plcVariablePath: 'GVL.tank_level',
            declaringBlock: 'GVL',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            readers: [],
            writers: [],
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      expect(output, contains('PLC_A'));
      expect(output, contains('PLC_B'));
    });

    test('includes NON-PLC KEYS section for unresolved keys', () {
      final context = PlcContext(
        resolvedKeys: [],
        unresolvedKeys: [
          const UnresolvedKey(
            hmiKey: 'pump3.power_kwh',
            protocol: 'modbus',
            reason: 'Modbus device (no PLC code available)',
          ),
          const UnresolvedKey(
            hmiKey: 'meter.energy',
            protocol: 'm2400',
            reason: 'M2400 device (no PLC code available)',
          ),
        ],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      expect(output, contains('[NON-PLC KEYS]'));
      expect(output, contains('pump3.power_kwh'));
      expect(output, contains('Modbus'));
      expect(output, contains('meter.energy'));
      expect(output, contains('M2400'));
    });

    test('omits NON-PLC KEYS section when all keys resolved', () {
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'pump3.speed',
            serverAlias: 'PLC1',
            plcVariablePath: 'GVL.speed',
            declaringBlock: 'GVL',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            readers: [],
            writers: [],
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      expect(output, isNot(contains('[NON-PLC KEYS]')));
    });

    test('omits PLC CONTEXT section when all keys unresolved', () {
      final context = PlcContext(
        resolvedKeys: [],
        unresolvedKeys: [
          const UnresolvedKey(
            hmiKey: 'pump3.power',
            protocol: 'modbus',
            reason: 'Modbus device',
          ),
        ],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      expect(output, isNot(contains('[PLC CONTEXT')));
      expect(output, contains('[NON-PLC KEYS]'));
    });

    test('includes FB instance info when present', () {
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'pump3.speed',
            serverAlias: 'PLC1',
            plcVariablePath: 'GVL_Main.pump3_speed',
            declaringBlock: 'GVL_Main',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            readers: [],
            writers: [],
            fbInstance: const FbInstanceInfo(
              instanceName: 'pump3',
              fbTypeName: 'FB_PumpControl',
              memberName: 'speed',
              memberSection: 'VAR_OUTPUT',
            ),
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      expect(output, contains('FB_PumpControl'));
      expect(output, contains('pump3'));
      expect(output, contains('.speed'));
      expect(output, contains('VAR_OUTPUT'));
    });

    test('handles references without line numbers gracefully', () {
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'valve.open',
            serverAlias: 'PLC1',
            plcVariablePath: 'GVL.valve_open',
            declaringBlock: 'GVL',
            declaringBlockType: 'GVL',
            variableType: 'BOOL',
            readers: [],
            writers: [
              const VariableReference(
                variablePath: 'GVL.valve_open',
                kind: ReferenceKind.write,
                blockName: 'FB_ValveControl',
                blockType: 'FunctionBlock',
                // No lineNumber or sourceLine
              ),
            ],
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      // Should still show the edge, just without line number/source
      expect(output, contains('FB_ValveControl writes'));
      // Should NOT have `:` prefix when no line number
      expect(output, isNot(contains('FB_ValveControl: writes')));
    });

    test('omits edges section when no readers or writers', () {
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'pump3.speed',
            serverAlias: 'PLC1',
            plcVariablePath: 'GVL.speed',
            declaringBlock: 'GVL',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            readers: [],
            writers: [],
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      // Should still have the variable header
      expect(output, contains('pump3.speed'));
      expect(output, contains('GVL.speed'));
      // But no edge lines
      expect(output, isNot(contains('writes')));
      expect(output, isNot(contains('reads')));
    });

    test('returns empty string for empty context', () {
      final context = PlcContext(
        resolvedKeys: [],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      expect(output, isEmpty);
    });

    test('uses "unknown" header when server alias is literally unknown', () {
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'pump3.speed',
            serverAlias: 'unknown',
            plcVariablePath: 'GVL.speed',
            declaringBlock: 'GVL',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            readers: [],
            writers: [],
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      // When alias is 'unknown', header should be plain [PLC CONTEXT]
      expect(output, contains('[PLC CONTEXT]'));
      expect(output, isNot(contains('[PLC CONTEXT - unknown]')));
    });
  });

  // ====================================================================
  // 9. resolveKeys — server alias fallback from ServerAliasProvider
  // ====================================================================
  group('resolveKeys - server alias fallback', () {
    test('uses default alias when mapping has no server_alias and one server exists',
        () async {
      final index = MockPlcCodeIndex();
      // Key mapping WITHOUT server_alias field
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          // No 'server_alias' key at all
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\nEND_VAR',
          implementation: 'GVL_Main.pump3_speed := 100.0;',
          fullSource:
              'PROGRAM MAIN\nVAR\nEND_VAR\nGVL_Main.pump3_speed := 100.0;',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ]);

      final plcCodeService = PlcCodeService(index, keyMapping);

      // Provide a ServerAliasProvider with one active server
      final aliasProvider = _StubServerAliasProvider(['TwinCAT_PLC1']);
      final contextService = PlcContextService(
        plcCodeService,
        keyMapping,
        serverAliasProvider: aliasProvider,
      );

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      final resolved = result.resolvedKeys.first;
      // Should use the single available alias, not 'unknown'
      expect(resolved.serverAlias, 'TwinCAT_PLC1');
    });

    test('falls back to "unknown" when mapping has no server_alias and multiple servers exist',
        () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          // No 'server_alias'
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\nEND_VAR',
          implementation: 'GVL_Main.pump3_speed := 100.0;',
          fullSource:
              'PROGRAM MAIN\nVAR\nEND_VAR\nGVL_Main.pump3_speed := 100.0;',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ]);

      final plcCodeService = PlcCodeService(index, keyMapping);

      // Multiple servers — ambiguous, should fall back to 'unknown'
      final aliasProvider =
          _StubServerAliasProvider(['PLC_A', 'PLC_B']);
      final contextService = PlcContextService(
        plcCodeService,
        keyMapping,
        serverAliasProvider: aliasProvider,
      );

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      expect(result.resolvedKeys.first.serverAlias, 'unknown');
    });

    test('falls back to "unknown" when no ServerAliasProvider is given',
        () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          // No 'server_alias'
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\nEND_VAR',
          implementation: 'GVL_Main.pump3_speed := 100.0;',
          fullSource:
              'PROGRAM MAIN\nVAR\nEND_VAR\nGVL_Main.pump3_speed := 100.0;',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ]);

      final plcCodeService = PlcCodeService(index, keyMapping);

      // No alias provider — backwards compatible, should fall back to 'unknown'
      final contextService = PlcContextService(plcCodeService, keyMapping);

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      expect(result.resolvedKeys.first.serverAlias, 'unknown');
    });

    test('explicit mapping server_alias takes priority over provider',
        () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
          'server_alias': 'ExplicitPLC',
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\nEND_VAR',
          implementation: 'GVL_Main.pump3_speed := 100.0;',
          fullSource:
              'PROGRAM MAIN\nVAR\nEND_VAR\nGVL_Main.pump3_speed := 100.0;',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ], serverAlias: 'ExplicitPLC');

      final plcCodeService = PlcCodeService(index, keyMapping);

      // Provider has a different alias, but mapping has an explicit one
      final aliasProvider = _StubServerAliasProvider(['ProviderPLC']);
      final contextService = PlcContextService(
        plcCodeService,
        keyMapping,
        serverAliasProvider: aliasProvider,
      );

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      // Explicit mapping alias wins over provider
      expect(result.resolvedKeys.first.serverAlias, 'ExplicitPLC');
    });

    test('falls back to "unknown" when provider has no servers', () async {
      final index = MockPlcCodeIndex();
      final keyMapping = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
        },
      ]);

      await index.indexAsset('plc1', [
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\nEND_VAR',
          implementation: 'GVL_Main.pump3_speed := 100.0;',
          fullSource:
              'PROGRAM MAIN\nVAR\nEND_VAR\nGVL_Main.pump3_speed := 100.0;',
          filePath: 'POUs/MAIN.st',
          variables: [],
          children: [],
        ),
      ]);

      final plcCodeService = PlcCodeService(index, keyMapping);

      // Empty provider
      final aliasProvider = _StubServerAliasProvider([]);
      final contextService = PlcContextService(
        plcCodeService,
        keyMapping,
        serverAliasProvider: aliasProvider,
      );

      final result = await contextService.resolveKeys(['pump3.speed']);

      expect(result.resolvedKeys, hasLength(1));
      expect(result.resolvedKeys.first.serverAlias, 'unknown');
    });
  });

  // ====================================================================
  // 10. MAIN-prefixed variable paths (GarageDoor bug)
  // ====================================================================
  group('resolveKeys - MAIN-prefixed FB instance paths', () {
    // Reproduces the bug where OPC-UA paths like
    // MAIN.GarageDoor.p_stat_uposition don't match the call graph's
    // variable index (which stores FB_GarageDoor.p_stat_uposition and
    // MAIN.GarageDoor).
    late MockPlcCodeIndex index;
    late _StubKeyMappingLookup keyMapping;
    late PlcCodeService plcCodeService;
    late PlcContextService contextService;

    setUp(() async {
      index = MockPlcCodeIndex();

      // FB_GarageDoor function block with VAR_OUTPUT p_stat_uposition
      const fbGarageDoor = ParsedCodeBlock(
        name: 'FB_GarageDoor',
        type: 'FunctionBlock',
        declaration: '''FUNCTION_BLOCK FB_GarageDoor
VAR_INPUT
  bEnable : BOOL;
END_VAR
VAR_OUTPUT
  p_stat_uposition : UINT;
  bOpen : BOOL;
  bClosed : BOOL;
END_VAR
VAR
  nRawPosition : UINT;
END_VAR''',
        implementation:
            '''p_stat_uposition := nRawPosition;
bOpen := p_stat_uposition >= 1000;
bClosed := p_stat_uposition <= 10;''',
        fullSource: '''FUNCTION_BLOCK FB_GarageDoor
VAR_INPUT
  bEnable : BOOL;
END_VAR
VAR_OUTPUT
  p_stat_uposition : UINT;
  bOpen : BOOL;
  bClosed : BOOL;
END_VAR
VAR
  nRawPosition : UINT;
END_VAR
p_stat_uposition := nRawPosition;
bOpen := p_stat_uposition >= 1000;
bClosed := p_stat_uposition <= 10;''',
        filePath: 'POUs/FB_GarageDoor.TcPOU',
        variables: [
          ParsedVariable(
              name: 'bEnable', type: 'BOOL', section: 'VAR_INPUT'),
          ParsedVariable(
              name: 'p_stat_uposition', type: 'UINT', section: 'VAR_OUTPUT'),
          ParsedVariable(
              name: 'bOpen', type: 'BOOL', section: 'VAR_OUTPUT'),
          ParsedVariable(
              name: 'bClosed', type: 'BOOL', section: 'VAR_OUTPUT'),
          ParsedVariable(
              name: 'nRawPosition', type: 'UINT', section: 'VAR'),
        ],
        children: [],
      );

      // MAIN program with GarageDoor instance
      const mainBlock = ParsedCodeBlock(
        name: 'MAIN',
        type: 'Program',
        declaration: '''PROGRAM MAIN
VAR
  GarageDoor : FB_GarageDoor;
  doorPosition : UINT;
END_VAR''',
        implementation:
            '''GarageDoor(bEnable := TRUE);
doorPosition := GarageDoor.p_stat_uposition;
IF GarageDoor.bOpen THEN
  // door is open
END_IF''',
        fullSource: '''PROGRAM MAIN
VAR
  GarageDoor : FB_GarageDoor;
  doorPosition : UINT;
END_VAR
GarageDoor(bEnable := TRUE);
doorPosition := GarageDoor.p_stat_uposition;
IF GarageDoor.bOpen THEN
  // door is open
END_IF''',
        filePath: 'POUs/MAIN.TcPOU',
        variables: [
          ParsedVariable(
              name: 'GarageDoor', type: 'FB_GarageDoor', section: 'VAR'),
          ParsedVariable(
              name: 'doorPosition', type: 'UINT', section: 'VAR'),
        ],
        children: [],
      );

      await index.indexAsset(
        'garage_project',
        [fbGarageDoor, mainBlock],
        serverAlias: 'TwinCAT_Garage',
      );

      // Key mapping: Door.position -> ns=4;s=MAIN.GarageDoor.p_stat_uposition
      keyMapping = _StubKeyMappingLookup([
        {
          'key': 'Door.position',
          'protocol': 'opcua',
          'identifier': 'ns=4;s=MAIN.GarageDoor.p_stat_uposition',
          'server_alias': 'TwinCAT_Garage',
        },
      ]);

      plcCodeService = PlcCodeService(index, keyMapping);
      contextService = PlcContextService(plcCodeService, keyMapping);
    });

    test('resolves MAIN.GarageDoor.p_stat_uposition with call graph data',
        () async {
      final result = await contextService.resolveKeys(['Door.position']);

      // Should be resolved, not unresolved
      expect(result.unresolvedKeys, isEmpty,
          reason: 'Door.position should not be unresolved');
      expect(result.resolvedKeys, hasLength(1));

      final resolved = result.resolvedKeys.first;
      expect(resolved.hmiKey, 'Door.position');
      expect(resolved.plcVariablePath, 'MAIN.GarageDoor.p_stat_uposition');
      expect(resolved.variableType, 'UINT');

      // The declaring block should be found (FB_GarageDoor declares
      // p_stat_uposition as VAR_OUTPUT)
      expect(resolved.declaringBlock, isNotNull,
          reason: 'Should find the declaring block for p_stat_uposition');

      // Should have readers and/or writers — MAIN reads
      // GarageDoor.p_stat_uposition
      final allRefs = [...resolved.readers, ...resolved.writers];
      expect(allRefs, isNotEmpty,
          reason: 'Should have readers or writers from MAIN');
    });

    test('finds FB instance info for MAIN-prefixed path', () async {
      final result = await contextService.resolveKeys(['Door.position']);

      expect(result.resolvedKeys, hasLength(1));
      final resolved = result.resolvedKeys.first;

      // Should identify that GarageDoor is an FB_GarageDoor instance
      expect(resolved.fbInstance, isNotNull,
          reason: 'Should find FB instance info for GarageDoor');
      expect(resolved.fbInstance!.instanceName, 'GarageDoor');
      expect(resolved.fbInstance!.fbTypeName, 'FB_GarageDoor');
    });

    test('formatForLlm does not contain "unknown" for server alias',
        () async {
      final result = await contextService.resolveKeys(['Door.position']);
      final output = contextService.formatForLlm(result);

      // Should NOT be "[PLC CONTEXT - unknown]"
      expect(output, isNot(contains('unknown')),
          reason: 'Server alias should be TwinCAT_Garage, not unknown');
      expect(output, contains('TwinCAT_Garage'));
    });

    test('formatForLlm contains block names from call graph', () async {
      final result = await contextService.resolveKeys(['Door.position']);
      final output = contextService.formatForLlm(result);

      // Should mention block names where the variable is used
      expect(output, contains('MAIN'),
          reason: 'MAIN should appear as reader/writer');
      // Should contain the variable path
      expect(output, contains('MAIN.GarageDoor.p_stat_uposition'));
      // Should contain the type
      expect(output, contains('UINT'));
    });

    test('call graph getVariableContext works with MAIN prefix', () async {
      final callGraph =
          await plcCodeService.buildCallGraph('garage_project');

      // The variable index stores:
      //   MAIN.GarageDoor -> FB_GarageDoor (FB instance)
      //   FB_GarageDoor.p_stat_uposition -> UINT
      // But the query path is MAIN.GarageDoor.p_stat_uposition.
      // getVariableContext should handle this via suffix matching.
      final context = callGraph
          .getVariableContext('MAIN.GarageDoor.p_stat_uposition');
      expect(context, isNotNull,
          reason:
              'getVariableContext should find FB_GarageDoor.p_stat_uposition '
              'when queried with MAIN.GarageDoor.p_stat_uposition');
      expect(context!['declaringBlock'], 'FB_GarageDoor');
      expect(context['variableType'], 'UINT');
    });

    test('call graph getReferences works with MAIN prefix', () async {
      final callGraph =
          await plcCodeService.buildCallGraph('garage_project');

      final refs = callGraph
          .getReferences('MAIN.GarageDoor.p_stat_uposition');
      expect(refs, isNotEmpty,
          reason:
              'getReferences should find references to '
              'GarageDoor.p_stat_uposition from MAIN');
    });
  });

  // ====================================================================
  // 11. formatForLlm — server alias fallback display
  // ====================================================================
  group('formatForLlm - server alias fallback display', () {
    test('shows real server name instead of "unknown" when alias provided',
        () {
      // Simulate what happens after resolveKeys with fallback alias
      final context = PlcContext(
        resolvedKeys: [
          ResolvedKey(
            hmiKey: 'pump3.speed',
            serverAlias: 'TwinCAT_PLC1',
            plcVariablePath: 'GVL.speed',
            declaringBlock: 'GVL',
            declaringBlockType: 'GVL',
            variableType: 'REAL',
            readers: [],
            writers: [],
          ),
        ],
        unresolvedKeys: [],
      );

      final plcCodeService = PlcCodeService(
        MockPlcCodeIndex(),
        _StubKeyMappingLookup(),
      );
      final service =
          PlcContextService(plcCodeService, _StubKeyMappingLookup());
      final output = service.formatForLlm(context);

      expect(output, contains('[PLC CONTEXT - TwinCAT_PLC1]'));
      expect(output, isNot(contains('[PLC CONTEXT]')));
    });
  });
}

// ---------------------------------------------------------------------------
// Stub ServerAliasProvider for testing.
// ---------------------------------------------------------------------------
class _StubServerAliasProvider implements ServerAliasProvider {
  _StubServerAliasProvider(this._aliases);

  final List<String> _aliases;

  @override
  List<String> get serverAliases => _aliases;
}

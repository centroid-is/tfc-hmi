import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/services/drift_plc_code_index.dart';

/// Test fixtures for DriftPlcCodeIndex tests.
ParsedCodeBlock _makeBlock({
  String name = 'FB_Pump',
  String type = 'FunctionBlock',
  String declaration = 'VAR\n  speed : REAL;\nEND_VAR',
  String? implementation = 'speed := 42.0;',
  String filePath = 'POUs/FB_Pump.TcPOU',
  List<ParsedVariable> variables = const [],
  List<ParsedChildBlock> children = const [],
}) {
  final fullSource = [
    declaration,
    if (implementation != null) implementation,
  ].join('\n');
  return ParsedCodeBlock(
    name: name,
    type: type,
    declaration: declaration,
    implementation: implementation,
    fullSource: fullSource,
    filePath: filePath,
    variables: variables,
    children: children,
  );
}

void main() {
  group('DriftPlcCodeIndex', () {
    late ServerDatabase db;
    late DriftPlcCodeIndex index;

    setUp(() async {
      db = ServerDatabase.inMemory();
      // Ensure tables are created.
      await db.customStatement('SELECT 1');
      index = DriftPlcCodeIndex(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('isEmpty returns true when no blocks indexed', () {
      expect(index.isEmpty, isTrue);
    });

    test('indexAsset stores blocks and variables, isEmpty becomes false',
        () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\nEND_VAR',
          implementation: null,
          variables: [
            const ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
        ),
      ]);

      expect(index.isEmpty, isFalse);

      // Verify via getBlock that data was stored
      final summary = await index.getIndexSummary();
      expect(summary, hasLength(1));
      expect(summary.first.assetKey, equals('plc-1'));
      expect(summary.first.blockCount, equals(1));
      expect(summary.first.variableCount, equals(1));
    });

    test('indexAsset stores child blocks with parentBlockId', () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'FB_Pump',
          type: 'FunctionBlock',
          children: [
            const ParsedChildBlock(
              name: 'Start',
              childType: 'Method',
              declaration: 'VAR\nEND_VAR',
              implementation: 'bRunning := TRUE;',
            ),
            const ParsedChildBlock(
              name: 'Stop',
              childType: 'Method',
              declaration: 'VAR\nEND_VAR',
              implementation: 'bRunning := FALSE;',
            ),
          ],
        ),
      ]);

      final summary = await index.getIndexSummary();
      expect(summary.first.blockCount, equals(3)); // parent + 2 children
    });

    test('getBlock returns full block with variables', () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  pump3_speed : REAL;\n  valve_pos : INT;\nEND_VAR',
          implementation: null,
          variables: [
            const ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
            const ParsedVariable(
              name: 'valve_pos',
              type: 'INT',
              section: 'VAR_GLOBAL',
            ),
          ],
        ),
      ]);

      // Get summary to find the block ID
      final summary = await index.getIndexSummary();
      expect(summary, hasLength(1));

      // Search to get a block ID
      final results = await index.search('pump3_speed');
      expect(results, isNotEmpty);

      final block = await index.getBlock(results.first.blockId);
      expect(block, isNotNull);
      expect(block!.blockName, equals('GVL_Main'));
      expect(block.blockType, equals('GVL'));
      expect(block.variables, hasLength(2));
      expect(block.variables.map((v) => v.variableName),
          containsAll(['pump3_speed', 'valve_pos']));
    });

    test('getBlock returns null for nonexistent ID', () async {
      final block = await index.getBlock(99999);
      expect(block, isNull);
    });

    test('search text mode returns matches via fuzzyMatch against fullSource',
        () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'FB_Pump',
          type: 'FunctionBlock',
          declaration: 'VAR\n  speed : REAL;\nEND_VAR',
          implementation: 'speed := targetSpeed * 0.5;',
        ),
        _makeBlock(
          name: 'FB_Valve',
          type: 'FunctionBlock',
          declaration: 'VAR\n  position : INT;\nEND_VAR',
          implementation: 'position := requestedPosition;',
          filePath: 'POUs/FB_Valve.TcPOU',
        ),
      ]);

      final results = await index.search('targetSpeed');
      expect(results, hasLength(1));
      expect(results.first.blockName, equals('FB_Pump'));
      expect(results.first.blockType, equals('FunctionBlock'));
      expect(results.first.assetKey, equals('plc-1'));
    });

    test('search key mode returns matches via fuzzyMatch against qualifiedName',
        () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          variables: [
            const ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
            const ParsedVariable(
              name: 'valve_pos',
              type: 'INT',
              section: 'VAR_GLOBAL',
            ),
          ],
        ),
      ]);

      // Search by qualified name (GVL_Main.pump3_speed)
      final results = await index.search('GVL_Main.pump3', mode: 'key');
      expect(results, isNotEmpty);
      expect(results.first.variableName, equals('pump3_speed'));
      expect(results.first.variableType, equals('REAL'));
      expect(results.first.blockName, equals('GVL_Main'));
    });

    test(
        'search variable mode returns matches via fuzzyMatch against variableName',
        () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          variables: [
            const ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
            const ParsedVariable(
              name: 'valve_pos',
              type: 'INT',
              section: 'VAR_GLOBAL',
            ),
          ],
        ),
      ]);

      final results = await index.search('pump3', mode: 'variable');
      expect(results, isNotEmpty);
      expect(results.first.variableName, equals('pump3_speed'));
      expect(results.first.variableType, equals('REAL'));
    });

    test('search with assetFilter limits results to that asset', () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'FB_Pump',
          type: 'FunctionBlock',
          implementation: 'speed := 42.0;',
        ),
      ]);
      await index.indexAsset('plc-2', [
        _makeBlock(
          name: 'FB_Motor',
          type: 'FunctionBlock',
          implementation: 'speed := 100.0;',
          filePath: 'POUs/FB_Motor.TcPOU',
        ),
      ]);

      // Both have 'speed' in fullSource, but filter to plc-1
      final results = await index.search('speed', assetFilter: 'plc-1');
      expect(results, hasLength(1));
      expect(results.first.assetKey, equals('plc-1'));
      expect(results.first.blockName, equals('FB_Pump'));
    });

    test('search respects limit parameter', () async {
      // Create 5 blocks all containing 'motor' in fullSource
      final blocks = List.generate(
        5,
        (i) => _makeBlock(
          name: 'FB_Motor_$i',
          implementation: 'motor_$i := running;',
          filePath: 'POUs/FB_Motor_$i.TcPOU',
        ),
      );
      await index.indexAsset('plc-1', blocks);

      final results = await index.search('motor', limit: 3);
      expect(results, hasLength(3));
    });

    test('deleteAssetIndex removes blocks and variables, updates isEmpty',
        () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          variables: [
            const ParsedVariable(
              name: 'pump3_speed',
              type: 'REAL',
              section: 'VAR_GLOBAL',
            ),
          ],
        ),
      ]);

      expect(index.isEmpty, isFalse);

      await index.deleteAssetIndex('plc-1');

      expect(index.isEmpty, isTrue);
      final results = await index.search('pump3_speed');
      expect(results, isEmpty);
    });

    test('indexAsset replaces existing index for same asset (idempotent)',
        () async {
      // First index
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'FB_OldPump',
          type: 'FunctionBlock',
          implementation: 'oldPumpLogic := TRUE;',
        ),
      ]);

      // Re-index same asset with different data
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'FB_NewPump',
          type: 'FunctionBlock',
          implementation: 'newPumpLogic := TRUE;',
        ),
      ]);

      // Old data should be gone
      final oldResults = await index.search('oldPumpLogic');
      expect(oldResults, isEmpty);

      // New data should be present
      final newResults = await index.search('newPumpLogic');
      expect(newResults, hasLength(1));
      expect(newResults.first.blockName, equals('FB_NewPump'));

      // Only one block total
      final summary = await index.getIndexSummary();
      expect(summary, hasLength(1));
      expect(summary.first.blockCount, equals(1));
    });

    test(
        'getIndexSummary returns per-asset block/variable counts and type breakdown',
        () async {
      await index.indexAsset('plc-1', [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          variables: [
            const ParsedVariable(
                name: 'v1', type: 'REAL', section: 'VAR_GLOBAL'),
            const ParsedVariable(
                name: 'v2', type: 'INT', section: 'VAR_GLOBAL'),
          ],
        ),
        _makeBlock(
          name: 'FB_Pump',
          type: 'FunctionBlock',
          filePath: 'POUs/FB_Pump.TcPOU',
          variables: [
            const ParsedVariable(name: 'speed', type: 'REAL', section: 'VAR'),
          ],
        ),
      ]);

      await index.indexAsset('plc-2', [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          filePath: 'POUs/MAIN.TcPOU',
        ),
      ]);

      final summaries = await index.getIndexSummary();
      expect(summaries, hasLength(2));

      final plc1 = summaries.firstWhere((s) => s.assetKey == 'plc-1');
      expect(plc1.blockCount, equals(2));
      expect(plc1.variableCount, equals(3));
      expect(plc1.blockTypeCounts, equals({'GVL': 1, 'FunctionBlock': 1}));

      final plc2 = summaries.firstWhere((s) => s.assetKey == 'plc-2');
      expect(plc2.blockCount, equals(1));
      expect(plc2.variableCount, equals(0));
      expect(plc2.blockTypeCounts, equals({'Program': 1}));
    });

    test('isEmpty reflects database state after restart (lazy initialization)',
        () async {
      // Index data
      await index.indexAsset('plc-1', [
        _makeBlock(name: 'GVL_Main', type: 'GVL'),
      ]);

      // Create a NEW DriftPlcCodeIndex instance on the same DB
      // (simulates server restart -- new instance, same database)
      final index2 = DriftPlcCodeIndex(db);

      // Before any async operation, isEmpty starts as true (cache default)
      expect(index2.isEmpty, isTrue);

      // After a search (triggers _ensureInitialized), isEmpty should reflect DB state
      await index2.search('anything');
      expect(index2.isEmpty, isFalse);
    });

    group('Call graph pre-computation', () {
      test('indexAsset populates plc_var_ref table', () async {
        // Index a program that reads and writes variables:
        // MAIN with variables: speed (REAL), running (BOOL)
        // Implementation: "speed := 42.0; running := TRUE;"
        // After indexing, getVarRefsForBlock should return refs for writes
        // to speed and running.
        await index.indexAsset('plc-1', [
          _makeBlock(
            name: 'MAIN',
            type: 'Program',
            declaration: 'VAR\n  speed : REAL;\n  running : BOOL;\nEND_VAR',
            implementation: 'speed := 42.0;\nrunning := TRUE;',
            filePath: 'POUs/MAIN.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'speed', type: 'REAL', section: 'VAR'),
              const ParsedVariable(
                  name: 'running', type: 'BOOL', section: 'VAR'),
            ],
          ),
        ]);
        final blocks = await index.getBlocksForAsset('plc-1');
        final mainBlock = blocks.firstWhere((b) => b.blockName == 'MAIN');
        final refs = await index.getVarRefsForBlock(mainBlock.id);
        expect(refs, isNotEmpty);
        // Should have write refs for MAIN.speed and MAIN.running
        final writePaths = refs
            .where((r) => r.kind == 'write')
            .map((r) => r.variablePath)
            .toSet();
        expect(writePaths, contains('MAIN.speed'));
        expect(writePaths, contains('MAIN.running'));
      });

      test('indexAsset populates plc_fb_instance table', () async {
        // MAIN declares an instance of FB_Pump. Need both blocks so
        // CallGraphBuilder recognizes the FB type.
        await index.indexAsset('plc-1', [
          _makeBlock(
            name: 'FB_Pump',
            type: 'FunctionBlock',
            declaration: 'VAR\n  speed : REAL;\nEND_VAR',
            implementation: 'speed := 100.0;',
            filePath: 'POUs/FB_Pump.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'speed', type: 'REAL', section: 'VAR'),
            ],
          ),
          _makeBlock(
            name: 'MAIN',
            type: 'Program',
            declaration: 'VAR\n  pump1 : FB_Pump;\nEND_VAR',
            implementation: 'pump1();',
            filePath: 'POUs/MAIN.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'pump1', type: 'FB_Pump', section: 'VAR'),
            ],
          ),
        ]);
        final fbInstances = await index.getFbInstances(fbTypeName: 'FB_Pump');
        expect(fbInstances, hasLength(1));
        expect(fbInstances.first.instanceName, equals('pump1'));
        expect(fbInstances.first.fbTypeName, equals('FB_Pump'));
      });

      test('indexAsset populates plc_block_call table', () async {
        // Same fixture as FB instance test -- MAIN calls pump1 (FB_Pump
        // instance). getBlockCalls on MAIN should show the call.
        await index.indexAsset('plc-1', [
          _makeBlock(
            name: 'FB_Pump',
            type: 'FunctionBlock',
            declaration: 'VAR\n  speed : REAL;\nEND_VAR',
            implementation: 'speed := 100.0;',
            filePath: 'POUs/FB_Pump.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'speed', type: 'REAL', section: 'VAR'),
            ],
          ),
          _makeBlock(
            name: 'MAIN',
            type: 'Program',
            declaration: 'VAR\n  pump1 : FB_Pump;\nEND_VAR',
            implementation: 'pump1();',
            filePath: 'POUs/MAIN.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'pump1', type: 'FB_Pump', section: 'VAR'),
            ],
          ),
        ]);
        final blocks = await index.getBlocksForAsset('plc-1');
        final mainBlock = blocks.firstWhere((b) => b.blockName == 'MAIN');
        final calls = await index.getBlockCalls(mainBlock.id);
        expect(calls, isNotEmpty);
        expect(calls.first.calleeBlockName, equals('pump1'));
      });

      test('getVarRefs returns matches by suffix', () async {
        // Index a program that writes to a GVL variable, then query by
        // partial path suffix.
        await index.indexAsset('plc-1', [
          _makeBlock(
            name: 'MAIN',
            type: 'Program',
            declaration: 'VAR\nEND_VAR',
            implementation: 'GVL_Main.pump3_speed := 42.0;',
            filePath: 'POUs/MAIN.TcPOU',
            variables: [],
          ),
        ]);
        final refs = await index.getVarRefs('pump3_speed');
        expect(refs, isNotEmpty);
        expect(refs.first.variablePath, contains('pump3_speed'));
      });

      test('deleteAssetIndex cascade-deletes call graph rows', () async {
        // Index with call graph data, then delete and verify tables are empty.
        await index.indexAsset('plc-1', [
          _makeBlock(
            name: 'MAIN',
            type: 'Program',
            declaration: 'VAR\n  speed : REAL;\nEND_VAR',
            implementation: 'speed := 42.0;',
            filePath: 'POUs/MAIN.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'speed', type: 'REAL', section: 'VAR'),
            ],
          ),
        ]);
        // Verify data exists
        final blocks = await index.getBlocksForAsset('plc-1');
        final refs = await index.getVarRefsForBlock(blocks.first.id);
        expect(refs, isNotEmpty);

        // Delete
        await index.deleteAssetIndex('plc-1');

        // Call graph tables should be empty (CASCADE DELETE via FK)
        final allRefs = await index.getVarRefs('speed');
        expect(allRefs, isEmpty);
        final fbInstances = await index.getFbInstances();
        expect(fbInstances, isEmpty);
      });

      test('deleteAssetIndex of one asset preserves another asset', () async {
        // Index two assets with call graph data.
        await index.indexAsset('plc-1', [
          _makeBlock(
            name: 'MAIN',
            type: 'Program',
            declaration: 'VAR\n  speed : REAL;\nEND_VAR',
            implementation: 'speed := 42.0;',
            filePath: 'POUs/MAIN.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'speed', type: 'REAL', section: 'VAR'),
            ],
          ),
        ]);
        await index.indexAsset('plc-2', [
          _makeBlock(
            name: 'FB_Motor',
            type: 'FunctionBlock',
            declaration: 'VAR\n  torque : REAL;\nEND_VAR',
            implementation: 'torque := 99.0;',
            filePath: 'POUs/FB_Motor.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'torque', type: 'REAL', section: 'VAR'),
            ],
          ),
        ]);

        // Verify both exist.
        var summary = await index.getIndexSummary();
        expect(summary, hasLength(2));

        // Delete plc-1.
        await index.deleteAssetIndex('plc-1');

        // plc-2 should be intact.
        summary = await index.getIndexSummary();
        expect(summary, hasLength(1));
        expect(summary.first.assetKey, equals('plc-2'));
        expect(index.isEmpty, isFalse);

        // plc-2 blocks and vars still present.
        final blocks = await index.getBlocksForAsset('plc-2');
        expect(blocks, hasLength(1));
        expect(blocks.first.blockName, equals('FB_Motor'));
        expect(blocks.first.variables, hasLength(1));

        // plc-1 blocks should be gone.
        final gone = await index.getBlocksForAsset('plc-1');
        expect(gone, isEmpty);
      });

      test('getCallers returns reverse call lookup', () async {
        await index.indexAsset('plc-1', [
          _makeBlock(
            name: 'FB_Pump',
            type: 'FunctionBlock',
            declaration: 'VAR\n  speed : REAL;\nEND_VAR',
            implementation: 'speed := 100.0;',
            filePath: 'POUs/FB_Pump.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'speed', type: 'REAL', section: 'VAR'),
            ],
          ),
          _makeBlock(
            name: 'MAIN',
            type: 'Program',
            declaration: 'VAR\n  pump1 : FB_Pump;\nEND_VAR',
            implementation: 'pump1();',
            filePath: 'POUs/MAIN.TcPOU',
            variables: [
              const ParsedVariable(
                  name: 'pump1', type: 'FB_Pump', section: 'VAR'),
            ],
          ),
        ]);
        final callers = await index.getCallers('pump1');
        expect(callers, isNotEmpty);
      });
    });
  });
}

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/call_graph_builder.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';

void main() {
  late CallGraphBuilder builder;

  setUp(() {
    builder = CallGraphBuilder();
  });

  // ==================================================================
  // 1. Reference extraction — simple assignments
  // ==================================================================
  group('simple assignment references', () {
    test('x := y — x is written, y is read', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'x := y;',
          variables: [
            _makeVar('x', 'INT'),
            _makeVar('y', 'INT'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final xRefs = data.getReferences('MAIN.x');
      final yRefs = data.getReferences('MAIN.y');

      expect(xRefs.where((r) => r.kind == ReferenceKind.write), isNotEmpty,
          reason: 'x should have a write reference');
      expect(yRefs.where((r) => r.kind == ReferenceKind.read), isNotEmpty,
          reason: 'y should have a read reference');
    });

    test('a := b + c — a written, b and c read', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'a := b + c;',
          variables: [
            _makeVar('a', 'INT'),
            _makeVar('b', 'INT'),
            _makeVar('c', 'INT'),
          ],
        ),
      ];

      final data = builder.build(blocks);

      expect(
        data.getReferences('MAIN.a').where((r) => r.kind == ReferenceKind.write),
        isNotEmpty,
      );
      expect(
        data.getReferences('MAIN.b').where((r) => r.kind == ReferenceKind.read),
        isNotEmpty,
      );
      expect(
        data.getReferences('MAIN.c').where((r) => r.kind == ReferenceKind.read),
        isNotEmpty,
      );
    });

    test('x := 42 — literal on RHS does not produce variable refs', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'x := 42;',
          variables: [_makeVar('x', 'INT')],
        ),
      ];

      final data = builder.build(blocks);
      final xRefs = data.getReferences('MAIN.x');

      expect(xRefs, hasLength(1));
      expect(xRefs.first.kind, ReferenceKind.write);
    });
  });

  // ==================================================================
  // 2. Member access references
  // ==================================================================
  group('member access references', () {
    test('GVL.pump3.speed := 100 — GVL.pump3.speed is written', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'GVL.pump3.speed := 100;',
          variables: [],
        ),
      ];

      final data = builder.build(blocks);
      final refs = data.getReferences('GVL.pump3.speed');

      expect(refs.where((r) => r.kind == ReferenceKind.write), isNotEmpty);
    });

    test('y := motor.speed — motor.speed is read', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'y := motor.speed;',
          variables: [_makeVar('y', 'REAL')],
        ),
      ];

      final data = builder.build(blocks);
      final refs = data.getReferences('motor.speed');

      expect(refs.where((r) => r.kind == ReferenceKind.read), isNotEmpty);
    });
  });

  // ==================================================================
  // 3. FB call references
  // ==================================================================
  group('FB call references', () {
    test('timer1(IN := sensor) — timer1 is called, sensor is read', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'timer1(IN := sensor);',
          variables: [
            _makeVar('timer1', 'TON'),
            _makeVar('sensor', 'BOOL'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final timer1Refs = data.getReferences('MAIN.timer1');
      final sensorRefs = data.getReferences('MAIN.sensor');

      expect(
        timer1Refs.where((r) => r.kind == ReferenceKind.call),
        isNotEmpty,
        reason: 'timer1 should have a call reference',
      );
      expect(
        sensorRefs.where((r) => r.kind == ReferenceKind.read),
        isNotEmpty,
        reason: 'sensor should have a read reference from FB call arg',
      );
    });

    test('FB call with output capture: fb1(Q => outVar)', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'fb1(IN := x, Q => outVar);',
          variables: [
            _makeVar('fb1', 'TON'),
            _makeVar('x', 'BOOL'),
            _makeVar('outVar', 'BOOL'),
          ],
        ),
      ];

      final data = builder.build(blocks);

      expect(
        data.getReferences('MAIN.outVar').where((r) => r.kind == ReferenceKind.write),
        isNotEmpty,
        reason: 'outVar should be written via output capture',
      );
    });
  });

  // ==================================================================
  // 4. FB instance -> type mapping
  // ==================================================================
  group('FB instance to type mapping', () {
    test('pump3 : FB_PumpControl maps pump3 to FB_PumpControl', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: '',
          variables: [_makeVar('pump3', 'FB_PumpControl')],
        ),
        _makeBlock(
          name: 'FB_PumpControl',
          type: 'FunctionBlock',
          implementation: '',
          variables: [
            _makeVar('speed', 'REAL', section: 'VAR_INPUT'),
            _makeVar('running', 'BOOL', section: 'VAR_OUTPUT'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final instances = data.getInstances('FB_PumpControl');

      expect(instances, isNotEmpty);
      expect(instances.first.instanceName, 'pump3');
      expect(instances.first.declaringBlock, 'MAIN');
    });

    test('multiple instances of same FB type', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: '',
          variables: [
            _makeVar('pump1', 'FB_Motor'),
            _makeVar('pump2', 'FB_Motor'),
            _makeVar('counter', 'INT'),
          ],
        ),
        _makeBlock(
          name: 'FB_Motor',
          type: 'FunctionBlock',
          implementation: '',
          variables: [_makeVar('speed', 'REAL')],
        ),
      ];

      final data = builder.build(blocks);
      final instances = data.getInstances('FB_Motor');

      expect(instances, hasLength(2));
      final names = instances.map((i) => i.instanceName).toSet();
      expect(names, containsAll(['pump1', 'pump2']));
    });

    test('primitive type is NOT treated as FB instance', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: '',
          variables: [_makeVar('counter', 'INT')],
        ),
      ];

      final data = builder.build(blocks);
      final instances = data.getInstances('INT');
      expect(instances, isEmpty);
    });
  });

  // ==================================================================
  // 5. Call chain / variable context
  // ==================================================================
  group('call chain', () {
    test('traces writers and readers for a variable', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'x := 10;\ny := x + 1;',
          variables: [
            _makeVar('x', 'INT'),
            _makeVar('y', 'INT'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final chain = data.getCallChain('MAIN.x');

      // x is written in MAIN and read in MAIN
      expect(chain, isNotEmpty);
      expect(
        chain.where((e) => e.kind == ReferenceKind.write),
        isNotEmpty,
      );
      expect(
        chain.where((e) => e.kind == ReferenceKind.read),
        isNotEmpty,
      );
    });

    test('cross-block references via qualified name', () {
      final blocks = [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          implementation: null,
          variables: [_makeVar('globalSpeed', 'REAL', section: 'VAR_GLOBAL')],
        ),
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'GVL_Main.globalSpeed := 50.0;',
          variables: [],
        ),
        _makeBlock(
          name: 'FB_Display',
          type: 'FunctionBlock',
          implementation: 'displayVal := GVL_Main.globalSpeed;',
          variables: [_makeVar('displayVal', 'REAL')],
        ),
      ];

      final data = builder.build(blocks);
      final refs = data.getReferences('GVL_Main.globalSpeed');

      expect(
        refs.where((r) => r.kind == ReferenceKind.write && r.blockName == 'MAIN'),
        isNotEmpty,
        reason: 'MAIN should write GVL_Main.globalSpeed',
      );
      expect(
        refs.where((r) => r.kind == ReferenceKind.read && r.blockName == 'FB_Display'),
        isNotEmpty,
        reason: 'FB_Display should read GVL_Main.globalSpeed',
      );
    });
  });

  // ==================================================================
  // 6. IF/CASE/FOR body references
  // ==================================================================
  group('control flow body references', () {
    test('IF condition and body variables are tracked', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: '''
IF sensor > 100 THEN
  alarm := TRUE;
END_IF;
''',
          variables: [
            _makeVar('sensor', 'INT'),
            _makeVar('alarm', 'BOOL'),
          ],
        ),
      ];

      final data = builder.build(blocks);

      expect(
        data.getReferences('MAIN.sensor').where((r) => r.kind == ReferenceKind.read),
        isNotEmpty,
      );
      expect(
        data.getReferences('MAIN.alarm').where((r) => r.kind == ReferenceKind.write),
        isNotEmpty,
      );
    });

    test('FOR loop variable is both written and read', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: '''
FOR i := 0 TO 10 DO
  arr[i] := 0;
END_FOR;
''',
          variables: [
            _makeVar('i', 'INT'),
            _makeVar('arr', 'ARRAY [0..10] OF INT'),
          ],
        ),
      ];

      final data = builder.build(blocks);

      // FOR loop variable 'i' is written (assigned) and read (in body arr[i])
      final iRefs = data.getReferences('MAIN.i');
      expect(
        iRefs.where((r) => r.kind == ReferenceKind.write),
        isNotEmpty,
        reason: 'FOR iterator should be written',
      );
      expect(
        iRefs.where((r) => r.kind == ReferenceKind.read),
        isNotEmpty,
        reason: 'FOR iterator used as array index should be read',
      );
    });
  });

  // ==================================================================
  // 7. Resilient parsing — malformed code
  // ==================================================================
  group('resilient parsing', () {
    test('partial parse failure still extracts what it can', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'x := 10;\n@#\$GARBAGE\ny := x;',
          variables: [
            _makeVar('x', 'INT'),
            _makeVar('y', 'INT'),
          ],
        ),
      ];

      final data = builder.build(blocks);

      // Should still get references for the valid parts
      final xRefs = data.getReferences('MAIN.x');
      expect(xRefs, isNotEmpty,
          reason: 'should extract references from valid statements');
    });

    test('empty implementation produces no references', () {
      final blocks = [
        _makeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          implementation: null,
          variables: [_makeVar('speed', 'REAL', section: 'VAR_GLOBAL')],
        ),
      ];

      final data = builder.build(blocks);
      final refs = data.getReferences('GVL_Main.speed');

      // GVL has no implementation, so no read/write references — just exists
      expect(refs, isEmpty);
    });
  });

  // ==================================================================
  // 8. getVariableContext aggregation
  // ==================================================================
  group('getVariableContext', () {
    test('returns declaring block, readers, writers, and FB type', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'pump3.speed := setpoint;\ntemp := pump3.running;',
          variables: [
            _makeVar('pump3', 'FB_PumpControl'),
            _makeVar('setpoint', 'REAL'),
            _makeVar('temp', 'BOOL'),
          ],
        ),
        _makeBlock(
          name: 'FB_PumpControl',
          type: 'FunctionBlock',
          implementation: '',
          variables: [
            _makeVar('speed', 'REAL', section: 'VAR_INPUT'),
            _makeVar('running', 'BOOL', section: 'VAR_OUTPUT'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final context = data.getVariableContext('MAIN.pump3');

      expect(context, isNotNull);
      expect(context!['declaringBlock'], 'MAIN');
      expect(context['variableType'], 'FB_PumpControl');
      expect(context['isFbInstance'], true);
      expect(context['fbTypeName'], 'FB_PumpControl');
    });

    test('returns null for unknown variable', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: '',
          variables: [],
        ),
      ];

      final data = builder.build(blocks);
      final context = data.getVariableContext('MAIN.nonexistent');

      expect(context, isNull);
    });
  });

  // ==================================================================
  // 9. FB instance member decomposition
  // ==================================================================
  group('FB instance member decomposition', () {
    test('pump3.speed resolves to FB_PumpControl.speed', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'pump3.speed := 100;',
          variables: [_makeVar('pump3', 'FB_PumpControl')],
        ),
        _makeBlock(
          name: 'FB_PumpControl',
          type: 'FunctionBlock',
          implementation: '',
          variables: [
            _makeVar('speed', 'REAL', section: 'VAR_INPUT'),
            _makeVar('running', 'BOOL', section: 'VAR_OUTPUT'),
          ],
        ),
      ];

      final data = builder.build(blocks);

      // When we write pump3.speed, we should see it as a write to that member
      final refs = data.getReferences('pump3.speed');
      expect(refs.where((r) => r.kind == ReferenceKind.write), isNotEmpty);

      // The context should tell us the FB type
      final ctx = data.getVariableContext('MAIN.pump3');
      expect(ctx?['fbTypeName'], 'FB_PumpControl');
      expect(ctx?['fbMembers'], isNotNull);
      final members = ctx!['fbMembers'] as List;
      expect(members, contains('speed'));
      expect(members, contains('running'));
    });
  });

  // ==================================================================
  // 10. Source line enrichment
  // ==================================================================
  group('source line enrichment', () {
    test('simple assignment gets line number and source line', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'x := 10;\ny := x;',
          variables: [
            _makeVar('x', 'INT'),
            _makeVar('y', 'INT'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final xWriteRefs = data.getReferences('MAIN.x')
          .where((r) => r.kind == ReferenceKind.write)
          .toList();

      expect(xWriteRefs, hasLength(1));
      expect(xWriteRefs.first.lineNumber, 1);
      expect(xWriteRefs.first.sourceLine, 'x := 10;');
    });

    test('multiple writes to same variable get different line numbers', () {
      final blocks = [
        _makeBlock(
          name: 'FB_Dimmer',
          type: 'FunctionBlock',
          implementation:
              'i_stDimmer.xLightOnOut := bLampOn;\n'
              'i_stDimmer.xLightOnOut := bDimActive;\n'
              'i_stDimmer.xLightOnOut := bOverride;',
          variables: [
            _makeVar('i_stDimmer', 'ST_Dimmer'),
            _makeVar('bLampOn', 'BOOL'),
            _makeVar('bDimActive', 'BOOL'),
            _makeVar('bOverride', 'BOOL'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final refs = data.getReferences('i_stDimmer.xLightOnOut')
          .where((r) => r.kind == ReferenceKind.write)
          .toList();

      expect(refs, hasLength(3));

      // Each reference should have a distinct line number.
      final lineNumbers = refs.map((r) => r.lineNumber).toSet();
      expect(lineNumbers, {1, 2, 3});

      // Each reference should show its source line.
      final sourceLines = refs.map((r) => r.sourceLine).toSet();
      expect(sourceLines, contains('i_stDimmer.xLightOnOut := bLampOn;'));
      expect(sourceLines, contains('i_stDimmer.xLightOnOut := bDimActive;'));
      expect(sourceLines, contains('i_stDimmer.xLightOnOut := bOverride;'));
    });

    test('FB call gets line number', () {
      final blocks = [
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: 'x := 0;\ntimer1(IN := sensor);',
          variables: [
            _makeVar('x', 'INT'),
            _makeVar('timer1', 'TON'),
            _makeVar('sensor', 'BOOL'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final callRefs = data.getReferences('MAIN.timer1')
          .where((r) => r.kind == ReferenceKind.call)
          .toList();

      expect(callRefs, hasLength(1));
      expect(callRefs.first.lineNumber, 2);
      expect(callRefs.first.sourceLine, 'timer1(IN := sensor);');
    });
  });

  // ==================================================================
  // 11. FB_Dimmer deduplication scenario (end-to-end)
  // ==================================================================
  group('FB_Dimmer deduplication scenario', () {
    test('MAIN.Instance.member path matches FB implementation refs', () {
      final blocks = [
        _makeBlock(
          name: 'FB_Dimmer',
          type: 'FunctionBlock',
          implementation:
              'i_stDimmer.xLightOnOut := bLampOn;\n'
              'i_stDimmer.xLightOnOut := bDimActive;\n'
              'i_stDimmer.xLightOnOut := bOverride;',
          variables: [
            _makeVar('i_stDimmer', 'ST_Dimmer'),
            _makeVar('bLampOn', 'BOOL'),
            _makeVar('bDimActive', 'BOOL'),
            _makeVar('bOverride', 'BOOL'),
          ],
        ),
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation:
              'DimmerBathroomMirror();\nDimmerKitchen();\nDimmerBedroom();',
          variables: [
            _makeVar('DimmerBathroomMirror', 'FB_Dimmer'),
            _makeVar('DimmerKitchen', 'FB_Dimmer'),
            _makeVar('DimmerBedroom', 'FB_Dimmer'),
          ],
        ),
      ];

      final data = builder.build(blocks);

      // The OPC-UA path from key mapping.
      final refs = data.getReferences(
          'MAIN.DimmerBathroomMirror.i_stDimmer.xLightOnOut');

      // Should find 3 write references (one per assignment in FB_Dimmer).
      expect(refs, hasLength(3));

      // All should be writes in FB_Dimmer.
      for (final ref in refs) {
        expect(ref.kind, ReferenceKind.write);
        expect(ref.blockName, 'FB_Dimmer');
      }

      // Each should have a distinct line number (1, 2, 3).
      final lines = refs.map((r) => r.lineNumber).toSet();
      expect(lines, {1, 2, 3});

      // Each should have a distinct source line.
      final sources = refs.map((r) => r.sourceLine).toSet();
      expect(sources, hasLength(3));
    });

    test('FB instances are correctly identified', () {
      final blocks = [
        _makeBlock(
          name: 'FB_Dimmer',
          type: 'FunctionBlock',
          implementation: '',
          variables: [
            _makeVar('bLampOn', 'BOOL'),
          ],
        ),
        _makeBlock(
          name: 'MAIN',
          type: 'Program',
          implementation: '',
          variables: [
            _makeVar('DimmerBathroomMirror', 'FB_Dimmer'),
            _makeVar('DimmerKitchen', 'FB_Dimmer'),
            _makeVar('DimmerBedroom', 'FB_Dimmer'),
          ],
        ),
      ];

      final data = builder.build(blocks);
      final instances = data.getInstances('FB_Dimmer');

      expect(instances, hasLength(3));
      final names = instances.map((i) => i.instanceName).toSet();
      expect(names, containsAll([
        'DimmerBathroomMirror',
        'DimmerKitchen',
        'DimmerBedroom',
      ]));
    });
  });
}

// ==================================================================
// Test helpers
// ==================================================================

PlcCodeBlock _makeBlock({
  required String name,
  required String type,
  required String? implementation,
  required List<PlcVariable> variables,
  int id = 0,
}) {
  return PlcCodeBlock(
    id: id,
    assetKey: 'test-asset',
    blockName: name,
    blockType: type,
    filePath: 'test/$name.st',
    declaration: 'VAR ... END_VAR',
    implementation: implementation,
    fullSource: '...',
    indexedAt: DateTime.now(),
    variables: variables,
  );
}

PlcVariable _makeVar(String name, String type, {String section = 'VAR'}) {
  return PlcVariable(
    id: 0,
    blockId: 0,
    variableName: name,
    variableType: type,
    section: section,
    qualifiedName: '$name',
  );
}

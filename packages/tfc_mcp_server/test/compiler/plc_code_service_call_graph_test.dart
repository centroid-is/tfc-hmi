import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/call_graph_builder.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/services/plc_code_service.dart';

/// In-memory PlcCodeIndex for testing PlcCodeService integration.
class _InMemoryPlcCodeIndex implements PlcCodeIndex {
  final _blocks = <int, PlcCodeBlock>{};
  final _variables = <int, List<PlcVariable>>{};
  int _nextId = 1;
  bool _isEmpty = true;

  @override
  bool get isEmpty => _isEmpty;

  @override
  Future<void> indexAsset(
    String assetKey,
    List<ParsedCodeBlock> blocks, {
    String? vendorType,
    String? serverAlias,
  }) async {
    for (final block in blocks) {
      final id = _nextId++;
      final vars = <PlcVariable>[];
      for (final v in block.variables) {
        vars.add(PlcVariable(
          id: _nextId++,
          blockId: id,
          variableName: v.name,
          variableType: v.type,
          section: v.section,
          qualifiedName: '${block.name}.${v.name}',
          comment: v.comment,
        ));
      }
      _variables[id] = vars;
      _blocks[id] = PlcCodeBlock(
        id: id,
        assetKey: assetKey,
        blockName: block.name,
        blockType: block.type,
        filePath: block.filePath,
        declaration: block.declaration,
        implementation: block.implementation,
        fullSource: block.fullSource,
        indexedAt: DateTime.now(),
        variables: vars,
        vendorType: vendorType,
        serverAlias: serverAlias,
      );
      _isEmpty = false;
    }
  }

  @override
  Future<void> deleteAssetIndex(String assetKey) async {
    final toRemove = _blocks.entries
        .where((e) => e.value.assetKey == assetKey)
        .map((e) => e.key)
        .toList();
    for (final id in toRemove) {
      _blocks.remove(id);
      _variables.remove(id);
    }
    _isEmpty = _blocks.isEmpty;
  }

  @override
  Future<PlcCodeBlock?> getBlock(int blockId) async => _blocks[blockId];

  @override
  Future<List<PlcCodeBlock>> getBlocksForAsset(String assetKey) async {
    return _blocks.values.where((b) => b.assetKey == assetKey).toList();
  }

  @override
  Future<List<PlcAssetSummary>> getIndexSummary() async => [];

  @override
  Future<List<PlcCodeSearchResult>> search(
    String query, {
    String mode = 'text',
    String? assetFilter,
    String? serverAlias,
    int limit = 20,
  }) async {
    return [];
  }

  @override
  Future<void> renameAsset(String oldAssetKey, String newAssetKey) async {
    final toUpdate = _blocks.entries
        .where((e) => e.value.assetKey == oldAssetKey)
        .map((e) => e.key)
        .toList();
    for (final id in toUpdate) {
      final old = _blocks[id]!;
      _blocks[id] = PlcCodeBlock(
        id: old.id,
        assetKey: newAssetKey,
        blockName: old.blockName,
        blockType: old.blockType,
        filePath: old.filePath,
        declaration: old.declaration,
        implementation: old.implementation,
        fullSource: old.fullSource,
        indexedAt: old.indexedAt,
        variables: old.variables,
        vendorType: old.vendorType,
        serverAlias: old.serverAlias,
      );
    }
  }
}

/// Stub KeyMappingLookup for testing.
class _StubKeyMappingLookup implements KeyMappingLookup {
  @override
  Future<List<Map<String, dynamic>>> listKeyMappings({
    String? filter,
    int limit = 50,
  }) async {
    return [];
  }
}

void main() {
  late _InMemoryPlcCodeIndex index;
  late PlcCodeService service;

  setUp(() {
    index = _InMemoryPlcCodeIndex();
    service = PlcCodeService(index, _StubKeyMappingLookup());
  });

  group('PlcCodeService.buildCallGraph', () {
    test('builds call graph from indexed blocks', () async {
      // Index some blocks first
      await index.indexAsset('asset1', [
        ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration:
              'PROGRAM MAIN\nVAR\n  pump3 : FB_PumpControl;\n  setpoint : REAL;\nEND_VAR',
          implementation: 'pump3.speed := setpoint;',
          fullSource: '...',
          filePath: 'test/MAIN.st',
          variables: [
            const ParsedVariable(
                name: 'pump3', type: 'FB_PumpControl', section: 'VAR'),
            const ParsedVariable(
                name: 'setpoint', type: 'REAL', section: 'VAR'),
          ],
          children: [],
        ),
        ParsedCodeBlock(
          name: 'FB_PumpControl',
          type: 'FunctionBlock',
          declaration:
              'FUNCTION_BLOCK FB_PumpControl\nVAR_INPUT\n  speed : REAL;\nEND_VAR',
          implementation: '',
          fullSource: '...',
          filePath: 'test/FB_PumpControl.st',
          variables: [
            const ParsedVariable(
                name: 'speed', type: 'REAL', section: 'VAR_INPUT'),
          ],
          children: [],
        ),
      ]);

      final data = await service.buildCallGraph('asset1');

      expect(data, isNotNull);

      // pump3 should be recognized as an FB instance
      final instances = data.getInstances('FB_PumpControl');
      expect(instances, isNotEmpty);
      expect(instances.first.instanceName, 'pump3');
    });

    test('returns empty call graph for unknown asset', () async {
      final data = await service.buildCallGraph('nonexistent');
      expect(data.getInstances('anything'), isEmpty);
    });
  });

  group('PlcCodeService.getVariableContext', () {
    test('returns context for a known variable', () async {
      await index.indexAsset('asset1', [
        ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\n  counter : INT;\nEND_VAR',
          implementation: 'counter := counter + 1;',
          fullSource: '...',
          filePath: 'test/MAIN.st',
          variables: [
            const ParsedVariable(name: 'counter', type: 'INT', section: 'VAR'),
          ],
          children: [],
        ),
      ]);

      final context = await service.getVariableContext(
        'MAIN.counter',
        assetKey: 'asset1',
      );

      expect(context, isNotNull);
      expect(context!['declaringBlock'], 'MAIN');
      expect(context['variableType'], 'INT');
      expect(context['isFbInstance'], false);
    });

    test('returns null for unknown variable', () async {
      await index.indexAsset('asset1', [
        ParsedCodeBlock(
          name: 'MAIN',
          type: 'Program',
          declaration: 'PROGRAM MAIN\nVAR\nEND_VAR',
          implementation: '',
          fullSource: '...',
          filePath: 'test/MAIN.st',
          variables: [],
          children: [],
        ),
      ]);

      final context = await service.getVariableContext(
        'MAIN.nonexistent',
        assetKey: 'asset1',
      );

      expect(context, isNull);
    });
  });
}

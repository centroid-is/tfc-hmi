import 'package:tfc_dart/tfc_dart_core.dart' show fuzzyMatch;
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';

/// In-memory implementation of [PlcCodeIndex] for testing.
///
/// Use [indexAsset] to populate test data and [deleteAssetIndex] to remove.
/// Search uses [fuzzyMatch] from tfc_dart to match against variable names,
/// qualified names, and code content depending on the search mode.
class MockPlcCodeIndex implements PlcCodeIndex {
  final Map<String, List<ParsedCodeBlock>> _assets = {};
  final List<PlcCodeBlock> _blocks = [];
  final List<PlcVariable> _allVariables = [];
  int _nextBlockId = 1;
  int _nextVariableId = 1;

  /// Remove all indexed data.
  void clear() {
    _assets.clear();
    _blocks.clear();
    _allVariables.clear();
    _nextBlockId = 1;
    _nextVariableId = 1;
  }

  @override
  bool get isEmpty => _assets.isEmpty;

  @override
  Future<void> indexAsset(
    String assetKey,
    List<ParsedCodeBlock> blocks, {
    String? vendorType,
    String? serverAlias,
  }) async {
    // Remove existing data for this asset.
    await deleteAssetIndex(assetKey);

    _assets[assetKey] = blocks;

    for (final parsed in blocks) {
      final blockId = _nextBlockId++;
      final variables = <PlcVariable>[];

      for (final pv in parsed.variables) {
        final varId = _nextVariableId++;
        final variable = PlcVariable(
          id: varId,
          blockId: blockId,
          variableName: pv.name,
          variableType: pv.type,
          section: pv.section,
          qualifiedName: '${parsed.name}.${pv.name}',
          comment: pv.comment,
        );
        variables.add(variable);
        _allVariables.add(variable);
      }

      _blocks.add(PlcCodeBlock(
        id: blockId,
        assetKey: assetKey,
        blockName: parsed.name,
        blockType: parsed.type,
        filePath: parsed.filePath,
        declaration: parsed.declaration,
        implementation: parsed.implementation,
        fullSource: parsed.fullSource,
        indexedAt: DateTime.now(),
        vendorType: vendorType,
        serverAlias: serverAlias,
        variables: variables,
      ));

      // Index child blocks (methods, actions, properties, transitions).
      for (final child in parsed.children) {
        final childBlockId = _nextBlockId++;
        final childFullSource = [
          child.declaration,
          if (child.implementation != null) child.implementation,
        ].join('\n');

        _blocks.add(PlcCodeBlock(
          id: childBlockId,
          assetKey: assetKey,
          blockName: child.name,
          blockType: child.childType,
          filePath: parsed.filePath,
          declaration: child.declaration,
          implementation: child.implementation,
          fullSource: childFullSource,
          indexedAt: DateTime.now(),
          vendorType: vendorType,
          serverAlias: serverAlias,
          parentBlockId: blockId,
          variables: const [],
        ));
      }
    }
  }

  @override
  Future<List<PlcCodeBlock>> getBlocksForAsset(String assetKey) async {
    return _blocks.where((b) => b.assetKey == assetKey).toList();
  }

  @override
  Future<void> deleteAssetIndex(String assetKey) async {
    _assets.remove(assetKey);
    final removedBlockIds =
        _blocks.where((b) => b.assetKey == assetKey).map((b) => b.id).toSet();
    _blocks.removeWhere((b) => b.assetKey == assetKey);
    _allVariables.removeWhere((v) => removedBlockIds.contains(v.blockId));
  }

  @override
  Future<void> renameAsset(String oldAssetKey, String newAssetKey) async {
    // Move parsed blocks entry.
    final parsedBlocks = _assets.remove(oldAssetKey);
    if (parsedBlocks != null) {
      _assets[newAssetKey] = parsedBlocks;
    }

    // Rebuild _blocks list with updated assetKey.
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].assetKey == oldAssetKey) {
        final b = _blocks[i];
        _blocks[i] = PlcCodeBlock(
          id: b.id,
          assetKey: newAssetKey,
          blockName: b.blockName,
          blockType: b.blockType,
          filePath: b.filePath,
          declaration: b.declaration,
          implementation: b.implementation,
          fullSource: b.fullSource,
          indexedAt: b.indexedAt,
          vendorType: b.vendorType,
          serverAlias: b.serverAlias,
          parentBlockId: b.parentBlockId,
          variables: b.variables,
        );
      }
    }
  }

  @override
  Future<PlcCodeBlock?> getBlock(int blockId) async {
    for (final block in _blocks) {
      if (block.id == blockId) return block;
    }
    return null;
  }

  @override
  Future<List<PlcAssetSummary>> getIndexSummary() async {
    final summaries = <PlcAssetSummary>[];

    for (final entry in _assets.entries) {
      final assetKey = entry.key;
      final assetBlocks = _blocks.where((b) => b.assetKey == assetKey).toList();
      final assetVars = _allVariables.where((v) {
        return assetBlocks.any((b) => b.id == v.blockId);
      }).toList();

      final typeCounts = <String, int>{};
      for (final block in assetBlocks) {
        typeCounts[block.blockType] = (typeCounts[block.blockType] ?? 0) + 1;
      }

      DateTime lastIndexed = DateTime(2000);
      for (final block in assetBlocks) {
        if (block.indexedAt.isAfter(lastIndexed)) {
          lastIndexed = block.indexedAt;
        }
      }

      summaries.add(PlcAssetSummary(
        assetKey: assetKey,
        blockCount: assetBlocks.length,
        variableCount: assetVars.length,
        lastIndexedAt: lastIndexed,
        blockTypeCounts: typeCounts,
      ));
    }

    return summaries;
  }

  @override
  Future<List<PlcCodeSearchResult>> search(
    String query, {
    String mode = 'text',
    String? assetFilter,
    String? serverAlias,
    int limit = 20,
  }) async {
    if (_blocks.isEmpty) return [];

    final q = query.toLowerCase();
    final results = <PlcCodeSearchResult>[];

    switch (mode) {
      case 'key':
        // Search by qualified name (OPC UA s= path correlation).
        for (final variable in _allVariables) {
          // Use suffix matching — the query path may have a MAIN. prefix
          // that the qualifiedName doesn't have.
          final textLower = variable.qualifiedName.toLowerCase();
          if (_matchesFilters(variable.blockId, assetFilter, serverAlias) &&
              (textLower == q ||
                  q.endsWith('.$textLower') ||
                  q.endsWith(textLower))) {
            final block = _blockForId(variable.blockId);
            if (block != null) {
              results.add(PlcCodeSearchResult(
                blockId: variable.blockId,
                blockName: block.blockName,
                blockType: block.blockType,
                variableName: variable.variableName,
                variableType: variable.variableType,
                assetKey: block.assetKey,
                declarationLine:
                    '${variable.variableName} : ${variable.variableType}',
              ));
            }
          }
        }

      case 'variable':
        // Search by variable name.
        for (final variable in _allVariables) {
          if (_matchesFilters(variable.blockId, assetFilter, serverAlias) &&
              fuzzyMatch(variable.variableName.toLowerCase(), q)) {
            final block = _blockForId(variable.blockId);
            if (block != null) {
              results.add(PlcCodeSearchResult(
                blockId: variable.blockId,
                blockName: block.blockName,
                blockType: block.blockType,
                variableName: variable.variableName,
                variableType: variable.variableType,
                assetKey: block.assetKey,
                declarationLine:
                    '${variable.variableName} : ${variable.variableType}',
              ));
            }
          }
        }

      default:
        // Free-text search in fullSource (declaration + implementation + comments).
        for (final block in _blocks) {
          if (assetFilter != null && block.assetKey != assetFilter) continue;
          if (serverAlias != null && block.serverAlias != serverAlias) continue;
          if (fuzzyMatch(block.fullSource.toLowerCase(), q)) {
            results.add(PlcCodeSearchResult(
              blockId: block.id,
              blockName: block.blockName,
              blockType: block.blockType,
              assetKey: block.assetKey,
            ));
          }
        }
    }

    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  bool _matchesFilters(int blockId, String? assetFilter, String? serverAlias) {
    final block = _blockForId(blockId);
    if (block == null) return false;
    if (assetFilter != null && block.assetKey != assetFilter) return false;
    if (serverAlias != null && block.serverAlias != serverAlias) return false;
    return true;
  }

  PlcCodeBlock? _blockForId(int blockId) {
    for (final block in _blocks) {
      if (block.id == blockId) return block;
    }
    return null;
  }
}

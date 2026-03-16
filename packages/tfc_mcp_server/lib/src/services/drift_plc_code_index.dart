import 'package:drift/drift.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase, fuzzyMatch;

import '../compiler/call_graph_builder.dart';
import '../database/server_database.dart'
    show
        $PlcBlockCallTableTable,
        $PlcCodeBlockTableTable,
        $PlcFbInstanceTableTable,
        $PlcVarRefTableTable,
        $PlcVariableTableTable,
        PlcBlockCallTableCompanion,
        PlcBlockCallTableData,
        PlcCodeBlockTableCompanion,
        PlcCodeBlockTableData,
        PlcFbInstanceTableCompanion,
        PlcFbInstanceTableData,
        PlcVarRefTableCompanion,
        PlcVarRefTableData,
        PlcVariableTableCompanion,
        PlcVariableTableData;
import '../interfaces/plc_code_index.dart';

/// Database-backed implementation of [PlcCodeIndex] using Drift.
///
/// Stores PLC code blocks and variables in [PlcCodeBlockTable] and
/// [PlcVariableTable]. Search uses in-Dart fuzzyMatch filtering after
/// DB fetch, following the same pattern as [DriftDrawingIndex].
///
/// [isEmpty] is a synchronous cached getter. It is lazily initialized
/// on the first async operation (_ensureInitialized) to handle server
/// restart correctly -- a fresh instance starts with _isEmptyCache = true
/// but updates from database state on first query.
///
/// Accepts [McpDatabase] (not ServerDatabase) so it works with both
/// AppDatabase (Flutter in-process) and ServerDatabase (standalone binary).
/// Creates table references directly from generated table classes since
/// McpDatabase is a marker interface without typed table accessors.
class DriftPlcCodeIndex implements PlcCodeIndex {
  /// Creates a [DriftPlcCodeIndex] backed by the given [McpDatabase].
  DriftPlcCodeIndex(this._db)
      : _plcCodeBlockTable = $PlcCodeBlockTableTable(_db),
        _plcVariableTable = $PlcVariableTableTable(_db),
        _plcVarRefTable = $PlcVarRefTableTable(_db),
        _plcFbInstanceTable = $PlcFbInstanceTableTable(_db),
        _plcBlockCallTable = $PlcBlockCallTableTable(_db);

  final McpDatabase _db;
  final $PlcCodeBlockTableTable _plcCodeBlockTable;
  final $PlcVariableTableTable _plcVariableTable;
  final $PlcVarRefTableTable _plcVarRefTable;
  final $PlcFbInstanceTableTable _plcFbInstanceTable;
  final $PlcBlockCallTableTable _plcBlockCallTable;
  bool _isEmptyCache = true;
  bool _isInitialized = false;

  /// Runs a count query on first async access to sync the isEmpty cache
  /// with actual database state. Handles the server-restart case where
  /// the database has data from a prior session.
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    final count = await (_db.selectOnly(_plcCodeBlockTable)
          ..addColumns([_plcCodeBlockTable.id.count()]))
        .map((row) => row.read(_plcCodeBlockTable.id.count()))
        .getSingle();
    _isEmptyCache = (count ?? 0) == 0;
    _isInitialized = true;
  }

  @override
  bool get isEmpty => _isEmptyCache;

  @override
  Future<void> indexAsset(
    String assetKey,
    List<ParsedCodeBlock> blocks, {
    String? vendorType,
    String? serverAlias,
  }) async {
    // Idempotent: delete existing index for this asset first.
    await deleteAssetIndex(assetKey);

    for (final block in blocks) {
      final blockId = await _db.into(_plcCodeBlockTable).insert(
            PlcCodeBlockTableCompanion.insert(
              assetKey: assetKey,
              blockName: block.name,
              blockType: block.type,
              filePath: block.filePath,
              declaration: block.declaration,
              implementation: Value(block.implementation),
              fullSource: block.fullSource,
              parentBlockId: const Value(null),
              indexedAt: DateTime.now(),
              vendorType: Value(vendorType),
              serverAlias: Value(serverAlias),
            ),
          );

      // Insert variables with qualified name = blockName.variableName.
      for (final v in block.variables) {
        await _db.into(_plcVariableTable).insert(
              PlcVariableTableCompanion.insert(
                blockId: blockId,
                variableName: v.name,
                variableType: v.type,
                section: v.section,
                qualifiedName: '${block.name}.${v.name}',
                comment: Value(v.comment),
              ),
            );
      }

      // Insert child blocks (methods, actions, properties, transitions).
      for (final child in block.children) {
        final childFullSource = [
          child.declaration,
          if (child.implementation != null) child.implementation,
        ].join('\n');

        await _db.into(_plcCodeBlockTable).insert(
              PlcCodeBlockTableCompanion.insert(
                assetKey: assetKey,
                blockName: child.name,
                blockType: child.childType,
                filePath: block.filePath,
                declaration: child.declaration,
                implementation: Value(child.implementation),
                fullSource: childFullSource,
                parentBlockId: Value(blockId),
                indexedAt: DateTime.now(),
                vendorType: Value(vendorType),
                serverAlias: Value(serverAlias),
              ),
            );
      }
    }

    // Build call graph from the inserted blocks (re-read to get DB IDs).
    final dbBlocks = await getBlocksForAsset(assetKey);
    if (dbBlocks.isNotEmpty) {
      final callGraph = CallGraphBuilder().build(dbBlocks);

      // Build blockName -> blockId map for FK lookups.
      final blockNameToId = <String, int>{};
      for (final b in dbBlocks) {
        blockNameToId[b.blockName] = b.id;
      }

      // Populate plc_var_ref table.
      for (final ref in callGraph.references) {
        final blockId = blockNameToId[ref.blockName];
        if (blockId == null) continue;
        await _db.into(_plcVarRefTable).insert(
          PlcVarRefTableCompanion.insert(
            blockId: blockId,
            variablePath: ref.variablePath,
            kind: ref.kind.name, // "read", "write", or "call"
            lineNumber: Value(ref.lineNumber),
            sourceLine: Value(ref.sourceLine),
          ),
        );
      }

      // Populate plc_fb_instance table.
      for (final fb in callGraph.fbInstances) {
        final blockId = blockNameToId[fb.declaringBlock];
        if (blockId == null) continue;
        await _db.into(_plcFbInstanceTable).insert(
          PlcFbInstanceTableCompanion.insert(
            declaringBlockId: blockId,
            instanceName: fb.instanceName,
            fbTypeName: fb.fbTypeName,
          ),
        );
      }

      // Populate plc_block_call table from "call" references.
      for (final ref in callGraph.references) {
        if (ref.kind != ReferenceKind.call) continue;
        final blockId = blockNameToId[ref.blockName];
        if (blockId == null) continue;
        // Extract the callee block name from the variable path.
        // For call references, variablePath is like "MAIN.fbInstance" —
        // the last segment before any dot-member is the callee.
        final calleeName = ref.variablePath.contains('.')
            ? ref.variablePath.split('.').last
            : ref.variablePath;
        await _db.into(_plcBlockCallTable).insert(
          PlcBlockCallTableCompanion.insert(
            callerBlockId: blockId,
            calleeBlockName: calleeName,
            lineNumber: Value(ref.lineNumber),
          ),
        );
      }
    }

    _isEmptyCache = false;
    _isInitialized = true;
  }

  @override
  Future<List<PlcCodeBlock>> getBlocksForAsset(String assetKey) async {
    await _ensureInitialized();

    final rows = await (_db.select(_plcCodeBlockTable)
          ..where((t) => t.assetKey.equals(assetKey)))
        .get();

    final blocks = <PlcCodeBlock>[];
    for (final row in rows) {
      final variables = await (_db.select(_plcVariableTable)
            ..where((t) => t.blockId.equals(row.id)))
          .get();

      blocks.add(PlcCodeBlock(
        id: row.id,
        assetKey: row.assetKey,
        blockName: row.blockName,
        blockType: row.blockType,
        filePath: row.filePath,
        declaration: row.declaration,
        implementation: row.implementation,
        fullSource: row.fullSource,
        indexedAt: row.indexedAt,
        vendorType: row.vendorType,
        serverAlias: row.serverAlias,
        parentBlockId: row.parentBlockId,
        variables: variables
            .map((v) => PlcVariable(
                  id: v.id,
                  blockId: v.blockId,
                  variableName: v.variableName,
                  variableType: v.variableType,
                  section: v.section,
                  qualifiedName: v.qualifiedName,
                  comment: v.comment,
                ))
            .toList(),
      ));
    }

    return blocks;
  }

  @override
  Future<void> deleteAssetIndex(String assetKey) async {
    // Get all block IDs for this asset to delete their variables.
    final blocks = await (_db.select(_plcCodeBlockTable)
          ..where((t) => t.assetKey.equals(assetKey)))
        .get();
    final blockIds = blocks.map((b) => b.id).toList();

    // Delete call graph data for all blocks of this asset.
    for (final id in blockIds) {
      await (_db.delete(_plcVarRefTable)..where((t) => t.blockId.equals(id)))
          .go();
      await (_db.delete(_plcFbInstanceTable)
            ..where((t) => t.declaringBlockId.equals(id)))
          .go();
      await (_db.delete(_plcBlockCallTable)
            ..where((t) => t.callerBlockId.equals(id)))
          .go();
    }

    // Delete variables for all blocks of this asset.
    for (final id in blockIds) {
      await (_db.delete(_plcVariableTable)..where((t) => t.blockId.equals(id)))
          .go();
    }

    // Delete blocks for this asset.
    await (_db.delete(_plcCodeBlockTable)
          ..where((t) => t.assetKey.equals(assetKey)))
        .go();

    // Update isEmpty cache by recounting.
    final remaining = await (_db.selectOnly(_plcCodeBlockTable)
          ..addColumns([_plcCodeBlockTable.id.count()]))
        .map((row) => row.read(_plcCodeBlockTable.id.count()))
        .getSingle();
    _isEmptyCache = (remaining ?? 0) == 0;
    _isInitialized = true;
  }

  @override
  Future<PlcCodeBlock?> getBlock(int blockId) async {
    final row = await (_db.select(_plcCodeBlockTable)
          ..where((t) => t.id.equals(blockId)))
        .getSingleOrNull();
    if (row == null) return null;

    final variables = await (_db.select(_plcVariableTable)
          ..where((t) => t.blockId.equals(blockId)))
        .get();

    return PlcCodeBlock(
      id: row.id,
      assetKey: row.assetKey,
      blockName: row.blockName,
      blockType: row.blockType,
      filePath: row.filePath,
      declaration: row.declaration,
      implementation: row.implementation,
      fullSource: row.fullSource,
      indexedAt: row.indexedAt,
      vendorType: row.vendorType,
      serverAlias: row.serverAlias,
      parentBlockId: row.parentBlockId,
      variables: variables
          .map((v) => PlcVariable(
                id: v.id,
                blockId: v.blockId,
                variableName: v.variableName,
                variableType: v.variableType,
                section: v.section,
                qualifiedName: v.qualifiedName,
                comment: v.comment,
              ))
          .toList(),
    );
  }

  @override
  Future<List<PlcCodeSearchResult>> search(
    String query, {
    String mode = 'text',
    String? assetFilter,
    String? serverAlias,
    int limit = 20,
  }) async {
    await _ensureInitialized();

    final q = query.toLowerCase();
    final results = <PlcCodeSearchResult>[];

    switch (mode) {
      case 'key':
        // Search by qualified name (OPC UA s= path correlation).
        final varQuery = _db.select(_plcVariableTable).join([
          innerJoin(
            _plcCodeBlockTable,
            _plcCodeBlockTable.id.equalsExp(_plcVariableTable.blockId),
          ),
        ]);
        if (assetFilter != null) {
          varQuery.where(_plcCodeBlockTable.assetKey.equals(assetFilter));
        }
        if (serverAlias != null) {
          varQuery.where(_plcCodeBlockTable.serverAlias.equals(serverAlias));
        }
        final varRows = await varQuery.get();

        for (final row in varRows) {
          final variable = row.readTable(_plcVariableTable);
          final block = row.readTable(_plcCodeBlockTable);

          // Match by exact, suffix, or fuzzy match against qualifiedName.
          // Suffix matching handles OPC UA paths where the query may have
          // a MAIN. prefix that the qualifiedName doesn't have. Fuzzy
          // matching handles partial queries like "GVL_Main.pump3".
          final textLower = variable.qualifiedName.toLowerCase();
          if (textLower == q ||
              q.endsWith('.$textLower') ||
              q.endsWith(textLower) ||
              fuzzyMatch(textLower, q)) {
            results.add(PlcCodeSearchResult(
              blockId: block.id,
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

      case 'variable':
        // Search by variable name.
        final varQuery = _db.select(_plcVariableTable).join([
          innerJoin(
            _plcCodeBlockTable,
            _plcCodeBlockTable.id.equalsExp(_plcVariableTable.blockId),
          ),
        ]);
        if (assetFilter != null) {
          varQuery.where(_plcCodeBlockTable.assetKey.equals(assetFilter));
        }
        if (serverAlias != null) {
          varQuery.where(_plcCodeBlockTable.serverAlias.equals(serverAlias));
        }
        final varRows = await varQuery.get();

        for (final row in varRows) {
          final variable = row.readTable(_plcVariableTable);
          final block = row.readTable(_plcCodeBlockTable);

          if (fuzzyMatch(variable.variableName.toLowerCase(), q)) {
            results.add(PlcCodeSearchResult(
              blockId: block.id,
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

      default:
        // Free-text search in fullSource (declaration + implementation).
        final blockQuery = _db.select(_plcCodeBlockTable);
        if (assetFilter != null) {
          blockQuery.where((t) => t.assetKey.equals(assetFilter));
        }
        if (serverAlias != null) {
          blockQuery.where((t) => t.serverAlias.equals(serverAlias));
        }
        final blockRows = await blockQuery.get();

        for (final block in blockRows) {
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

  @override
  Future<List<PlcAssetSummary>> getIndexSummary() async {
    await _ensureInitialized();

    // Get all blocks grouped by asset.
    final blocks = await _db.select(_plcCodeBlockTable).get();
    if (blocks.isEmpty) return [];

    // Group by assetKey.
    final byAsset = <String, List<PlcCodeBlockTableData>>{};
    for (final block in blocks) {
      byAsset.putIfAbsent(block.assetKey, () => []).add(block);
    }

    // Get all variables for counting.
    final allVariables = await _db.select(_plcVariableTable).get();
    final varsByBlock = <int, List<PlcVariableTableData>>{};
    for (final v in allVariables) {
      varsByBlock.putIfAbsent(v.blockId, () => []).add(v);
    }

    final summaries = <PlcAssetSummary>[];
    for (final entry in byAsset.entries) {
      final assetKey = entry.key;
      final assetBlocks = entry.value;

      // Count variables for this asset's blocks.
      var variableCount = 0;
      for (final block in assetBlocks) {
        variableCount += (varsByBlock[block.id]?.length ?? 0);
      }

      // Build block type counts.
      final typeCounts = <String, int>{};
      for (final block in assetBlocks) {
        typeCounts[block.blockType] = (typeCounts[block.blockType] ?? 0) + 1;
      }

      // Find latest indexedAt.
      DateTime lastIndexed = DateTime(2000);
      for (final block in assetBlocks) {
        if (block.indexedAt.isAfter(lastIndexed)) {
          lastIndexed = block.indexedAt;
        }
      }

      final firstBlock = assetBlocks.first;

      summaries.add(PlcAssetSummary(
        assetKey: assetKey,
        blockCount: assetBlocks.length,
        variableCount: variableCount,
        lastIndexedAt: lastIndexed,
        blockTypeCounts: typeCounts,
        serverAlias: firstBlock.serverAlias,
        vendorType: firstBlock.vendorType,
      ));
    }

    return summaries;
  }

  // ---------------------------------------------------------------------------
  // Call graph query methods
  // ---------------------------------------------------------------------------

  /// Get all variable references matching a path pattern.
  ///
  /// Uses SQL LIKE for suffix matching so "pump3_speed" finds
  /// "GVL_Main.pump3_speed", "MAIN.pump3_speed", etc.
  Future<List<PlcVarRefTableData>> getVarRefs(String variablePath) async {
    await _ensureInitialized();
    return (_db.select(_plcVarRefTable)
          ..where((t) => t.variablePath.like('%$variablePath')))
        .get();
  }

  /// Get all variable references originating from a specific block.
  Future<List<PlcVarRefTableData>> getVarRefsForBlock(int blockId) async {
    await _ensureInitialized();
    return (_db.select(_plcVarRefTable)
          ..where((t) => t.blockId.equals(blockId)))
        .get();
  }

  /// Get FB instance declarations, optionally filtered by type or name.
  Future<List<PlcFbInstanceTableData>> getFbInstances({
    String? fbTypeName,
    String? instanceName,
  }) async {
    await _ensureInitialized();
    final query = _db.select(_plcFbInstanceTable);
    if (fbTypeName != null) {
      query.where((t) => t.fbTypeName.equals(fbTypeName));
    }
    if (instanceName != null) {
      query.where((t) => t.instanceName.equals(instanceName));
    }
    return query.get();
  }

  /// Get all block-to-block call edges originating from a specific block.
  Future<List<PlcBlockCallTableData>> getBlockCalls(int blockId) async {
    await _ensureInitialized();
    return (_db.select(_plcBlockCallTable)
          ..where((t) => t.callerBlockId.equals(blockId)))
        .get();
  }

  /// Get all blocks that call a specific block (reverse lookup).
  Future<List<PlcBlockCallTableData>> getCallers(String blockName) async {
    await _ensureInitialized();
    return (_db.select(_plcBlockCallTable)
          ..where((t) => t.calleeBlockName.equals(blockName)))
        .get();
  }

  @override
  Future<void> renameAsset(String oldAssetKey, String newAssetKey) async {
    await _ensureInitialized();

    await (_db.update(_plcCodeBlockTable)
          ..where((t) => t.assetKey.equals(oldAssetKey)))
        .write(PlcCodeBlockTableCompanion(
      assetKey: Value(newAssetKey),
    ));
  }

  /// Re-index an asset by re-parsing stored source code and rebuilding
  /// the index.
  ///
  /// Reads existing blocks from the database, converts them back to
  /// [ParsedCodeBlock] format (preserving the original source code),
  /// deletes the old index, and re-inserts the blocks. This refreshes
  /// variable extraction and updates the indexedAt timestamp.
  ///
  /// Returns the number of blocks re-indexed, or 0 if no blocks exist.
  Future<int> reindexAsset(String assetKey) async {
    final existingBlocks = await getBlocksForAsset(assetKey);
    if (existingBlocks.isEmpty) return 0;

    final serverAlias = existingBlocks.first.serverAlias;
    final vendorType = existingBlocks.first.vendorType;

    // Separate top-level blocks from child blocks.
    final topLevelBlocks =
        existingBlocks.where((b) => b.parentBlockId == null).toList();
    final childBlocksByParent = <int, List<PlcCodeBlock>>{};
    for (final block in existingBlocks) {
      if (block.parentBlockId != null) {
        childBlocksByParent
            .putIfAbsent(block.parentBlockId!, () => [])
            .add(block);
      }
    }

    // Convert PlcCodeBlock -> ParsedCodeBlock.
    final parsedBlocks = <ParsedCodeBlock>[];
    for (final block in topLevelBlocks) {
      final children = childBlocksByParent[block.id] ?? [];
      parsedBlocks.add(ParsedCodeBlock(
        name: block.blockName,
        type: block.blockType,
        declaration: block.declaration,
        implementation: block.implementation,
        fullSource: block.fullSource,
        filePath: block.filePath,
        variables: block.variables
            .map((v) => ParsedVariable(
                  name: v.variableName,
                  type: v.variableType,
                  section: v.section,
                  comment: v.comment,
                ))
            .toList(),
        children: children
            .map((c) => ParsedChildBlock(
                  name: c.blockName,
                  childType: c.blockType,
                  declaration: c.declaration,
                  implementation: c.implementation,
                ))
            .toList(),
      ));
    }

    // Delete existing index and re-insert.
    await deleteAssetIndex(assetKey);
    await indexAsset(
      assetKey,
      parsedBlocks,
      vendorType: vendorType,
      serverAlias: serverAlias,
    );

    return parsedBlocks.length;
  }
}

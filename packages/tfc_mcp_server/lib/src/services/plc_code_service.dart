// ---------------------------------------------------------------------------
// PLC code service: orchestrates upload-parse-index pipeline and provides
// key-mapping-correlated PLC code search.
//
// Connects TwinCAT and Schneider parsers to PlcCodeIndex storage and
// adds OPC UA identifier correlation for searching PLC code by HMI key name.
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../cache/ttl_cache.dart';
import '../compiler/call_graph_builder.dart';
import '../interfaces/plc_code_index.dart';
import '../parser/schneider_xml_parser.dart';
import '../parser/twincat_zip_extractor.dart';
import '../parser/twincat_xml_parser.dart';
import '../parser/structured_text_parser.dart';

/// Supported PLC vendor types for upload processing.
enum PlcVendor {
  /// Beckhoff TwinCAT (default). Expects .zip of TcPOU/TcGVL/ST files.
  twincat,

  /// Schneider Electric Control Expert. Expects XML export (.xef or .xml).
  schneiderControlExpert,

  /// Schneider Electric Machine Expert. Expects PLCopen XML export.
  schneiderMachineExpert,
}

/// Map [PlcVendor] to database string representation.
String vendorTypeToString(PlcVendor vendor) {
  switch (vendor) {
    case PlcVendor.twincat:
      return 'twincat';
    case PlcVendor.schneiderControlExpert:
      return 'schneider_control_expert';
    case PlcVendor.schneiderMachineExpert:
      return 'schneider_machine_expert';
  }
}

/// Parse a database vendor type string back to [PlcVendor].
PlcVendor? vendorTypeFromString(String? vendorType) {
  switch (vendorType) {
    case 'twincat':
      return PlcVendor.twincat;
    case 'schneider_control_expert':
      return PlcVendor.schneiderControlExpert;
    case 'schneider_machine_expert':
      return PlcVendor.schneiderMachineExpert;
    default:
      return null; // null = legacy data, treated as twincat
  }
}

/// Abstract interface for key mapping lookup.
///
/// Implemented by [ConfigService] in production and test stubs in tests.
/// Allows [PlcCodeService] to resolve HMI key names to OPC UA identifiers
/// without depending on the database-backed [ConfigService] directly.
abstract class KeyMappingLookup {
  /// Returns key-to-OPC-UA-node mappings matching [filter].
  Future<List<Map<String, dynamic>>> listKeyMappings({
    String? filter,
    int limit = 50,
  });
}

/// Result of processing a PLC project upload.
class UploadResult {
  /// Creates an [UploadResult] with all fields.
  const UploadResult({
    required this.totalBlocks,
    required this.totalVariables,
    required this.blockTypeCounts,
    required this.skippedFiles,
    this.detectedVendor,
  });

  /// Total number of code blocks successfully parsed and indexed.
  final int totalBlocks;

  /// Total number of variables across all indexed blocks.
  final int totalVariables;

  /// Count of blocks by type (e.g. {'FunctionBlock': 3, 'GVL': 2}).
  final Map<String, int> blockTypeCounts;

  /// Number of files that failed to parse and were skipped.
  final int skippedFiles;

  /// Vendor detected or specified for this upload.
  final PlcVendor? detectedVendor;
}

/// Service for PLC code upload, indexing, and key-correlated search.
///
/// Orchestrates the full upload pipeline:
/// 1. Extract files from TwinCAT project zip or Schneider XML export
/// 2. Parse XML/ST files into [ParsedCodeBlock] models
/// 3. Store parsed blocks via [PlcCodeIndex]
///
/// Provides search methods including key-mapping correlation that resolves
/// HMI key names to PLC variable paths via OPC UA `s=` identifiers.
class PlcCodeService {
  /// Creates a [PlcCodeService] backed by the given [PlcCodeIndex] and
  /// [KeyMappingLookup] for OPC UA identifier correlation.
  PlcCodeService(this._index, this._keyMappingLookup);

  final PlcCodeIndex _index;
  final KeyMappingLookup _keyMappingLookup;

  /// Cache for search results (keyed by query:mode:assetFilter:limit).
  final _searchCache = TtlCache<String, List<PlcCodeSearchResult>>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 100,
  );

  /// Cache for code blocks (keyed by blockId).
  final _blockCache = TtlCache<int, PlcCodeBlock?>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 50,
  );

  /// Cache for index summary (static reference data).
  final _summaryCache = TtlCache<String, List<PlcAssetSummary>>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 1,
  );

  /// Cache for call graph data (keyed by assetKey).
  final _callGraphCache = TtlCache<String, CallGraphData>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 10,
  );

  /// Invalidate all PLC code caches.
  ///
  /// Call after a new PLC project is uploaded to ensure the AI
  /// sees fresh index data.
  void invalidateCache() {
    _searchCache.clear();
    _blockCache.clear();
    _summaryCache.clear();
    _callGraphCache.clear();
  }

  /// Whether any PLC code has been indexed.
  bool get hasCode => !_index.isEmpty;

  /// Process a PLC project upload for the given [assetKey].
  ///
  /// For TwinCAT (default): extracts files from [zipBytes] zip archive.
  /// For Schneider: parses [zipBytes] as XML content directly, or extracts
  /// XML files from a zip archive.
  ///
  /// [vendor] specifies the PLC vendor. If null, auto-detection is attempted.
  /// [serverAlias] is the optional StateMan server alias for OPC UA scope.
  ///
  /// Files that fail to parse (e.g. malformed XML) are skipped -- not fatal.
  /// Returns an [UploadResult] with counts of what was indexed.
  Future<UploadResult> processUpload(
    String assetKey,
    Uint8List fileBytes, {
    PlcVendor? vendor,
    String? serverAlias,
  }) async {
    // Auto-detect vendor if not specified
    final effectiveVendor = vendor ?? _autoDetectVendor(fileBytes);

    final UploadResult result;
    switch (effectiveVendor) {
      case PlcVendor.twincat:
        result = await _processTwinCatUpload(
          assetKey,
          fileBytes,
          serverAlias: serverAlias,
        );
      case PlcVendor.schneiderControlExpert:
      case PlcVendor.schneiderMachineExpert:
        result = await _processSchneiderUpload(
          assetKey,
          fileBytes,
          vendor: effectiveVendor,
          serverAlias: serverAlias,
        );
    }

    // Invalidate caches after upload so the AI sees the new index data
    invalidateCache();
    return result;
  }

  /// Process a TwinCAT project zip upload.
  Future<UploadResult> _processTwinCatUpload(
    String assetKey,
    Uint8List zipBytes, {
    String? serverAlias,
  }) async {
    // Step 1: Extract TwinCAT source files from zip
    final extractedFiles = extractTwinCatFiles(zipBytes);

    // Step 2: Parse each file by type, collecting successful results
    final blocks = <ParsedCodeBlock>[];
    var skippedFiles = 0;

    for (final file in extractedFiles) {
      try {
        ParsedCodeBlock? parsed;
        switch (file.type) {
          case TwinCatFileType.tcPou:
            parsed = parseTcPou(file.content, file.path);
          case TwinCatFileType.tcGvl:
            parsed = parseTcGvl(file.content, file.path);
          case TwinCatFileType.st:
            parsed = parseStFile(file.content, file.path);
        }
        if (parsed != null) {
          blocks.add(parsed);
        } else {
          skippedFiles++;
        }
      } catch (_) {
        skippedFiles++;
      }
    }

    // Step 3: Replace existing index and store new blocks
    await _index.deleteAssetIndex(assetKey);
    await _index.indexAsset(
      assetKey,
      blocks,
      vendorType: vendorTypeToString(PlcVendor.twincat),
      serverAlias: serverAlias,
    );

    return _buildResult(blocks, skippedFiles, PlcVendor.twincat);
  }

  /// Process a Schneider PLC XML upload.
  ///
  /// Accepts either raw XML bytes or a zip containing XML files.
  Future<UploadResult> _processSchneiderUpload(
    String assetKey,
    Uint8List fileBytes, {
    required PlcVendor vendor,
    String? serverAlias,
  }) async {
    final blocks = <ParsedCodeBlock>[];
    var skippedFiles = 0;

    // Try to decode as UTF-8 text first (raw XML file)
    String? xmlContent;
    try {
      xmlContent = utf8.decode(fileBytes);
    } catch (_) {
      // Not valid UTF-8
    }

    if (xmlContent != null && _looksLikeXml(xmlContent)) {
      // Direct XML file upload
      try {
        final parsed = parseSchneiderXml(xmlContent, 'upload.xml');
        blocks.addAll(parsed);
        if (parsed.isEmpty) skippedFiles++;
      } catch (_) {
        skippedFiles++;
      }
    } else {
      // Try as zip archive containing XML files
      try {
        final archive = ZipDecoder().decodeBytes(fileBytes);

        for (final entry in archive) {
          if (!entry.isFile) continue;
          final nameLower = entry.name.toLowerCase();

          if (nameLower.endsWith('.xml') ||
              nameLower.endsWith('.xef') ||
              nameLower.endsWith('.st')) {
            try {
              final content = String.fromCharCodes(entry.content as List<int>);

              if (nameLower.endsWith('.st')) {
                // Raw ST file
                final parsed = parseStFile(content, entry.name);
                if (parsed != null) {
                  blocks.add(parsed);
                } else {
                  skippedFiles++;
                }
              } else {
                // XML file -- try Schneider parser
                final parsed = parseSchneiderXml(content, entry.name);
                blocks.addAll(parsed);
                if (parsed.isEmpty) skippedFiles++;
              }
            } catch (_) {
              skippedFiles++;
            }
          }
        }
      } catch (_) {
        // Not a valid zip -- if we had XML content, try one more time
        if (xmlContent != null) {
          try {
            final parsed = parseSchneiderXml(xmlContent, 'upload.xml');
            blocks.addAll(parsed);
            if (parsed.isEmpty) skippedFiles++;
          } catch (_) {
            skippedFiles++;
          }
        } else {
          skippedFiles++;
        }
      }
    }

    // Replace existing index and store new blocks
    await _index.deleteAssetIndex(assetKey);
    await _index.indexAsset(
      assetKey,
      blocks,
      vendorType: vendorTypeToString(vendor),
      serverAlias: serverAlias,
    );

    return _buildResult(blocks, skippedFiles, vendor);
  }

  /// Auto-detect vendor from file content.
  ///
  /// Checks for Schneider XML markers first, falls back to TwinCAT.
  PlcVendor _autoDetectVendor(Uint8List fileBytes) {
    // Try to read as text for XML detection
    String? content;
    try {
      content = utf8.decode(fileBytes, allowMalformed: true);
    } catch (_) {
      return PlcVendor.twincat; // Binary zip, assume TwinCAT
    }

    final format = detectSchneiderFormat(content);
    if (format != null) {
      return format == SchneiderFormat.controlExpert
          ? PlcVendor.schneiderControlExpert
          : PlcVendor.schneiderMachineExpert;
    }

    return PlcVendor.twincat;
  }

  /// Check if a string looks like XML content.
  bool _looksLikeXml(String content) {
    final trimmed = content.trimLeft();
    return trimmed.startsWith('<?xml') || trimmed.startsWith('<');
  }

  /// Build an [UploadResult] from parsed blocks.
  UploadResult _buildResult(
    List<ParsedCodeBlock> blocks,
    int skippedFiles,
    PlcVendor vendor,
  ) {
    final blockTypeCounts = <String, int>{};
    var totalVariables = 0;

    for (final block in blocks) {
      blockTypeCounts[block.type] = (blockTypeCounts[block.type] ?? 0) + 1;
      totalVariables += block.variables.length;
    }

    return UploadResult(
      totalBlocks: blocks.length,
      totalVariables: totalVariables,
      blockTypeCounts: blockTypeCounts,
      skippedFiles: skippedFiles,
      detectedVendor: vendor,
    );
  }

  /// Search PLC code with the given [query].
  ///
  /// Results are cached for 30 minutes since PLC code is static reference
  /// data. Cache is invalidated automatically after new uploads.
  ///
  /// [serverAlias] scopes results to blocks from a specific PLC server,
  /// preventing cross-PLC collisions when two PLCs share variable names.
  Future<List<PlcCodeSearchResult>> search(
    String query, {
    String mode = 'text',
    String? assetFilter,
    String? serverAlias,
    int limit = 20,
  }) {
    final cacheKey =
        'search:$query:$mode:${assetFilter ?? ''}:${serverAlias ?? ''}:$limit';
    return _searchCache.getOrCompute(cacheKey, () {
      return _index.search(
        query,
        mode: mode,
        assetFilter: assetFilter,
        serverAlias: serverAlias,
        limit: limit,
      );
    });
  }

  /// Search PLC code by HMI key name via OPC UA identifier correlation.
  ///
  /// 1. Looks up key mappings matching [keyName]
  /// 2. Extracts PLC variable path from OPC UA `s=` identifier
  /// 3. Extracts `server_alias` from key mapping to scope search to the
  ///    correct PLC (avoids cross-PLC collisions when two PLCs share
  ///    the same variable name, e.g. `GVL_Main.speed`)
  /// 4. Searches index in 'key' mode for exact match
  /// 5. Falls back to 'variable' mode for fuzzy matches
  ///
  /// Returns empty list if no mappings found, all identifiers are numeric,
  /// or the key is Modbus/M2400 with no OPC UA identifier.
  Future<List<PlcCodeSearchResult>> searchByKey(
    String keyName, {
    int limit = 20,
  }) async {
    // Look up key mappings for this key name
    final mappings = await _keyMappingLookup.listKeyMappings(
      filter: keyName,
      limit: 10,
    );

    if (mappings.isEmpty) return [];

    final allResults = <PlcCodeSearchResult>[];
    final seenBlockIds = <int>{};

    for (final mapping in mappings) {
      final identifier = mapping['identifier'] as String?;
      if (identifier == null) continue;

      final variablePath = extractPlcVariablePath(identifier);
      if (variablePath == null) continue;

      // Extract server_alias from key mapping to scope search to the
      // correct PLC server. Null means no scoping (backwards compat).
      final serverAlias = mapping['server_alias'] as String?;

      // Try exact match via 'key' mode
      final keyResults = await _index.search(
        variablePath,
        mode: 'key',
        serverAlias: serverAlias,
        limit: limit,
      );

      for (final r in keyResults) {
        if (seenBlockIds.add(r.blockId)) {
          allResults.add(r);
        }
      }

      // If no exact results, try fuzzy via 'variable' mode.
      // Extract just the variable name (last segment) for variable-mode
      // search — the full OPC-UA path like "MAIN.GarageDoor.p_stat_uposition"
      // won't fuzzy-match against just "p_stat_uposition".
      if (keyResults.isEmpty) {
        final varName = variablePath.contains('.')
            ? variablePath.split('.').last
            : variablePath;
        final fuzzyResults = await _index.search(
          varName,
          mode: 'variable',
          serverAlias: serverAlias,
          limit: limit,
        );

        for (final r in fuzzyResults) {
          if (seenBlockIds.add(r.blockId)) {
            allResults.add(r);
          }
        }
      }
    }

    if (allResults.length > limit) {
      return allResults.sublist(0, limit);
    }
    return allResults;
  }

  /// Extract the PLC variable path from an OPC UA identifier string.
  ///
  /// Handles three formats:
  /// - Full OPC UA: `"ns=4;s=GVL_Main.pump3_speed"` -> `"GVL_Main.pump3_speed"`
  /// - String-only: `"s=GVL_Main.pump3_speed"` -> `"GVL_Main.pump3_speed"`
  /// - Plain path:  `"GVL_Main.pump3_speed"` -> `"GVL_Main.pump3_speed"`
  ///
  /// Returns `null` for numeric identifiers (`i=`) since they cannot
  /// be correlated to PLC variable names.
  static String? extractPlcVariablePath(String opcUaIdentifier) {
    String? path;
    // Look for ";s=" to avoid matching "ns=" prefix
    final semiSIndex = opcUaIdentifier.indexOf(';s=');
    if (semiSIndex != -1) {
      path = opcUaIdentifier.substring(semiSIndex + 3);
    }
    // Handle case where identifier starts with "s=" (no namespace prefix)
    else if (opcUaIdentifier.startsWith('s=')) {
      path = opcUaIdentifier.substring(2);
    }
    // Reject numeric identifiers (ns=N;i=NNN or i=NNN)
    else if (opcUaIdentifier.contains('i=')) {
      return null;
    }
    // Plain identifier with no OPC UA prefix — treat as variable path directly.
    else if (opcUaIdentifier.isNotEmpty) {
      path = opcUaIdentifier;
    }
    if (path == null) return null;
    // Strip array indices — OPC-UA identifiers may include subscripts
    // (e.g. "Sensor.Mapped_values[2]") but PLC variable declarations
    // and code references use the base name without indices.
    return path.replaceAll(RegExp(r'\[\d+\]'), '');
  }

  /// Get HMI keys whose OPC UA identifier maps to the given PLC variable.
  ///
  /// Searches all key mappings for identifiers containing `s=[plcVariablePath]`.
  /// This enables reverse lookup: given a PLC variable name, find which HMI
  /// keys are wired to it.
  Future<List<Map<String, dynamic>>> getCorrelatedKeys(
    String plcVariablePath,
  ) async {
    final allMappings = await _keyMappingLookup.listKeyMappings(limit: 500);

    return allMappings.where((mapping) {
      final identifier = mapping['identifier'] as String?;
      if (identifier == null) return false;

      final varPath = extractPlcVariablePath(identifier);
      if (varPath == null) return false;

      // Exact match or suffix match (e.g. path is "pump3_speed" and
      // varPath is "GVL_Main.pump3_speed")
      return varPath == plcVariablePath ||
          varPath.endsWith('.$plcVariablePath');
    }).toList();
  }

  /// Get full code block content by [blockId].
  ///
  /// Block content is cached for 5 minutes since PLC code only changes
  /// on upload.
  Future<PlcCodeBlock?> getBlock(int blockId) {
    return _blockCache.getOrCompute(blockId, () {
      return _index.getBlock(blockId);
    });
  }

  /// Get per-asset summary of all indexed code.
  ///
  /// Summary is cached for 5 minutes since it only changes on upload.
  Future<List<PlcAssetSummary>> getIndexSummary() {
    return _summaryCache.getOrCompute('summary', () {
      return _index.getIndexSummary();
    });
  }

  /// Build a call graph from all indexed blocks for an asset.
  ///
  /// The call graph is cached for 30 minutes and invalidated on upload.
  /// Uses the ST AST parser to extract variable references from
  /// implementation bodies.
  Future<CallGraphData> buildCallGraph(String assetKey) {
    return _callGraphCache.getOrCompute(assetKey, () async {
      final blocks = await _index.getBlocksForAsset(assetKey);
      final builder = CallGraphBuilder();
      return builder.build(blocks);
    });
  }

  /// Get all code blocks for a specific asset.
  ///
  /// Returns full [PlcCodeBlock] objects for every block indexed under
  /// [assetKey]. Delegates to the underlying [PlcCodeIndex].
  Future<List<PlcCodeBlock>> getBlocksForAsset(String assetKey) {
    return _index.getBlocksForAsset(assetKey);
  }

  /// Get aggregated context for a variable.
  ///
  /// Returns a map with declaring block, all readers, all writers,
  /// FB type info (if the variable is an FB instance), and related
  /// variables.
  ///
  /// Returns null if the variable is not found.
  Future<Map<String, dynamic>?> getVariableContext(
    String variablePath, {
    required String assetKey,
  }) async {
    final callGraph = await buildCallGraph(assetKey);
    return callGraph.getVariableContext(variablePath);
  }
}

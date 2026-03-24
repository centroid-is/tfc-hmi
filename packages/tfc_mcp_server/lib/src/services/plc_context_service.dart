// ---------------------------------------------------------------------------
// PLC context service: pre-computes all PLC context for an asset's keys.
//
// Ties together key mappings, PlcCodeService (search + call graph), and
// CallGraphBuilder to resolve HMI keys through to PLC variables, code
// blocks, readers, writers, and FB instance info in a single call.
// ---------------------------------------------------------------------------

import '../compiler/call_graph_builder.dart';
import '../interfaces/plc_code_index.dart';
import '../interfaces/server_alias_provider.dart';
import 'plc_code_service.dart';

/// Complete PLC context resolved for a set of HMI keys.
class PlcContext {
  /// Creates a [PlcContext] with resolved and unresolved keys.
  const PlcContext({
    required this.resolvedKeys,
    required this.unresolvedKeys,
  });

  /// Keys that were successfully resolved to PLC code context.
  final List<ResolvedKey> resolvedKeys;

  /// Keys that could not be resolved (Modbus, M2400, no mapping, etc.).
  final List<UnresolvedKey> unresolvedKeys;
}

/// A key that was successfully resolved to PLC code context.
class ResolvedKey {
  /// Creates a [ResolvedKey] with all context fields.
  ResolvedKey({
    required this.hmiKey,
    required this.serverAlias,
    required this.plcVariablePath,
    this.declaringBlock,
    this.declaringBlockType,
    this.variableType,
    required this.readers,
    required this.writers,
    this.fbInstance,
    this.bitMask,
    this.bitShift,
    this.declarationLine,
  });

  /// The original HMI key name (e.g. "pump3.speed").
  final String hmiKey;

  /// The StateMan server alias for this PLC (e.g. "TwinCAT_PLC1").
  final String serverAlias;

  /// The PLC variable path extracted from OPC-UA identifier
  /// (e.g. "GVL_Main.pump3_speed").
  final String plcVariablePath;

  /// The block where this variable is declared (e.g. "GVL_Main").
  final String? declaringBlock;

  /// The type of the declaring block (e.g. "GVL", "FunctionBlock").
  final String? declaringBlockType;

  /// The declared type of the variable (e.g. "REAL", "BOOL").
  final String? variableType;

  /// Code blocks that read this variable.
  ///
  /// Each reference includes [VariableReference.lineNumber] and
  /// [VariableReference.sourceLine] when available, enabling compact
  /// one-line-per-edge call graph output.
  final List<VariableReference> readers;

  /// Code blocks that write this variable.
  ///
  /// Each reference includes [VariableReference.lineNumber] and
  /// [VariableReference.sourceLine] when available.
  final List<VariableReference> writers;

  /// If this variable is related to an FB instance member.
  final FbInstanceInfo? fbInstance;

  /// Optional bit mask for extracting bits from a word register.
  /// When non-null, indicates that this key reads specific bit(s) from the PLC variable.
  final int? bitMask;

  /// Bit shift applied after masking (position of lowest set bit in mask).
  final int? bitShift;

  /// The declaration line of this variable in the declaring block
  /// (e.g. "pump3_speed : REAL;"). Null when not found.
  final String? declarationLine;
}

/// A key that could not be resolved to PLC code.
class UnresolvedKey {
  /// Creates an [UnresolvedKey] with reason information.
  const UnresolvedKey({
    required this.hmiKey,
    this.protocol,
    this.reason,
  });

  /// The original HMI key name.
  final String hmiKey;

  /// The protocol if known ('opcua', 'modbus', 'm2400').
  final String? protocol;

  /// Human-readable reason for not resolving.
  final String? reason;
}

/// Information about an FB instance member relationship.
class FbInstanceInfo {
  /// Creates an [FbInstanceInfo].
  const FbInstanceInfo({
    required this.instanceName,
    required this.fbTypeName,
    this.memberName,
    this.memberSection,
  });

  /// The instance variable name (e.g. "pump3").
  final String instanceName;

  /// The FB type name (e.g. "FB_PumpControl").
  final String fbTypeName;

  /// The member name if the variable maps to an FB member (e.g. "speed").
  final String? memberName;

  /// The VAR section of the member (e.g. "VAR_OUTPUT").
  final String? memberSection;
}

/// Service that resolves HMI keys to complete PLC code context.
///
/// Given a list of HMI key names, this service:
/// 1. Looks up key mappings to find OPC-UA identifiers
/// 2. Extracts PLC variable paths from the identifiers
/// 3. Uses searchByKey to find matching code blocks
/// 4. Builds call graphs to find readers/writers
/// 5. Resolves FB instance relationships
///
/// Non-OPC-UA keys (Modbus, M2400) or keys without mappings are
/// tracked as unresolved with reason information.
class PlcContextService {
  /// Creates a [PlcContextService] backed by the given services.
  ///
  /// When [serverAliasProvider] is given, it is used to resolve the server
  /// alias for keys whose key mapping has no explicit `server_alias` field.
  /// If the provider reports exactly one active server, that alias is used
  /// as the default. Otherwise the service falls back to `'unknown'`.
  PlcContextService(
    this._plcCodeService,
    this._keyMappingLookup, {
    ServerAliasProvider? serverAliasProvider,
  }) : _serverAliasProvider = serverAliasProvider;

  final PlcCodeService _plcCodeService;
  final KeyMappingLookup _keyMappingLookup;
  final ServerAliasProvider? _serverAliasProvider;

  /// Resolve all given HMI [keys] to PLC code context.
  ///
  /// Returns a [PlcContext] with resolved keys (those that have PLC code)
  /// and unresolved keys (Modbus, M2400, no mapping, etc.).
  Future<PlcContext> resolveKeys(List<String> keys) async {
    if (keys.isEmpty) {
      return const PlcContext(resolvedKeys: [], unresolvedKeys: []);
    }

    final resolvedKeys = <ResolvedKey>[];
    final unresolvedKeys = <UnresolvedKey>[];

    // Step 1: Classify each key by looking up its mapping.
    final opcuaKeys = <_OpcUaKeyInfo>[];

    for (final key in keys) {
      final mappings = await _keyMappingLookup.listKeyMappings(
        filter: key,
        limit: 10,
      );

      if (mappings.isEmpty) {
        unresolvedKeys.add(UnresolvedKey(
          hmiKey: key,
          reason: 'no key mapping found',
        ));
        continue;
      }

      // Find the best mapping for this key (exact match preferred).
      final exactMatch = mappings.where(
        (m) => (m['key'] as String).toLowerCase() == key.toLowerCase(),
      );
      final mapping =
          exactMatch.isNotEmpty ? exactMatch.first : mappings.first;

      final protocol = mapping['protocol'] as String?;

      if (protocol == 'modbus') {
        unresolvedKeys.add(UnresolvedKey(
          hmiKey: key,
          protocol: 'modbus',
          reason: 'Modbus device (no PLC code available)',
        ));
        continue;
      }

      if (protocol == 'm2400') {
        unresolvedKeys.add(UnresolvedKey(
          hmiKey: key,
          protocol: 'm2400',
          reason: 'M2400 device (no PLC code available)',
        ));
        continue;
      }

      // OPC-UA: extract the PLC variable path.
      final identifier = mapping['identifier'] as String?;
      if (identifier == null) {
        unresolvedKeys.add(UnresolvedKey(
          hmiKey: key,
          protocol: protocol,
          reason: 'no identifier in key mapping',
        ));
        continue;
      }

      final variablePath =
          PlcCodeService.extractPlcVariablePath(identifier);
      if (variablePath == null) {
        unresolvedKeys.add(UnresolvedKey(
          hmiKey: key,
          protocol: 'opcua',
          reason: 'numeric identifier (cannot resolve to PLC variable)',
        ));
        continue;
      }

      final serverAlias = mapping['server_alias'] as String? ??
          _resolveDefaultAlias();

      opcuaKeys.add(_OpcUaKeyInfo(
        hmiKey: key,
        serverAlias: serverAlias,
        variablePath: variablePath,
        bitMask: mapping['bit_mask'] as int?,
        bitShift: mapping['bit_shift'] as int?,
      ));
    }

    // Step 2: For each OPC-UA key, search for matching code blocks to
    // find the asset key, then build call graphs.
    //
    // Cache call graphs and asset blocks by asset key to avoid redundant builds.
    final callGraphCache = <String, CallGraphData>{};
    final assetBlocksCache = <String, Map<String, PlcCodeBlock>>{};

    for (final keyInfo in opcuaKeys) {
      // Use searchByKey to find the code block containing this variable.
      // This leverages the existing PlcCodeService key correlation logic.
      final searchResults = await _plcCodeService.searchByKey(keyInfo.hmiKey);

      if (searchResults.isEmpty) {
        // No code found — still mark as resolved if we have mapping info,
        // just without code context.
        unresolvedKeys.add(UnresolvedKey(
          hmiKey: keyInfo.hmiKey,
          protocol: 'opcua',
          reason: 'no PLC code found for variable ${keyInfo.variablePath}',
        ));
        continue;
      }

      // Get the asset key from the first search result.
      final assetKey = searchResults.first.assetKey;

      // Build or retrieve cached call graph for this asset.
      final callGraph = callGraphCache[assetKey] ??=
          await _plcCodeService.buildCallGraph(assetKey);

      // Build or retrieve cached block-name-to-block map for source snippets.
      if (!assetBlocksCache.containsKey(assetKey)) {
        final blocks = await _plcCodeService.getBlocksForAsset(assetKey);
        assetBlocksCache[assetKey] = {
          for (final b in blocks) b.blockName: b,
        };
      }
      final blocksByName = assetBlocksCache[assetKey]!;

      // Get variable context from call graph.
      final varContext =
          callGraph.getVariableContext(keyInfo.variablePath);

      // Get readers and writers from call graph.
      final refs = callGraph.getReferences(keyInfo.variablePath);
      final readers =
          refs.where((r) => r.kind == ReferenceKind.read).toList();
      final writers =
          refs.where((r) => r.kind == ReferenceKind.write).toList();

      // Enrich references with line numbers and source lines.
      final enrichedReaders = _enrichReferences(readers, blocksByName,
          keyInfo.variablePath);
      final enrichedWriters = _enrichReferences(writers, blocksByName,
          keyInfo.variablePath);

      // Look up FB instance info if available.
      final fbInstance = _findFbInstanceInfo(callGraph, keyInfo.variablePath);

      // Get block type from search result or inference.
      String? declaringBlockType;
      if (varContext != null) {
        final declaringBlock = varContext['declaringBlock'] as String?;
        // Try to find the block type from the search results.
        for (final result in searchResults) {
          if (result.blockName == declaringBlock) {
            declaringBlockType = result.blockType;
            break;
          }
        }
        // Fallback: infer from name convention.
        declaringBlockType ??= _inferBlockType(declaringBlock);
      }

      // Find the declaration line for this variable in the declaring block.
      final declBlockName = varContext?['declaringBlock'] as String?;
      final declLine = _findDeclarationLine(
          declBlockName, keyInfo.variablePath, blocksByName);

      resolvedKeys.add(ResolvedKey(
        hmiKey: keyInfo.hmiKey,
        serverAlias: keyInfo.serverAlias,
        plcVariablePath: keyInfo.variablePath,
        declaringBlock: declBlockName,
        declaringBlockType: declaringBlockType,
        variableType: varContext?['variableType'] as String? ??
            searchResults.first.variableType,
        readers: enrichedReaders,
        writers: enrichedWriters,
        fbInstance: fbInstance,
        bitMask: keyInfo.bitMask,
        bitShift: keyInfo.bitShift,
        declarationLine: declLine,
      ));
    }

    return PlcContext(
      resolvedKeys: resolvedKeys,
      unresolvedKeys: unresolvedKeys,
    );
  }

  /// Format resolved PLC context for LLM consumption.
  ///
  /// Produces a compact call-graph output grouped by server alias.
  /// Each variable gets a one-line declaration, then one line per
  /// reader/writer edge showing the block name, line number, and
  /// the actual source line at that reference. This is much more
  /// compact than embedding full source blocks.
  ///
  /// The LLM can call `get_plc_code_block(block_name)` to fetch
  /// full source for any block listed in the output.
  String formatForLlm(PlcContext context) {
    if (context.resolvedKeys.isEmpty && context.unresolvedKeys.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();

    // Group resolved keys by server alias.
    if (context.resolvedKeys.isNotEmpty) {
      final byServer = <String, List<ResolvedKey>>{};
      for (final key in context.resolvedKeys) {
        byServer.putIfAbsent(key.serverAlias, () => []).add(key);
      }

      for (final entry in byServer.entries) {
        final serverAlias = entry.key;
        final keys = entry.value;

        if (serverAlias == 'unknown') {
          buffer.writeln('[PLC CONTEXT]');
        } else {
          buffer.writeln('[PLC CONTEXT - $serverAlias]');
        }
        buffer.writeln();

        // Each resolved key as a compact call graph
        for (final key in keys) {
          final typeStr =
              key.variableType != null ? ' (${key.variableType})' : '';
          final bitStr = _formatBitInfo(key.bitMask, key.bitShift);
          final declBlockStr = key.declaringBlock != null
              ? ' declared @ ${key.declaringBlock}'
              : '';
          final declLineStr = key.declarationLine != null
              ? '  |  ${key.declarationLine}'
              : '';

          // Header line: key -> variable (TYPE) declared @ BLOCK
          buffer.writeln(
              '${key.hmiKey} \u2192 ${key.plcVariablePath}$typeStr$bitStr$declBlockStr$declLineStr');

          // FB instance info (compact, same indentation as edges)
          if (key.fbInstance != null) {
            final fb = key.fbInstance!;
            final memberStr = fb.memberName != null
                ? '.${fb.memberName}'
                : '';
            final sectionStr = fb.memberSection != null
                ? ' (${fb.memberSection})'
                : '';
            buffer.writeln(
                '  FB: ${fb.instanceName} is ${fb.fbTypeName}$memberStr$sectionStr');
          }

          // Writer edges: one line each
          for (final w in key.writers) {
            final lineStr = w.lineNumber != null ? ':${w.lineNumber}' : '';
            final srcStr = w.sourceLine != null ? '  |  ${w.sourceLine}' : '';
            buffer.writeln(
                '  \u2190 ${w.blockName}$lineStr writes$srcStr');
          }

          // Reader edges: one line each
          for (final r in key.readers) {
            final lineStr = r.lineNumber != null ? ':${r.lineNumber}' : '';
            final srcStr = r.sourceLine != null ? '  |  ${r.sourceLine}' : '';
            buffer.writeln(
                '  \u2190 ${r.blockName}$lineStr reads$srcStr');
          }

          if (key.readers.isEmpty && key.writers.isEmpty && key.fbInstance == null) {
            buffer.writeln('  (variable found in index, no call graph data available)');
          }

          buffer.writeln();
        }

        final hasBlockRefs = keys.any((k) => k.readers.isNotEmpty || k.writers.isNotEmpty);
        if (hasBlockRefs) {
          buffer.writeln(
              'Use get_plc_code_block(block_name) to fetch full source for any block listed above.');
          buffer.writeln();
        }
      }
    }

    // Unresolved keys section
    if (context.unresolvedKeys.isNotEmpty) {
      buffer.writeln('[NON-PLC KEYS]');
      for (final key in context.unresolvedKeys) {
        final protocolStr = key.protocol != null
            ? _protocolDisplayName(key.protocol!)
            : 'Unknown protocol';
        final reasonStr =
            key.reason != null ? ' (${key.reason})' : '';
        buffer.writeln('  ${key.hmiKey} \u2192 $protocolStr$reasonStr');
      }
    }

    return buffer.toString().trimRight();
  }

  /// Resolves a default server alias when the key mapping has no explicit one.
  ///
  /// If a [ServerAliasProvider] is available and reports exactly one active
  /// server, returns that server's alias. Otherwise returns `'unknown'`.
  String _resolveDefaultAlias() {
    if (_serverAliasProvider == null) return 'unknown';
    final aliases = _serverAliasProvider.serverAliases;
    if (aliases.length == 1) return aliases.first;
    return 'unknown';
  }

  /// Enriches a list of [VariableReference]s with line numbers and
  /// source lines by scanning the implementation source of each block.
  ///
  /// For each reference, finds the first line in the block's implementation
  /// that contains the variable name (last segment of the variable path).
  /// Returns new [VariableReference] instances with [lineNumber] and
  /// [sourceLine] populated.
  List<VariableReference> _enrichReferences(
    List<VariableReference> refs,
    Map<String, PlcCodeBlock> blocksByName,
    String variablePath,
  ) {
    return refs.map((ref) {
      final block = blocksByName[ref.blockName];
      if (block == null) return ref;

      final impl = block.implementation;
      if (impl == null || impl.trim().isEmpty) return ref;

      // Search for the variable path (or its last segment for member access)
      // in the implementation source to find the line number.
      final lines = impl.split('\n');
      final varName = variablePath.split('.').last;
      // Also try matching the full path (e.g. GVL_Main.pump3_speed)
      final fullPath = variablePath;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Prefer full path match, fall back to variable name match
        if (line.contains(fullPath) || line.contains(varName)) {
          // Calculate the line number relative to the full source
          // (declaration lines come before implementation).
          final declLines = block.declaration.split('\n').length;
          final lineNumber = declLines + i + 1;
          return ref.withSourceLocation(lineNumber, line.trim());
        }
      }

      return ref;
    }).toList();
  }

  /// Finds the declaration line for a variable within its declaring block.
  ///
  /// Scans the block's declaration text for a line containing the variable
  /// name. Returns the trimmed line or null if not found.
  String? _findDeclarationLine(
    String? declBlockName,
    String variablePath,
    Map<String, PlcCodeBlock> blocksByName,
  ) {
    if (declBlockName == null) return null;
    final block = blocksByName[declBlockName];
    if (block == null) return null;

    final varName = variablePath.split('.').last;
    final lines = block.declaration.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      // Match variable declarations like "pump3_speed : REAL;"
      if (trimmed.contains(varName) &&
          !trimmed.startsWith('VAR') &&
          !trimmed.startsWith('END_VAR') &&
          !trimmed.startsWith('PROGRAM') &&
          !trimmed.startsWith('FUNCTION')) {
        return trimmed;
      }
    }
    return null;
  }

  /// Infer block type from the declaring block name.
  String? _inferBlockType(String? declaringBlock) {
    if (declaringBlock == null) return null;
    if (declaringBlock.startsWith('GVL')) return 'GVL';
    if (declaringBlock.startsWith('FB_')) return 'FunctionBlock';
    if (declaringBlock == 'MAIN') return 'Program';
    return null;
  }

  /// Find FB instance info for a variable path.
  ///
  /// Checks two cases:
  /// 1. The variable itself IS an FB instance (e.g. `MAIN.pump3` where
  ///    pump3 is `FB_PumpControl`)
  /// 2. The variable is a MEMBER of an FB instance (e.g.
  ///    `MAIN.GarageDoor.p_stat_uposition` where GarageDoor is
  ///    `FB_GarageDoor` and p_stat_uposition is a VAR_OUTPUT)
  ///
  /// For case 2, walks up the path segments to find an FB instance
  /// parent, then returns info about the instance + member.
  FbInstanceInfo? _findFbInstanceInfo(
      CallGraphData callGraph, String variablePath) {
    final parts = variablePath.split('.');
    if (parts.length < 2) return null;

    // Case 1: The variable itself is an FB instance.
    final varName = parts.last;
    final context = callGraph.getVariableContext(variablePath);
    if (context != null &&
        context['isFbInstance'] == true &&
        context['fbTypeName'] != null) {
      return FbInstanceInfo(
        instanceName: varName,
        fbTypeName: context['fbTypeName'] as String,
      );
    }

    // Case 2: The variable is a member of an FB instance.
    // Walk up the path to find an FB instance parent.
    // For "MAIN.GarageDoor.p_stat_uposition", try:
    //   "MAIN.GarageDoor" — is this an FB instance?
    //   "MAIN" — is this an FB instance?
    final memberName = parts.last;
    for (var i = parts.length - 2; i >= 0; i--) {
      final candidatePath = parts.sublist(0, i + 1).join('.');
      final candidateContext = callGraph.getVariableContext(candidatePath);
      if (candidateContext != null &&
          candidateContext['isFbInstance'] == true &&
          candidateContext['fbTypeName'] != null) {
        final instanceName = parts[i]; // e.g. "GarageDoor"
        final fbTypeName = candidateContext['fbTypeName'] as String;

        return FbInstanceInfo(
          instanceName: instanceName,
          fbTypeName: fbTypeName,
          memberName: memberName,
        );
      }
    }

    return null;
  }

  /// Format bit mask/shift info for LLM display.
  ///
  /// Returns empty string when [bitMask] is null.
  /// Single-bit mask: `[bit N, mask 0xHH]`
  /// Multi-bit mask: `[bits N-M, mask 0xHH]`
  static String _formatBitInfo(int? bitMask, int? bitShift) {
    if (bitMask == null) return '';
    final shift = bitShift ?? 0;
    final hexMask = '0x${bitMask.toRadixString(16).padLeft(2, '0')}';
    // Check if single-bit (power of two)
    final isSingleBit = bitMask != 0 && (bitMask & (bitMask - 1)) == 0;
    if (isSingleBit) {
      return ' [bit $shift, mask $hexMask]';
    }
    // Multi-bit: find highest set bit position
    final highBit = bitMask.bitLength - 1;
    return ' [bits $shift-$highBit, mask $hexMask]';
  }

  /// Get a human-readable display name for a protocol.
  String _protocolDisplayName(String protocol) {
    switch (protocol) {
      case 'opcua':
        return 'OPC-UA';
      case 'modbus':
        return 'Modbus';
      case 'm2400':
        return 'M2400';
      default:
        return protocol;
    }
  }
}

/// Internal class for tracking OPC-UA key resolution info.
class _OpcUaKeyInfo {
  const _OpcUaKeyInfo({
    required this.hmiKey,
    required this.serverAlias,
    required this.variablePath,
    this.bitMask,
    this.bitShift,
  });

  final String hmiKey;
  final String serverAlias;
  final String variablePath;
  final int? bitMask;
  final int? bitShift;
}

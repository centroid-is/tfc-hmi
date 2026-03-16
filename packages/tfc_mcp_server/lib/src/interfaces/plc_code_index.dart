// ---------------------------------------------------------------------------
// PLC Code Index interface and data models.
//
// Defines the contract for PLC code search, retrieval, and indexing.
// Following the DrawingIndex pattern: abstract interface injected into
// TfcMcpServer, optional (null until Phase 8 implementation connected).
// ---------------------------------------------------------------------------

/// Metadata-only search result from the PLC code index.
///
/// Contains enough context to identify a match without returning full code.
/// Use [PlcCodeIndex.getBlock] with [blockId] to retrieve the complete code.
class PlcCodeSearchResult {
  /// Creates a [PlcCodeSearchResult] with the required metadata fields.
  const PlcCodeSearchResult({
    required this.blockId,
    required this.blockName,
    required this.blockType,
    this.variableName,
    this.variableType,
    required this.assetKey,
    this.declarationLine,
  });

  /// Database ID of the containing code block.
  final int blockId;

  /// Name of the code block (e.g. "GVL_Main", "FB_Pump").
  final String blockName;

  /// Type of the code block (e.g. "FunctionBlock", "Program", "GVL").
  final String blockType;

  /// Matched variable name, if the search matched a specific variable.
  final String? variableName;

  /// Type of the matched variable (e.g. "REAL", "BOOL").
  final String? variableType;

  /// Asset key identifying the Beckhoff equipment.
  final String assetKey;

  /// Single-line preview of the variable declaration for search context.
  final String? declarationLine;
}

/// Full PLC code block with declaration, implementation, and variables.
///
/// Returned by [PlcCodeIndex.getBlock] for detailed code inspection.
class PlcCodeBlock {
  /// Creates a [PlcCodeBlock] with all fields.
  const PlcCodeBlock({
    required this.id,
    required this.assetKey,
    required this.blockName,
    required this.blockType,
    required this.filePath,
    required this.declaration,
    this.implementation,
    required this.fullSource,
    required this.indexedAt,
    required this.variables,
    this.vendorType,
    this.serverAlias,
    this.parentBlockId,
  });

  /// Database ID of this code block.
  final int id;

  /// Asset key identifying the equipment.
  final String assetKey;

  /// Name of the code block (e.g. "GVL_Main", "FB_Pump").
  final String blockName;

  /// Type of the code block (e.g. "FunctionBlock", "Program", "GVL").
  final String blockType;

  /// Original file path within the project zip/export.
  final String filePath;

  /// Full VAR declaration text.
  final String declaration;

  /// Structured text implementation body (null for GVLs).
  final String? implementation;

  /// Complete source text (declaration + implementation).
  final String fullSource;

  /// When this block was indexed.
  final DateTime indexedAt;

  /// Variables declared within this block.
  final List<PlcVariable> variables;

  /// PLC vendor type: "twincat", "schneider_control_expert",
  /// "schneider_machine_expert". Null defaults to "twincat".
  final String? vendorType;

  /// StateMan server alias for OPC UA server scope correlation.
  final String? serverAlias;

  /// Database ID of the parent block, if this is a child block (Action,
  /// Method, Property, Transition). Null for top-level blocks.
  final int? parentBlockId;
}

/// Individual variable declaration within a PLC code block.
///
/// Represents a single variable extracted from a VAR/VAR_INPUT/etc. section.
class PlcVariable {
  /// Creates a [PlcVariable] with all fields.
  const PlcVariable({
    required this.id,
    required this.blockId,
    required this.variableName,
    required this.variableType,
    required this.section,
    required this.qualifiedName,
    this.comment,
  });

  /// Database ID of this variable.
  final int id;

  /// Database ID of the containing code block.
  final int blockId;

  /// Variable name (e.g. "pump3_speed").
  final String variableName;

  /// Variable type (e.g. "REAL", "BOOL", "INT").
  final String variableType;

  /// VAR section where this variable is declared
  /// (e.g. "VAR_INPUT", "VAR_GLOBAL", "VAR").
  final String section;

  /// Fully qualified name (e.g. "GVL_Main.pump3_speed").
  final String qualifiedName;

  /// Inline comment from the declaration, if present.
  final String? comment;
}

/// Per-asset summary of indexed PLC code.
///
/// Returned by [PlcCodeIndex.getIndexSummary] for the
/// `scada://plc/code` MCP resource.
class PlcAssetSummary {
  /// Creates a [PlcAssetSummary] with all fields.
  const PlcAssetSummary({
    required this.assetKey,
    required this.blockCount,
    required this.variableCount,
    required this.lastIndexedAt,
    required this.blockTypeCounts,
    this.serverAlias,
    this.vendorType,
  });

  /// Asset key identifying the Beckhoff equipment.
  final String assetKey;

  /// Total number of code blocks indexed for this asset.
  final int blockCount;

  /// Total number of variables indexed across all blocks.
  final int variableCount;

  /// When this asset's code was last indexed.
  final DateTime lastIndexedAt;

  /// Count of blocks by type (e.g. {'FunctionBlock': 5, 'GVL': 2}).
  final Map<String, int> blockTypeCounts;

  /// StateMan server alias (from first block).
  final String? serverAlias;

  /// PLC vendor type (e.g. "twincat", "schneider_control_expert").
  final String? vendorType;
}

// ---------------------------------------------------------------------------
// Parser input models (used by Plan 02 parsers, stored via Plan 03).
// These represent parsed output before database storage.
// ---------------------------------------------------------------------------

/// Output of XML/ST parser before database storage.
///
/// Represents a single parsed code block (POU, GVL, etc.) with its
/// variables and child blocks (methods, actions, properties, transitions).
class ParsedCodeBlock {
  /// Creates a [ParsedCodeBlock] with all fields.
  const ParsedCodeBlock({
    required this.name,
    required this.type,
    required this.declaration,
    this.implementation,
    required this.fullSource,
    required this.filePath,
    required this.variables,
    required this.children,
  });

  /// Block name (e.g. "MAIN", "FB_Pump", "GVL_Main").
  final String name;

  /// Block type: "FunctionBlock", "Program", "GVL", "Function".
  final String type;

  /// Full VAR declaration text.
  final String declaration;

  /// Structured text implementation body (null for GVLs).
  final String? implementation;

  /// Complete source text (declaration + implementation).
  final String fullSource;

  /// Original file path within the TwinCAT project zip.
  final String filePath;

  /// Variables declared within this block.
  final List<ParsedVariable> variables;

  /// Child blocks: methods, actions, properties, transitions.
  final List<ParsedChildBlock> children;
}

/// A child block within a POU (method, action, property, or transition).
///
/// POUs can contain child elements that are separate code blocks with
/// their own declarations and implementations.
class ParsedChildBlock {
  /// Creates a [ParsedChildBlock] with all fields.
  const ParsedChildBlock({
    required this.name,
    required this.childType,
    required this.declaration,
    this.implementation,
  });

  /// Child block name (e.g. "DoSomething", "Reset", "IsRunning").
  final String name;

  /// Child type: "Method", "Action", "Property", "Transition".
  final String childType;

  /// Full VAR declaration text.
  final String declaration;

  /// Structured text implementation body.
  final String? implementation;
}

/// Parser output for a single variable declaration.
///
/// Represents a variable before database storage (no IDs assigned).
class ParsedVariable {
  /// Creates a [ParsedVariable] with all fields.
  const ParsedVariable({
    required this.name,
    required this.type,
    required this.section,
    this.comment,
  });

  /// Variable name (e.g. "pump3_speed").
  final String name;

  /// Variable type (e.g. "REAL", "BOOL", "INT").
  final String type;

  /// VAR section (e.g. "VAR_INPUT", "VAR_GLOBAL", "VAR").
  final String section;

  /// Inline comment from the declaration, if present.
  final String? comment;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Read-write interface for the PLC code index.
///
/// Provides search, retrieval, and indexing of PLC structured text code
/// blocks and variables. Follows the [DrawingIndex] pattern: injected into
/// [TfcMcpServer] as an optional dependency (null until implementation
/// connected).
///
/// Search modes:
/// - `'key'`: HMI key correlation via OPC UA `s=` path
/// - `'variable'`: PLC variable name search
/// - `'text'`: Free-text search in code body and comments
abstract class PlcCodeIndex {
  /// Search PLC code blocks by query string.
  ///
  /// Returns metadata-only results. Use [getBlock] with the result's
  /// [PlcCodeSearchResult.blockId] to retrieve full code.
  ///
  /// [mode] controls search behavior:
  /// - `'key'`: correlates HMI key mapping OPC UA identifier to PLC variable
  /// - `'variable'`: searches PLC variable names directly
  /// - `'text'`: free-text search within code body and comments
  ///
  /// [assetFilter] limits results to a specific Beckhoff asset.
  /// [serverAlias] limits results to blocks from a specific PLC server.
  /// [limit] caps the number of results returned (default 20).
  Future<List<PlcCodeSearchResult>> search(
    String query, {
    String mode = 'text',
    String? assetFilter,
    String? serverAlias,
    int limit = 20,
  });

  /// Get full code block content by block ID.
  ///
  /// Returns null if no block exists with the given [blockId].
  Future<PlcCodeBlock?> getBlock(int blockId);

  /// Get per-asset summary of all indexed code.
  ///
  /// Returns one [PlcAssetSummary] per asset that has indexed code.
  Future<List<PlcAssetSummary>> getIndexSummary();

  /// Whether any PLC code has been indexed.
  ///
  /// Used to distinguish "no matches for query" from "no code indexed".
  bool get isEmpty;

  /// Store parsed code blocks and variables for an asset.
  ///
  /// Replaces any existing index for [assetKey]. The [blocks] are the
  /// output of the TwinCAT or Schneider parser pipeline.
  ///
  /// [vendorType] identifies the PLC vendor ("twincat",
  /// "schneider_control_expert", "schneider_machine_expert").
  /// [serverAlias] is the StateMan server alias for OPC UA scope.
  Future<void> indexAsset(
    String assetKey,
    List<ParsedCodeBlock> blocks, {
    String? vendorType,
    String? serverAlias,
  });

  /// Get all code blocks for a specific asset.
  ///
  /// Returns full [PlcCodeBlock] objects (including variables) for every
  /// block indexed under [assetKey]. Used by the detail panel to display
  /// all blocks without requiring a search query.
  Future<List<PlcCodeBlock>> getBlocksForAsset(String assetKey);

  /// Delete all indexed code for an asset.
  Future<void> deleteAssetIndex(String assetKey);

  /// Rename an asset by changing its asset key across all code blocks.
  ///
  /// Updates the [assetKey] column on every [PlcCodeBlock] row that
  /// matches [oldAssetKey] to [newAssetKey]. No-op if no blocks match.
  Future<void> renameAsset(String oldAssetKey, String newAssetKey);
}

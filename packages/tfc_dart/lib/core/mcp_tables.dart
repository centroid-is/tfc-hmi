// ---------------------------------------------------------------------------
// Shared MCP table definitions.
//
// These 10 table classes are owned by the MCP server layer but defined here
// in tfc_dart so that both AppDatabase (Flutter app) and ServerDatabase
// (standalone binary) can include them in their @DriftDatabase annotations
// without duplicating source code.
//
// All tables are pure Drift definitions with ZERO FFI dependencies.
// ---------------------------------------------------------------------------

import 'package:drift/drift.dart';

/// Audit log table for recording all AI tool invocations.
///
/// Stores the pre-log/post-log audit trail required by SAFE-03 and SAFE-04.
class AuditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get operatorId => text()();
  TextColumn get tool => text()();
  TextColumn get arguments => text()(); // JSON-encoded tool arguments
  TextColumn get reasoning => text().nullable()(); // AI reasoning/rationale
  TextColumn get status => text()(); // pending, success, failed, declined
  TextColumn get error => text().nullable()(); // Error message if failed
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

// ---------------------------------------------------------------------------
// PLC Code Index tables
// ---------------------------------------------------------------------------

/// PLC code blocks indexed from TwinCAT/Schneider project uploads.
///
/// Each row represents a single code block: a Function Block, Program, GVL,
/// Function, Method, Action, Property, or Transition extracted from a
/// TwinCAT project zip or Schneider XML export.
class PlcCodeBlockTable extends Table {
  @override
  String get tableName => 'plc_code_block';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetKey => text()();
  TextColumn get blockName => text()();
  TextColumn get blockType =>
      text()(); // FunctionBlock, Program, GVL, Function, Method, Action, Property, Transition
  TextColumn get filePath => text()();
  TextColumn get declaration => text()();
  TextColumn get implementation => text().nullable()();
  TextColumn get fullSource => text()();
  IntColumn get parentBlockId =>
      integer().nullable()(); // For child blocks (methods, actions, etc.)
  DateTimeColumn get indexedAt => dateTime()();

  /// PLC vendor type: "twincat", "schneider_control_expert",
  /// "schneider_machine_expert". Null defaults to "twincat" for
  /// backward compatibility with existing data.
  TextColumn get vendorType => text().nullable()();

  /// StateMan server alias linking PLC code to OPC UA server scope.
  /// Replaces direct Beckhoff asset key linkage with server-scoped
  /// correlation chain: server alias -> key mappings -> OPC UA identifiers
  /// -> PLC qualified names -> code blocks.
  TextColumn get serverAlias => text().nullable()();
}

/// Individual variable declarations within PLC code blocks.
///
/// Each row represents a single variable from a VAR/VAR_INPUT/VAR_OUTPUT/
/// VAR_IN_OUT/VAR_GLOBAL section of a code block.
class PlcVariableTable extends Table {
  @override
  String get tableName => 'plc_variable';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get blockId => integer().references(PlcCodeBlockTable, #id)();
  TextColumn get variableName => text()();
  TextColumn get variableType => text()();
  TextColumn get section =>
      text()(); // VAR, VAR_INPUT, VAR_OUTPUT, VAR_IN_OUT, VAR_GLOBAL, etc.
  TextColumn get qualifiedName => text()(); // e.g. GVL_Main.pump3_speed
  TextColumn get comment => text().nullable()();
}

// ---------------------------------------------------------------------------
// Pre-computed call graph tables
// ---------------------------------------------------------------------------

/// Variable reference edges from call graph analysis.
///
/// Each row represents a single reference to a variable from a code block's
/// implementation body. Populated during indexAsset by CallGraphBuilder.
class PlcVarRefTable extends Table {
  @override
  String get tableName => 'plc_var_ref';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get blockId => integer().references(PlcCodeBlockTable, #id)();
  TextColumn get variablePath => text()(); // e.g. "GVL_Main.pump3_speed"
  TextColumn get kind => text()(); // "read", "write", or "call"
  IntColumn get lineNumber => integer().nullable()();
  TextColumn get sourceLine => text().nullable()();
}

/// Function block instance declarations.
///
/// Each row maps an instance variable to its FB type, enabling
/// instance-to-type resolution without AST parsing at query time.
class PlcFbInstanceTable extends Table {
  @override
  String get tableName => 'plc_fb_instance';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get declaringBlockId =>
      integer().references(PlcCodeBlockTable, #id)();
  TextColumn get instanceName => text()(); // e.g. "pump3"
  TextColumn get fbTypeName => text()(); // e.g. "FB_PumpControl"
}

/// Block-to-block call edges.
///
/// Each row represents a call from one code block to another,
/// enabling call chain traversal without AST parsing.
class PlcBlockCallTable extends Table {
  @override
  String get tableName => 'plc_block_call';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get callerBlockId =>
      integer().references(PlcCodeBlockTable, #id)();
  TextColumn get calleeBlockName =>
      text()(); // e.g. "FB_PumpControl", "TON"
  IntColumn get lineNumber => integer().nullable()();
}

// ---------------------------------------------------------------------------
// Drawing Index tables
// ---------------------------------------------------------------------------

/// Electrical drawing metadata indexed from PDF uploads.
///
/// Each row represents a single drawing PDF with its asset association
/// and page count.
///
/// Supports dual-mode storage: drawings can be referenced by filesystem
/// path OR stored as blobs via the optional [pdfBytes] column.
class DrawingTable extends Table {
  @override
  String get tableName => 'drawing';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetKey => text()();
  TextColumn get drawingName => text()();
  TextColumn get filePath => text()();
  IntColumn get pageCount => integer()();
  DateTimeColumn get uploadedAt => dateTime()();

  /// Optional PDF blob storage for drawings.
  /// Nullable because existing drawings use filesystem path only.
  BlobColumn get pdfBytes => blob().nullable()();
}

/// Full-text content of individual pages within a drawing PDF.
///
/// Each row stores the OCR/extracted text for one page of a drawing,
/// enabling full-text search across all indexed drawings.
class DrawingComponentTable extends Table {
  @override
  String get tableName => 'drawing_component';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get drawingId => integer().references(DrawingTable, #id)();
  IntColumn get pageNumber => integer()();
  TextColumn get fullPageText => text()();
}

// ---------------------------------------------------------------------------
// Technical Documentation tables
// ---------------------------------------------------------------------------

/// Technical document metadata and PDF blob storage.
///
/// Each row represents a single uploaded document (manual, datasheet, etc.)
/// with its PDF stored as a blob for portability.
class TechDocTable extends Table {
  @override
  String get tableName => 'tech_doc';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BlobColumn get pdfBytes => blob()();
  IntColumn get pageCount => integer()();
  IntColumn get sectionCount => integer()();
  DateTimeColumn get uploadedAt => dateTime()();
}

/// Sections extracted from technical documents.
///
/// Each row represents a chapter, section, or subsection with its full
/// text content. Sections are hierarchical via [parentId] references.
class TechDocSectionTable extends Table {
  @override
  String get tableName => 'tech_doc_section';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get docId => integer().references(TechDocTable, #id)();
  IntColumn get parentId => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  IntColumn get pageStart => integer()();
  IntColumn get pageEnd => integer()();
  IntColumn get level => integer()();
  IntColumn get sortOrder => integer()();
}

// ---------------------------------------------------------------------------
// MCP Proposal notification table
// ---------------------------------------------------------------------------

/// Proposals generated by MCP write tools (alarm, page, asset, key mapping).
///
/// When Claude Desktop or in-app chat generates a proposal, it is recorded
/// here so the Flutter HMI can show a notification to the operator — even
/// when the MCP server runs as a separate process (SSE mode).
class McpProposalTable extends Table {
  @override
  String get tableName => 'mcp_proposal';

  IntColumn get id => integer().autoIncrement()();

  /// Proposal type: alarm, page, asset, key_mapping.
  TextColumn get proposalType => text()();

  /// Human-readable title for the notification (e.g. "Pump Overcurrent").
  TextColumn get title => text()();

  /// Full proposal JSON for routing to the editor.
  TextColumn get proposalJson => text()();

  /// Operator who triggered the proposal.
  TextColumn get operatorId => text()();

  /// pending → notified → reviewed → dismissed.
  TextColumn get status =>
      text().withDefault(const Constant('pending'))();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
}

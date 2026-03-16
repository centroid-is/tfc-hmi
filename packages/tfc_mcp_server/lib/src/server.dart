import 'package:logger/logger.dart' as log;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase;

import 'audit/audit_log_service.dart';
import 'identity/operator_identity.dart';
import 'interfaces/alarm_reader.dart';
import 'interfaces/drawing_index.dart';
import 'interfaces/plc_code_index.dart';
import 'interfaces/state_reader.dart';
import 'interfaces/tech_doc_index.dart';
import 'logging/stderr_logger.dart';
import 'prompts/diagnose_equipment_prompt.dart';
import 'prompts/explain_alarm_prompt.dart';
import 'prompts/shift_handover_prompt.dart';
import 'resources/config_snapshot_resource.dart';
import 'resources/drawings_index_resource.dart';
import 'resources/history_resource.dart';
import 'resources/plc_code_index_resource.dart';
import 'resources/knowledge_resource.dart';
import 'resources/tech_docs_resource.dart';
import 'services/alarm_context_service.dart';
import 'services/alarm_service.dart';
import 'services/config_service.dart';
import 'services/diagnostic_service.dart';
import 'services/drawing_service.dart';
import 'services/drift_drawing_index.dart';
import 'services/plc_code_service.dart';
import 'services/tech_doc_service.dart';
import 'services/tag_service.dart';
import 'services/trend_service.dart';
import 'expression/expression_validator.dart';
import 'safety/elicitation_risk_gate.dart';
import 'services/proposal_service.dart';
import 'tools/alarm_tools.dart';
import 'tools/alarm_write_tools.dart';
import 'tools/asset_write_tools.dart';
import 'tools/config_tools.dart';
import 'tools/diagnostic_tools.dart';
import 'tools/drawing_tools.dart';
import 'tools/plc_code_tools.dart';
import 'tools/tech_doc_tools.dart';
import 'tools/key_mapping_write_tools.dart';
import 'tools/page_write_tools.dart';
import 'tools/ping_tool.dart';
import 'tools/tag_tools.dart';
import 'tools/tool_registry.dart';
import 'tools/tool_toggles.dart';
import 'tools/asset_type_catalog_tools.dart';
import 'tools/trend_tools.dart';

/// The TFC MCP Server wrapping [McpServer] from mcp_dart.
///
/// This server communicates over stdio using [StdioServerTransport].
/// Every tool call is gated by [OperatorIdentity] validation and creates
/// an audit trail via [AuditLogService].
///
/// **Subprocess contract:** This binary expects SIGTERM for clean shutdown.
/// It will close database connections and flush logs before exiting.
/// The Flutter-side McpBridgeNotifier (Phase 5) spawns this process
/// and sends SIGTERM when the chat widget is disposed.
class TfcMcpServer {
  TfcMcpServer({
    required OperatorIdentity identity,
    required McpDatabase database,
    required StateReader stateReader,
    required AlarmReader alarmReader,
    DrawingIndex? drawingIndex,
    PlcCodeIndex? plcCodeIndex,
    TechDocIndex? techDocIndex,
    McpToolToggles toggles = McpToolToggles.allEnabled,
    McpServer? mcpServer,
    log.Logger? logger,
    ProposalCallback? onProposal,
  })  : _mcpServer = mcpServer ??
            McpServer(
              const Implementation(
                  name: 'tfc-mcp-server', version: '0.1.0'),
              options: McpServerOptions(
                capabilities: ServerCapabilities(
                  tools: ServerCapabilitiesTools(),
                  resources: ServerCapabilitiesResources(),
                  prompts: ServerCapabilitiesPrompts(),
                ),
              ),
            ),
        _database = database,
        _logger = logger ?? createServerLogger() {
    // Create audit service from database
    final auditService = AuditLogService(_database);

    // Create tool registry with identity + audit middleware
    final registry = ToolRegistry(
      mcpServer: _mcpServer,
      identity: identity,
      auditLogService: auditService,
    );

    // Create services
    final tagService = TagService(stateReader);
    final alarmService = AlarmService(
      alarmReader: alarmReader,
      db: _database,
    );
    final configService = ConfigService(_database);
    final effectiveDrawingIndex = drawingIndex ?? DriftDrawingIndex(_database);
    final drawingService = DrawingService(effectiveDrawingIndex);
    final plcCodeService = plcCodeIndex != null
        ? PlcCodeService(plcCodeIndex, configService)
        : null;
    final techDocService = techDocIndex != null
        ? TechDocService(techDocIndex)
        : null;

    // Create trend and context services (Phase 7)
    final trendService = TrendService(_database);
    final alarmContextService = AlarmContextService(
      alarmService: alarmService,
      tagService: tagService,
      trendService: trendService,
      configService: toggles.configEnabled ? configService : null,
    );

    // Register tool groups based on toggle config.
    // Ping is always registered (health check, not a domain tool group).
    registerPingTool(registry);

    if (toggles.tagsEnabled) {
      registerTagTools(registry, tagService);
    }
    if (toggles.alarmsEnabled) {
      registerAlarmTools(registry, alarmService);
    }
    if (toggles.configEnabled) {
      registerConfigTools(registry, configService);
      registerAssetTypeCatalogTools(registry);
    }
    if (toggles.drawingsEnabled) {
      registerDrawingTools(registry, drawingService);
    }
    if (toggles.plcCodeEnabled && plcCodeService != null) {
      registerPlcCodeTools(registry, plcCodeService);
    }
    if (toggles.trendsEnabled) {
      registerTrendTools(registry, trendService);
    }
    if (toggles.techDocsEnabled && techDocService != null) {
      registerTechDocTools(registry, techDocService);
    }

    // ── Composite diagnostic tool ────────────────────────────────────────
    // Always registered when tags and alarms are enabled (its core deps).
    // Optional services (drawings, PLC code, tech docs) degrade gracefully.
    if (toggles.tagsEnabled && toggles.alarmsEnabled) {
      final diagnosticService = DiagnosticService(
        tagService: tagService,
        alarmService: alarmService,
        configService: toggles.configEnabled ? configService : null,
        trendService: toggles.trendsEnabled ? trendService : null,
        drawingService: toggles.drawingsEnabled ? drawingService : null,
        plcCodeService: toggles.plcCodeEnabled ? plcCodeService : null,
        techDocService: toggles.techDocsEnabled ? techDocService : null,
      );
      registerDiagnosticTools(registry, diagnosticService);
    }

    // ── Write tools (proposal-only, gated by ElicitationRiskGate) ──────
    if (toggles.proposalsEnabled) {
      final riskGate = ElicitationRiskGate(_mcpServer);
      final expressionValidator = ExpressionValidator();
      final proposalService = ProposalService(
        database: _database,
        operatorId:
            identity.isAuthenticated ? identity.operatorId : 'unknown',
        onProposal: onProposal,
      );

      if (toggles.alarmsEnabled && toggles.configEnabled) {
        registerAlarmWriteTools(
          registry: registry,
          configService: configService,
          riskGate: riskGate,
          expressionValidator: expressionValidator,
          proposalService: proposalService,
        );
      }
      if (toggles.configEnabled) {
        registerKeyMappingWriteTools(
          registry,
          configService: configService,
          riskGate: riskGate,
          proposalService: proposalService,
        );
      }
      registerPageWriteTools(
        registry: registry,
        riskGate: riskGate,
        proposalService: proposalService,
      );
      registerAssetWriteTools(
        registry: registry,
        riskGate: riskGate,
        proposalService: proposalService,
      );
    }

    // Resources (registered directly on McpServer, no identity/audit gate)
    if (toggles.configEnabled) {
      registerConfigSnapshotResource(_mcpServer, configService);
    }
    if (toggles.alarmsEnabled) {
      registerHistoryResource(_mcpServer, alarmService);
    }
    registerDrawingsIndexResource(
        _mcpServer, toggles.drawingsEnabled ? drawingService : null);
    registerKnowledgeResource(_mcpServer);
    registerPlcCodeIndexResource(_mcpServer, plcCodeService);
    registerTechDocsResource(_mcpServer, techDocService);

    // Prompts (registered directly on McpServer, no identity/audit gate)
    if (toggles.alarmsEnabled) {
      registerExplainAlarmPrompt(_mcpServer, alarmContextService);
      registerShiftHandoverPrompt(_mcpServer, alarmService, tagService);
    }

    // Diagnostic prompt (Phase 7) -- uses all data sources.
    // Gated by tagsEnabled && alarmsEnabled to match the diagnose_asset tool.
    if (toggles.tagsEnabled && toggles.alarmsEnabled) {
      registerDiagnoseEquipmentPrompt(
        _mcpServer,
        alarmService,
        tagService,
        toggles.trendsEnabled ? trendService : null,
        toggles.configEnabled ? configService : null,
        toggles.drawingsEnabled ? drawingService : null,
        toggles.plcCodeEnabled ? plcCodeService : null,
        toggles.techDocsEnabled ? techDocService : null,
      );
    }

    _logger.i('TFC MCP Server initialized with identity gate and audit trail');
  }

  final McpServer _mcpServer;
  final McpDatabase _database;
  final log.Logger _logger;

  /// The underlying [McpServer] instance.
  McpServer get mcpServer => _mcpServer;

  /// Connect the server to a [Transport] (typically [StdioServerTransport]).
  Future<void> connect(Transport transport) async {
    _logger.i('TFC MCP Server connecting via transport...');
    await _mcpServer.connect(transport);
    _logger.i('TFC MCP Server connected.');
  }

  /// Clean up server resources.
  ///
  /// When [closeDatabase] is true (the default, used by standalone binary),
  /// closes the database connection to flush audit records and release the
  /// connection pool. When false (used in-process), the caller owns the
  /// database and manages its lifecycle.
  Future<void> close({bool closeDatabase = true}) async {
    _logger.i('TFC MCP Server shutting down...');
    if (closeDatabase) {
      await _database.close();
    }
    _logger.i('TFC MCP Server shutdown complete.');
  }
}

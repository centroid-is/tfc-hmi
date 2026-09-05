import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

import '../audit/audit_log_service.dart';
import '../safety/proposal_declined_exception.dart';

/// A counting semaphore that limits concurrent async operations.
///
/// When the number of running operations reaches [maxCount], additional
/// callers queue up and are resumed FIFO when a slot frees up.
///
/// Used by [ToolRegistry] to prevent parallel LLM tool calls from
/// overwhelming the remote PostgreSQL connection (which causes
/// SocketException and 300s timeouts under 6+ concurrent queries).
class Semaphore {
  /// Creates a semaphore that allows at most [maxCount] concurrent operations.
  Semaphore(this.maxCount);

  /// Maximum number of concurrent operations.
  final int maxCount;

  int _current = 0;
  final _waiters = <Completer<void>>[];

  /// Execute [fn] when a slot is available.
  ///
  /// If fewer than [maxCount] operations are running, starts immediately.
  /// Otherwise queues until a running operation completes.
  /// The slot is always released, even if [fn] throws.
  Future<T> run<T>(Future<T> Function() fn) async {
    if (_current >= maxCount) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _current++;
    try {
      return await fn();
    } finally {
      _current--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }
}

/// Central tool registration with audit middleware.
///
/// Every tool registered through [ToolRegistry] is automatically wrapped
/// with audit trail creation and concurrency limiting. Tool implementations
/// do not need to handle these concerns -- the middleware is transparent.
///
/// Pipeline per tool call:
/// 1. Acquire concurrency slot (max 3 concurrent tool handlers)
/// 2. Log intent via [AuditLogService.executeWithAudit()]
/// 3. Execute the tool handler
/// 4. Update audit outcome (success/failed)
/// 5. Release concurrency slot
///
/// **There is no identity step, and its absence is a decision rather than an
/// omission.** Every tool registered here either reads, or returns a proposal
/// that a human must approve in the app through an access-gated store
/// (`lib/src/tools/access_template_tools.dart:28`: "they return a proposal").
/// Authorization and attribution both live at that approval, so a caller
/// identity here would authorize nothing and attribute nothing. The audit row
/// records provenance instead, under [kMcpAuditOperator], whose doc comment
/// carries the full reasoning.
class ToolRegistry {
  /// Creates a [ToolRegistry] that wraps tool registrations on [mcpServer]
  /// with an [auditLogService] audit trail and concurrency limiting.
  ///
  /// The [maxConcurrency] parameter controls how many tool handlers can
  /// execute simultaneously (default 3). This prevents parallel LLM tool
  /// calls from overwhelming the database connection pool.
  ToolRegistry({
    required McpServer mcpServer,
    required AuditLogService auditLogService,
    int maxConcurrency = 3,
  })  : _mcpServer = mcpServer,
        _auditLogService = auditLogService,
        _semaphore = Semaphore(maxConcurrency);

  final McpServer _mcpServer;
  final AuditLogService _auditLogService;
  final Semaphore _semaphore;

  /// Register a tool with audit + concurrency middleware.
  ///
  /// The [handler] receives the tool arguments and [RequestHandlerExtra]
  /// from the MCP protocol. It should focus only on business logic --
  /// audit logging and concurrency limiting are handled transparently.
  ///
  /// [metered] excludes the tool from the concurrency semaphore. The
  /// semaphore holds its slot for the handler's entire duration, which is
  /// right for a tool that queries the database and wrong for one that parks
  /// waiting on a human: three parked long polls would occupy every slot and
  /// freeze the whole server for a minute at a time. Only turn this off for a
  /// handler that spends its time idle rather than working.
  ///
  /// [audited] skips the audit trail. Off only for tools that are called on a
  /// timer and record no intent -- `await_proposal_feedback` re-arms once a
  /// minute forever, and an audit row per call would bury the rows that
  /// describe something someone actually did.
  void registerTool({
    required String name,
    required String description,
    ToolInputSchema? inputSchema,
    bool metered = true,
    bool audited = true,
    required Future<CallToolResult> Function(
            Map<String, dynamic> arguments, RequestHandlerExtra extra)
        handler,
  }) {
    _mcpServer.registerTool(
      name,
      description: description,
      inputSchema: inputSchema,
      callback: (Map<String, dynamic> args, RequestHandlerExtra extra) async {
        // Acquire concurrency slot, then execute with audit trail
        Future<CallToolResult> execute() async {
          try {
            if (!audited) {
              return await handler(args, extra);
            }
            return await _auditLogService.executeWithAudit<CallToolResult>(
              operatorId: kMcpAuditOperator,
              tool: name,
              arguments: args,
              handler: () => handler(args, extra),
            );
          } on ProposalDeclinedException catch (e) {
            // Decline is not an error -- return the message as a normal tool result.
            // Audit trail was already updated to "declined" by executeWithAudit.
            return CallToolResult(
              content: [TextContent(text: e.message)],
              isError: false,
            );
          } on Exception catch (e) {
            // The audit trail already recorded the failure in executeWithAudit.
            // Return an error result to the MCP client.
            return CallToolResult(
              content: [TextContent(text: e.toString())],
              isError: true,
            );
          }
        }

        return metered ? _semaphore.run(execute) : execute();
      },
    );
  }
}

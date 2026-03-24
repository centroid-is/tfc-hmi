import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

import '../audit/audit_log_service.dart';
import '../identity/operator_identity.dart';
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

/// Central tool registration with identity + audit middleware.
///
/// Every tool registered through [ToolRegistry] is automatically wrapped
/// with identity validation, audit trail creation, and concurrency limiting.
/// Tool implementations do not need to handle these concerns -- the
/// middleware is transparent.
///
/// Pipeline per tool call:
/// 1. Acquire concurrency slot (max 3 concurrent tool handlers)
/// 2. Validate operator identity via [OperatorIdentity.validate()]
/// 3. Log intent via [AuditLogService.executeWithAudit()]
/// 4. Execute the tool handler
/// 5. Update audit outcome (success/failed)
/// 6. Release concurrency slot
class ToolRegistry {
  /// Creates a [ToolRegistry] that wraps tool registrations on [mcpServer]
  /// with [identity] validation, [auditLogService] audit trail, and
  /// concurrency limiting.
  ///
  /// The [maxConcurrency] parameter controls how many tool handlers can
  /// execute simultaneously (default 3). This prevents parallel LLM tool
  /// calls from overwhelming the database connection pool.
  ToolRegistry({
    required McpServer mcpServer,
    required OperatorIdentity identity,
    required AuditLogService auditLogService,
    int maxConcurrency = 3,
  })  : _mcpServer = mcpServer,
        _identity = identity,
        _auditLogService = auditLogService,
        _semaphore = Semaphore(maxConcurrency);

  final McpServer _mcpServer;
  final OperatorIdentity _identity;
  final AuditLogService _auditLogService;
  final Semaphore _semaphore;

  /// Register a tool with identity + audit + concurrency middleware.
  ///
  /// The [handler] receives the tool arguments and [RequestHandlerExtra]
  /// from the MCP protocol. It should focus only on business logic --
  /// identity validation, audit logging, and concurrency limiting are
  /// handled transparently.
  void registerTool({
    required String name,
    required String description,
    ToolInputSchema? inputSchema,
    required Future<CallToolResult> Function(
            Map<String, dynamic> arguments, RequestHandlerExtra extra)
        handler,
  }) {
    _mcpServer.registerTool(
      name,
      description: description,
      inputSchema: inputSchema,
      callback: (Map<String, dynamic> args, RequestHandlerExtra extra) async {
        // Step 1: Validate operator identity (per-call, not cached)
        // Done OUTSIDE the semaphore so auth failures don't consume a slot.
        try {
          await _identity.validate();
        } on OperatorNotAuthenticatedError catch (e) {
          // Return error to the client without creating an audit record.
          // No audit record because we don't have a valid operator to log.
          return CallToolResult(
            content: [TextContent(text: e.message)],
            isError: true,
          );
        }

        // Step 2: Acquire concurrency slot, then execute with audit trail
        return _semaphore.run(() async {
          try {
            return await _auditLogService.executeWithAudit<CallToolResult>(
              operatorId: _identity.operatorId,
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
        });
      },
    );
  }
}

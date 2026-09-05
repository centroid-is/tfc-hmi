/// Why a tool call is not gated on who is asking.
///
/// This file is the positive statement of what replaced the operator-identity
/// gate that used to sit in front of every tool dispatch. The gate is not
/// missing; it was removed on purpose, and the reason is worth having written
/// down next to the tests that hold the new shape in place.
///
/// **MCP cannot write.** Every write-shaped tool in this package returns a
/// *proposal* rather than touching the database.
/// `lib/src/tools/access_template_tools.dart:28` says it in the source: "they
/// return a proposal". The imperative names -- `create_alarm`,
/// `update_key_mapping`, `delete_access_template`, `update_asset` -- are
/// misleading; every one of them wraps a proposal.
///
/// **Authorization happens at approval.** A proposal is inert until a human
/// applies it in the app, and that application goes through the same
/// access-gated store as any hand-made edit
/// (`lib/core/access_template_store.dart:10`). The control lives there, not
/// here.
///
/// **Attribution is the approver, not the proposer.**
/// `lib/core/access_template_store.dart:609` -- an accepted proposal's row
/// "still names the human who approved it rather than the agent that suggested
/// it". There is no parameter through which a caller could name somebody else.
///
/// So an operator identity carried into this package authorized nothing and
/// attributed nothing. What survives is provenance: the audit row records that
/// the machine ran a tool, under the constant [kMcpAuditOperator]. Its doc
/// comment in `lib/src/audit/audit_log_service.dart` carries the full
/// reasoning.
///
/// There is deliberately no test here asserting that an unauthenticated call is
/// refused. There is no such path any more, and no interface for a fake
/// identity to implement.
library;

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

// Reached through the barrel rather than by `src/` path on purpose: the
// provenance constant has to be nameable from outside this package, because
// the root suite's end-to-end tests assert against it across the package
// boundary. A forgotten export fails here rather than there.
import 'package:tfc_mcp_server/tfc_mcp_server.dart';

import '../helpers/mock_mcp_client.dart';

void main() {
  group('a tool call with no identity', () {
    late ServerDatabase db;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');
    });

    tearDown(() async {
      await db.close();
    });

    McpServer createMcpServer() {
      return McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
    }

    test('runs with nobody signed in -- MCP proposes, it does not write',
        () async {
      final auditService = AuditLogService(db);
      final mcpServer = createMcpServer();

      // No identity argument. There is no identity concept to supply.
      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        final result = await client.callTool('ping', {});

        expect(
          result.isError,
          isNot(true),
          reason: 'nothing gates a tool call, because nothing needs to: a '
              'write-shaped tool returns a proposal that is inert until a '
              'human with the right permission approves it in the app, and '
              'the server is a stdio subprocess the app spawns, so its reach '
              'is the local machine.',
        );
      } finally {
        await client.close();
      }
    });

    test('is audited under the MCP provenance constant', () async {
      final auditService = AuditLogService(db);
      final mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        await client.callTool('ping', {});
      } finally {
        await client.close();
      }

      final rows = await db.select(db.auditLog).get();

      expect(rows, hasLength(1));
      expect(
        rows.single.operatorId,
        kMcpAuditOperator,
        reason: 'this column records that the machine ran a tool, not that a '
            'person authorized one. The human name lands on the *approval* '
            'row (lib/core/access_template_store.dart:609), never on this '
            'one. Asserted against the constant rather than its value so the '
            'provenance token is spelled in exactly one place.',
      );
      expect(rows.single.tool, 'ping');
    });

    test('names its operator through a constant the barrel exports', () {
      // The assertion is the import at the top of this file: if the barrel
      // stops exporting the constant this file stops compiling. This test
      // states the requirement out loud so the import is not "tidied" into a
      // src/ path, which would move the failure into the root suite.
      expect(
        kMcpAuditOperator,
        isNotEmpty,
        reason: 'the audit table column is non-nullable, so an MCP row needs '
            'a value here; a constant is what lets the assertions pin it by '
            'name instead of re-spelling the token.',
      );
    });
  });
}

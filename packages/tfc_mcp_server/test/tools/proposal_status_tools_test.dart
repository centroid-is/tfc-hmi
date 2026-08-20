import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/expression/expression_validator.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/src/services/config_service.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';
import 'package:tfc_mcp_server/src/tools/alarm_write_tools.dart';
import 'package:tfc_mcp_server/src/tools/proposal_status_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

Map<String, dynamic> _alarmArgs(String title) => {
      'title': title,
      'description': 'Current exceeds threshold',
      'key': 'pump3.overcurrent',
      'rules': [
        {
          'level': 'error',
          'formula': 'pump3.current > 15',
          'acknowledge_required': true,
        }
      ],
    };

void main() {
  group('get_proposal_status (end-to-end)', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockMcpClient client;

    setUp(() async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: AuditLogService(db),
      );

      final proposalService = ProposalService(database: db, operatorId: 'op1');

      registerAlarmWriteTools(
        registry: registry,
        configService: ConfigService(db),
        riskGate: NoOpRiskGate(),
        expressionValidator: ExpressionValidator(),
        proposalService: proposalService,
      );
      registerProposalStatusTools(registry, proposalService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    Map<String, dynamic> decode(CallToolResult result) =>
        jsonDecode((result.content.first as TextContent).text)
            as Map<String, dynamic>;

    test('write tool result carries _proposal_id', () async {
      final result = await client.callTool('create_alarm', _alarmArgs('A'));
      final wrapped = decode(result);

      expect(wrapped['_proposal_id'], isA<int>());
    });

    test('lists proposals with pending status after creation', () async {
      await client.callTool('create_alarm', _alarmArgs('First'));
      await client.callTool('create_alarm', _alarmArgs('Second'));

      final result = await client.callTool('get_proposal_status', {});
      final proposals = decode(result)['proposals'] as List<dynamic>;

      expect(proposals, hasLength(2));
      final byTitle = {
        for (final p in proposals.cast<Map<String, dynamic>>()) p['title']: p,
      };
      expect(byTitle['First']?['status'], 'pending');
      expect(byTitle['Second']?['status'], 'pending');
      expect(byTitle['First']?['type'], 'alarm');
    });

    test('reports operator decision for requested ids', () async {
      final created = decode(
          await client.callTool('create_alarm', _alarmArgs('Decided')));
      await client.callTool('create_alarm', _alarmArgs('Other'));
      final id = created['_proposal_id'] as int;

      // Simulate the HMI accepting the proposal.
      await db.customStatement(
        'UPDATE mcp_proposal SET status = ? WHERE id = ?',
        ['accepted', id],
      );

      final result = await client.callTool('get_proposal_status', {
        'ids': [id],
      });
      final proposals = decode(result)['proposals'] as List<dynamic>;

      expect(proposals, hasLength(1));
      final row = proposals.first as Map<String, dynamic>;
      expect(row['id'], id);
      expect(row['status'], 'accepted');
      expect(row['title'], 'Decided');
    });
  });
}

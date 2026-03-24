import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/safety/proposal_declined_exception.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';
import 'package:tfc_mcp_server/src/tools/page_write_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

void main() {
  group('Page write tools', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockMcpClient client;

    Future<void> setupWithAutoConfirm() async {
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
      final auditService = AuditLogService(db);
      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerPageWriteTools(
        registry: registry,
        riskGate: NoOpRiskGate(),
        proposalService: ProposalService(),
      );

      client = await MockMcpClient.connect(mcpServer);
    }

    Future<void> setupWithDecline() async {
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
      final auditService = AuditLogService(db);
      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerPageWriteTools(
        registry: registry,
        riskGate: _DecliningRiskGate(),
        proposalService: ProposalService(),
      );

      client = await MockMcpClient.connect(mcpServer);
    }

    tearDown(() async {
      await client.close();
      await db.close();
    });

    group('propose_page', () {
      test('valid args returns proposal JSON with asset structure', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_page', {
          'title': 'Pump Overview',
          'assets': [
            {
              'asset_type': 'NumberConfig',
              'key': 'pump3.speed',
              'label': 'Pump 3 Speed',
              'x': 0.1,
              'y': 0.05,
            },
            {
              'asset_type': 'LEDConfig',
              'key': 'pump3.running',
              'label': 'Pump 3 Status',
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('page'));
        expect(json['key'], equals('page-pump-overview'));
        expect(json['title'], equals('Pump Overview'));
        expect(json['assets'], isList);
        final assets = json['assets'] as List;
        expect(assets.length, equals(2));
        // Each asset must have asset_name for AssetRegistry.parse
        expect(assets[0]['asset_name'], equals('NumberConfig'));
        expect(assets[0]['key'], equals('pump3.speed'));
        expect(assets[0]['text'], equals('Pump 3 Speed'));
        expect(assets[0]['coordinates']['x'], equals(0.1));
        expect(assets[0]['coordinates']['y'], equals(0.05));
        expect(assets[1]['asset_name'], equals('LEDConfig'));
        expect(assets[1]['key'], equals('pump3.running'));
      });

      test('generates slug key from title', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_page', {
          'title': 'My Cool Page Layout',
          'assets': [
            {'asset_type': 'TextAssetConfig', 'key': 'label1'},
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['key'], equals('page-my-cool-page-layout'));
      });

      test('TextAssetConfig gets textContent field', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_page', {
          'title': 'Label Page',
          'assets': [
            {
              'asset_type': 'TextAssetConfig',
              'key': 'label1',
              'label': 'Hello World',
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final assets = json['assets'] as List;
        expect(assets[0]['asset_name'], equals('TextAssetConfig'));
        expect(assets[0]['textContent'], equals('Hello World'));
      });

      test('declined proposal returns non-error decline message', () async {
        await setupWithDecline();

        final result = await client.callTool('propose_page', {
          'title': 'Declined Page',
          'assets': [
            {'asset_type': 'TextAssetConfig', 'key': 'label1'},
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text.toLowerCase(), contains('declined'));
      });

      test('empty assets array returns proposal with empty assets', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_page', {
          'title': 'Empty Page',
          'assets': <Map<String, dynamic>>[],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['assets'], isEmpty);
      });
    });
  });
}

class _DecliningRiskGate implements RiskGate {
  @override
  Future<RiskConfirmation> requestConfirmation({
    required String description,
    required RiskLevel level,
    Map<String, dynamic>? details,
  }) async {
    throw ProposalDeclinedException('Proposal declined by operator.');
  }
}

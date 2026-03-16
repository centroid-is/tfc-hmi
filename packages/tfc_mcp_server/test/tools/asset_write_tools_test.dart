import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/safety/proposal_declined_exception.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';
import 'package:tfc_mcp_server/src/tools/asset_write_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

void main() {
  group('Asset write tools', () {
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

      registerAssetWriteTools(
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

      registerAssetWriteTools(
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

    group('propose_asset', () {
      test('valid args returns proposal JSON with asset hierarchy', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'Pump Station',
          'children': [
            {
              'asset_type': 'NumberConfig',
              'key': 'pump3.speed',
              'title': 'Pump 3 Speed',
            },
            {
              'asset_type': 'LEDConfig',
              'key': 'pump4.status',
              'title': 'Pump 4 Status',
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('asset'));
        expect(json['key'], equals('asset-pump-station'));
        expect(json['title'], equals('Pump Station'));
        expect(json['children'], isList);
        final children = json['children'] as List;
        expect(children.length, equals(2));
        // Each child must have asset_name for AssetRegistry.parse
        expect(children[0]['asset_name'], equals('NumberConfig'));
        expect(children[0]['key'], equals('pump3.speed'));
        expect(children[0]['title'], equals('Pump 3 Speed'));
        expect(children[1]['asset_name'], equals('LEDConfig'));
        expect(children[1]['key'], equals('pump4.status'));
        expect(children[1]['title'], equals('Pump 4 Status'));
      });

      test('generates slug key from title', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'My Asset Group',
          'children': [
            {
              'asset_type': 'ButtonConfig',
              'key': 'child1',
              'title': 'Child 1',
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['key'], equals('asset-my-asset-group'));
      });

      test('page_key is included in proposal when provided', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'New Sensors',
          'page_key': '/',
          'children': [
            {
              'asset_type': 'NumberConfig',
              'key': 'temp1',
              'title': 'Temperature 1',
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['page_key'], equals('/'));
      });

      test('declined proposal returns non-error decline message', () async {
        await setupWithDecline();

        final result = await client.callTool('propose_asset', {
          'title': 'Declined Asset',
          'children': [
            {
              'asset_type': 'LEDConfig',
              'key': 'child1',
              'title': 'Child 1',
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text.toLowerCase(), contains('declined'));
      });

      test('x and y position are passed through to proposal children',
          () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'Positioned Assets',
          'children': [
            {
              'asset_type': 'NumberConfig',
              'key': 'pump3.speed',
              'title': 'Pump 3 Speed',
              'x': 0.5,
              'y': 0.4,
            },
            {
              'asset_type': 'LEDConfig',
              'key': 'pump4.status',
              'title': 'Pump 4 Status',
              // No x/y — should be absent, not defaulted by the tool.
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final children = json['children'] as List;
        // First child: x and y present.
        expect(children[0]['x'], equals(0.5));
        expect(children[0]['y'], equals(0.4));
        // Second child: no x/y keys at all.
        expect(children[1].containsKey('x'), isFalse);
        expect(children[1].containsKey('y'), isFalse);
      });

      test('integer x and y values are passed through', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'Integer Pos',
          'children': [
            {
              'asset_type': 'ButtonConfig',
              'key': 'btn1',
              'title': 'Button 1',
              'x': 0,
              'y': 1,
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final children = json['children'] as List;
        expect(children[0]['x'], equals(0));
        expect(children[0]['y'], equals(1));
      });

      test('config object is passed through to proposal children', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'Configured Button',
          'children': [
            {
              'asset_type': 'ButtonConfig',
              'key': 'bathroom.ceiling_led',
              'title': 'Ceiling LED',
              'x': 0.3,
              'y': 0.2,
              'config': {
                'button_type': 'square',
                'is_toggle': true,
                'text': 'Ceiling LED',
                'text_pos': 'below',
              },
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final children = json['children'] as List;
        expect(children.length, equals(1));
        expect(children[0]['asset_name'], equals('ButtonConfig'));
        expect(children[0]['key'], equals('bathroom.ceiling_led'));
        expect(children[0]['config'], isA<Map<String, dynamic>>());
        final config = children[0]['config'] as Map<String, dynamic>;
        expect(config['button_type'], equals('square'));
        expect(config['is_toggle'], isTrue);
        expect(config['text'], equals('Ceiling LED'));
        expect(config['text_pos'], equals('below'));
      });

      test('child without config has no config key in proposal', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'No Config',
          'children': [
            {
              'asset_type': 'LEDConfig',
              'key': 'led1',
              'title': 'LED 1',
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final children = json['children'] as List;
        expect(children[0].containsKey('config'), isFalse);
      });

      test('config with multiple children passes each config independently',
          () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'Mixed Config',
          'children': [
            {
              'asset_type': 'ButtonConfig',
              'key': 'btn1',
              'title': 'Button 1',
              'config': {'is_toggle': true},
            },
            {
              'asset_type': 'NumberConfig',
              'key': 'num1',
              'title': 'Number 1',
              'config': {'suffix': 'rpm'},
            },
            {
              'asset_type': 'LEDConfig',
              'key': 'led1',
              'title': 'LED 1',
              // No config
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final children = json['children'] as List;
        expect(children.length, equals(3));
        // First child has config with is_toggle
        expect(
            (children[0]['config'] as Map)['is_toggle'], isTrue);
        // Second child has config with suffix
        expect(
            (children[1]['config'] as Map)['suffix'], equals('rpm'));
        // Third child has no config
        expect(children[2].containsKey('config'), isFalse);
      });

      test('empty children array returns proposal with no children', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('propose_asset', {
          'title': 'Leaf Asset',
          'children': <Map<String, dynamic>>[],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['children'], isEmpty);
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

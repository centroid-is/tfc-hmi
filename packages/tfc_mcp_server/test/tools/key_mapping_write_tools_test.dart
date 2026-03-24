import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/safety/elicitation_risk_gate.dart';
import 'package:tfc_mcp_server/src/safety/proposal_declined_exception.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/src/services/config_service.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';
import 'package:tfc_mcp_server/src/tools/key_mapping_write_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';

void main() {
  group('Key mapping write tools', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockMcpClient client;

    /// Sample key_mappings JSON with existing entries for update tests.
    final keyMappings = {
      'nodes': {
        'belt.speed': {
          'opcua_node': {'namespace': 2, 'identifier': 'Belt.Speed'},
          'collect': {'enabled': true},
        },
        'pump3.pressure': {
          'opcua_node': {'namespace': 3, 'identifier': 'Pump3.Pressure'},
          'collect': {'enabled': false},
        },
      },
    };

    /// Helper to set up with a configurable elicitation callback.
    Future<MockMcpClient> setupWithElicitation({
      required Future<ElicitResult> Function(ElicitRequest) onElicit,
    }) async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      // Seed key_mappings preference
      await db.into(db.serverFlutterPreferences).insert(
            ServerFlutterPreferencesCompanion.insert(
              key: 'key_mappings',
              value: Value(jsonEncode(keyMappings)),
              type: 'String',
            ),
          );

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      final riskGate = ElicitationRiskGate(mcpServer);
      final configService = ConfigService(db);
      final proposalService = ProposalService();

      registerKeyMappingWriteTools(
        registry,
        configService: configService,
        riskGate: riskGate,
        proposalService: proposalService,
      );

      return MockMcpClient.connectWithElicitation(
        mcpServer,
        onElicit: onElicit,
      );
    }

    /// Helper to set up with auto-confirm (NoOpRiskGate).
    Future<MockMcpClient> setupAutoConfirm() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      // Seed key_mappings preference
      await db.into(db.serverFlutterPreferences).insert(
            ServerFlutterPreferencesCompanion.insert(
              key: 'key_mappings',
              value: Value(jsonEncode(keyMappings)),
              type: 'String',
            ),
          );

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      final riskGate = NoOpRiskGate();
      final configService = ConfigService(db);
      final proposalService = ProposalService();

      registerKeyMappingWriteTools(
        registry,
        configService: configService,
        riskGate: riskGate,
        proposalService: proposalService,
      );

      return MockMcpClient.connect(mcpServer);
    }

    tearDown(() async {
      await client.close();
      await db.close();
    });

    group('create_key_mapping', () {
      test('returns proposal JSON with key, opcua_node, and _proposal_type',
          () async {
        client = await setupAutoConfirm();

        final result = await client.callTool('create_key_mapping', {
          'key': 'motor.rpm',
          'namespace': 2,
          'identifier': 'Motor.RPM',
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['key'], 'motor.rpm');
        expect(json['opcua_node']['namespace'], 2);
        expect(json['opcua_node']['identifier'], 'Motor.RPM');
        expect(json['_proposal_type'], 'key_mapping');
      });

      test('elicitation message shows key name, namespace, identifier',
          () async {
        String? capturedMessage;
        client = await setupWithElicitation(
          onElicit: (request) async {
            capturedMessage = request.message;
            return ElicitResult(
              action: 'accept',
              content: {'confirm': true},
            );
          },
        );

        await client.callTool('create_key_mapping', {
          'key': 'motor.rpm',
          'namespace': 2,
          'identifier': 'Motor.RPM',
        });

        expect(capturedMessage, isNotNull);
        expect(capturedMessage, contains('motor.rpm'));
        expect(capturedMessage, contains('2'));
        expect(capturedMessage, contains('Motor.RPM'));
      });

      test('declined proposal returns non-error decline message', () async {
        client = await setupWithElicitation(
          onElicit: (request) async {
            return ElicitResult(action: 'decline');
          },
        );

        final result = await client.callTool('create_key_mapping', {
          'key': 'motor.rpm',
          'namespace': 2,
          'identifier': 'Motor.RPM',
        });

        // ElicitationRiskGate auto-confirms even on decline (Flutter UI is the
        // real safety gate), so the tool returns the proposal JSON.
        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], 'key_mapping');
      });

      test('does not write to database', () async {
        client = await setupAutoConfirm();

        await client.callTool('create_key_mapping', {
          'key': 'motor.rpm',
          'namespace': 2,
          'identifier': 'Motor.RPM',
        });

        // Verify key_mappings preference is unchanged
        final query = db.select(db.serverFlutterPreferences)
          ..where((t) => t.key.equals('key_mappings'));
        final rows = await query.get();
        final stored =
            jsonDecode(rows.first.value!) as Map<String, dynamic>;
        final nodes = stored['nodes'] as Map<String, dynamic>;
        // Original two keys still there, no new key added
        expect(nodes.length, 2);
        expect(nodes.containsKey('motor.rpm'), isFalse);
      });
    });

    group('update_key_mapping', () {
      test('returns updated proposal for existing key', () async {
        client = await setupAutoConfirm();

        final result = await client.callTool('update_key_mapping', {
          'key': 'belt.speed',
          'namespace': 4,
          'identifier': 'Belt.SpeedV2',
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['key'], 'belt.speed');
        expect(json['opcua_node']['namespace'], 4);
        expect(json['opcua_node']['identifier'], 'Belt.SpeedV2');
        expect(json['_proposal_type'], 'key_mapping');
      });

      test('returns isError for non-existent key', () async {
        client = await setupAutoConfirm();

        final result = await client.callTool('update_key_mapping', {
          'key': 'nonexistent.key',
          'namespace': 2,
        });

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text, contains('nonexistent.key'));
      });

      test('partial update changes only specified fields', () async {
        client = await setupAutoConfirm();

        // Only update namespace, keep identifier as-is
        final result = await client.callTool('update_key_mapping', {
          'key': 'belt.speed',
          'namespace': 5,
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['opcua_node']['namespace'], 5);
        expect(json['opcua_node']['identifier'], 'Belt.Speed'); // unchanged
      });

      test('elicitation message shows before/after changes', () async {
        String? capturedMessage;
        client = await setupWithElicitation(
          onElicit: (request) async {
            capturedMessage = request.message;
            return ElicitResult(
              action: 'accept',
              content: {'confirm': true},
            );
          },
        );

        await client.callTool('update_key_mapping', {
          'key': 'belt.speed',
          'namespace': 4,
        });

        expect(capturedMessage, isNotNull);
        expect(capturedMessage, contains('belt.speed'));
        // Should show before/after diff
        expect(capturedMessage, contains('Before'));
        expect(capturedMessage, contains('After'));
      });

      test('declined proposal returns non-error decline message', () async {
        client = await setupWithElicitation(
          onElicit: (request) async {
            return ElicitResult(action: 'decline');
          },
        );

        final result = await client.callTool('update_key_mapping', {
          'key': 'belt.speed',
          'namespace': 4,
        });

        // ElicitationRiskGate auto-confirms even on decline (Flutter UI is the
        // real safety gate), so the tool returns the proposal JSON.
        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], 'key_mapping');
      });

      test('does not write to database', () async {
        client = await setupAutoConfirm();

        await client.callTool('update_key_mapping', {
          'key': 'belt.speed',
          'namespace': 99,
          'identifier': 'Changed.Value',
        });

        // Verify key_mappings preference is unchanged
        final query = db.select(db.serverFlutterPreferences)
          ..where((t) => t.key.equals('key_mappings'));
        final rows = await query.get();
        final stored =
            jsonDecode(rows.first.value!) as Map<String, dynamic>;
        final nodes = stored['nodes'] as Map<String, dynamic>;
        final beltNode = nodes['belt.speed'] as Map<String, dynamic>;
        final opcuaNode = beltNode['opcua_node'] as Map<String, dynamic>;
        // Original values unchanged
        expect(opcuaNode['namespace'], 2);
        expect(opcuaNode['identifier'], 'Belt.Speed');
      });
    });
  });
}

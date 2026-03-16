import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/expression/expression_validator.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/safety/proposal_declined_exception.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/src/services/config_service.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';
import 'package:tfc_mcp_server/src/tools/alarm_write_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

void main() {
  group('Alarm write tools', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockMcpClient client;
    late ConfigService configService;

    /// Helper to set up tools with a NoOpRiskGate (auto-confirm).
    Future<void> setupWithAutoConfirm() async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');

      configService = ConfigService(db);

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

      registerAlarmWriteTools(
        registry: registry,
        configService: configService,
        riskGate: NoOpRiskGate(),
        expressionValidator: ExpressionValidator(),
        proposalService: ProposalService(),
      );

      client = await MockMcpClient.connect(mcpServer);
    }

    /// Helper to set up tools with elicitation that declines.
    Future<void> setupWithDecline() async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');

      configService = ConfigService(db);

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

      registerAlarmWriteTools(
        registry: registry,
        configService: configService,
        riskGate: _DecliningRiskGate(),
        expressionValidator: ExpressionValidator(),
        proposalService: ProposalService(),
      );

      client = await MockMcpClient.connect(mcpServer);
    }

    tearDown(() async {
      await client.close();
      await db.close();
    });

    group('create_alarm', () {
      test('valid args with single rule returns proposal JSON', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('create_alarm', {
          'title': 'Pump 3 Overcurrent',
          'description': 'Current exceeds 15A threshold',
          'key': 'pump3.overcurrent',
          'rules': [
            {
              'level': 'error',
              'formula': 'pump3.current > 15',
              'acknowledge_required': true,
            }
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('alarm'));
        expect(json['title'], equals('Pump 3 Overcurrent'));
        expect(json['description'], equals('Current exceeds 15A threshold'));
        expect(json['key'], equals('pump3.overcurrent'));
        expect(json['uid'], isNotNull);
        expect(json['rules'], isList);
        final rules = json['rules'] as List;
        expect(rules.length, equals(1));
        expect(rules[0]['level'], equals('error'));
        expect(rules[0]['expression']['value']['formula'],
            equals('pump3.current > 15'));
        expect(rules[0]['acknowledgeRequired'], isTrue);
      });

      test('valid args with compound expression returns proposal', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('create_alarm', {
          'title': 'Compound Alarm',
          'description': 'Tests AND expression',
          'rules': [
            {
              'level': 'warning',
              'formula': 'a > 1 AND b < 2',
            }
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('alarm'));
        final rules = json['rules'] as List;
        expect(rules[0]['expression']['value']['formula'],
            equals('a > 1 AND b < 2'));
      });

      test('invalid expression returns isError=true', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('create_alarm', {
          'title': 'Bad Alarm',
          'description': 'Invalid expression',
          'rules': [
            {
              'level': 'error',
              'formula': 'AND > >',
            }
          ],
        });

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text.toLowerCase(), contains('invalid expression'));
      });

      test('expression round-trip failure returns isError=true', () async {
        await setupWithAutoConfirm();

        // An expression with extra whitespace that would fail round-trip
        // We use a mock validator that claims valid but produces different
        // serialize output. Instead, let's use a formula that the validator
        // considers valid but round-trip changes it.
        // Actually, ExpressionValidator normalizes whitespace, so
        // "pump3.current  >  15" would round-trip to "pump3.current > 15".
        // The round-trip check should catch this.
        final result = await client.callTool('create_alarm', {
          'title': 'Roundtrip Alarm',
          'description': 'Expression changes on roundtrip',
          'rules': [
            {
              'level': 'error',
              // Extra spaces will get normalized during round-trip
              'formula': 'pump3.current  >  15',
            }
          ],
        });

        // The extra spaces will be parsed as part of the variable name,
        // causing a whitespace error in the parser.
        expect(result.isError, isTrue);
      });

      test('declined elicitation returns non-error decline message', () async {
        await setupWithDecline();

        final result = await client.callTool('create_alarm', {
          'title': 'Declined Alarm',
          'description': 'This will be declined',
          'rules': [
            {
              'level': 'info',
              'formula': 'pump3.current > 15',
            }
          ],
        });

        // ToolRegistry catches ProposalDeclinedException and returns non-error
        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text.toLowerCase(), contains('declined'));
      });

      test('proposal JSON never writes to database', () async {
        await setupWithAutoConfirm();

        await client.callTool('create_alarm', {
          'title': 'No Write Alarm',
          'description': 'Should not write to DB',
          'rules': [
            {
              'level': 'error',
              'formula': 'pump3.current > 15',
            }
          ],
        });

        // Verify no new alarm rows exist in the alarm table
        final alarms = await db.select(db.serverAlarm).get();
        expect(alarms, isEmpty);
      });
    });

    group('update_alarm', () {
      test('valid args with existing alarm returns updated proposal',
          () async {
        await setupWithAutoConfirm();

        // Seed an alarm
        await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
              uid: 'alarm-1',
              title: 'Old Title',
              description: 'Old description',
              rules:
                  '[{"level":"error","expression":{"value":{"formula":"pump3.current > 15"}},"acknowledgeRequired":true}]',
            ));

        final result = await client.callTool('update_alarm', {
          'alarm_uid': 'alarm-1',
          'title': 'New Title',
          'description': 'New description',
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('alarm'));
        expect(json['title'], equals('New Title'));
        expect(json['description'], equals('New description'));
        expect(json['uid'], equals('alarm-1'));
      });

      test('non-existent alarm_uid returns isError=true', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('update_alarm', {
          'alarm_uid': 'nonexistent',
          'title': 'Updated',
        });

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text, contains('No alarm found with UID: nonexistent'));
      });

      test('updated expression validates before elicitation', () async {
        await setupWithAutoConfirm();

        await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
              uid: 'alarm-2',
              title: 'Existing Alarm',
              description: 'Existing',
              rules:
                  '[{"level":"error","expression":{"value":{"formula":"pump3.current > 15"}},"acknowledgeRequired":true}]',
            ));

        final result = await client.callTool('update_alarm', {
          'alarm_uid': 'alarm-2',
          'rules': [
            {
              'level': 'error',
              'formula': 'AND > >',
            }
          ],
        });

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text.toLowerCase(), contains('invalid expression'));
      });

      test('declined update returns non-error decline message', () async {
        await setupWithDecline();

        await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
              uid: 'alarm-3',
              title: 'To Decline',
              description: 'Will be declined',
              rules: '[]',
            ));

        final result = await client.callTool('update_alarm', {
          'alarm_uid': 'alarm-3',
          'title': 'Updated Title',
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text.toLowerCase(), contains('declined'));
      });

      test('update does not write to database', () async {
        await setupWithAutoConfirm();

        await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
              uid: 'alarm-4',
              title: 'Original',
              description: 'Original desc',
              rules: '[]',
            ));

        await client.callTool('update_alarm', {
          'alarm_uid': 'alarm-4',
          'title': 'Modified',
        });

        // Verify the alarm was NOT modified in the database
        final query = db.select(db.serverAlarm)
          ..where((t) => t.uid.equals('alarm-4'));
        final rows = await query.get();
        expect(rows.first.title, equals('Original'));
      });
    });

    group('ConfigService.getAlarmConfig', () {
      test('returns alarm config with parsed rules', () async {
        await setupWithAutoConfirm();

        await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
              uid: 'cfg-alarm',
              title: 'Config Test',
              description: 'Test desc',
              rules: '[{"level":"error"}]',
            ));

        final config = await configService.getAlarmConfig('cfg-alarm');
        expect(config, isNotNull);
        expect(config!['uid'], equals('cfg-alarm'));
        expect(config['title'], equals('Config Test'));
        expect(config['rules'], isList);
        expect((config['rules'] as List).length, equals(1));
      });

      test('returns null for non-existent uid', () async {
        await setupWithAutoConfirm();

        final config = await configService.getAlarmConfig('nope');
        expect(config, isNull);
      });
    });
  });
}

/// A RiskGate that always throws ProposalDeclinedException.
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

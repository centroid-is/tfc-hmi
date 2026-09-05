import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/expression/expression_validator.dart';
import 'package:tfc_mcp_server/src/safety/elicitation_risk_gate.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/src/services/config_service.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';
import 'package:tfc_mcp_server/src/tools/alarm_write_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

/// Standard alarm arguments used across multiple tests.
Map<String, dynamic> _validAlarmArgs() => {
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
    };

void main() {
  group('Alarm proposal flow (end-to-end)', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockMcpClient client;
    late ProposalService proposalService;

    /// Proposals handed to the UI by [ProposalService]'s callback -- the
    /// whole of what a write tool delivers, since nothing is persisted.
    late List<Map<String, dynamic>> delivered;

    /// Sets up the MCP server with an [ElicitationRiskGate] and a
    /// client that responds to elicitation with [onElicit].
    Future<void> setupWithElicitation({
      required Future<ElicitResult> Function(ElicitRequest) onElicit,
    }) async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final auditService = AuditLogService(db);
      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      delivered = [];
      proposalService = ProposalService(onProposal: delivered.add);

      final configService = ConfigService(db);

      // Use ElicitationRiskGate -- the real production implementation
      final riskGate = ElicitationRiskGate(mcpServer);

      registerAlarmWriteTools(
        registry: registry,
        configService: configService,
        riskGate: riskGate,
        expressionValidator: ExpressionValidator(),
        proposalService: proposalService,
      );

      client = await MockMcpClient.connectWithElicitation(
        mcpServer,
        onElicit: onElicit,
      );
    }

    /// Sets up MCP server with a NoOpRiskGate (no elicitation).
    Future<void> setupWithAutoConfirm() async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final auditService = AuditLogService(db);
      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      delivered = [];
      proposalService = ProposalService(onProposal: delivered.add);

      final configService = ConfigService(db);

      registerAlarmWriteTools(
        registry: registry,
        configService: configService,
        riskGate: NoOpRiskGate(),
        expressionValidator: ExpressionValidator(),
        proposalService: proposalService,
      );

      client = await MockMcpClient.connect(mcpServer);
    }

    tearDown(() async {
      await client.close();
      await db.close();
    });

    // -----------------------------------------------------------------------
    // Scenario 1: Happy path -- client accepts elicitation
    // -----------------------------------------------------------------------
    group('happy path (client accepts elicitation)', () {
      test('create_alarm returns proposal JSON with _proposal_type', () async {
        await setupWithElicitation(
          onElicit: (request) async => const ElicitResult(
            action: 'accept',
            content: {'confirm': true},
          ),
        );

        final result =
            await client.callTool('create_alarm', _validAlarmArgs());

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['_proposal_type'], equals('alarm'));
        expect(json['title'], equals('Pump 3 Overcurrent'));
        expect(json['description'], equals('Current exceeds 15A threshold'));
        expect(json['key'], equals('pump3.overcurrent'));
        expect(json['uid'], isA<String>());
        expect(json['uid'], isNotEmpty);
      });

      test('elicitation request includes alarm title and risk level', () async {
        ElicitRequest? capturedRequest;

        await setupWithElicitation(
          onElicit: (request) async {
            capturedRequest = request;
            return const ElicitResult(
              action: 'accept',
              content: {'confirm': true},
            );
          },
        );

        await client.callTool('create_alarm', _validAlarmArgs());

        expect(capturedRequest, isNotNull);
        expect(
          capturedRequest!.message,
          contains('Create alarm: Pump 3 Overcurrent'),
        );
        expect(capturedRequest!.message, contains('MEDIUM'));
      });
    });

    // -----------------------------------------------------------------------
    // Scenario 2: Client declines elicitation
    // -----------------------------------------------------------------------
    group('client declines elicitation', () {
      test(
          'create_alarm STILL returns proposal JSON (decline is not a blocker)',
          () async {
        await setupWithElicitation(
          onElicit: (request) async => const ElicitResult(action: 'decline'),
        );

        final result =
            await client.callTool('create_alarm', _validAlarmArgs());

        // The ElicitationRiskGate auto-confirms on decline, so the tool
        // should still return a valid proposal.
        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('alarm'));
        expect(json['title'], equals('Pump 3 Overcurrent'));
        expect(json['uid'], isA<String>());
      });
    });

    // -----------------------------------------------------------------------
    // Scenario 3: Client cancels elicitation
    // -----------------------------------------------------------------------
    group('client cancels elicitation', () {
      test(
          'create_alarm STILL returns proposal JSON (cancel is not a blocker)',
          () async {
        await setupWithElicitation(
          onElicit: (request) async => const ElicitResult(action: 'cancel'),
        );

        final result =
            await client.callTool('create_alarm', _validAlarmArgs());

        // Same as decline -- ElicitationRiskGate auto-confirms on cancel.
        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('alarm'));
        expect(json['title'], equals('Pump 3 Overcurrent'));
        expect(json['uid'], isA<String>());
      });
    });

    // -----------------------------------------------------------------------
    // Scenario 4: Client throws McpError on elicitation
    // -----------------------------------------------------------------------
    group('client throws McpError on elicitation', () {
      test('create_alarm STILL returns proposal (elicitation unsupported)',
          () async {
        await setupWithElicitation(
          onElicit: (request) async {
            throw McpError(
                -32601, 'Method not found: elicitation/create');
          },
        );

        final result =
            await client.callTool('create_alarm', _validAlarmArgs());

        // ElicitationRiskGate catches McpError and auto-confirms.
        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_proposal_type'], equals('alarm'));
        expect(json['title'], equals('Pump 3 Overcurrent'));
        expect(json['uid'], isA<String>());
      });
    });

    // -----------------------------------------------------------------------
    // Scenario 5: Proposal JSON format validation
    // -----------------------------------------------------------------------
    group('proposal JSON format', () {
      test('contains uid, title, description, rules, _proposal_type',
          () async {
        await setupWithAutoConfirm();

        final result =
            await client.callTool('create_alarm', _validAlarmArgs());

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;

        // Required top-level fields
        expect(json, containsPair('uid', isA<String>()));
        expect(json, containsPair('title', 'Pump 3 Overcurrent'));
        expect(
            json, containsPair('description', 'Current exceeds 15A threshold'));
        expect(json, containsPair('key', 'pump3.overcurrent'));
        expect(json, containsPair('_proposal_type', 'alarm'));
        expect(json, containsPair('rules', isA<List>()));
      });

      test('rules contain level, expression, and acknowledgeRequired',
          () async {
        await setupWithAutoConfirm();

        final result =
            await client.callTool('create_alarm', _validAlarmArgs());

        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final rules = json['rules'] as List;

        expect(rules, hasLength(1));
        final rule = rules[0] as Map<String, dynamic>;
        expect(rule['level'], equals('error'));
        expect(rule['expression']['value']['formula'],
            equals('pump3.current > 15'));
        expect(rule['acknowledgeRequired'], isTrue);
      });

      test('uid is a valid UUID v4 format', () async {
        await setupWithAutoConfirm();

        final result =
            await client.callTool('create_alarm', _validAlarmArgs());

        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final uid = json['uid'] as String;

        // UUID v4 format: 8-4-4-4-12 hex chars
        expect(
          uid,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
        );
      });

      test('multiple rules are preserved in order', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('create_alarm', {
          'title': 'Multi-Rule Alarm',
          'description': 'Has info, warning, and error rules',
          'rules': [
            {'level': 'info', 'formula': 'pump3.current > 10'},
            {
              'level': 'warning',
              'formula': 'pump3.current > 12',
              'acknowledge_required': false,
            },
            {
              'level': 'error',
              'formula': 'pump3.current > 15',
              'acknowledge_required': true,
            },
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        final rules = json['rules'] as List;

        expect(rules, hasLength(3));
        expect(rules[0]['level'], 'info');
        expect(rules[1]['level'], 'warning');
        expect(rules[2]['level'], 'error');
        expect(rules[0]['acknowledgeRequired'], isFalse);
        expect(rules[1]['acknowledgeRequired'], isFalse);
        expect(rules[2]['acknowledgeRequired'], isTrue);
      });

      test('key field is omitted when not provided', () async {
        await setupWithAutoConfirm();

        final result = await client.callTool('create_alarm', {
          'title': 'No Key Alarm',
          'description': 'Alarm without explicit key',
          'rules': [
            {'level': 'info', 'formula': 'pump3.current > 10'},
          ],
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json.containsKey('key'), isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // Scenario: Proposal delivered to the UI
    // -----------------------------------------------------------------------
    group('proposal delivery', () {
      test('proposal reaches the UI callback with the full proposal',
          () async {
        await setupWithAutoConfirm();

        await client.callTool('create_alarm', _validAlarmArgs());

        // Synchronous: no write to wait for, no poll to wait for.
        expect(delivered, hasLength(1));
        expect(delivered.first['_proposal_type'], 'alarm');
        expect(delivered.first['title'], 'Pump 3 Overcurrent');
        expect(delivered.first['uid'], isA<String>());
      });

      test('proposal is delivered even when client declines elicitation',
          () async {
        await setupWithElicitation(
          onElicit: (request) async => const ElicitResult(action: 'decline'),
        );

        await client.callTool('create_alarm', _validAlarmArgs());

        expect(delivered, hasLength(1));
        expect(delivered.first['_proposal_type'], 'alarm');
        expect(delivered.first['title'], 'Pump 3 Overcurrent');
      });

      test('no alarm rows written to server_alarm table (proposal only)',
          () async {
        await setupWithAutoConfirm();

        await client.callTool('create_alarm', _validAlarmArgs());

        final alarms = await db.select(db.serverAlarm).get();
        expect(alarms, isEmpty);
      });
    });

    // -----------------------------------------------------------------------
    // Scenario: Non-blocking behavior -- all elicitation outcomes complete
    // -----------------------------------------------------------------------
    group('non-blocking behavior', () {
      test('accept completes without hanging', () async {
        await setupWithElicitation(
          onElicit: (request) async => const ElicitResult(
            action: 'accept',
            content: {'confirm': true},
          ),
        );

        // This should complete promptly, not hang.
        final result = await client
            .callTool('create_alarm', _validAlarmArgs())
            .timeout(const Duration(seconds: 10));

        expect(result.isError, isNot(true));
      });

      test('decline completes without hanging', () async {
        await setupWithElicitation(
          onElicit: (request) async => const ElicitResult(action: 'decline'),
        );

        final result = await client
            .callTool('create_alarm', _validAlarmArgs())
            .timeout(const Duration(seconds: 10));

        expect(result.isError, isNot(true));
      });

      test('cancel completes without hanging', () async {
        await setupWithElicitation(
          onElicit: (request) async => const ElicitResult(action: 'cancel'),
        );

        final result = await client
            .callTool('create_alarm', _validAlarmArgs())
            .timeout(const Duration(seconds: 10));

        expect(result.isError, isNot(true));
      });

      test('McpError completes without hanging', () async {
        await setupWithElicitation(
          onElicit: (request) async {
            throw McpError(-32601, 'Method not found');
          },
        );

        final result = await client
            .callTool('create_alarm', _validAlarmArgs())
            .timeout(const Duration(seconds: 10));

        expect(result.isError, isNot(true));
      });
    });

    // -----------------------------------------------------------------------
    // Scenario: Each call produces a distinct uid
    // -----------------------------------------------------------------------
    group('uid uniqueness', () {
      test('two sequential calls produce different uids', () async {
        await setupWithAutoConfirm();

        final result1 =
            await client.callTool('create_alarm', _validAlarmArgs());
        final result2 =
            await client.callTool('create_alarm', _validAlarmArgs());

        final json1 =
            jsonDecode((result1.content.first as TextContent).text)
                as Map<String, dynamic>;
        final json2 =
            jsonDecode((result2.content.first as TextContent).text)
                as Map<String, dynamic>;

        expect(json1['uid'], isNot(equals(json2['uid'])));
      });
    });

    // -----------------------------------------------------------------------
    // Scenario: ProposalCallback fires for in-process notification
    // -----------------------------------------------------------------------
    group('onProposal callback', () {
      test('callback fires with wrapped proposal when tool succeeds', () async {
        final captured = <Map<String, dynamic>>[];

        db = createTestDatabase();
        await db.customStatement('SELECT 1');

        mcpServer = McpServer(
          const Implementation(name: 'test-server', version: '0.1.0'),
          options: McpServerOptions(
            capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
          ),
        );

        final auditService = AuditLogService(db);
        final registry = ToolRegistry(
          mcpServer: mcpServer,
          auditLogService: auditService,
        );

        proposalService = ProposalService(
          onProposal: (wrapped) => captured.add(wrapped),
        );

        final configService = ConfigService(db);

        registerAlarmWriteTools(
          registry: registry,
          configService: configService,
          riskGate: NoOpRiskGate(),
          expressionValidator: ExpressionValidator(),
          proposalService: proposalService,
        );

        client = await MockMcpClient.connect(mcpServer);

        await client.callTool('create_alarm', _validAlarmArgs());

        expect(captured, hasLength(1));
        expect(captured.first['_proposal_type'], equals('alarm'));
        expect(captured.first['title'], equals('Pump 3 Overcurrent'));
        expect(captured.first['uid'], isA<String>());
      });

      test('callback does not fire when tool returns validation error',
          () async {
        final captured = <Map<String, dynamic>>[];

        db = createTestDatabase();
        await db.customStatement('SELECT 1');

        mcpServer = McpServer(
          const Implementation(name: 'test-server', version: '0.1.0'),
          options: McpServerOptions(
            capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
          ),
        );

        final auditService = AuditLogService(db);
        final registry = ToolRegistry(
          mcpServer: mcpServer,
          auditLogService: auditService,
        );

        proposalService = ProposalService(
          onProposal: (wrapped) => captured.add(wrapped),
        );

        final configService = ConfigService(db);

        registerAlarmWriteTools(
          registry: registry,
          configService: configService,
          riskGate: NoOpRiskGate(),
          expressionValidator: ExpressionValidator(),
          proposalService: proposalService,
        );

        client = await MockMcpClient.connect(mcpServer);

        // Invalid formula should fail validation before reaching wrapProposal
        await client.callTool('create_alarm', {
          'title': 'Bad Alarm',
          'description': 'Invalid formula',
          'rules': [
            {'level': 'error', 'formula': '> >'},
          ],
        });

        expect(captured, isEmpty);
      });
    });
  });
}

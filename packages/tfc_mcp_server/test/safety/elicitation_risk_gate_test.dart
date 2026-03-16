import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/safety/elicitation_risk_gate.dart';
import 'package:tfc_mcp_server/src/safety/proposal_declined_exception.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';

import '../helpers/mock_mcp_client.dart';

void main() {
  group('ElicitationRiskGate', () {
    late McpServer server;

    setUp(() {
      server = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
      );
    });

    test('returns RiskConfirmation(confirmed: true) when operator accepts',
        () async {
      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async => const ElicitResult(
          action: 'accept',
          content: {'confirm': true},
        ),
      );

      final gate = ElicitationRiskGate(server);
      final result = await gate.requestConfirmation(
        description: 'Create alarm pump3.high_temp',
        level: RiskLevel.medium,
      );

      expect(result.confirmed, isTrue);
      expect(result.reason, isNull);

      await mockClient.close();
    });

    test('confirms when client accepts without confirm field in content',
        () async {
      // Claude Agent SDK and other MCP clients may accept elicitation
      // without filling in the schema fields (no {'confirm': true}).
      // This should still be treated as confirmation.
      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async => const ElicitResult(
          action: 'accept',
          // No content — simulates Claude Agent SDK auto-accept
        ),
      );

      final gate = ElicitationRiskGate(server);
      final result = await gate.requestConfirmation(
        description: 'Create alarm pump3.high_temp',
        level: RiskLevel.medium,
      );

      expect(result.confirmed, isTrue);
      expect(result.reason, isNull);

      await mockClient.close();
    });

    test('auto-confirms when operator declines (proposal is the safety gate)',
        () async {
      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async => const ElicitResult(action: 'decline'),
      );

      final gate = ElicitationRiskGate(server);
      final result = await gate.requestConfirmation(
        description: 'Create alarm pump3.high_temp',
        level: RiskLevel.medium,
      );

      expect(result.confirmed, isTrue);
      expect(result.reason, equals('client_declined'));

      await mockClient.close();
    });

    test('auto-confirms when operator cancels (proposal is the safety gate)',
        () async {
      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async => const ElicitResult(action: 'cancel'),
      );

      final gate = ElicitationRiskGate(server);
      final result = await gate.requestConfirmation(
        description: 'Create alarm pump3.high_temp',
        level: RiskLevel.medium,
      );

      expect(result.confirmed, isTrue);
      expect(result.reason, equals('client_cancelled'));

      await mockClient.close();
    });

    test(
        'auto-confirms with elicitation_unsupported when client lacks '
        'elicitation capability', () async {
      // Connect a client WITHOUT elicitation capability.
      // McpServer.elicitInput() throws McpError when the client has no
      // elicitation support — the gate should catch it and auto-confirm.
      final mockClient = await MockMcpClient.connect(server);

      final gate = ElicitationRiskGate(server);
      final result = await gate.requestConfirmation(
        description: 'Create alarm pump3.high_temp',
        level: RiskLevel.medium,
      );

      expect(result.confirmed, isTrue);
      expect(result.reason, equals('elicitation_unsupported'));

      await mockClient.close();
    });

    test(
        'auto-confirms with descriptive reason for unknown elicitation action',
        () async {
      // Future MCP spec additions might introduce new action strings.
      // The gate should auto-confirm and include the action in the reason.
      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async =>
            const ElicitResult(action: 'some_future_action'),
      );

      final gate = ElicitationRiskGate(server);
      final result = await gate.requestConfirmation(
        description: 'Create alarm pump3.high_temp',
        level: RiskLevel.medium,
      );

      expect(result.confirmed, isTrue);
      expect(result.reason, equals('client_action_some_future_action'));

      await mockClient.close();
    });

    test('auto-confirms for all risk levels (proposal is the safety gate)',
        () async {
      for (final level in RiskLevel.values) {
        // Fresh server per iteration to avoid transport reuse issues.
        final iterServer = McpServer(
          const Implementation(name: 'test-server', version: '0.1.0'),
        );

        final mockClient = await MockMcpClient.connectWithElicitation(
          iterServer,
          onElicit: (request) async => const ElicitResult(action: 'decline'),
        );

        final gate = ElicitationRiskGate(iterServer);
        final result = await gate.requestConfirmation(
          description: 'Test operation',
          level: level,
        );

        expect(result.confirmed, isTrue,
            reason: 'Should auto-confirm for ${level.name}');
        expect(result.reason, equals('client_declined'),
            reason: 'Reason should be client_declined for ${level.name}');

        await mockClient.close();
      }
    });

    test('message contains description and risk level', () async {
      ElicitRequest? capturedRequest;

      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async {
          capturedRequest = request;
          return const ElicitResult(
            action: 'accept',
            content: {'confirm': true},
          );
        },
      );

      final gate = ElicitationRiskGate(server);
      await gate.requestConfirmation(
        description: 'Create alarm pump3.high_temp',
        level: RiskLevel.high,
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.message, contains('Create alarm pump3.high_temp'));
      expect(capturedRequest!.message, contains('HIGH'));

      await mockClient.close();
    });

    test('message includes formatted details when provided', () async {
      ElicitRequest? capturedRequest;

      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async {
          capturedRequest = request;
          return const ElicitResult(
            action: 'accept',
            content: {'confirm': true},
          );
        },
      );

      final gate = ElicitationRiskGate(server);
      await gate.requestConfirmation(
        description: 'Create alarm',
        level: RiskLevel.medium,
        details: {
          'expression': 'pump3.temp > 80',
          'severity': 'high',
        },
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.message, contains('expression'));
      expect(capturedRequest!.message, contains('pump3.temp > 80'));
      expect(capturedRequest!.message, contains('severity'));
      expect(capturedRequest!.message, contains('high'));

      await mockClient.close();
    });

    test('message omits details section when details is null', () async {
      ElicitRequest? capturedRequest;

      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async {
          capturedRequest = request;
          return const ElicitResult(
            action: 'accept',
            content: {'confirm': true},
          );
        },
      );

      final gate = ElicitationRiskGate(server);
      await gate.requestConfirmation(
        description: 'Create alarm',
        level: RiskLevel.low,
        // details: null (default)
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.message, contains('LOW'));
      expect(capturedRequest!.message, contains('Create alarm'));
      // Should NOT contain the separator line used for details
      expect(capturedRequest!.message, isNot(contains('---')));

      await mockClient.close();
    });

    test('message omits details section when details is empty map', () async {
      ElicitRequest? capturedRequest;

      final mockClient = await MockMcpClient.connectWithElicitation(
        server,
        onElicit: (request) async {
          capturedRequest = request;
          return const ElicitResult(
            action: 'accept',
            content: {'confirm': true},
          );
        },
      );

      final gate = ElicitationRiskGate(server);
      await gate.requestConfirmation(
        description: 'Delete page',
        level: RiskLevel.critical,
        details: {},
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.message, contains('CRITICAL'));
      expect(capturedRequest!.message, contains('Delete page'));
      // Empty map should be treated same as null — no separator
      expect(capturedRequest!.message, isNot(contains('---')));

      await mockClient.close();
    });

    test('message shows correct label for each risk level', () async {
      final expectedLabels = {
        RiskLevel.low: 'LOW',
        RiskLevel.medium: 'MEDIUM',
        RiskLevel.high: 'HIGH',
        RiskLevel.critical: 'CRITICAL',
      };

      for (final entry in expectedLabels.entries) {
        final iterServer = McpServer(
          const Implementation(name: 'test-server', version: '0.1.0'),
        );
        ElicitRequest? capturedRequest;

        final mockClient = await MockMcpClient.connectWithElicitation(
          iterServer,
          onElicit: (request) async {
            capturedRequest = request;
            return const ElicitResult(
              action: 'accept',
              content: {'confirm': true},
            );
          },
        );

        final gate = ElicitationRiskGate(iterServer);
        await gate.requestConfirmation(
          description: 'Test op',
          level: entry.key,
        );

        expect(capturedRequest!.message, contains(entry.value),
            reason: '${entry.key.name} should show ${entry.value}');

        await mockClient.close();
      }
    });
  });

  group('ProposalService', () {
    late ProposalService service;

    setUp(() {
      service = ProposalService();
    });

    test('formatCreateDiff produces markdown with title and fields', () {
      final result = service.formatCreateDiff(
        'Alarm',
        'pump3.high_temp',
        {
          'expression': 'pump3.temp > 80',
          'severity': 'high',
          'delay': '5s',
        },
      );

      expect(result, contains('## Proposal: Create Alarm'));
      expect(result, contains('**pump3.high_temp**'));
      expect(result, contains('| expression | pump3.temp > 80 |'));
      expect(result, contains('| severity | high |'));
      expect(result, contains('| delay | 5s |'));
    });

    test('formatUpdateDiff produces markdown with before/after table', () {
      final result = service.formatUpdateDiff(
        'Alarm',
        'pump3.high_temp',
        {
          'expression': 'pump3.temp > 80 -> pump3.temp > 90',
          'severity': 'medium -> high',
        },
      );

      expect(result, contains('## Proposal: Update Alarm'));
      expect(result, contains('**pump3.high_temp**'));
      expect(result, contains('| Before | After |'));
      expect(result, contains('| expression | pump3.temp > 80 | pump3.temp > 90 |'));
      expect(result, contains('| severity | medium | high |'));
    });

    test('wrapProposal adds _proposal_type field', () {
      final wrapped = service.wrapProposal('alarm', {
        'name': 'pump3.high_temp',
        'expression': 'pump3.temp > 80',
      });

      expect(wrapped['_proposal_type'], equals('alarm'));
      expect(wrapped['name'], equals('pump3.high_temp'));
      expect(wrapped['expression'], equals('pump3.temp > 80'));
    });
  });

  group('ProposalDeclinedException', () {
    test('carries a human-readable message for decline', () {
      final e = ProposalDeclinedException('Proposal declined by operator.');
      expect(e.message, equals('Proposal declined by operator.'));
      expect(e.toString(), equals('Proposal declined by operator.'));
    });

    test('carries a human-readable message for cancel', () {
      final e = ProposalDeclinedException('Proposal cancelled by operator.');
      expect(e.message, equals('Proposal cancelled by operator.'));
      expect(e.toString(), equals('Proposal cancelled by operator.'));
    });
  });
}

import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';

import '../expression/expression_validator.dart';
import '../safety/risk_gate.dart';
import '../services/config_service.dart';
import '../services/proposal_service.dart';
import 'tool_registry.dart';

const _uuid = Uuid();

/// Registers create_alarm and update_alarm MCP write tools.
///
/// These tools generate alarm configuration proposals from LLM-provided
/// arguments. They validate boolean expressions, present diffs via
/// elicitation, and return proposal JSON for the Flutter layer to route
/// to the alarm editor. Neither tool writes to the database.
void registerAlarmWriteTools({
  required ToolRegistry registry,
  required ConfigService configService,
  required RiskGate riskGate,
  required ExpressionValidator expressionValidator,
  required ProposalService proposalService,
}) {
  _registerCreateAlarm(
    registry: registry,
    riskGate: riskGate,
    expressionValidator: expressionValidator,
    proposalService: proposalService,
  );
  _registerUpdateAlarm(
    registry: registry,
    configService: configService,
    riskGate: riskGate,
    expressionValidator: expressionValidator,
    proposalService: proposalService,
  );
}

/// Validates a formula via ExpressionValidator: checks isValid and round-trip.
/// Returns null on success, or an error message string on failure.
String? _validateFormula(
    ExpressionValidator validator, String formula, int ruleIndex) {
  if (!validator.isValid(formula)) {
    return 'Invalid expression in rule $ruleIndex: "$formula"';
  }

  // Round-trip check: parse -> serialize -> compare
  final tokens = validator.parse(formula);
  final serialized = validator.serialize(tokens);
  if (serialized != formula) {
    return 'Expression round-trip failed in rule $ruleIndex: '
        '"$formula" became "$serialized"';
  }

  return null;
}

/// Builds a rules list in AlarmConfig.toJson() format from LLM-provided args.
List<Map<String, dynamic>> _buildRules(List<dynamic> rawRules) {
  return rawRules.map((rule) {
    final r = rule as Map<String, dynamic>;
    return {
      'level': r['level'] ?? 'info',
      'expression': {
        'value': {'formula': r['formula'] as String}
      },
      'acknowledgeRequired': r['acknowledge_required'] ?? false,
    };
  }).toList();
}

void _registerCreateAlarm({
  required ToolRegistry registry,
  required RiskGate riskGate,
  required ExpressionValidator expressionValidator,
  required ProposalService proposalService,
}) {
  registry.registerTool(
    name: 'create_alarm',
    description: 'Create a new alarm configuration proposal. '
        'Returns proposal JSON for the operator to review -- does not write to database.',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(
          description: 'Alarm title (e.g., "Pump 3 Overcurrent")',
        ),
        'description': JsonSchema.string(
          description:
              'Alarm description (e.g., "Current exceeds 15A threshold")',
        ),
        'key': JsonSchema.string(
          description:
              'Optional alarm key (e.g., "pump3.overcurrent")',
        ),
        'rules': JsonSchema.array(
          description: 'Alarm rules with severity and expression',
          items: JsonSchema.object(
            properties: {
              'level': JsonSchema.string(
                description: 'Severity level',
                enumValues: ['info', 'warning', 'error'],
              ),
              'formula': JsonSchema.string(
                description:
                    'Boolean expression (e.g., "pump3.current > 15")',
              ),
              'acknowledge_required': JsonSchema.boolean(
                description: 'Whether acknowledgement is required',
                defaultValue: false,
              ),
            },
            required: ['level', 'formula'],
          ),
        ),
      },
      required: ['title', 'description', 'rules'],
    ),
    handler: (arguments, extra) async {
      final title = arguments['title'] as String;
      final description = arguments['description'] as String;
      final key = arguments['key'] as String?;
      final rawRules = arguments['rules'] as List<dynamic>;

      // Validate all expressions before building proposal
      for (var i = 0; i < rawRules.length; i++) {
        final rule = rawRules[i] as Map<String, dynamic>;
        final formula = rule['formula'] as String;
        final error = _validateFormula(expressionValidator, formula, i);
        if (error != null) {
          return CallToolResult(
            content: [TextContent(text: error)],
            isError: true,
          );
        }
      }

      // Build proposal JSON matching AlarmConfig.toJson() format
      final rules = _buildRules(rawRules);
      final proposal = <String, dynamic>{
        'uid': _uuid.v4(),
        'title': title,
        'description': description,
        'rules': rules,
      };
      if (key != null) {
        proposal['key'] = key;
      }

      // Format diff for elicitation
      final diffFields = <String, dynamic>{
        'title': title,
        'description': description,
        if (key != null) 'key': key,
        'rules': rules
            .map((r) =>
                '${r['level']}: ${r['expression']['value']['formula']}')
            .join(', '),
      };
      final diff =
          proposalService.formatCreateDiff('Alarm', title, diffFields);

      // Elicit confirmation -- ProposalDeclinedException propagates to middleware
      await riskGate.requestConfirmation(
        description: 'Create alarm: $title',
        level: RiskLevel.medium,
        details: {'diff': diff},
      );

      // Wrap with _proposal_type and return as JSON
      final wrapped = proposalService.wrapProposal('alarm', proposal);
      return CallToolResult(
        content: [TextContent(text: jsonEncode(wrapped))],
      );
    },
  );
}

void _registerUpdateAlarm({
  required ToolRegistry registry,
  required ConfigService configService,
  required RiskGate riskGate,
  required ExpressionValidator expressionValidator,
  required ProposalService proposalService,
}) {
  registry.registerTool(
    name: 'update_alarm',
    description: 'Update an existing alarm configuration. '
        'Shows before/after diff for operator review -- does not write to database.',
    inputSchema: JsonSchema.object(
      properties: {
        'alarm_uid': JsonSchema.string(
          description: 'UID of the alarm to update',
        ),
        'title': JsonSchema.string(
          description: 'Updated alarm title',
        ),
        'description': JsonSchema.string(
          description: 'Updated alarm description',
        ),
        'key': JsonSchema.string(
          description: 'Updated alarm key',
        ),
        'rules': JsonSchema.array(
          description: 'Updated alarm rules (replaces all existing rules)',
          items: JsonSchema.object(
            properties: {
              'level': JsonSchema.string(
                description: 'Severity level',
                enumValues: ['info', 'warning', 'error'],
              ),
              'formula': JsonSchema.string(
                description: 'Boolean expression',
              ),
              'acknowledge_required': JsonSchema.boolean(
                description: 'Whether acknowledgement is required',
                defaultValue: false,
              ),
            },
            required: ['level', 'formula'],
          ),
        ),
      },
      required: ['alarm_uid'],
    ),
    handler: (arguments, extra) async {
      final alarmUid = arguments['alarm_uid'] as String;

      // Look up existing alarm
      final existing = await configService.getAlarmConfig(alarmUid);
      if (existing == null) {
        return CallToolResult(
          content: [
            TextContent(text: 'No alarm found with UID: $alarmUid'),
          ],
          isError: true,
        );
      }

      // Build updated proposal by merging provided fields over existing
      final newTitle =
          arguments['title'] as String? ?? existing['title'] as String;
      final newDescription = arguments['description'] as String? ??
          existing['description'] as String;
      final newKey =
          arguments['key'] as String? ?? existing['key'] as String?;

      List<Map<String, dynamic>> newRules;
      if (arguments.containsKey('rules') && arguments['rules'] != null) {
        final rawRules = arguments['rules'] as List<dynamic>;

        // Validate new expressions
        for (var i = 0; i < rawRules.length; i++) {
          final rule = rawRules[i] as Map<String, dynamic>;
          final formula = rule['formula'] as String;
          final error = _validateFormula(expressionValidator, formula, i);
          if (error != null) {
            return CallToolResult(
              content: [TextContent(text: error)],
              isError: true,
            );
          }
        }

        newRules = _buildRules(rawRules);
      } else {
        // Keep existing rules
        newRules =
            (existing['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
      }

      // Build the updated proposal
      final proposal = <String, dynamic>{
        'uid': alarmUid,
        'title': newTitle,
        'description': newDescription,
        'rules': newRules,
      };
      if (newKey != null) {
        proposal['key'] = newKey;
      }

      // Compute before/after changes for diff
      final changes = <String, String>{};
      if (newTitle != existing['title']) {
        changes['title'] = '${existing['title']} -> $newTitle';
      }
      if (newDescription != existing['description']) {
        changes['description'] =
            '${existing['description']} -> $newDescription';
      }
      if (newKey != existing['key']) {
        changes['key'] = '${existing['key']} -> $newKey';
      }
      if (arguments.containsKey('rules')) {
        changes['rules'] = 'Updated';
      }

      final diff = proposalService.formatUpdateDiff(
          'Alarm', newTitle, changes);

      // Elicit confirmation -- ProposalDeclinedException propagates to middleware
      await riskGate.requestConfirmation(
        description: 'Update alarm: $newTitle',
        level: RiskLevel.medium,
        details: {'diff': diff},
      );

      // Wrap with _proposal_type and return as JSON
      final wrapped = proposalService.wrapProposal('alarm', proposal);
      return CallToolResult(
        content: [TextContent(text: jsonEncode(wrapped))],
      );
    },
  );
}

import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../safety/risk_gate.dart';
import '../services/config_service.dart';
import '../services/proposal_service.dart';
import 'tool_registry.dart';

/// Registers key mapping write tools on the given [registry].
///
/// These tools generate OPC UA key mapping proposals for the key repository
/// editor. None of them writes to the database -- they return proposal JSON
/// that the Flutter UI routes to the appropriate editor.
///
/// Tools registered:
/// - `create_key_mapping`: Build a new key mapping proposal
/// - `update_key_mapping`: Look up an existing mapping and propose changes
/// - `delete_key_mapping`: Propose removing a mapping
///
/// ## Units
///
/// Retention is taken in **days** and sampling in **seconds**, and converted
/// here to the minutes and microseconds the stored config uses. Callers never
/// see `drop_after_min` or `sample_interval_us`, because naming a field for one
/// unit and storing another is how a one-year retention came to be applied as
/// half a second.
void registerKeyMappingWriteTools(
  ToolRegistry registry, {
  required ConfigService configService,
  required RiskGate riskGate,
  required ProposalService proposalService,
}) {
  // Schema shared by create and update.
  JsonSchema collectSchema() => JsonSchema.object(
        description:
            'Data collection for this key. Omit to leave collection as it is.',
        properties: {
          'name': JsonSchema.string(
            description:
                'Series name to store under. Defaults to the key. Two keys '
                'given the same name write into one series -- that is how the '
                'per-head checkweigher keys feed a combined per-batcher one.',
          ),
          'retention_days': JsonSchema.integer(
            description: 'Days of history to keep before chunks are dropped.',
          ),
          'sample_interval_seconds': JsonSchema.number(
            description:
                'Seconds between samples. Use 0 to turn periodic sampling off '
                'so only changes in value are recorded -- right for event-like '
                'values such as the weight of the last accepted batch.',
          ),
        },
      );

  // Builds the stored `collect` shape from the tool's day/second inputs.
  Map<String, dynamic> buildCollect(String key, Map<String, dynamic> args) {
    final name = args['name'] as String?;
    final retentionDays = (args['retention_days'] as num?)?.toInt();
    final sampleSeconds = (args['sample_interval_seconds'] as num?)?.toDouble();
    return <String, dynamic>{
      'key': key,
      'name': name ?? key,
      'retention': <String, dynamic>{
        // Minutes. See the units note above.
        'drop_after_min': (retentionDays ?? 365) * 24 * 60,
        'schedule_interval_min': null,
      },
      // Microseconds, or null for "record every change and nothing else".
      'sample_interval_us': (sampleSeconds == null || sampleSeconds <= 0)
          ? null
          : (sampleSeconds * 1000000).round(),
      'sample_expression': null,
      'sample_members': null,
    };
  }

  // Human-readable summary of a collect block, for the confirmation diff.
  String describeCollect(Map<String, dynamic> collect) {
    final retention = collect['retention'] as Map<String, dynamic>;
    final minutes = retention['drop_after_min'] as int;
    final us = collect['sample_interval_us'] as int?;
    final sampling =
        us == null ? 'on change only' : 'every ${us / 1000000}s';
    return 'series "${collect['name']}", keep ${minutes ~/ (24 * 60)} days, '
        '$sampling';
  }

  // -- create_key_mapping ------------------------------------------------

  registry.registerTool(
    name: 'create_key_mapping',
    description:
        'Create a new OPC UA key mapping proposal. Returns proposal JSON '
        'for the key repository editor -- does not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'Logical key name e.g. belt.speed',
        ),
        'namespace': JsonSchema.integer(
          description: 'OPC UA namespace index',
        ),
        'identifier': JsonSchema.string(
          description: 'OPC UA node identifier e.g. Belt.Speed',
        ),
        'server_alias': JsonSchema.string(
          description:
              'Which configured server holds the node, e.g. "st201". Required '
              'whenever more than one server is configured: a mapping without '
              'it cannot be resolved and reads as null.',
        ),
        'collect': collectSchema(),
      },
      required: ['key', 'namespace', 'identifier'],
    ),
    handler: (args, extra) async {
      final key = args['key'] as String;
      final namespace = args['namespace'] as int;
      final identifier = args['identifier'] as String;
      final serverAlias = args['server_alias'] as String?;
      final collectArgs = args['collect'] as Map<String, dynamic>?;

      final proposal = <String, dynamic>{
        'key': key,
        'opcua_node': <String, dynamic>{
          'namespace': namespace,
          'identifier': identifier,
          if (serverAlias != null) 'server_alias': serverAlias,
        },
      };

      final fields = <String, dynamic>{
        'key': key,
        'namespace': namespace,
        'identifier': identifier,
        if (serverAlias != null) 'server_alias': serverAlias,
      };

      if (collectArgs != null) {
        final collect = buildCollect(key, collectArgs);
        proposal['collect'] = collect;
        fields['collect'] = describeCollect(collect);
      }

      final diffMessage =
          proposalService.formatCreateDiff('Key Mapping', key, fields);

      // Elicit operator confirmation -- throws ProposalDeclinedException
      // on decline/cancel, which propagates up to ToolRegistry middleware.
      await riskGate.requestConfirmation(
        description: diffMessage,
        level: RiskLevel.medium,
      );

      final wrapped = await proposalService.wrapProposal('key_mapping', proposal);
      return CallToolResult(content: [TextContent(text: jsonEncode(wrapped))]);
    },
  );

  // -- update_key_mapping ------------------------------------------------

  registry.registerTool(
    name: 'update_key_mapping',
    description:
        'Update an existing OPC UA key mapping. Looks up the current mapping '
        'and returns a proposal with the changes -- does not write to the '
        'database. Fields left out keep their current value; the editor merges '
        'the proposal onto the existing entry rather than replacing it.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'The key name to update (must already exist)',
        ),
        'namespace': JsonSchema.integer(
          description: 'New OPC UA namespace index (optional)',
        ),
        'identifier': JsonSchema.string(
          description: 'New OPC UA node identifier (optional)',
        ),
        'server_alias': JsonSchema.string(
          description:
              'New server alias, e.g. "st201". Set this on any mapping that '
              'reads null despite a correct node id.',
        ),
        'collect': collectSchema(),
        'remove_collect': JsonSchema.boolean(
          description:
              'Stop collecting this key entirely, dropping its series config.',
        ),
      },
      required: ['key'],
    ),
    handler: (args, extra) async {
      final key = args['key'] as String;
      final newNamespace = args['namespace'] as int?;
      final newIdentifier = args['identifier'] as String?;
      final newServerAlias = args['server_alias'] as String?;
      final collectArgs = args['collect'] as Map<String, dynamic>?;
      final removeCollect = args['remove_collect'] as bool? ?? false;

      final mappings = await configService.listKeyMappings(filter: key);
      final existing = mappings.where((m) => m['key'] == key).firstOrNull;

      if (existing == null) {
        return CallToolResult(
          content: [TextContent(text: 'No key mapping found for: $key')],
          isError: true,
        );
      }

      if (collectArgs != null && removeCollect) {
        return CallToolResult(
          content: [
            TextContent(text: 'Pass either collect or remove_collect, not both.')
          ],
          isError: true,
        );
      }

      final oldNamespace = existing['namespace'] as int;
      final oldIdentifier = existing['identifier'] as String;
      final oldServerAlias = existing['server_alias'] as String?;

      final updatedNamespace = newNamespace ?? oldNamespace;
      final updatedIdentifier = newIdentifier ?? oldIdentifier;
      final updatedServerAlias = newServerAlias ?? oldServerAlias;

      final changes = <String, String>{};
      if (updatedNamespace != oldNamespace) {
        changes['namespace'] = '$oldNamespace -> $updatedNamespace';
      }
      if (updatedIdentifier != oldIdentifier) {
        changes['identifier'] = '$oldIdentifier -> $updatedIdentifier';
      }
      if (updatedServerAlias != oldServerAlias) {
        final before = oldServerAlias ?? '(none)';
        final after = updatedServerAlias ?? '(none)';
        changes['server_alias'] = '$before -> $after';
      }

      final proposal = <String, dynamic>{
        'key': key,
        'opcua_node': <String, dynamic>{
          'namespace': updatedNamespace,
          'identifier': updatedIdentifier,
          if (updatedServerAlias != null) 'server_alias': updatedServerAlias,
        },
      };

      if (collectArgs != null) {
        final collect = buildCollect(key, collectArgs);
        proposal['collect'] = collect;
        changes['collect'] = describeCollect(collect);
      } else if (removeCollect) {
        proposal['collect'] = null;
        changes['collect'] = 'removed';
      }

      if (changes.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'Nothing to change on: $key')],
          isError: true,
        );
      }

      final diffMessage =
          proposalService.formatUpdateDiff('Key Mapping', key, changes);

      await riskGate.requestConfirmation(
        description: diffMessage,
        level: RiskLevel.medium,
      );

      final wrapped = await proposalService.wrapProposal('key_mapping', proposal,
          op: 'update');
      return CallToolResult(content: [TextContent(text: jsonEncode(wrapped))]);
    },
  );

  // -- delete_key_mapping ------------------------------------------------

  registry.registerTool(
    name: 'delete_key_mapping',
    description:
        'Propose removing an OPC UA key mapping. Returns proposal JSON for the '
        'key repository editor -- does not write to the database. Anything '
        'still bound to the key (page assets, alarm formulas) reads null once '
        'it is gone, so check for references first.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'The key name to remove (must already exist)',
        ),
      },
      required: ['key'],
    ),
    handler: (args, extra) async {
      final key = args['key'] as String;

      final mappings = await configService.listKeyMappings(filter: key);
      final existing = mappings.where((m) => m['key'] == key).firstOrNull;

      if (existing == null) {
        return CallToolResult(
          content: [TextContent(text: 'No key mapping found for: $key')],
          isError: true,
        );
      }

      final diffMessage = proposalService.formatUpdateDiff(
        'Key Mapping',
        key,
        {'remove': '${existing['identifier']} -> (deleted)'},
      );

      // A removal cannot be undone from the editor once saved.
      await riskGate.requestConfirmation(
        description: diffMessage,
        level: RiskLevel.high,
      );

      final wrapped = await proposalService.wrapProposal(
        'key_mapping',
        {'key': key},
        op: 'delete',
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(wrapped))]);
    },
  );
}

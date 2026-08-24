import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../safety/risk_gate.dart';
import '../services/config_service.dart';
import '../services/proposal_service.dart';
import 'tool_registry.dart';

/// Registers key mapping write tools on the given [registry].
///
/// These tools generate key mapping proposals for the key repository editor
/// -- OPC UA, M2400 weigher, and Modbus (including UMAS-by-name) bindings
/// alike. None of them writes to the database; they return proposal JSON that
/// the Flutter UI routes to the appropriate editor.
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

  JsonSchema m2400NodeSchema() => JsonSchema.object(
        description:
            'Bind this key to an M2400 weigher record stream instead of an '
            'OPC UA node. Pass either this, modbus_node, or the OPC UA '
            'namespace/identifier pair -- exactly one.',
        properties: {
          'record_type': JsonSchema.string(
            enumValues: ['recWgt', 'recIntro', 'recStat', 'recLua', 'recBatch'],
            description:
                'Which record stream to read. recStat carries the live '
                'weight; recBatch fires once per weighed batch.',
          ),
          'field': JsonSchema.string(
            description:
                'Member to extract from the record, e.g. "weight". Omit to '
                'emit the whole record.',
          ),
          'server_alias': JsonSchema.string(
            description:
                'Which configured M2400 device, e.g. "weigher4v". Required '
                'whenever more than one is configured.',
          ),
          'status_filter': JsonSchema.integer(
            description:
                'Only emit recBatch records whose status field equals this '
                'code. On the SVN scales 0 is an accepted batch and 15 a '
                'rejected one -- read off the wire, not from the WeigherStatus '
                'enum labels, which describe a different Marel application.',
          ),
        },
        required: ['record_type'],
      );

  JsonSchema modbusNodeSchema() => JsonSchema.object(
        description:
            'Bind this key to a Modbus register instead of an OPC UA node. '
            'Pass either this, m2400_node, or the OPC UA namespace/identifier '
            'pair -- exactly one. For a Schneider PLC symbol that has no '
            'register address, set variable_name on the mapping as well and '
            'the key is read by UMAS name instead of by address.',
        properties: {
          'register_type': JsonSchema.string(
            enumValues: [
              'coil',
              'discreteInput',
              'holdingRegister',
              'inputRegister'
            ],
            description: 'Register class the address lives in.',
          ),
          'address': JsonSchema.integer(
            description: 'Register address, 0-65535.',
          ),
          'data_type': JsonSchema.string(
            enumValues: [
              'bit',
              'int16',
              'uint16',
              'int32',
              'uint32',
              'float32',
              'int64',
              'uint64',
              'float64'
            ],
            description: 'How to decode the register(s). Defaults to uint16.',
          ),
          'poll_group': JsonSchema.string(
            description:
                'Poll group name; keys in one group are read together. '
                'Defaults to "default".',
          ),
          'server_alias': JsonSchema.string(
            description: 'Which configured Modbus server holds the register.',
          ),
        },
        required: ['register_type', 'address'],
      );

  // Human-readable one-liner for a node object, for the confirmation diff.
  String describeNode(String kind, Map<String, dynamic> node) {
    final parts = node.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    return '$kind($parts)';
  }

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
        'Create a new key mapping proposal -- OPC UA, M2400 weigher, or '
        'Modbus/UMAS. Give exactly one binding: namespace+identifier for an '
        'OPC UA node, or m2400_node, or modbus_node. Returns proposal JSON '
        'for the key repository editor -- does not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'Logical key name e.g. belt.speed',
        ),
        'namespace': JsonSchema.integer(
          description: 'OPC UA namespace index (OPC UA bindings only)',
        ),
        'identifier': JsonSchema.string(
          description: 'OPC UA node identifier e.g. Belt.Speed '
              '(OPC UA bindings only)',
        ),
        'server_alias': JsonSchema.string(
          description:
              'Which configured server holds the node, e.g. "st201". Required '
              'whenever more than one server is configured: a mapping without '
              'it cannot be resolved and reads as null. OPC UA bindings only; '
              'the other kinds carry their alias inside their node object.',
        ),
        'm2400_node': m2400NodeSchema(),
        'modbus_node': modbusNodeSchema(),
        'variable_name': JsonSchema.string(
          description:
              'UMAS symbol path, e.g. "M_Elevator.i_isAuto". Only valid '
              'together with modbus_node, on a server with UMAS enabled: the '
              'key is then read by name rather than by register address.',
        ),
        'collect': collectSchema(),
      },
      required: ['key'],
    ),
    handler: (args, extra) async {
      final key = args['key'] as String;
      final namespace = args['namespace'] as int?;
      final identifier = args['identifier'] as String?;
      final serverAlias = args['server_alias'] as String?;
      final m2400Args = args['m2400_node'] as Map<String, dynamic>?;
      final modbusArgs = args['modbus_node'] as Map<String, dynamic>?;
      final variableName = args['variable_name'] as String?;
      final collectArgs = args['collect'] as Map<String, dynamic>?;

      final wantsOpcua = namespace != null || identifier != null;
      final kinds =
          (wantsOpcua ? 1 : 0) + (m2400Args != null ? 1 : 0) + (modbusArgs != null ? 1 : 0);
      if (kinds != 1) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'Give exactly one binding: namespace+identifier '
                    '(OPC UA), m2400_node, or modbus_node.')
          ],
          isError: true,
        );
      }
      if (wantsOpcua && (namespace == null || identifier == null)) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'An OPC UA binding needs both namespace and identifier.')
          ],
          isError: true,
        );
      }
      if (variableName != null && modbusArgs == null) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'variable_name is a UMAS read through a Modbus server; '
                    'pass modbus_node with it.')
          ],
          isError: true,
        );
      }

      final proposal = <String, dynamic>{'key': key};
      final fields = <String, dynamic>{'key': key};

      if (wantsOpcua) {
        proposal['opcua_node'] = <String, dynamic>{
          'namespace': namespace,
          'identifier': identifier,
          if (serverAlias != null) 'server_alias': serverAlias,
        };
        fields['namespace'] = namespace;
        fields['identifier'] = identifier;
        if (serverAlias != null) fields['server_alias'] = serverAlias;
      }
      if (m2400Args != null) {
        proposal['m2400_node'] = m2400Args;
        fields['m2400_node'] = describeNode('m2400', m2400Args);
      }
      if (modbusArgs != null) {
        proposal['modbus_node'] = modbusArgs;
        fields['modbus_node'] = describeNode('modbus', modbusArgs);
        if (variableName != null) {
          proposal['variable_name'] = variableName;
          fields['variable_name'] = variableName;
        }
      }

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
        'Update an existing key mapping of any kind. OPC UA fields left out '
        'keep their current value; passing m2400_node or modbus_node replaces '
        'that binding whole (and re-points the key to that kind). Returns a '
        'proposal -- does not write to the database.',
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
              'reads null despite a correct node id. OPC UA bindings only.',
        ),
        'm2400_node': m2400NodeSchema(),
        'modbus_node': modbusNodeSchema(),
        'variable_name': JsonSchema.string(
          description:
              'UMAS symbol path; only meaningful on a Modbus binding whose '
              'server has UMAS enabled.',
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
      final m2400Args = args['m2400_node'] as Map<String, dynamic>?;
      final modbusArgs = args['modbus_node'] as Map<String, dynamic>?;
      final variableName = args['variable_name'] as String?;
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

      final wantsOpcua = newNamespace != null ||
          newIdentifier != null ||
          newServerAlias != null;
      if ((wantsOpcua ? 1 : 0) +
              (m2400Args != null ? 1 : 0) +
              (modbusArgs != null ? 1 : 0) >
          1) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'Change one binding kind at a time: OPC UA fields, '
                    'm2400_node, or modbus_node.')
          ],
          isError: true,
        );
      }

      final changes = <String, String>{};
      final proposal = <String, dynamic>{'key': key};

      if (wantsOpcua) {
        // The flat fields are deltas against the existing OPC UA binding, so
        // there has to be one -- on a key bound to another protocol there is
        // nothing to merge them onto.
        final protocol = existing['protocol'] as String?;
        if (protocol != 'opcua') {
          return CallToolResult(
            content: [
              TextContent(
                  text: '"$key" is a $protocol mapping; pass the matching '
                      'node object instead of OPC UA fields.')
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
        proposal['opcua_node'] = <String, dynamic>{
          'namespace': updatedNamespace,
          'identifier': updatedIdentifier,
          if (updatedServerAlias != null) 'server_alias': updatedServerAlias,
        };
      }
      if (m2400Args != null) {
        proposal['m2400_node'] = m2400Args;
        changes['m2400_node'] = describeNode('m2400', m2400Args);
      }
      if (modbusArgs != null) {
        proposal['modbus_node'] = modbusArgs;
        changes['modbus_node'] = describeNode('modbus', modbusArgs);
      }
      if (variableName != null) {
        proposal['variable_name'] = variableName;
        changes['variable_name'] = variableName;
      }

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

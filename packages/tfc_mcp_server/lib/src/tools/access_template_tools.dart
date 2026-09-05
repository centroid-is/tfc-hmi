/// The six access-template tools of spec §7c.
///
/// `list_access_templates` and `list_unbound_keys` are here;
/// `create_access_template`, `update_access_template`,
/// `delete_access_template` and `bind_key_access_template` are in
/// `registerAccessTemplateWriteTools` below. The split follows
/// `alarm_tools.dart` / `alarm_write_tools.dart`, and it is also the toggle
/// boundary: reading the templates is configuration, changing them is
/// authorization and rides the proposal path.
///
/// ## Why forty explicit bindings is the right amount of work
///
/// Spec §7b forbids inferring a binding from a pattern — no `ST101.*` rule,
/// no "everything that looks like a conveyor". The alternative to a pattern
/// match is not a person clicking forty times: it is an agent proposing forty
/// explicit rows that a person reads once and approves. That is what these
/// tools are for, and it is why `bind_key_access_template` takes a **list**.
///
/// ## Why nothing here is gated on `users`, and why that is not a hole
///
/// Spec §7c says "gate these tools on `users`". This package has no session
/// and cannot have one: it is deliberately free of `tfc_dart`'s Flutter graph,
/// it serves a remote agent over SSE, and it has no idea who is standing at
/// the panel. Shipping an `AccessSession` into it would be exactly the
/// dependency `packages/tfc_access`'s purity rule exists to prevent.
///
/// So the gate is at the **approval**. These four write tools change nothing
/// at all; they return a proposal, and `lib/pages/access_templates_section.dart`
/// applies it through `AccessTemplateStore`, which asks for `users` from the
/// live session and records the answer. An agent proposing a change nobody may
/// make gets a proposal nobody can approve — and a denial row saying so, which
/// is the correct outcome rather than a weaker one.
///
/// Two properties hold that argument up, and both are asserted by tests rather
/// than left as prose: nothing in this file or in `AccessTemplateService`
/// writes, and the audit row's `who` comes from the approving session and can
/// never be named by a tool argument.
library;

import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:tfc_access/tfc_access.dart';

import '../safety/risk_gate.dart';
import '../services/access_template_service.dart';
import '../services/config_service.dart';
import '../services/proposal_service.dart';
import 'tool_registry.dart';

// ---------------------------------------------------------------------------
// Shared copy
// ---------------------------------------------------------------------------

/// A station whose schema predates the access tables — or whose database will
/// not answer. Both read the same from here, and the next step is the same.
///
/// Says `no access_template table` in those words because the agent's only
/// other reading of an empty list is "nothing is configured", and the two need
/// different actions: one is a schema upgrade, the other is a template.
const String _kNoTablesNote =
    'This station has no access_template table, so no template exists and no '
    'key is gated above the Operate floor — every key needs only Operate. This is "cannot tell you", not '
    '"there are none": the tables arrive with the database schema upgrade '
    'that adds access templates. Nothing can be proposed until they do.';

/// Every `AccessGroup` name, in enum order.
///
/// Named on every rejection rather than left to the schema's `enum`: an agent
/// that guessed a group has already ignored the schema once, and the seven are
/// fixed in code — a customer invents a role, never a group.
final String _kGroupList = AccessGroup.values.map((g) => g.name).join(', ');

/// How a member name is written back to a reader. `*` is a storage sentinel
/// chosen because it cannot collide with an IEC 61131-3 identifier; on its own
/// it reads as a bug.
String _member(String member) =>
    member == kWholeKeyMember ? '$kWholeKeyMember (the whole key)' : member;

/// The whole key universe, from the `key_mappings` preference.
///
/// `ConfigService.listKeyMappings` emits one entry per key **per protocol**,
/// so a key bound over two protocols arrives twice; deduplicated here. Its
/// limit is a context-window guard for the agent-facing tool, not a plant
/// size, so it is opened right up: a station has thousands of keys and an
/// answer that silently stopped at fifty would let an agent believe it had
/// swept the plant.
///
/// One difference from what the key repository lists, small and deliberate: an
/// entry carrying no protocol mapping at all is not returned by
/// `listKeyMappings` and so is not seen here. Such a key cannot be read or
/// written through `stateMan`, so it cannot be a write-path gap.
Future<List<String>> _keyUniverse(ConfigService configService) async {
  final mappings = await configService.listKeyMappings(limit: 1000000);
  final keys = <String>{for (final m in mappings) m['key'] as String}.toList()
    ..sort();
  return keys;
}

// ---------------------------------------------------------------------------
// Read tools
// ---------------------------------------------------------------------------

/// Registers `list_access_templates` and `list_unbound_keys`.
///
/// Read-only: no [RiskGate], no proposal, no write. Registered under the
/// toggle that carries configuration reads — templates are configuration to
/// *read* and authorization only to *change*.
void registerAccessTemplateTools({
  required ToolRegistry registry,
  required AccessTemplateService service,
  required ConfigService configService,
}) {
  _registerListAccessTemplates(registry, service);
  _registerListUnboundKeys(registry, service, configService);
}

void _registerListAccessTemplates(
    ToolRegistry registry, AccessTemplateService service) {
  registry.registerTool(
    name: 'list_access_templates',
    description:
        'List every access template on this station: its name, the permission '
        'each struct member of a bound key needs, and which keys are bound to '
        'it. A template is the only thing that restricts a write — a key with '
        'no template needs only Operate, so this is also the list of everything '
        'that IS gated here. Read this before proposing any change to a '
        'template, because create_access_template refuses a name that already '
        'exists and update_access_template replaces a template\'s rules '
        'wholesale rather than merging into them.',
    inputSchema: JsonSchema.object(properties: {}),
    handler: (arguments, extra) async {
      final snapshot = await service.snapshot();
      if (!snapshot.tablesPresent) {
        return CallToolResult(content: [TextContent(text: _kNoTablesNote)]);
      }
      if (snapshot.templates.isEmpty) {
        return CallToolResult(content: [
          TextContent(
              text: 'No access templates exist on this station. That is the '
                  'shipped state, not a fault: until a template is created '
                  'and a key is bound to it, every key needs only Operate. '
                  'Use list_unbound_keys to see what that covers.')
        ]);
      }

      final buffer = StringBuffer();
      buffer.writeln(
          '${snapshot.templates.length} access template(s) on this station.');
      buffer.writeln();
      for (final record in snapshot.templates) {
        final template = record.template;
        final bound = snapshot.keysBoundTo(template.name);
        buffer.writeln('${template.name} — ${template.rules.length} rule(s), '
            '${bound.length} key(s) bound');
        if (record.updatedAt != null) {
          buffer.writeln('  last changed: ${record.updatedAt}');
        }
        if (template.rules.isEmpty) {
          buffer.writeln('  no rules, so a key bound to it stays open');
        }
        for (final member in template.rules.keys.toList()..sort()) {
          buffer.writeln(
              '  ${_member(member)} -> ${template.rules[member]!.name}');
        }
        buffer.writeln(
            '  bound keys: ${bound.isEmpty ? '(none)' : bound.join(', ')}');
        buffer.writeln();
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}

void _registerListUnboundKeys(
  ToolRegistry registry,
  AccessTemplateService service,
  ConfigService configService,
) {
  registry.registerTool(
    name: 'list_unbound_keys',
    description:
        'List the keys on this station that no access template governs — the '
        'keys anybody may write. "Unbound" means one of two things and both '
        'are reported, because both drop the key to the Operate floor: '
        'the key has no binding row at all, OR it is bound to a template that '
        'no longer exists (a dangling binding, usually left by a rename). It '
        'does NOT mean "not yet configured": an Operate-floor key still reads '
        'and writes normally, it is simply not gated. This is the sweep tool — '
        'call it, then propose the whole plant\'s bindings in one '
        'bind_key_access_template call. Note that a binding row naming a key '
        'that has since been deleted from the key mappings is an orphan, is '
        'not a key, and is not listed here; do not try to reconcile it '
        'against list_access_templates\' bound-key lists.',
    inputSchema: JsonSchema.object(
      properties: {
        'prefix': JsonSchema.string(
          description: 'Only keys starting with this string. Keys follow the '
              'AREAnn.DEVnn.SUBnn convention, so "ST201." narrows to one '
              'station and "ST101.CN" to one line of conveyors.',
        ),
        'limit': JsonSchema.integer(
          description: 'Maximum number of keys to return (1-1000, default '
              '200). The answer always says how many there were in total, so '
              'a truncated list is visible as one.',
          minimum: 1,
          maximum: 1000,
          defaultValue: 200,
        ),
      },
    ),
    handler: (arguments, extra) async {
      final prefix = arguments['prefix'] as String?;
      final limit = (arguments['limit'] as num?)?.toInt() ?? 200;

      final snapshot = await service.snapshot();
      var keys = await _keyUniverse(configService);
      if (prefix != null && prefix.isNotEmpty) {
        keys = [for (final key in keys) if (key.startsWith(prefix)) key];
      }

      final header = StringBuffer();
      if (!snapshot.tablesPresent) header.writeln('$_kNoTablesNote\n');

      if (keys.isEmpty) {
        header.write(prefix == null || prefix.isEmpty
            ? 'This station has no key mappings, so there is nothing to bind.'
            : 'This station has no key mappings starting with "$prefix", so '
                'there is nothing to bind. (It may still have keys under '
                'another prefix — call again without one.)');
        return CallToolResult(
          content: [TextContent(text: header.toString().trimRight())],
        );
      }

      // One definition of "unbound", shared with the guard and with the key
      // repository's own count: the resolver's, over the same snapshot. A
      // second implementation here is how the agent and the operator start
      // disagreeing about which keys are open (T-04-46).
      final resolver = snapshot.resolver;
      final unbound = resolver.unboundKeys(keys).toList();

      if (unbound.isEmpty) {
        header.write('Every one of the ${keys.length} key(s)'
            '${prefix == null || prefix.isEmpty ? '' : ' under "$prefix"'} is '
            'bound to a template that exists.');
        return CallToolResult(
          content: [TextContent(text: header.toString().trimRight())],
        );
      }

      header.writeln('${unbound.length} of ${keys.length} key(s)'
          '${prefix == null || prefix.isEmpty ? '' : ' under "$prefix"'} have '
          'no template governing them.');
      if (unbound.length > limit) {
        header.writeln('Showing the first $limit of ${unbound.length}.');
      }
      header.writeln();
      for (final key in unbound.take(limit)) {
        final dangling = resolver.boundTemplateName(key);
        header.writeln(dangling == null
            ? key
            : '$key — bound to "$dangling", which has no template row, so it '
                'needs only Operate');
      }
      return CallToolResult(
        content: [TextContent(text: header.toString().trimRight())],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Write tools — every one of them a proposal, and nothing else
// ---------------------------------------------------------------------------

/// Registers `create_access_template`, `update_access_template`,
/// `delete_access_template` and `bind_key_access_template`.
///
/// None of them touches the database. Each validates its arguments against
/// the current snapshot, formats a diff, elicits confirmation through
/// [RiskGate], and returns `wrapProposal('access_template', …)` with `_op`
/// stamped. The application happens in the app, at the accept, through the
/// `users`-gated store — see the library doc above for why the gate lives
/// there and not here.
///
/// Registered under `toggles.proposalsEnabled && toggles.configEnabled`, the
/// same pairing `registerAlarmWriteTools` uses: the tools need the read half
/// to validate against, and the read half rides the config toggle.
void registerAccessTemplateWriteTools({
  required ToolRegistry registry,
  required AccessTemplateService service,
  required RiskGate riskGate,
  required ProposalService proposalService,
}) {
  _registerCreateAccessTemplate(registry, service, riskGate, proposalService);
  _registerUpdateAccessTemplate(registry, service, riskGate, proposalService);
  _registerDeleteAccessTemplate(registry, service, riskGate, proposalService);
  _registerBindKeyAccessTemplate(registry, service, riskGate, proposalService);
}

/// The `rules` argument, shared by create and update.
///
/// An array of `{member, group}` rather than a free-form object, because a
/// JSON-schema object with arbitrary keys tells the agent nothing about what
/// a value may be, and `group` carries an `enum` of exactly the seven.
JsonSchema _rulesSchema() => JsonSchema.array(
      description:
          'One entry per struct member that needs a permission. A member with '
          'no entry is UNRESTRICTED — rules do not fail closed. Use the '
          'member name "$kWholeKeyMember" for the whole key: it is the '
          'key-level default, applied to a scalar write and to any member '
          'without its own entry, so "the whole conveyor needs device except '
          'jogging" is two entries and not twenty.',
      items: JsonSchema.object(
        properties: {
          'member': JsonSchema.string(
            description:
                'Struct member name, spelled exactly as the PLC spells it '
                '(e.g. "p_cfg_ManualFreq"), or "$kWholeKeyMember" for the '
                'whole key.',
          ),
          'group': JsonSchema.string(
            description: 'The permission a write to this member requires.',
            enumValues: [for (final g in AccessGroup.values) g.name],
          ),
        },
        required: ['member', 'group'],
      ),
    );

/// Either the decoded rules or a tool error naming what was wrong.
///
/// The seven are listed on every failure. `AccessGroup.byName` answers null
/// for anything else, and an agent that guessed "supervisor" has no other way
/// to learn the vocabulary.
Object _decodeRules(Object? raw) {
  final rules = <String, AccessGroup>{};
  if (raw == null) return rules;
  if (raw is! List) {
    return 'rules must be an array of {member, group} objects.';
  }
  for (final entry in raw) {
    if (entry is! Map) {
      return 'Each rule must be an object with "member" and "group". '
          'Got: $entry';
    }
    final member = entry['member'];
    final group = entry['group'];
    if (member is! String || member.isEmpty) {
      return 'Each rule needs a non-empty "member". Got: $entry';
    }
    if (group is! String) {
      return 'Rule for "$member" needs a "group". The seven are: '
          '$_kGroupList.';
    }
    final parsed = AccessGroup.byName(group);
    if (parsed == null) {
      return 'Unknown permission group "$group" for member "$member". '
          'The seven are: $_kGroupList. They are fixed in code — a customer '
          'invents a role, never a group.';
    }
    rules[member] = parsed;
  }
  return rules;
}

CallToolResult _error(String message) => CallToolResult(
      content: [TextContent(text: message)],
      isError: true,
    );

/// Rules as a diff-table value: `member -> group`, sorted, one per line.
String _describeRules(Map<String, AccessGroup> rules) => rules.isEmpty
    ? '(no rules — a key bound to this needs only Operate)'
    : [
        for (final member in rules.keys.toList()..sort())
          '${_member(member)} -> ${rules[member]!.name}'
      ].join('; ');

void _registerCreateAccessTemplate(
  ToolRegistry registry,
  AccessTemplateService service,
  RiskGate riskGate,
  ProposalService proposalService,
) {
  registry.registerTool(
    name: 'create_access_template',
    description:
        'Propose a new access template — a named set of member-to-permission '
        'rules that keys can then be bound to. Returns proposal JSON for a '
        'person to approve in the key repository; it does NOT write to the '
        'database, and the change only happens when somebody holding the '
        '"users" permission accepts it. Creating a template gates nothing on '
        'its own: bind keys to it with bind_key_access_template afterwards.',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(
          description: 'Template name, at most 64 characters, no leading or '
              'trailing spaces. It is the identity of the template — keys '
              'name it — so pick what the equipment is, not what the rule is.',
        ),
        'rules': _rulesSchema(),
        'reason': JsonSchema.string(
          description: 'Why this template is needed. Recorded on the audit '
              'row when the change is approved.',
        ),
      },
      required: ['name'],
    ),
    handler: (arguments, extra) async {
      final name = arguments['name'] as String;
      final snapshot = await service.snapshot();
      if (!snapshot.tablesPresent) return _error(_kNoTablesNote);

      if (!AccessTemplate.isValidTemplateName(name)) {
        return _error('"$name" is not a usable template name: it must be '
            'non-empty, at most 64 characters, and carry no leading or '
            'trailing spaces.');
      }
      if (snapshot.named(name) != null) {
        return _error('A template named "$name" already exists. Use '
            'update_access_template to change its rules — this tool would '
            'produce a proposal that fails when somebody tries to approve it.');
      }

      final decoded = _decodeRules(arguments['rules']);
      if (decoded is String) return _error(decoded);
      final rules = decoded as Map<String, AccessGroup>;

      final diff = proposalService.formatCreateDiff('Access template', name, {
        'rules': _describeRules(rules),
        'keys bound': 'none yet — bind them with bind_key_access_template',
        'applied by': 'a person holding "users", in the key repository',
      });
      // ProposalDeclinedException propagates to middleware.
      await riskGate.requestConfirmation(
        description: 'Create access template: $name',
        level: RiskLevel.medium,
        details: {'diff': diff},
      );

      final wrapped = await proposalService.wrapProposal(
        'access_template',
        <String, dynamic>{
          'title': 'Access template "$name"',
          'name': name,
          'rules': {
            for (final member in rules.keys.toList()..sort())
              member: rules[member]!.name,
          },
          if (arguments['reason'] is String) 'reason': arguments['reason'],
        },
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(wrapped))]);
    },
  );
}

void _registerUpdateAccessTemplate(
  ToolRegistry registry,
  AccessTemplateService service,
  RiskGate riskGate,
  ProposalService proposalService,
) {
  registry.registerTool(
    name: 'update_access_template',
    description:
        'Propose replacing an access template\'s rules. The rules given here '
        'REPLACE the template\'s whole rule set — they are not merged into '
        'it, so a member you leave out drops to the Operate floor for every key '
        'bound to this template. Call list_access_templates first and send '
        'back the entries you want to keep. Returns proposal JSON for a '
        'person to approve; it does not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(
          description: 'The template to change. It must already exist.',
        ),
        'rules': _rulesSchema(),
        'reason': JsonSchema.string(
          description: 'Why the rules are changing. Recorded on the audit row '
              'when the change is approved.',
        ),
      },
      required: ['name', 'rules'],
    ),
    handler: (arguments, extra) async {
      final name = arguments['name'] as String;
      final snapshot = await service.snapshot();
      if (!snapshot.tablesPresent) return _error(_kNoTablesNote);

      final existing = snapshot.named(name);
      if (existing == null) {
        return _error('No access template named "$name" on this station. '
            'Call list_access_templates to see what exists, or '
            'create_access_template to propose a new one.');
      }

      final decoded = _decodeRules(arguments['rules']);
      if (decoded is String) return _error(decoded);
      final rules = decoded as Map<String, AccessGroup>;

      final bound = snapshot.keysBoundTo(name);
      final diff = proposalService.formatUpdateDiff('Access template', name, {
        'rules': '${_describeRules(existing.template.rules)} -> '
            '${_describeRules(rules)}',
        'keys affected': '${bound.length} -> '
            '${bound.isEmpty ? 'none' : bound.join(', ')}',
      });
      await riskGate.requestConfirmation(
        description: 'Update access template: $name '
            '(${bound.length} key(s) bound)',
        level: RiskLevel.medium,
        details: {'diff': diff},
      );

      final wrapped = await proposalService.wrapProposal(
        'access_template',
        <String, dynamic>{
          'title': 'Access template "$name"',
          'name': name,
          'rules': {
            for (final member in rules.keys.toList()..sort())
              member: rules[member]!.name,
          },
          'bound_keys': bound,
          if (arguments['reason'] is String) 'reason': arguments['reason'],
        },
        op: 'update',
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(wrapped))]);
    },
  );
}

void _registerDeleteAccessTemplate(
  ToolRegistry registry,
  AccessTemplateService service,
  RiskGate riskGate,
  ProposalService proposalService,
) {
  registry.registerTool(
    name: 'delete_access_template',
    description:
        'Propose removing an access template. A template that keys are still '
        'bound to CANNOT be deleted — the store blocks it, because deleting '
        'it would leave every one of those keys unrestricted with nothing on '
        'screen to say so. The proposal names the keys currently bound so the '
        'approving person sees the cost before agreeing; unbind them first '
        'with bind_key_access_template if the delete is what you want. '
        'Returns proposal JSON; it does not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(
          description: 'The template to remove. It must already exist.',
        ),
        'reason': JsonSchema.string(
          description: 'Why it is being removed. Recorded on the audit row '
              'when the change is approved.',
        ),
      },
      required: ['name'],
    ),
    handler: (arguments, extra) async {
      final name = arguments['name'] as String;
      final snapshot = await service.snapshot();
      if (!snapshot.tablesPresent) return _error(_kNoTablesNote);

      final existing = snapshot.named(name);
      if (existing == null) {
        return _error('No access template named "$name" on this station. '
            'Call list_access_templates to see what exists.');
      }

      // Reported, not decided. The block belongs to the store, which reads
      // `access_key_binding` again at the accept: a key bound between this
      // call and the approval must still stop the delete, and a decision
      // made here would be a decision made on a stale read (T-04-54).
      final bound = snapshot.keysBoundTo(name);
      final diff = proposalService.formatUpdateDiff('Access template', name, {
        'template': '${_describeRules(existing.template.rules)} -> (deleted)',
        'keys still bound': bound.isEmpty
            ? 'none -> the delete is free'
            : '${bound.join(', ')} -> the delete is BLOCKED while they are '
                'bound',
      });
      // High, like delete_alarm: the rules go with the template, and on a
      // station where the block does not apply the keys it governed become
      // writable by anybody.
      await riskGate.requestConfirmation(
        description: bound.isEmpty
            ? 'Delete access template: $name'
            : 'Delete access template: $name — ${bound.length} key(s) still '
                'bound, which blocks it',
        level: RiskLevel.high,
        details: {'diff': diff},
      );

      final wrapped = await proposalService.wrapProposal(
        'access_template',
        <String, dynamic>{
          'title': 'Access template "$name"',
          'name': name,
          'rules': {
            for (final member in existing.template.rules.keys.toList()..sort())
              member: existing.template.rules[member]!.name,
          },
          'bound_keys': bound,
          if (arguments['reason'] is String) 'reason': arguments['reason'],
        },
        op: 'delete',
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(wrapped))]);
    },
  );
}

void _registerBindKeyAccessTemplate(
  ToolRegistry registry,
  AccessTemplateService service,
  RiskGate riskGate,
  ProposalService proposalService,
) {
  registry.registerTool(
    name: 'bind_key_access_template',
    description:
        'Propose binding keys to access templates — or unbinding them, by '
        'omitting the template. Takes a LIST and produces ONE proposal for '
        'the whole list: sweeping a plant is what this tool is for, and forty '
        'separate proposals would be forty separate approvals. Use '
        'list_unbound_keys to find what needs binding, then send the whole '
        'sweep in one call. Every key must be named explicitly; there is no '
        'pattern, prefix or wildcard binding, deliberately (spec §7b) — an '
        'inferred binding is one nobody can audit. Returns proposal JSON; it '
        'does not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'bindings': JsonSchema.array(
          description: 'One entry per key. Send the whole sweep at once.',
          items: JsonSchema.object(
            properties: {
              'key': JsonSchema.string(
                description: 'The key mapping name, e.g. "ST101.CN01".',
              ),
              'template': JsonSchema.string(
                description: 'The template this key resolves through. It must '
                    'already exist. OMIT this field to UNBIND the key, which '
                    'leaves it unrestricted.',
              ),
            },
            required: ['key'],
          ),
        ),
        'reason': JsonSchema.string(
          description: 'Why the sweep is being made. Recorded on the audit '
              'row of every binding when the change is approved.',
        ),
      },
      required: ['bindings'],
    ),
    handler: (arguments, extra) async {
      final snapshot = await service.snapshot();
      if (!snapshot.tablesPresent) return _error(_kNoTablesNote);

      final raw = arguments['bindings'];
      if (raw is! List || raw.isEmpty) {
        return _error('bindings must be a non-empty array of {key, template} '
            'objects. Call list_unbound_keys to find the keys that need one.');
      }

      final bindings = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final entry in raw) {
        if (entry is! Map) {
          return _error('Each binding must be an object with "key" and an '
              'optional "template". Got: $entry');
        }
        final key = entry['key'];
        if (key is! String || key.isEmpty) {
          return _error('Each binding needs a non-empty "key". Got: $entry');
        }
        if (!seen.add(key)) {
          // A key has one binding — `key_name` is the primary key — so two
          // entries for one key is an ambiguous proposal, not a last-wins one.
          return _error('"$key" appears twice in this call. A key resolves '
              'through exactly one template, so name it once.');
        }
        final template = entry['template'];
        if (template != null && template is! String) {
          return _error('"template" must be a template name or omitted (to '
              'unbind). Got: $template for key "$key".');
        }
        if (template is String && snapshot.named(template) == null) {
          return _error('No access template named "$template" on this '
              'station, so binding "$key" to it would leave a DANGLING '
              'binding — which resolves to no restriction at all. Call '
              'list_access_templates, or propose the template first with '
              'create_access_template.');
        }
        bindings.add({'key': key, 'template': template as String?});
      }

      bindings.sort((a, b) =>
          (a['key'] as String).compareTo(b['key'] as String));

      // A readable diff at N rows: one line per key, sorted, saying what it
      // resolves through now and what it would resolve through. A JSON dump
      // of forty bindings is not something a person approves, it is something
      // a person clicks past.
      final changes = <String, String>{};
      var unbinds = 0;
      for (final binding in bindings) {
        final key = binding['key'] as String;
        final to = binding['template'] as String?;
        if (to == null) unbinds++;
        final from = snapshot.bindings[key];
        changes[key] = '${from ?? '(unbound)'} -> ${to ?? '(unbound)'}';
      }
      final diff = proposalService.formatUpdateDiff(
          'Key bindings', '${bindings.length} key(s)', changes);

      // High when anything is unbound: an unbind takes a restriction off, and
      // a sweep that silently included one is the change worth stopping on.
      await riskGate.requestConfirmation(
        description: unbinds == 0
            ? 'Bind ${bindings.length} key(s) to access templates'
            : 'Bind ${bindings.length} key(s) — $unbinds of them UNBOUND, '
                'which leaves those keys unrestricted',
        level: unbinds == 0 ? RiskLevel.medium : RiskLevel.high,
        details: {'diff': diff},
      );

      final wrapped = await proposalService.wrapProposal(
        'access_template',
        <String, dynamic>{
          'title': bindings.length == 1
              ? 'Binding for "${bindings.single['key']}"'
              : '${bindings.length} key bindings',
          'bindings': bindings,
          if (arguments['reason'] is String) 'reason': arguments['reason'],
        },
        op: 'bind',
      );
      return CallToolResult(content: [TextContent(text: jsonEncode(wrapped))]);
    },
  );
}

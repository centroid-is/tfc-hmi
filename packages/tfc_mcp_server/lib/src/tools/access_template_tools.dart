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

import 'package:mcp_dart/mcp_dart.dart';
import 'package:tfc_access/tfc_access.dart';

import '../services/access_template_service.dart';
import '../services/config_service.dart';
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
    'key is gated — every key is unrestricted. This is "cannot tell you", not '
    '"there are none": the tables arrive with the database schema upgrade '
    'that adds access templates. Nothing can be proposed until they do.';

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
        'no template is unrestricted, so this is also the list of everything '
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
                  'and a key is bound to it, every key is unrestricted. '
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
        'are reported, because both leave the key completely unrestricted: '
        'the key has no binding row at all, OR it is bound to a template that '
        'no longer exists (a dangling binding, usually left by a rename). It '
        'does NOT mean "not yet configured": an unrestricted key still reads '
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
                'is unrestricted');
      }
      return CallToolResult(
        content: [TextContent(text: header.toString().trimRight())],
      );
    },
  );
}

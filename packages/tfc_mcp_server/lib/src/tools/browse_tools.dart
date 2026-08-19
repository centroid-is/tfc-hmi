import 'package:mcp_dart/mcp_dart.dart';

import '../interfaces/node_browser.dart';
import 'tool_registry.dart';

/// Registers address-space browsing with the given [ToolRegistry].
///
/// `list_tags` and `get_tag_value` are both bounded by the configured key
/// mappings, so neither can say what a PLC actually publishes. Browsing
/// answers that, and it is what distinguishes a key that is mis-mapped from
/// one the PLC never exposed -- a distinction that is otherwise guesswork.
///
/// Read-only: it reports what is there and never writes.
void registerBrowseTools(ToolRegistry registry, NodeBrowser browser) {
  _registerListSources(registry, browser);
  _registerBrowseNodes(registry, browser);
}

void _registerListSources(ToolRegistry registry, NodeBrowser browser) {
  registry.registerTool(
    name: 'list_browse_sources',
    description: 'List the PLC servers whose address space can be browsed, '
        'with their protocol and endpoint. The alias returned here is the '
        'same one used by key mappings, so a browsed node can be turned into '
        'a mapping directly.',
    inputSchema: JsonSchema.object(properties: {}),
    handler: (arguments, extra) async {
      final sources = browser.sources;
      if (sources.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'No browsable servers. Live PLC connections are '
                    'unavailable, so only configured tags can be queried.'),
          ],
        );
      }
      final buffer = StringBuffer('Browsable servers (${sources.length}):\n');
      for (final s in sources) {
        buffer.writeln('  ${s.alias}  [${s.protocol}]'
            '${s.endpoint != null ? "  ${s.endpoint}" : ""}');
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}

void _registerBrowseNodes(ToolRegistry registry, NodeBrowser browser) {
  registry.registerTool(
    name: 'browse_nodes',
    description: 'Browse one level of a PLC address space. Omit node_id for '
        'the server roots, then pass a returned id to descend. Works for both '
        'OPC UA; ids look like "ns=4;s=A.B.C". Other protocols are covered by '
            'the same interface but are not wired up yet.'
        'whether a tag that reads as unknown actually exists on the server.',
    inputSchema: JsonSchema.object(
      properties: {
        'server_alias': JsonSchema.string(
          description: 'Server to browse, as returned by list_browse_sources '
              '(e.g. "st301")',
        ),
        'node_id': JsonSchema.string(
          description: 'Node whose children to list. Omit for the roots.',
        ),
        'filter': JsonSchema.string(
          description: 'Optional case-insensitive substring filter on the '
              'child name or id',
        ),
        'limit': JsonSchema.integer(
          description: 'Maximum children to return (default 100). A folder '
              'can hold thousands; narrow with filter rather than raising '
              'this.',
          minimum: 1,
          maximum: 500,
          defaultValue: 100,
        ),
      },
      required: ['server_alias'],
    ),
    handler: (arguments, extra) async {
      final alias = arguments['server_alias'] as String;
      final nodeId = arguments['node_id'] as String?;
      final filter = (arguments['filter'] as String?)?.toLowerCase();
      final limit = arguments['limit'] as int? ?? 100;

      final List<BrowsedNode> children;
      try {
        children = await browser.browse(alias, nodeId: nodeId);
      } on ArgumentError catch (e) {
        return CallToolResult(
          content: [TextContent(text: '${e.message}')],
          isError: true,
        );
      } catch (e) {
        // A browse against an unhealthy server can hang or fail outright.
        // Say so plainly -- that is itself a diagnosis.
        return CallToolResult(
          content: [
            TextContent(
                text: 'Browse of "$alias" failed'
                    '${nodeId != null ? " at $nodeId" : ""}: $e'),
          ],
          isError: true,
        );
      }

      var nodes = children;
      if (filter != null && filter.isNotEmpty) {
        nodes = nodes
            .where((n) =>
                n.name.toLowerCase().contains(filter) ||
                n.id.toLowerCase().contains(filter))
            .toList();
      }
      final total = nodes.length;
      if (total > limit) nodes = nodes.sublist(0, limit);

      if (nodes.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'No children under '
                    '${nodeId ?? "the roots"} on "$alias"'
                    '${filter != null ? ' matching "$filter"' : ''}.'),
          ],
        );
      }

      final buffer = StringBuffer(
          '$alias ${nodeId ?? "(roots)"} -- $total child(ren)'
          '${total > nodes.length ? ", showing ${nodes.length}" : ""}:\n');
      for (final n in nodes) {
        buffer.writeln('  [${n.type.name}] ${n.name}'
            '${n.dataType != null ? " : ${n.dataType}" : ""}\n'
            '      id: ${n.id}');
      }
      if (total > nodes.length) {
        buffer.writeln('  ... ${total - nodes.length} more; narrow with '
            '"filter" rather than raising "limit".');
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}

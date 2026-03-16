import 'package:mcp_dart/mcp_dart.dart';

import '../services/tag_service.dart';
import 'tool_registry.dart';

/// Registers tag query tools with the given [ToolRegistry].
///
/// Implements progressive discovery (CORE-05):
/// - **list_tags** (Level 1): Browse available tags with optional fuzzy search
/// - **get_tag_value** (Level 2): Get the current value of a specific tag
///
/// Both tools go through the identity + audit middleware provided by
/// [ToolRegistry], so tool handlers focus only on business logic.
void registerTagTools(ToolRegistry registry, TagService tagService) {
  _registerListTags(registry, tagService);
  _registerGetTagValue(registry, tagService);
}

void _registerListTags(ToolRegistry registry, TagService tagService) {
  registry.registerTool(
    name: 'list_tags',
    description: 'List available tags with optional fuzzy search. '
        'Use this to discover tag names before querying specific values.',
    inputSchema: JsonSchema.object(
      properties: {
        'filter': JsonSchema.string(
          description: 'Optional fuzzy search query to filter tag names '
              '(e.g., "pump" matches "pump3.speed")',
        ),
        'limit': JsonSchema.integer(
          description: 'Maximum number of results to return (default 50)',
          minimum: 1,
          maximum: 200,
          defaultValue: 50,
        ),
      },
    ),
    handler: (arguments, extra) async {
      final filter = arguments['filter'] as String?;
      final limit = arguments['limit'] as int? ?? TagService.defaultLimit;

      final tags = tagService.listTags(filter: filter, limit: limit);

      if (tags.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No tags found.')],
        );
      }

      final buffer = StringBuffer('Tags (${tags.length} results):\n');
      for (final tag in tags) {
        buffer.writeln('  ${tag['key']}: ${tag['value']}');
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}

void _registerGetTagValue(ToolRegistry registry, TagService tagService) {
  registry.registerTool(
    name: 'get_tag_value',
    description: 'Get the current value of a specific tag by its logical key '
        'name. Call directly when you have the key name. Only use list_tags '
        'if you need to discover key names. Do NOT call if the tag value was '
        'already provided in the conversation context.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'The logical key name of the tag '
              '(e.g., "pump3.speed")',
        ),
      },
      required: ['key'],
    ),
    handler: (arguments, extra) async {
      final key = arguments['key'] as String;

      final result = tagService.getTagValue(key);

      if (result == null) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'Tag not found: $key. '
                  'Use list_tags to discover available tag names.',
            ),
          ],
          isError: true,
        );
      }

      return CallToolResult(
        content: [TextContent(text: '${result['key']}: ${result['value']}')],
      );
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/mcp/tool_schema_converter.dart';

void main() {
  late Tool simpleTool;
  late Tool toolWithProperties;

  setUp(() {
    simpleTool = Tool(
      name: 'get_value',
      description: 'Gets a tag value',
      inputSchema: JsonSchema.fromJson({
        'type': 'object',
        'properties': {
          'tag': {'type': 'string', 'description': 'Tag name'},
        },
        'required': ['tag'],
      }),
    );

    toolWithProperties = Tool(
      name: 'search_docs',
      description: 'Searches documents',
      inputSchema: JsonSchema.fromJson({
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'limit': {'type': 'number'},
          'filters': {
            'type': 'object',
            'properties': {
              'category': {'type': 'string'},
              'tags': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
          },
        },
        'required': ['query'],
      }),
    );
  });

  group('toAnthropic', () {
    test('produces name, description, input_schema', () {
      final result = ToolSchemaConverter.toAnthropic(simpleTool);

      expect(result['name'], 'get_value');
      expect(result['description'], 'Gets a tag value');
      expect(result['input_schema'], isA<Map>());
      expect(
        (result['input_schema'] as Map)['type'],
        'object',
      );
    });

    test('omits description when null', () {
      final tool = Tool(
        name: 'no_desc',
        inputSchema: JsonSchema.fromJson({'type': 'object'}),
      );
      final result = ToolSchemaConverter.toAnthropic(tool);

      expect(result.containsKey('description'), isFalse);
    });
  });

  group('toOpenAI', () {
    test('wraps in function envelope', () {
      final result = ToolSchemaConverter.toOpenAI(simpleTool);

      expect(result['type'], 'function');
      final fn = result['function'] as Map<String, dynamic>;
      expect(fn['name'], 'get_value');
      expect(fn['description'], 'Gets a tag value');
      expect(fn['parameters'], isA<Map>());
    });

    test('omits description when null', () {
      final tool = Tool(
        name: 'no_desc',
        inputSchema: JsonSchema.fromJson({'type': 'object'}),
      );
      final result = ToolSchemaConverter.toOpenAI(tool);
      final fn = result['function'] as Map<String, dynamic>;

      expect(fn.containsKey('description'), isFalse);
    });
  });

  group('toGemini', () {
    test('uppercases type names', () {
      final result = ToolSchemaConverter.toGemini(simpleTool);

      expect(result['name'], 'get_value');
      expect(result['description'], 'Gets a tag value');
      final params = result['parameters'] as Map<String, dynamic>;
      expect(params['type'], 'OBJECT');
      final props = params['properties'] as Map<String, dynamic>;
      expect((props['tag'] as Map)['type'], 'STRING');
    });

    test('recursively uppercases nested types', () {
      final result = ToolSchemaConverter.toGemini(toolWithProperties);
      final params = result['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;

      // Nested object type
      final filters = props['filters'] as Map<String, dynamic>;
      expect(filters['type'], 'OBJECT');

      // Nested string inside nested object
      final filterProps = filters['properties'] as Map<String, dynamic>;
      expect((filterProps['category'] as Map)['type'], 'STRING');

      // Array type
      final tags = filterProps['tags'] as Map<String, dynamic>;
      expect(tags['type'], 'ARRAY');
    });
  });

  group('convertAll', () {
    test('converts to Anthropic format for claude provider', () {
      final results = ToolSchemaConverter.convertAll(
        [simpleTool],
        LlmProviderType.claude,
      );

      expect(results, hasLength(1));
      expect(results.first['name'], 'get_value');
      expect(results.first.containsKey('input_schema'), isTrue);
    });

    test('converts to OpenAI format for openai provider', () {
      final results = ToolSchemaConverter.convertAll(
        [simpleTool],
        LlmProviderType.openai,
      );

      expect(results, hasLength(1));
      expect(results.first['type'], 'function');
    });

    test('converts to Gemini format for gemini provider', () {
      final results = ToolSchemaConverter.convertAll(
        [simpleTool],
        LlmProviderType.gemini,
      );

      expect(results, hasLength(1));
      final params = results.first['parameters'] as Map<String, dynamic>;
      expect(params['type'], 'OBJECT');
    });

    test('handles multiple tools', () {
      final results = ToolSchemaConverter.convertAll(
        [simpleTool, toolWithProperties],
        LlmProviderType.claude,
      );

      expect(results, hasLength(2));
      expect(results[0]['name'], 'get_value');
      expect(results[1]['name'], 'search_docs');
    });

    test('handles empty tool list', () {
      final results = ToolSchemaConverter.convertAll(
        [],
        LlmProviderType.claude,
      );

      expect(results, isEmpty);
    });
  });
}

import 'package:mcp_dart/mcp_dart.dart';

import '../llm/llm_models.dart';

/// Converts MCP [Tool] definitions to provider-specific tool schema formats.
///
/// Each LLM provider (Claude/Anthropic, OpenAI, Gemini) expects tool
/// definitions in a slightly different JSON format. This converter takes
/// the canonical MCP Tool definition and produces the correct format.
class ToolSchemaConverter {
  /// Converts an MCP [Tool] to Anthropic/Claude tool format.
  ///
  /// Output format:
  /// ```json
  /// {
  ///   "name": "...",
  ///   "description": "...",
  ///   "input_schema": { "type": "object", "properties": {...}, "required": [...] }
  /// }
  /// ```
  static Map<String, dynamic> toAnthropic(Tool mcpTool) {
    return {
      'name': mcpTool.name,
      if (mcpTool.description != null) 'description': mcpTool.description,
      'input_schema': mcpTool.inputSchema.toJson(),
    };
  }

  /// Converts an MCP [Tool] to OpenAI tool format.
  ///
  /// Output format:
  /// ```json
  /// {
  ///   "type": "function",
  ///   "function": {
  ///     "name": "...",
  ///     "description": "...",
  ///     "parameters": { "type": "object", "properties": {...}, "required": [...] }
  ///   }
  /// }
  /// ```
  static Map<String, dynamic> toOpenAI(Tool mcpTool) {
    return {
      'type': 'function',
      'function': {
        'name': mcpTool.name,
        if (mcpTool.description != null) 'description': mcpTool.description,
        'parameters': mcpTool.inputSchema.toJson(),
      },
    };
  }

  /// Converts an MCP [Tool] to Gemini tool format.
  ///
  /// Gemini uses UPPERCASE type names (OBJECT, STRING, NUMBER, etc.)
  /// instead of the lowercase JSON Schema types.
  ///
  /// Output format:
  /// ```json
  /// {
  ///   "name": "...",
  ///   "description": "...",
  ///   "parameters": { "type": "OBJECT", "properties": {...}, "required": [...] }
  /// }
  /// ```
  static Map<String, dynamic> toGemini(Tool mcpTool) {
    final schema = mcpTool.inputSchema.toJson();
    return {
      'name': mcpTool.name,
      if (mcpTool.description != null) 'description': mcpTool.description,
      'parameters': _uppercaseTypes(schema),
    };
  }

  /// Converts all [tools] to the format expected by [provider].
  static List<Map<String, dynamic>> convertAll(
    List<Tool> tools,
    LlmProviderType provider,
  ) {
    switch (provider) {
      case LlmProviderType.claude:
        return tools.map(toAnthropic).toList();
      case LlmProviderType.openai:
        return tools.map(toOpenAI).toList();
      case LlmProviderType.gemini:
        return tools.map(toGemini).toList();
    }
  }

  /// Recursively converts lowercase JSON Schema type names to UPPERCASE
  /// as required by Gemini's API.
  static Map<String, dynamic> _uppercaseTypes(Map<String, dynamic> schema) {
    final result = <String, dynamic>{};
    for (final entry in schema.entries) {
      if (entry.key == 'type' && entry.value is String) {
        result['type'] = (entry.value as String).toUpperCase();
      } else if (entry.value is Map<String, dynamic>) {
        result[entry.key] = _uppercaseTypes(entry.value as Map<String, dynamic>);
      } else if (entry.value is List) {
        result[entry.key] = (entry.value as List).map((item) {
          if (item is Map<String, dynamic>) {
            return _uppercaseTypes(item);
          }
          return item;
        }).toList();
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }
}

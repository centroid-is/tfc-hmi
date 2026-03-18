import 'dart:convert';
import 'dart:io' if (dart.library.js_interop) '../core/io_stub.dart';

import 'llm_models.dart';
import 'llm_provider.dart';

/// Result of converting [ChatMessage]s to Gemini REST API format.
class GeminiConvertedMessages {
  /// System instruction content, or null if no system messages.
  final Map<String, dynamic>? systemInstruction;

  /// Conversation contents in Gemini format (role/parts).
  final List<Map<String, dynamic>> contents;

  const GeminiConvertedMessages({
    required this.systemInstruction,
    required this.contents,
  });
}

/// Gemini LLM provider implementation.
///
/// Uses raw HTTP (`dart:io` [HttpClient]) to call the Gemini REST API
/// at `generativelanguage.googleapis.com`. This avoids depending on the
/// deprecated `google_generative_ai` package or Firebase AI Logic SDK.
///
/// Handles Gemini-specific quirks:
/// - Uses 'model' role instead of 'assistant'
/// - Uses UPPERCASE type names in tool schemas (OBJECT, STRING, etc.)
/// - Uses `functionCall`/`functionResponse` instead of tool_use/tool_result
/// - System messages go in `systemInstruction` field
class GeminiProvider extends LlmProvider {
  /// The HTTP client for making requests.
  final HttpClient _httpClient;

  /// The Gemini API key.
  final String _apiKey;

  /// The model to use for completions.
  final String model;

  /// Creates a [GeminiProvider].
  ///
  /// Throws [ArgumentError] if [apiKey] is empty.
  GeminiProvider({
    required String apiKey,
    this.model = 'gemini-2.5-flash',
  })  : _apiKey = apiKey,
        _httpClient = HttpClient() {
    if (apiKey.isEmpty) {
      throw ArgumentError('API key must not be empty');
    }
  }

  @override
  LlmProviderType get providerType => LlmProviderType.gemini;

  @override
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final converted = convertMessages(messages);
    final toolDefs = tools.isNotEmpty ? convertTools(tools) : null;

    final body = <String, dynamic>{
      'contents': converted.contents,
      if (converted.systemInstruction != null)
        'systemInstruction': converted.systemInstruction,
      if (toolDefs != null) 'tools': toolDefs,
    };

    final url = buildRequestUrl();
    final uri = Uri.parse(url);
    final request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini API error ${response.statusCode}: $responseBody',
      );
    }

    final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;
    return parseResponse(responseJson);
  }

  /// Builds the Gemini REST API URL for the `generateContent` endpoint.
  ///
  /// Visible for testing.
  String buildRequestUrl() {
    return 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey';
  }

  /// Converts a list of [ChatMessage]s to Gemini REST API format.
  ///
  /// System messages are extracted to the `systemInstruction` field.
  /// User messages use role 'user', assistant messages use role 'model'.
  /// Tool results become role 'function' with `functionResponse` parts.
  ///
  /// Visible for testing.
  GeminiConvertedMessages convertMessages(List<ChatMessage> messages) {
    Map<String, dynamic>? systemInstruction;
    final contents = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case ChatRole.system:
          // System messages go in systemInstruction
          systemInstruction = {
            'parts': [
              {'text': msg.content},
            ],
          };
          break;

        case ChatRole.user:
          final parts = <Map<String, dynamic>>[];
          if (msg.attachments != null) {
            for (final attachment in msg.attachments!) {
              parts.add({
                'inline_data': {
                  'mime_type': attachment.mimeType,
                  'data': base64Encode(attachment.bytes),
                },
              });
            }
          }
          parts.add({'text': msg.content});
          contents.add({
            'role': 'user',
            'parts': parts,
          });
          break;

        case ChatRole.assistant:
          final parts = <Map<String, dynamic>>[];
          if (msg.content.isNotEmpty) {
            parts.add({'text': msg.content});
          }
          // Include tool calls as functionCall parts
          for (final tc in msg.toolCalls) {
            parts.add({
              'functionCall': {
                'name': tc.name,
                'args': tc.arguments,
              },
            });
          }
          contents.add({
            'role': 'model',
            'parts': parts,
          });
          break;

        case ChatRole.tool:
          // Tool results go as function role with functionResponse
          // The toolCallId is the function name in Gemini's format
          String content;
          try {
            // Try to parse as JSON for structured response
            content = msg.content;
          } catch (_) {
            content = msg.content;
          }
          contents.add({
            'role': 'function',
            'parts': [
              {
                'functionResponse': {
                  'name': msg.toolCallId ?? 'unknown',
                  'response': {
                    'content': content,
                  },
                },
              },
            ],
          });
          break;
      }
    }

    return GeminiConvertedMessages(
      systemInstruction: systemInstruction,
      contents: contents,
    );
  }

  /// Converts tool definition maps (Gemini format from [ToolSchemaConverter])
  /// to Gemini REST API tool format.
  ///
  /// Wraps each tool as a `functionDeclarations` entry.
  ///
  /// Visible for testing.
  List<Map<String, dynamic>> convertTools(List<Map<String, dynamic>> tools) {
    return [
      {
        'functionDeclarations': tools.map((t) {
          return {
            'name': t['name'],
            if (t['description'] != null) 'description': t['description'],
            if (t['parameters'] != null) 'parameters': t['parameters'],
          };
        }).toList(),
      },
    ];
  }

  /// Parses a Gemini REST API response JSON into an [LlmResponse].
  ///
  /// Extracts text from `text` parts and tool calls from `functionCall` parts.
  ///
  /// Visible for testing.
  LlmResponse parseResponse(Map<String, dynamic> responseJson) {
    final candidates = responseJson['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return const LlmResponse(
        content: '',
        toolCalls: [],
        stopReason: 'STOP',
      );
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>?;
    final finishReason = candidate['finishReason'] as String? ?? 'STOP';

    if (content == null) {
      return LlmResponse(
        content: '',
        toolCalls: [],
        stopReason: finishReason,
      );
    }

    final parts = content['parts'] as List? ?? [];
    final textParts = <String>[];
    final toolCalls = <ToolCall>[];
    var toolCallCounter = 0;

    for (final part in parts) {
      final partMap = (part as Map).cast<String, dynamic>();
      if (partMap.containsKey('text')) {
        textParts.add(partMap['text'] as String);
      } else if (partMap.containsKey('functionCall')) {
        final funcCall = (partMap['functionCall'] as Map).cast<String, dynamic>();
        final args = funcCall['args'];
        toolCalls.add(ToolCall(
          id: 'gemini-tc-${toolCallCounter++}',
          name: funcCall['name'] as String,
          arguments: args is Map
              ? args.cast<String, dynamic>()
              : <String, dynamic>{},
        ));
      }
    }

    return LlmResponse(
      content: textParts.join('\n'),
      toolCalls: toolCalls,
      stopReason: finishReason,
    );
  }

  /// Converts a lowercase JSON Schema type name to UPPERCASE for Gemini.
  ///
  /// Gemini REST API uses UPPERCASE type names: OBJECT, STRING, NUMBER, etc.
  static String convertTypeToGemini(String jsonSchemaType) {
    return jsonSchemaType.toUpperCase();
  }

  @override
  void dispose() {
    _httpClient.close();
  }
}

import 'dart:convert';

import 'package:openai_dart/openai_dart.dart' as openai;

import 'llm_models.dart';
import 'llm_provider.dart';

/// OpenAI LLM provider implementation.
///
/// Uses `openai_dart` to call the OpenAI Chat Completions API.
/// Handles conversion between the common [ChatMessage]/[ToolCall] types
/// and the OpenAI-specific message format.
class OpenAiProvider extends LlmProvider {
  /// The OpenAI API client.
  final openai.OpenAIClient _client;

  /// The model to use for completions.
  final String model;

  /// Creates an [OpenAiProvider].
  ///
  /// Throws [ArgumentError] if [apiKey] is empty.
  OpenAiProvider({
    required String apiKey,
    String? baseUrl,
    this.model = 'gpt-4o',
  }) : _client = _createClient(apiKey, baseUrl);

  static openai.OpenAIClient _createClient(String apiKey, String? baseUrl) {
    if (apiKey.isEmpty) {
      throw ArgumentError('API key must not be empty');
    }
    return openai.OpenAIClient(
      config: openai.OpenAIConfig(
        authProvider: openai.ApiKeyProvider(apiKey),
        baseUrl: baseUrl ?? 'https://api.openai.com/v1',
      ),
    );
  }

  @override
  LlmProviderType get providerType => LlmProviderType.openai;

  @override
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final converted = convertMessages(messages);
    final toolDefs = tools.isNotEmpty ? convertTools(tools) : null;

    final request = openai.ChatCompletionCreateRequest(
      model: model,
      messages: converted,
      tools: toolDefs,
    );

    final response = await _client.chat.completions.create(request);
    return parseResponse(response);
  }

  /// Converts a list of [ChatMessage]s to OpenAI API format.
  ///
  /// Maps each [ChatRole] to the corresponding OpenAI message type:
  /// - system -> [SystemMessage]
  /// - user -> [UserMessage]
  /// - assistant -> [AssistantMessage] (with optional tool calls)
  /// - tool -> [ToolMessage]
  ///
  /// Visible for testing.
  List<openai.ChatMessage> convertMessages(
    List<ChatMessage> messages, {
    void Function(String)? onWarning,
  }) {
    return messages.map((msg) {
      switch (msg.role) {
        case ChatRole.system:
          return openai.ChatMessage.system(msg.content);

        case ChatRole.user:
          if (msg.attachments != null && msg.attachments!.isNotEmpty) {
            onWarning?.call(
              'PDF attachments are not supported by OpenAI provider. '
              'Sending text-only message.',
            );
          }
          return openai.ChatMessage.user(msg.content);

        case ChatRole.assistant:
          return openai.ChatMessage.assistant(
            content: msg.content.isNotEmpty ? msg.content : null,
            toolCalls: msg.toolCalls.isNotEmpty
                ? msg.toolCalls.map((tc) {
                    return openai.ToolCall(
                      id: tc.id,
                      type: 'function',
                      function: openai.FunctionCall(
                        name: tc.name,
                        arguments: jsonEncode(tc.arguments),
                      ),
                    );
                  }).toList()
                : null,
          );

        case ChatRole.tool:
          return openai.ChatMessage.tool(
            toolCallId: msg.toolCallId!,
            content: msg.content,
          );
      }
    }).toList();
  }

  /// Converts tool definition maps (OpenAI format from [ToolSchemaConverter])
  /// to OpenAI SDK [Tool] objects.
  ///
  /// Visible for testing.
  List<openai.Tool> convertTools(List<Map<String, dynamic>> tools) {
    return tools.map((t) => openai.Tool.fromJson(t)).toList();
  }

  /// Parses an OpenAI [ChatCompletion] response into an [LlmResponse].
  ///
  /// Extracts text content and tool calls from the first choice.
  ///
  /// Visible for testing.
  LlmResponse parseResponse(openai.ChatCompletion response) {
    final choice = response.choices.first;
    final message = choice.message;

    final toolCalls = <ToolCall>[];
    if (message.toolCalls != null) {
      for (final tc in message.toolCalls!) {
        toolCalls.add(ToolCall(
          id: tc.id,
          name: tc.function.name,
          arguments: tc.function.argumentsMap,
        ));
      }
    }

    return LlmResponse(
      content: message.content ?? '',
      toolCalls: toolCalls,
      stopReason: choice.finishReason?.value ?? 'stop',
    );
  }

  @override
  void dispose() {
    _client.close();
  }
}

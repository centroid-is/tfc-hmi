import 'dart:convert';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;

import 'llm_models.dart';
import 'llm_provider.dart';

/// Result of converting [ChatMessage]s to Anthropic API format.
///
/// Separates system messages (which go in the `system` parameter)
/// from conversation messages (which go in the `messages` parameter).
class AnthropicConvertedMessages {
  /// System prompt text extracted from system messages, or null if none.
  final String? systemPrompt;

  /// Conversation messages in Anthropic API format.
  final List<anthropic.InputMessage> messages;

  const AnthropicConvertedMessages({
    required this.systemPrompt,
    required this.messages,
  });
}

/// Claude/Anthropic LLM provider implementation.
///
/// Uses `anthropic_sdk_dart` to call the Anthropic Messages API.
/// Handles conversion between the common [ChatMessage]/[ToolCall] types
/// and the Anthropic-specific message format.
class ClaudeProvider extends LlmProvider {
  /// The Anthropic API client.
  final anthropic.AnthropicClient _client;

  /// The model to use for completions.
  final String model;

  /// Creates a [ClaudeProvider].
  ///
  /// Throws [ArgumentError] if [apiKey] is empty.
  ClaudeProvider({
    required String apiKey,
    String? baseUrl,
    this.model = 'claude-sonnet-4-20250514',
  }) : _client = _createClient(apiKey, baseUrl);

  static anthropic.AnthropicClient _createClient(String apiKey, String? baseUrl) {
    if (apiKey.isEmpty) {
      throw ArgumentError('API key must not be empty');
    }
    return anthropic.AnthropicClient.withApiKey(apiKey, baseUrl: baseUrl);
  }

  @override
  LlmProviderType get providerType => LlmProviderType.claude;

  @override
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final converted = convertMessages(messages);
    final toolDefs = tools.isNotEmpty ? convertTools(tools) : null;

    final request = anthropic.MessageCreateRequest(
      model: model,
      maxTokens: 4096,
      messages: converted.messages,
      system: converted.systemPrompt != null
          ? buildCachedSystemPrompt(converted.systemPrompt!)
          : null,
      tools: toolDefs,
    );

    final response = await _client.messages.create(request);
    return parseResponse(response);
  }

  /// Converts a list of [ChatMessage]s to Anthropic API format.
  ///
  /// System messages are extracted to a separate system prompt string.
  /// Tool result messages become user messages with [ToolResultInputBlock].
  /// Assistant messages with tool calls include [ToolUseInputBlock]s.
  ///
  /// Visible for testing.
  AnthropicConvertedMessages convertMessages(List<ChatMessage> messages) {
    String? systemPrompt;
    final converted = <anthropic.InputMessage>[];

    for (final msg in messages) {
      switch (msg.role) {
        case ChatRole.system:
          // Anthropic expects system as a separate parameter, not in messages.
          // If multiple system messages, concatenate them.
          systemPrompt = systemPrompt != null
              ? '$systemPrompt\n${msg.content}'
              : msg.content;
          break;

        case ChatRole.user:
          if (msg.attachments != null && msg.attachments!.isNotEmpty) {
            final blocks = <anthropic.InputContentBlock>[];
            for (final attachment in msg.attachments!) {
              if (attachment.mimeType == 'application/pdf') {
                blocks.add(anthropic.InputContentBlock.document(
                  anthropic.DocumentSource.base64Pdf(
                    base64Encode(attachment.bytes),
                  ),
                  title: attachment.filename,
                ));
              }
            }
            blocks.add(anthropic.InputContentBlock.text(msg.content));
            converted.add(anthropic.InputMessage.userBlocks(blocks));
          } else {
            converted.add(anthropic.InputMessage.user(msg.content));
          }
          break;

        case ChatRole.assistant:
          if (msg.toolCalls.isNotEmpty) {
            // Assistant message with tool calls: include text + tool_use blocks
            final blocks = <anthropic.InputContentBlock>[];
            if (msg.content.isNotEmpty) {
              blocks.add(anthropic.InputContentBlock.text(msg.content));
            }
            for (final tc in msg.toolCalls) {
              blocks.add(anthropic.InputContentBlock.toolUse(
                id: tc.id,
                name: tc.name,
                input: tc.arguments,
              ));
            }
            converted.add(anthropic.InputMessage.assistantBlocks(blocks));
          } else {
            converted.add(anthropic.InputMessage.assistant(msg.content));
          }
          break;

        case ChatRole.tool:
          // Tool results go as user messages with ToolResultInputBlock
          converted.add(anthropic.InputMessage.userBlocks([
            anthropic.InputContentBlock.toolResultText(
              toolUseId: msg.toolCallId!,
              text: msg.content,
            ),
          ]));
          break;
      }
    }

    return AnthropicConvertedMessages(
      systemPrompt: systemPrompt,
      messages: converted,
    );
  }

  /// Builds a system prompt with `cache_control` set to ephemeral.
  ///
  /// Uses [SystemPrompt.blocks] with a single [SystemTextBlock] that has
  /// `cache_control: {"type": "ephemeral"}`. This tells the Anthropic API
  /// to cache the system prompt server-side, reducing cost by 90% on
  /// cached input tokens for subsequent turns in a conversation.
  ///
  /// Visible for testing.
  anthropic.SystemPrompt buildCachedSystemPrompt(String text) {
    return anthropic.SystemPrompt.blocks([
      anthropic.SystemTextBlock(
        text: text,
        cacheControl: const anthropic.CacheControlEphemeral(),
      ),
    ]);
  }

  /// Converts tool definition maps (Anthropic format from [ToolSchemaConverter])
  /// to Anthropic SDK [ToolDefinition] objects.
  ///
  /// Adds `cache_control: {"type": "ephemeral"}` to the **last** tool
  /// definition, which tells the Anthropic API to cache all tool definitions
  /// up to and including that breakpoint. This reduces cost by 90% on
  /// cached input tokens for multi-turn conversations.
  ///
  /// Visible for testing.
  List<anthropic.ToolDefinition> convertTools(
      List<Map<String, dynamic>> tools) {
    final result = <anthropic.ToolDefinition>[];
    for (var i = 0; i < tools.length; i++) {
      final t = tools[i];
      final isLast = i == tools.length - 1;
      final tool = anthropic.Tool(
        name: t['name'] as String,
        description: t['description'] as String?,
        inputSchema: anthropic.InputSchema.fromJson(
          t['input_schema'] as Map<String, dynamic>? ??
              {'type': 'object'},
        ),
        cacheControl: isLast
            ? const anthropic.CacheControlEphemeral()
            : null,
      );
      result.add(anthropic.ToolDefinition.custom(tool));
    }
    return result;
  }

  /// Parses an Anthropic [Message] response into an [LlmResponse].
  ///
  /// Extracts text from [TextBlock]s and tool calls from [ToolUseBlock]s.
  ///
  /// Visible for testing.
  LlmResponse parseResponse(anthropic.Message response) {
    final textParts = <String>[];
    final toolCalls = <ToolCall>[];

    for (final block in response.content) {
      if (block is anthropic.TextBlock) {
        textParts.add(block.text);
      } else if (block is anthropic.ToolUseBlock) {
        toolCalls.add(ToolCall(
          id: block.id,
          name: block.name,
          arguments: block.input,
        ));
      }
    }

    return LlmResponse(
      content: textParts.join('\n'),
      toolCalls: toolCalls,
      stopReason: response.stopReason?.value ?? 'end_turn',
    );
  }

  @override
  void dispose() {
    _client.close();
  }
}

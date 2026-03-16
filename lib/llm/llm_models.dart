import 'dart:typed_data';

/// LLM provider type selection.
enum LlmProviderType {
  claude,
  openai,
  gemini;

  /// Human-readable display name for this provider.
  String get displayName {
    switch (this) {
      case LlmProviderType.claude:
        return 'Claude';
      case LlmProviderType.openai:
        return 'OpenAI';
      case LlmProviderType.gemini:
        return 'Gemini';
    }
  }
}

/// Chat message role.
enum ChatRole {
  user,
  assistant,
  system,
  tool,
}

/// A file attachment on a chat message (e.g. PDF drawing).
class ChatAttachment {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const ChatAttachment({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
}

/// A message in a chat conversation.
class ChatMessage {
  /// The role of the message sender.
  final ChatRole role;

  /// The text content of the message.
  final String content;

  /// For tool result messages, the ID of the tool call this is a response to.
  final String? toolCallId;

  /// For assistant messages, any tool calls the assistant wants to make.
  final List<ToolCall> toolCalls;

  /// Optional file attachments (e.g. PDF drawings). Transient — not serialized.
  final List<ChatAttachment>? attachments;

  const ChatMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls = const [],
    this.attachments,
  });

  /// Serializes this message to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        if (toolCallId != null) 'toolCallId': toolCallId,
        if (toolCalls.isNotEmpty)
          'toolCalls': toolCalls.map((tc) => tc.toJson()).toList(),
      };

  /// Deserializes a [ChatMessage] from a JSON map.
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: ChatRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        toolCallId: json['toolCallId'] as String?,
        toolCalls: (json['toolCalls'] as List<dynamic>?)
                ?.map((tc) => ToolCall.fromJson(tc as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// Creates a user message, optionally with file attachments.
  factory ChatMessage.user(String text, {List<ChatAttachment>? attachments}) =>
      ChatMessage(
        role: ChatRole.user,
        content: text,
        attachments: attachments,
      );

  /// Creates an assistant message, optionally with tool calls.
  factory ChatMessage.assistant(String text,
          {List<ToolCall> toolCalls = const []}) =>
      ChatMessage(
        role: ChatRole.assistant,
        content: text,
        toolCalls: toolCalls,
      );

  /// Creates a system message.
  factory ChatMessage.system(String text) => ChatMessage(
        role: ChatRole.system,
        content: text,
      );

  /// Creates a tool result message.
  factory ChatMessage.toolResult(String toolCallId, String content,
          {bool isError = false}) =>
      ChatMessage(
        role: ChatRole.tool,
        content: content,
        toolCallId: toolCallId,
      );
}

/// A tool invocation requested by the LLM.
class ToolCall {
  /// Unique identifier for this tool call.
  final String id;

  /// The name of the tool to invoke.
  final String name;

  /// Arguments to pass to the tool.
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// Serializes this tool call to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
      };

  /// Deserializes a [ToolCall] from a JSON map.
  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        id: json['id'] as String,
        name: json['name'] as String,
        arguments: Map<String, dynamic>.from(json['arguments'] as Map),
      );
}

/// The result of executing a tool call.
class ToolResult {
  /// The ID of the tool call this result corresponds to.
  final String toolCallId;

  /// The text content of the result.
  final String content;

  /// Whether the tool execution resulted in an error.
  final bool isError;

  const ToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
  });
}

/// Response from an LLM completion call.
class LlmResponse {
  /// The text content of the response.
  final String content;

  /// Any tool calls the LLM wants to make.
  final List<ToolCall> toolCalls;

  /// The reason the LLM stopped generating (e.g., 'end_turn', 'tool_use').
  final String stopReason;

  const LlmResponse({
    required this.content,
    required this.toolCalls,
    required this.stopReason,
  });

  /// Whether this response contains tool calls.
  bool get hasToolCalls => toolCalls.isNotEmpty;
}

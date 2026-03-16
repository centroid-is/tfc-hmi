import 'llm_models.dart';

/// Preference key constants for LLM API key storage.
const kClaudeApiKey = 'llm.claude.api_key';
const kOpenAiApiKey = 'llm.openai.api_key';
const kGeminiApiKey = 'llm.gemini.api_key';
const kSelectedProvider = 'llm.selected_provider';

/// Preference key constants for custom LLM base URLs.
const kClaudeBaseUrl = 'llm.claude.base_url';
const kOpenAiBaseUrl = 'llm.openai.base_url';

/// Abstract interface for LLM providers.
///
/// Concrete implementations (Claude, OpenAI, Gemini) are created in Plan 02.
/// Each provider must implement [complete] to send messages to their API
/// and return an [LlmResponse].
abstract class LlmProvider {
  /// Which provider type this is.
  LlmProviderType get providerType;

  /// Send a list of messages to the LLM and get a response.
  ///
  /// [messages] is the conversation history.
  /// [tools] is an optional list of tool definitions in the provider's format
  /// (produced by [ToolSchemaConverter]).
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  });

  /// Clean up resources (e.g., close HTTP clients).
  void dispose();

  /// Returns the preference key for this provider's API key.
  String get apiKeyPreferenceKey {
    switch (providerType) {
      case LlmProviderType.claude:
        return kClaudeApiKey;
      case LlmProviderType.openai:
        return kOpenAiApiKey;
      case LlmProviderType.gemini:
        return kGeminiApiKey;
    }
  }
}

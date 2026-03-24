import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/llm/claude_provider.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/llm/openai_provider.dart';
import 'package:tfc/providers/chat.dart';

/// Tests for custom base URL configuration on LLM providers.
///
/// Verifies that ClaudeProvider and OpenAiProvider accept baseUrl
/// parameters for proxy/local LLM use cases.
void main() {
  group('ClaudeProvider baseUrl', () {
    test('accepts custom baseUrl', () {
      final provider = ClaudeProvider(
        apiKey: 'test-key',
        baseUrl: 'http://localhost:8082',
      );
      expect(provider.providerType, LlmProviderType.claude);
      provider.dispose();
    });

    test('works without baseUrl (default)', () {
      final provider = ClaudeProvider(apiKey: 'test-key');
      expect(provider.providerType, LlmProviderType.claude);
      provider.dispose();
    });
  });

  group('OpenAiProvider baseUrl', () {
    test('accepts custom baseUrl for Ollama', () {
      final provider = OpenAiProvider(
        apiKey: 'ollama',
        baseUrl: 'http://localhost:11434/v1',
      );
      expect(provider.providerType, LlmProviderType.openai);
      provider.dispose();
    });

    test('works without baseUrl (default)', () {
      final provider = OpenAiProvider(apiKey: 'test-key');
      expect(provider.providerType, LlmProviderType.openai);
      provider.dispose();
    });
  });

  group('createLlmProvider with baseUrl', () {
    test('creates ClaudeProvider with baseUrl', () {
      final p = createLlmProvider(
        LlmProviderType.claude,
        'test-key',
        baseUrl: 'http://localhost:8082',
      );
      expect(p, isA<ClaudeProvider>());
      p!.dispose();
    });

    test('creates OpenAiProvider with baseUrl', () {
      final p = createLlmProvider(
        LlmProviderType.openai,
        'test-key',
        baseUrl: 'http://localhost:11434/v1',
      );
      expect(p, isA<OpenAiProvider>());
      p!.dispose();
    });

    test('ignores baseUrl for Gemini', () {
      final p = createLlmProvider(
        LlmProviderType.gemini,
        'test-key',
        baseUrl: 'http://example.com',
      );
      // GeminiProvider doesn't accept baseUrl, so it should still create OK
      expect(p, isNotNull);
      p!.dispose();
    });

    test('still returns null for empty API key with baseUrl', () {
      final p = createLlmProvider(
        LlmProviderType.claude,
        '',
        baseUrl: 'http://localhost:8082',
      );
      expect(p, isNull);
    });
  });
}

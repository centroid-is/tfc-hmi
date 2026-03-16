import 'dart:typed_data';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/llm/llm_provider.dart';
import 'package:tfc/llm/claude_provider.dart';
import 'package:tfc/llm/gemini_provider.dart';
import 'package:tfc/llm/openai_provider.dart';
import 'package:tfc/providers/chat.dart';

void main() {
  group('LlmProviderType', () {
    test('displayName returns human-readable names', () {
      expect(LlmProviderType.claude.displayName, 'Claude');
      expect(LlmProviderType.openai.displayName, 'OpenAI');
      expect(LlmProviderType.gemini.displayName, 'Gemini');
    });
  });

  group('ChatMessage factories', () {
    test('user message', () {
      final msg = ChatMessage.user('hello');
      expect(msg.role, ChatRole.user);
      expect(msg.content, 'hello');
      expect(msg.toolCalls, isEmpty);
      expect(msg.toolCallId, isNull);
    });

    test('assistant message with tool calls', () {
      final calls = [
        ToolCall(id: 'tc1', name: 'get_value', arguments: {'tag': 'temp'}),
      ];
      final msg = ChatMessage.assistant('thinking...', toolCalls: calls);
      expect(msg.role, ChatRole.assistant);
      expect(msg.content, 'thinking...');
      expect(msg.toolCalls, hasLength(1));
    });

    test('system message', () {
      final msg = ChatMessage.system('You are a helper');
      expect(msg.role, ChatRole.system);
      expect(msg.content, 'You are a helper');
    });

    test('tool result message', () {
      final msg = ChatMessage.toolResult('tc1', '42');
      expect(msg.role, ChatRole.tool);
      expect(msg.toolCallId, 'tc1');
      expect(msg.content, '42');
    });
  });

  group('LlmResponse', () {
    test('hasToolCalls returns true when toolCalls is non-empty', () {
      const resp = LlmResponse(
        content: '',
        toolCalls: [ToolCall(id: 'x', name: 'y', arguments: {})],
        stopReason: 'tool_use',
      );
      expect(resp.hasToolCalls, isTrue);
    });

    test('hasToolCalls returns false when toolCalls is empty', () {
      const resp = LlmResponse(
        content: 'done',
        toolCalls: [],
        stopReason: 'end_turn',
      );
      expect(resp.hasToolCalls, isFalse);
    });
  });

  group('LlmProvider.apiKeyPreferenceKey', () {
    test('claude returns claude key', () {
      final provider = ClaudeProvider(apiKey: 'test-key');
      expect(provider.apiKeyPreferenceKey, kClaudeApiKey);
      provider.dispose();
    });

    test('openai returns openai key', () {
      final provider = OpenAiProvider(apiKey: 'test-key');
      expect(provider.apiKeyPreferenceKey, kOpenAiApiKey);
      provider.dispose();
    });

    test('gemini returns gemini key', () {
      final provider = GeminiProvider(apiKey: 'test-key');
      expect(provider.apiKeyPreferenceKey, kGeminiApiKey);
      provider.dispose();
    });
  });

  group('ClaudeProvider', () {
    test('throws on empty API key', () {
      expect(() => ClaudeProvider(apiKey: ''), throwsArgumentError);
    });

    test('providerType is claude', () {
      final provider = ClaudeProvider(apiKey: 'sk-test');
      expect(provider.providerType, LlmProviderType.claude);
      provider.dispose();
    });

    group('convertMessages', () {
      late ClaudeProvider provider;

      setUp(() => provider = ClaudeProvider(apiKey: 'sk-test'));
      tearDown(() => provider.dispose());

      test('extracts system prompt from system messages', () {
        final result = provider.convertMessages([
          ChatMessage.system('You are helpful'),
          ChatMessage.user('Hi'),
        ]);

        expect(result.systemPrompt, 'You are helpful');
        // Only user message in messages list (system goes separately)
        expect(result.messages, hasLength(1));
      });

      test('concatenates multiple system messages', () {
        final result = provider.convertMessages([
          ChatMessage.system('Rule 1'),
          ChatMessage.system('Rule 2'),
          ChatMessage.user('Hi'),
        ]);

        expect(result.systemPrompt, 'Rule 1\nRule 2');
      });

      test('handles user and assistant messages', () {
        final result = provider.convertMessages([
          ChatMessage.user('What is X?'),
          ChatMessage.assistant('X is 42'),
        ]);

        expect(result.systemPrompt, isNull);
        expect(result.messages, hasLength(2));
      });

      test('handles assistant message with tool calls', () {
        final result = provider.convertMessages([
          ChatMessage.user('Check temp'),
          ChatMessage.assistant('Let me check', toolCalls: [
            ToolCall(id: 'tc1', name: 'get_value', arguments: {'tag': 'temp'}),
          ]),
        ]);

        expect(result.messages, hasLength(2));
      });

      test('handles tool result messages', () {
        final result = provider.convertMessages([
          ChatMessage.user('Check temp'),
          ChatMessage.assistant('', toolCalls: [
            ToolCall(id: 'tc1', name: 'get_value', arguments: {'tag': 'temp'}),
          ]),
          ChatMessage.toolResult('tc1', '72.5'),
        ]);

        expect(result.messages, hasLength(3));
      });

      test('converts PDF attachment to document content block', () {
        final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
        final result = provider.convertMessages([
          ChatMessage.user(
            'Analyze this drawing',
            attachments: [
              ChatAttachment(
                bytes: pdfBytes,
                filename: 'schematic.pdf',
                mimeType: 'application/pdf',
              ),
            ],
          ),
        ]);

        expect(result.messages, hasLength(1));
        final msg = result.messages[0];
        final blocks = msg.blocks;
        // Should have document block + text block
        expect(blocks, hasLength(2));
        expect(blocks[0], isA<anthropic.DocumentInputBlock>());
        expect(blocks[1], isA<anthropic.TextInputBlock>());

        final docBlock = blocks[0] as anthropic.DocumentInputBlock;
        expect(docBlock.source, isA<anthropic.Base64PdfSource>());
        expect(docBlock.title, 'schematic.pdf');
      });

      test('user message without attachments uses simple text', () {
        final result = provider.convertMessages([
          ChatMessage.user('Just a question'),
        ]);

        expect(result.messages, hasLength(1));
        final msg = result.messages[0];
        // Should use simple text content, not blocks
        final json = msg.toJson();
        expect(json['content'], isA<String>());
      });

      test('converts multiple PDF attachments to multiple document blocks', () {
        final result = provider.convertMessages([
          ChatMessage.user(
            'Compare these',
            attachments: [
              ChatAttachment(
                bytes: Uint8List.fromList([1, 2, 3]),
                filename: 'drawing1.pdf',
                mimeType: 'application/pdf',
              ),
              ChatAttachment(
                bytes: Uint8List.fromList([4, 5, 6]),
                filename: 'drawing2.pdf',
                mimeType: 'application/pdf',
              ),
            ],
          ),
        ]);

        expect(result.messages, hasLength(1));
        final blocks = result.messages[0].blocks;
        // 2 document blocks + 1 text block
        expect(blocks, hasLength(3));
        expect(blocks[0], isA<anthropic.DocumentInputBlock>());
        expect(blocks[1], isA<anthropic.DocumentInputBlock>());
        expect(blocks[2], isA<anthropic.TextInputBlock>());
      });
    });

    test('convertTools produces ToolDefinition list', () {
      final provider = ClaudeProvider(apiKey: 'sk-test');
      final tools = provider.convertTools([
        {
          'name': 'get_value',
          'description': 'Gets a value',
          'input_schema': {
            'type': 'object',
            'properties': {
              'tag': {'type': 'string'},
            },
          },
        },
      ]);

      expect(tools, hasLength(1));
      provider.dispose();
    });

    group('prompt caching', () {
      late ClaudeProvider provider;

      setUp(() => provider = ClaudeProvider(apiKey: 'sk-test'));
      tearDown(() => provider.dispose());

      group('convertTools cache_control', () {
        test('sets cache_control on last tool only', () {
          final tools = provider.convertTools([
            {
              'name': 'tool_a',
              'description': 'First tool',
              'input_schema': {'type': 'object'},
            },
            {
              'name': 'tool_b',
              'description': 'Second tool',
              'input_schema': {'type': 'object'},
            },
            {
              'name': 'tool_c',
              'description': 'Third tool',
              'input_schema': {'type': 'object'},
            },
          ]);

          expect(tools, hasLength(3));

          // First two tools should NOT have cache_control
          final toolAJson = tools[0].toJson();
          expect(toolAJson.containsKey('cache_control'), isFalse);
          final toolBJson = tools[1].toJson();
          expect(toolBJson.containsKey('cache_control'), isFalse);

          // Last tool SHOULD have cache_control
          final toolCJson = tools[2].toJson();
          expect(toolCJson['cache_control'], {'type': 'ephemeral'});
        });

        test('sets cache_control on single tool', () {
          final tools = provider.convertTools([
            {
              'name': 'only_tool',
              'description': 'The only tool',
              'input_schema': {'type': 'object'},
            },
          ]);

          expect(tools, hasLength(1));
          final json = tools[0].toJson();
          expect(json['cache_control'], {'type': 'ephemeral'});
        });

        test('handles empty tool list without error', () {
          final tools = provider.convertTools([]);
          expect(tools, isEmpty);
        });
      });

      group('buildCachedSystemPrompt', () {
        test('returns BlocksSystemPrompt with cache_control', () {
          final prompt = provider.buildCachedSystemPrompt(
            'You are a helpful assistant',
          );

          expect(prompt, isA<anthropic.BlocksSystemPrompt>());
          final blocks = (prompt as anthropic.BlocksSystemPrompt).blocks;
          expect(blocks, hasLength(1));
          expect(blocks[0].text, 'You are a helpful assistant');
          expect(blocks[0].cacheControl, isNotNull);
          expect(blocks[0].cacheControl!.type, 'ephemeral');
        });

        test('serializes cache_control to JSON correctly', () {
          final prompt = provider.buildCachedSystemPrompt('Test prompt');
          final json = prompt.toJson() as List;

          expect(json, hasLength(1));
          final block = json[0] as Map<String, dynamic>;
          expect(block['type'], 'text');
          expect(block['text'], 'Test prompt');
          expect(block['cache_control'], {'type': 'ephemeral'});
        });
      });
    });
  });

  group('GeminiProvider', () {
    test('throws on empty API key', () {
      expect(() => GeminiProvider(apiKey: ''), throwsArgumentError);
    });

    test('providerType is gemini', () {
      final provider = GeminiProvider(apiKey: 'test-key');
      expect(provider.providerType, LlmProviderType.gemini);
      provider.dispose();
    });

    test('buildRequestUrl includes model and key', () {
      final provider = GeminiProvider(apiKey: 'my-key', model: 'gemini-pro');
      expect(
        provider.buildRequestUrl(),
        contains('gemini-pro:generateContent'),
      );
      expect(provider.buildRequestUrl(), contains('key=my-key'));
      provider.dispose();
    });

    group('convertMessages', () {
      late GeminiProvider provider;

      setUp(() => provider = GeminiProvider(apiKey: 'test-key'));
      tearDown(() => provider.dispose());

      test('extracts system instruction', () {
        final result = provider.convertMessages([
          ChatMessage.system('Be helpful'),
          ChatMessage.user('Hello'),
        ]);

        expect(result.systemInstruction, isNotNull);
        final parts =
            (result.systemInstruction!['parts'] as List).first as Map;
        expect(parts['text'], 'Be helpful');
        expect(result.contents, hasLength(1));
      });

      test('maps assistant to model role', () {
        final result = provider.convertMessages([
          ChatMessage.user('Hi'),
          ChatMessage.assistant('Hello!'),
        ]);

        expect(result.contents[1]['role'], 'model');
      });

      test('maps tool results to function role', () {
        final result = provider.convertMessages([
          ChatMessage.toolResult('get_value', '42'),
        ]);

        expect(result.contents[0]['role'], 'function');
        final parts = result.contents[0]['parts'] as List;
        final funcResp =
            (parts[0] as Map)['functionResponse'] as Map<String, dynamic>;
        expect(funcResp['name'], 'get_value');
      });

      test('includes functionCall parts for assistant tool calls', () {
        final result = provider.convertMessages([
          ChatMessage.assistant('Checking...', toolCalls: [
            ToolCall(id: 'tc1', name: 'get_value', arguments: {'tag': 'x'}),
          ]),
        ]);

        final parts = result.contents[0]['parts'] as List;
        expect(parts, hasLength(2)); // text + functionCall
        expect((parts[1] as Map).containsKey('functionCall'), isTrue);
      });

      test('converts PDF attachment to inline_data part', () {
        final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
        final result = provider.convertMessages([
          ChatMessage.user(
            'Analyze this drawing',
            attachments: [
              ChatAttachment(
                bytes: pdfBytes,
                filename: 'schematic.pdf',
                mimeType: 'application/pdf',
              ),
            ],
          ),
        ]);

        expect(result.contents, hasLength(1));
        final parts = result.contents[0]['parts'] as List;
        // inline_data part + text part
        expect(parts, hasLength(2));

        final inlineData = (parts[0] as Map)['inline_data'] as Map;
        expect(inlineData['mime_type'], 'application/pdf');
        expect(inlineData['data'], isA<String>());
        // Verify it's valid base64
        expect(inlineData['data'], isNotEmpty);
      });

      test('user message without attachments has text-only parts', () {
        final result = provider.convertMessages([
          ChatMessage.user('Just text'),
        ]);

        final parts = result.contents[0]['parts'] as List;
        expect(parts, hasLength(1));
        expect((parts[0] as Map).containsKey('text'), isTrue);
        expect((parts[0] as Map).containsKey('inline_data'), isFalse);
      });

      test('converts multiple PDF attachments to multiple inline_data parts',
          () {
        final result = provider.convertMessages([
          ChatMessage.user(
            'Compare these',
            attachments: [
              ChatAttachment(
                bytes: Uint8List.fromList([1, 2, 3]),
                filename: 'drawing1.pdf',
                mimeType: 'application/pdf',
              ),
              ChatAttachment(
                bytes: Uint8List.fromList([4, 5, 6]),
                filename: 'drawing2.pdf',
                mimeType: 'application/pdf',
              ),
            ],
          ),
        ]);

        final parts = result.contents[0]['parts'] as List;
        // 2 inline_data parts + 1 text part
        expect(parts, hasLength(3));
        expect((parts[0] as Map).containsKey('inline_data'), isTrue);
        expect((parts[1] as Map).containsKey('inline_data'), isTrue);
        expect((parts[2] as Map).containsKey('text'), isTrue);
      });
    });

    test('convertTools wraps in functionDeclarations', () {
      final provider = GeminiProvider(apiKey: 'test-key');
      final tools = provider.convertTools([
        {'name': 'get_value', 'description': 'Gets a value'},
      ]);

      expect(tools, hasLength(1));
      expect(tools[0].containsKey('functionDeclarations'), isTrue);
      provider.dispose();
    });

    group('parseResponse', () {
      late GeminiProvider provider;

      setUp(() => provider = GeminiProvider(apiKey: 'test-key'));
      tearDown(() => provider.dispose());

      test('extracts text from response', () {
        final result = provider.parseResponse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Hello there'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        });

        expect(result.content, 'Hello there');
        expect(result.toolCalls, isEmpty);
        expect(result.stopReason, 'STOP');
      });

      test('extracts function calls', () {
        final result = provider.parseResponse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'name': 'get_value',
                      'args': {'tag': 'temp'},
                    },
                  },
                ],
              },
              'finishReason': 'FUNCTION_CALL',
            },
          ],
        });

        expect(result.toolCalls, hasLength(1));
        expect(result.toolCalls.first.name, 'get_value');
        expect(result.toolCalls.first.arguments['tag'], 'temp');
        expect(result.toolCalls.first.id, startsWith('gemini-tc-'));
      });

      test('handles empty candidates', () {
        final result = provider.parseResponse({'candidates': []});
        expect(result.content, '');
        expect(result.toolCalls, isEmpty);
      });

      test('handles null candidates', () {
        final result = provider.parseResponse({});
        expect(result.content, '');
        expect(result.toolCalls, isEmpty);
      });

      test('handles mixed text and function call parts', () {
        final result = provider.parseResponse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Let me check that'},
                  {
                    'functionCall': {
                      'name': 'search',
                      'args': {'q': 'test'},
                    },
                  },
                ],
              },
              'finishReason': 'FUNCTION_CALL',
            },
          ],
        });

        expect(result.content, 'Let me check that');
        expect(result.toolCalls, hasLength(1));
      });
    });
  });

  group('OpenAiProvider', () {
    test('throws on empty API key', () {
      expect(() => OpenAiProvider(apiKey: ''), throwsArgumentError);
    });

    test('providerType is openai', () {
      final provider = OpenAiProvider(apiKey: 'sk-test');
      expect(provider.providerType, LlmProviderType.openai);
      provider.dispose();
    });

    group('convertMessages', () {
      late OpenAiProvider provider;

      setUp(() => provider = OpenAiProvider(apiKey: 'sk-test'));
      tearDown(() => provider.dispose());

      test('maps all roles correctly', () {
        final result = provider.convertMessages([
          ChatMessage.system('Be helpful'),
          ChatMessage.user('Hi'),
          ChatMessage.assistant('Hello'),
          ChatMessage.toolResult('tc1', 'result'),
        ]);

        expect(result, hasLength(4));
      });

      test('includes tool calls in assistant messages', () {
        final result = provider.convertMessages([
          ChatMessage.assistant('Checking', toolCalls: [
            ToolCall(id: 'tc1', name: 'get_value', arguments: {'tag': 'x'}),
          ]),
        ]);

        expect(result, hasLength(1));
      });

      test('drops PDF attachments and logs warning', () {
        final logs = <String>[];
        final result = provider.convertMessages(
          [
            ChatMessage.user(
              'Analyze this',
              attachments: [
                ChatAttachment(
                  bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
                  filename: 'drawing.pdf',
                  mimeType: 'application/pdf',
                ),
              ],
            ),
          ],
          onWarning: (msg) => logs.add(msg),
        );

        // Message should still be converted (text-only)
        expect(result, hasLength(1));
        // Warning should have been logged
        expect(logs, hasLength(1));
        expect(logs[0], contains('PDF'));
        expect(logs[0], contains('OpenAI'));
      });

      test('no warning when no attachments', () {
        final logs = <String>[];
        provider.convertMessages(
          [ChatMessage.user('Just text')],
          onWarning: (msg) => logs.add(msg),
        );

        expect(logs, isEmpty);
      });
    });
  });

  group('createLlmProvider', () {
    test('returns null for null API key', () {
      expect(createLlmProvider(LlmProviderType.claude, null), isNull);
    });

    test('returns null for empty API key', () {
      expect(createLlmProvider(LlmProviderType.claude, ''), isNull);
    });

    test('creates ClaudeProvider for claude type', () {
      final p = createLlmProvider(LlmProviderType.claude, 'sk-test');
      expect(p, isA<ClaudeProvider>());
      p!.dispose();
    });

    test('creates OpenAiProvider for openai type', () {
      final p = createLlmProvider(LlmProviderType.openai, 'sk-test');
      expect(p, isA<OpenAiProvider>());
      p!.dispose();
    });

    test('creates GeminiProvider for gemini type', () {
      final p = createLlmProvider(LlmProviderType.gemini, 'test-key');
      expect(p, isA<GeminiProvider>());
      p!.dispose();
    });
  });
}

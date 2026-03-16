import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/llm/llm_models.dart';

void main() {
  group('ToolCall serialization', () {
    test('toJson/fromJson round-trip preserves all fields', () {
      const tc = ToolCall(
        id: 'tc1',
        name: 'get_tag_value',
        arguments: {'tag': 'pump3.speed'},
      );

      final json = tc.toJson();
      final restored = ToolCall.fromJson(json);

      expect(restored.id, 'tc1');
      expect(restored.name, 'get_tag_value');
      expect(restored.arguments, {'tag': 'pump3.speed'});
    });

    test('round-trips with nested/complex arguments', () {
      const tc = ToolCall(
        id: 'tc2',
        name: 'create_alarm',
        arguments: {
          'name': 'High Temp',
          'threshold': 85.5,
          'tags': ['temp1', 'temp2'],
          'config': {'enabled': true, 'delay': 10},
        },
      );

      final json = tc.toJson();
      final restored = ToolCall.fromJson(json);

      expect(restored.id, 'tc2');
      expect(restored.name, 'create_alarm');
      expect(restored.arguments['name'], 'High Temp');
      expect(restored.arguments['threshold'], 85.5);
      expect(restored.arguments['tags'], ['temp1', 'temp2']);
      expect(restored.arguments['config'], {'enabled': true, 'delay': 10});
    });
  });

  group('ChatMessage serialization', () {
    test('user message round-trips via toJson/fromJson', () {
      final msg = ChatMessage.user('hello');
      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.role, ChatRole.user);
      expect(restored.content, 'hello');
      expect(restored.toolCallId, isNull);
      expect(restored.toolCalls, isEmpty);
    });

    test('assistant message with toolCalls round-trips', () {
      final msg = ChatMessage.assistant(
        'Let me check that.',
        toolCalls: [
          const ToolCall(
            id: 'tc1',
            name: 'get_tag_value',
            arguments: {'tag': 'pump3.speed'},
          ),
          const ToolCall(
            id: 'tc2',
            name: 'list_tags',
            arguments: {'filter': 'pump'},
          ),
        ],
      );

      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.role, ChatRole.assistant);
      expect(restored.content, 'Let me check that.');
      expect(restored.toolCalls, hasLength(2));
      expect(restored.toolCalls[0].id, 'tc1');
      expect(restored.toolCalls[0].name, 'get_tag_value');
      expect(restored.toolCalls[0].arguments, {'tag': 'pump3.speed'});
      expect(restored.toolCalls[1].id, 'tc2');
      expect(restored.toolCalls[1].name, 'list_tags');
    });

    test('tool result message round-trips preserving toolCallId', () {
      final msg = ChatMessage.toolResult('tc1', 'pump3.speed = 42.5');
      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.role, ChatRole.tool);
      expect(restored.content, 'pump3.speed = 42.5');
      expect(restored.toolCallId, 'tc1');
      expect(restored.toolCalls, isEmpty);
    });

    test('system message round-trips', () {
      final msg = ChatMessage.system('You are an industrial AI copilot.');
      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.role, ChatRole.system);
      expect(restored.content, 'You are an industrial AI copilot.');
      expect(restored.toolCallId, isNull);
      expect(restored.toolCalls, isEmpty);
    });

    test('empty toolCalls list serializes and deserializes correctly', () {
      final msg = ChatMessage.assistant('No tools needed.');
      final json = msg.toJson();

      // Empty toolCalls should not appear in JSON (conditional serialization)
      expect(json.containsKey('toolCalls'), isFalse);

      final restored = ChatMessage.fromJson(json);
      expect(restored.toolCalls, isEmpty);
    });

    test('null toolCallId does not appear in JSON', () {
      final msg = ChatMessage.user('test');
      final json = msg.toJson();

      expect(json.containsKey('toolCallId'), isFalse);
    });

    test('nested/complex tool call arguments survive round-trip', () {
      final msg = ChatMessage.assistant(
        'Creating alarm.',
        toolCalls: [
          const ToolCall(
            id: 'tc-complex',
            name: 'create_alarm',
            arguments: {
              'name': 'High Temp',
              'expression': 'temp1 > 85.5',
              'nested': {
                'a': [1, 2, 3],
                'b': {'deep': true},
              },
            },
          ),
        ],
      );

      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      final tc = restored.toolCalls.first;
      expect(tc.arguments['nested'], {
        'a': [1, 2, 3],
        'b': {'deep': true},
      });
    });
  });

  group('ChatAttachment', () {
    test('stores bytes, filename, and mimeType', () {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
      final attachment = ChatAttachment(
        bytes: bytes,
        filename: 'drawing.pdf',
        mimeType: 'application/pdf',
      );

      expect(attachment.bytes, bytes);
      expect(attachment.filename, 'drawing.pdf');
      expect(attachment.mimeType, 'application/pdf');
    });
  });

  group('ChatMessage with attachments', () {
    test('user message can have PDF attachments', () {
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
      final attachment = ChatAttachment(
        bytes: pdfBytes,
        filename: 'schematic.pdf',
        mimeType: 'application/pdf',
      );

      final msg = ChatMessage.user(
        'Analyze this drawing',
        attachments: [attachment],
      );

      expect(msg.role, ChatRole.user);
      expect(msg.content, 'Analyze this drawing');
      expect(msg.attachments, hasLength(1));
      expect(msg.attachments![0].filename, 'schematic.pdf');
      expect(msg.attachments![0].mimeType, 'application/pdf');
      expect(msg.attachments![0].bytes, pdfBytes);
    });

    test('user message without attachments has null attachments', () {
      final msg = ChatMessage.user('hello');
      expect(msg.attachments, isNull);
    });

    test('existing factory methods still work without attachments', () {
      final user = ChatMessage.user('hi');
      expect(user.attachments, isNull);

      final assistant = ChatMessage.assistant('hello');
      expect(assistant.attachments, isNull);

      final system = ChatMessage.system('prompt');
      expect(system.attachments, isNull);

      final tool = ChatMessage.toolResult('tc1', 'result');
      expect(tool.attachments, isNull);
    });

    test('attachments are NOT included in JSON serialization', () {
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
      final msg = ChatMessage.user(
        'Analyze this',
        attachments: [
          ChatAttachment(
            bytes: pdfBytes,
            filename: 'test.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      );

      final json = msg.toJson();
      expect(json.containsKey('attachments'), isFalse);
    });

    test('fromJson produces message with null attachments', () {
      final json = {'role': 'user', 'content': 'hello'};
      final msg = ChatMessage.fromJson(json);
      expect(msg.attachments, isNull);
    });

    test('multiple attachments are supported', () {
      final msg = ChatMessage.user(
        'Compare these drawings',
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
      );

      expect(msg.attachments, hasLength(2));
      expect(msg.attachments![0].filename, 'drawing1.pdf');
      expect(msg.attachments![1].filename, 'drawing2.pdf');
    });
  });
}

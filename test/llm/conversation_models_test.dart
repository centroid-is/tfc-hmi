import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/llm/conversation_models.dart';

void main() {
  group('ConversationMeta', () {
    group('generateId', () {
      test('produces non-empty base-36 string', () {
        final id = ConversationMeta.generateId();
        expect(id, isNotEmpty);
        // Base-36 chars: 0-9, a-z
        expect(id, matches(RegExp(r'^[0-9a-z]+$')));
      });

      test('ID is derived from microsecondsSinceEpoch.toRadixString(36)', () {
        // Capture time window around generation
        final before = DateTime.now().microsecondsSinceEpoch;
        final id = ConversationMeta.generateId();
        final after = DateTime.now().microsecondsSinceEpoch;

        // Parse the base-36 ID back to an integer
        final parsed = int.parse(id, radix: 36);

        // The parsed value should fall within the time window
        expect(parsed, greaterThanOrEqualTo(before));
        expect(parsed, lessThanOrEqualTo(after));
      });

      test('produces unique IDs', () {
        final ids = <String>{};
        for (var i = 0; i < 100; i++) {
          ids.add(ConversationMeta.generateId());
        }
        // At least many should be unique (microsecond resolution; tight
        // loops on fast machines may produce some duplicates)
        expect(ids.length, greaterThan(50));
      });

      test('IDs are monotonically increasing when parsed back', () {
        final id1 = ConversationMeta.generateId();
        final id2 = ConversationMeta.generateId();
        final val1 = int.parse(id1, radix: 36);
        final val2 = int.parse(id2, radix: 36);
        expect(val2, greaterThanOrEqualTo(val1));
      });
    });

    group('titleFromMessage', () {
      test('truncates long messages to 40 chars with ellipsis', () {
        final longMsg = 'A' * 50;
        final title = ConversationMeta.titleFromMessage(longMsg);
        expect(title.length, 40);
        expect(title, endsWith('...'));
        expect(title, startsWith('A' * 37));
      });

      test('keeps short messages as-is', () {
        const msg = 'Hello world';
        expect(ConversationMeta.titleFromMessage(msg), 'Hello world');
      });

      test('keeps exactly 40-char messages as-is', () {
        final msg = 'A' * 40;
        expect(ConversationMeta.titleFromMessage(msg), msg);
      });

      test('truncates at 41 chars', () {
        final msg = 'A' * 41;
        final title = ConversationMeta.titleFromMessage(msg);
        expect(title.length, 40);
        expect(title, '${('A' * 37)}...');
      });

      test('extracts identifier from debug-asset messages', () {
        const msg = 'Debug asset: pump3.speed\n\nPlease gather all info...';
        expect(ConversationMeta.titleFromMessage(msg), 'pump3.speed');
      });

      test('extracts multi-word debug-asset identifier', () {
        const msg =
            'Debug asset: Motor 3 VFD\n\nPlease gather all info...';
        expect(ConversationMeta.titleFromMessage(msg), 'Motor 3 VFD');
      });

      test('extracts identifier with dots and underscores', () {
        const msg =
            'Debug asset: sys1.pump_3.flow_rate\n\nPlease gather...';
        expect(
            ConversationMeta.titleFromMessage(msg), 'sys1.pump_3.flow_rate');
      });

      test('truncates long debug-asset identifiers', () {
        final msg = 'Debug asset: ${'x' * 50}\n\nPlease gather...';
        final title = ConversationMeta.titleFromMessage(msg);
        expect(title.length, 40);
        expect(title, endsWith('...'));
      });

      test('falls back to general truncation for empty debug-asset id', () {
        const msg = 'Debug asset: \n\nPlease gather all info...';
        final title = ConversationMeta.titleFromMessage(msg);
        // Falls through to general truncation (single line join)
        expect(title, isNotEmpty);
      });

      test('replaces newlines with spaces', () {
        const msg = 'Line one\nLine two';
        expect(ConversationMeta.titleFromMessage(msg), 'Line one Line two');
      });

      test('trims whitespace', () {
        const msg = '  Hello world  ';
        expect(ConversationMeta.titleFromMessage(msg), 'Hello world');
      });

      test('handles empty message', () {
        const msg = '';
        final title = ConversationMeta.titleFromMessage(msg);
        expect(title, isEmpty);
      });

      test('handles whitespace-only message', () {
        const msg = '   \n  \n  ';
        final title = ConversationMeta.titleFromMessage(msg);
        expect(title, isEmpty);
      });
    });

    group('serialization', () {
      test('round-trips through JSON', () {
        final now = DateTime.now();
        final meta = ConversationMeta(
          id: 'abc123',
          title: 'Test conversation',
          createdAt: now,
        );

        final json = meta.toJson();
        final restored = ConversationMeta.fromJson(json);

        expect(restored.id, 'abc123');
        expect(restored.title, 'Test conversation');
        expect(
            restored.createdAt.toIso8601String(), now.toIso8601String());
      });

      test('toJson produces expected keys', () {
        final meta = ConversationMeta(
          id: 'test-id',
          title: 'Test',
          createdAt: DateTime(2024, 1, 15, 10, 30),
        );

        final json = meta.toJson();
        expect(json.keys, containsAll(['id', 'title', 'createdAt']));
        expect(json['id'], 'test-id');
        expect(json['title'], 'Test');
      });

      test('createdAt serializes as ISO 8601 string', () {
        final dt = DateTime(2024, 3, 15, 14, 30, 45, 123, 456);
        final meta = ConversationMeta(
          id: 'ts-test',
          title: 'Timestamp test',
          createdAt: dt,
        );

        final json = meta.toJson();
        expect(json['createdAt'], isA<String>());
        expect(json['createdAt'], dt.toIso8601String());

        // Verify the ISO string can be parsed back correctly
        final parsed = DateTime.parse(json['createdAt'] as String);
        expect(parsed.year, 2024);
        expect(parsed.month, 3);
        expect(parsed.day, 15);
        expect(parsed.hour, 14);
        expect(parsed.minute, 30);
      });

      test('round-trips through JSON encode/decode string', () {
        final meta = ConversationMeta(
          id: 'json-str-test',
          title: 'JSON string round-trip',
          createdAt: DateTime(2024, 6, 15),
        );

        // Simulate what preferences does: encode to JSON string, decode back
        final jsonString = jsonEncode(meta.toJson());
        final decoded =
            ConversationMeta.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

        expect(decoded.id, meta.id);
        expect(decoded.title, meta.title);
        expect(decoded.createdAt.year, meta.createdAt.year);
        expect(decoded.createdAt.month, meta.createdAt.month);
        expect(decoded.createdAt.day, meta.createdAt.day);
      });

      test('list of ConversationMeta round-trips through JSON string', () {
        final metas = [
          ConversationMeta(
            id: 'conv-1',
            title: 'First',
            createdAt: DateTime(2024, 1, 1),
          ),
          ConversationMeta(
            id: 'conv-2',
            title: 'Second',
            createdAt: DateTime(2024, 2, 1),
          ),
          ConversationMeta(
            id: 'conv-3',
            title: 'Third with special chars: <>&"',
            createdAt: DateTime(2024, 3, 1),
          ),
        ];

        final jsonString =
            jsonEncode(metas.map((m) => m.toJson()).toList());
        final decoded = (jsonDecode(jsonString) as List<dynamic>)
            .map((e) => ConversationMeta.fromJson(e as Map<String, dynamic>))
            .toList();

        expect(decoded.length, 3);
        expect(decoded[0].id, 'conv-1');
        expect(decoded[1].title, 'Second');
        expect(decoded[2].title, 'Third with special chars: <>&"');
      });
    });

    group('equality', () {
      test('equal by ID', () {
        final a = ConversationMeta(
          id: 'same-id',
          title: 'Title A',
          createdAt: DateTime(2024, 1, 1),
        );
        final b = ConversationMeta(
          id: 'same-id',
          title: 'Title B',
          createdAt: DateTime(2024, 6, 1),
        );
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('not equal by different ID', () {
        final a = ConversationMeta(
          id: 'id-1',
          title: 'Same Title',
          createdAt: DateTime(2024, 1, 1),
        );
        final b = ConversationMeta(
          id: 'id-2',
          title: 'Same Title',
          createdAt: DateTime(2024, 1, 1),
        );
        expect(a, isNot(equals(b)));
      });
    });

    group('copyWith', () {
      test('copies with modified title', () {
        final original = ConversationMeta(
          id: 'test',
          title: 'Old',
          createdAt: DateTime(2024, 1, 1),
        );
        final copy = original.copyWith(title: 'New');
        expect(copy.title, 'New');
        expect(copy.id, 'test');
      });

      test('copies with modified id', () {
        final original = ConversationMeta(
          id: 'old-id',
          title: 'Title',
          createdAt: DateTime(2024, 1, 1),
        );
        final copy = original.copyWith(id: 'new-id');
        expect(copy.id, 'new-id');
        expect(copy.title, 'Title');
      });

      test('copies with modified createdAt', () {
        final original = ConversationMeta(
          id: 'test',
          title: 'Title',
          createdAt: DateTime(2024, 1, 1),
        );
        final newDate = DateTime(2025, 6, 15);
        final copy = original.copyWith(createdAt: newDate);
        expect(copy.createdAt, newDate);
        expect(copy.id, 'test');
        expect(copy.title, 'Title');
      });

      test('preserves all fields when no arguments given', () {
        final original = ConversationMeta(
          id: 'preserve-test',
          title: 'Original Title',
          createdAt: DateTime(2024, 5, 10),
        );
        final copy = original.copyWith();
        expect(copy.id, original.id);
        expect(copy.title, original.title);
        expect(copy.createdAt, original.createdAt);
      });
    });

    group('toString', () {
      test('contains id and title', () {
        final meta = ConversationMeta(
          id: 'str-test',
          title: 'My Title',
          createdAt: DateTime(2024, 1, 1),
        );
        final str = meta.toString();
        expect(str, contains('str-test'));
        expect(str, contains('My Title'));
      });
    });
  });
}

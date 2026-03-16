import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/services/tag_service.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('TagService', () {
    late MockStateReader stateReader;
    late TagService tagService;

    setUp(() {
      stateReader = MockStateReader();
      // Populate test data
      stateReader.setValue('pump3.speed', 1450);
      stateReader.setValue('pump3.current', 12.5);
      stateReader.setValue('conveyor.speed', 800);
      stateReader.setValue('conveyor.current', 5.2);
      stateReader.setValue('mixer.temp', 85);
      tagService = TagService(stateReader);
    });

    group('listTags', () {
      test('with no filter returns all tags with values', () {
        final result = tagService.listTags();
        expect(result, hasLength(5));
        // Each entry should be a map with 'key' and 'value'
        for (final tag in result) {
          expect(tag, contains('key'));
          expect(tag, contains('value'));
        }
      });

      test('with filter returns only fuzzy-matched tags', () {
        final result = tagService.listTags(filter: 'pump');
        // Should match pump3.speed and pump3.current, not conveyor or mixer
        expect(result, hasLength(2));
        final keys = result.map((t) => t['key']).toList();
        expect(keys, containsAll(['pump3.speed', 'pump3.current']));
        expect(keys, isNot(contains('conveyor.speed')));
      });

      test('with limit returns at most limit results', () {
        final result = tagService.listTags(limit: 2);
        expect(result, hasLength(2));
      });

      test('enforces default limit of 50', () {
        // Add 60 tags
        stateReader.clear();
        for (var i = 0; i < 60; i++) {
          stateReader.setValue('tag$i', i);
        }
        tagService = TagService(stateReader);

        final result = tagService.listTags();
        expect(result, hasLength(50));
      });

      test('with empty StateReader returns empty list', () {
        stateReader.clear();
        tagService = TagService(stateReader);

        final result = tagService.listTags();
        expect(result, isEmpty);
      });
    });

    group('getTagValue', () {
      test('returns map with key and value for existing key', () {
        final result = tagService.getTagValue('pump3.speed');
        expect(result, isNotNull);
        expect(result!['key'], equals('pump3.speed'));
        expect(result['value'], equals(1450));
      });

      test('returns null for nonexistent key', () {
        final result = tagService.getTagValue('nonexistent');
        expect(result, isNull);
      });
    });
  });
}

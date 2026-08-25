import 'package:test/test.dart';
import 'package:tfc_dart/core/fuzzy_match.dart';

void main() {
  group('fuzzyMatch', () {
    test('matches in-order subsequences', () {
      expect(fuzzyMatch('temperature', 'tmp'), isTrue);
      expect(fuzzyMatch('temperature', 'tpm'), isFalse);
      expect(fuzzyMatch('anything', ''), isTrue);
    });
  });

  group('fuzzyScore', () {
    test('null when a word does not match', () {
      expect(fuzzyScore('conveyor', 'gate'), isNull);
      expect(fuzzyScore('conveyor', 'conveyor gate'), isNull);
    });

    test('empty query matches with neutral score', () {
      expect(fuzzyScore('anything', ''), 0);
      expect(fuzzyScore('anything', '   '), 0);
    });

    test('tier ladder: exact > prefix > word boundary > substring > '
        'subsequence', () {
      final exact = fuzzyScore('belt', 'belt')!;
      final prefix = fuzzyScore('belt speed', 'belt')!;
      final boundary = fuzzyScore('main belt', 'belt')!;
      final substring = fuzzyScore('conveyorbelt', 'belt')!;
      final subsequence = fuzzyScore('bagel outlet', 'belt')!;
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(boundary));
      expect(boundary, greaterThan(substring));
      expect(substring, greaterThan(subsequence));
    });

    test('tiers hold regardless of within-tier penalties', () {
      // Worst-case prefix (very long text) still beats best-case
      // word-boundary match.
      final longPrefix = fuzzyScore('belt${'x' * 5000}', 'belt')!;
      final boundary = fuzzyScore('a belt', 'belt')!;
      expect(longPrefix, greaterThan(boundary));

      // Worst-case substring beats best-case subsequence.
      final lateSubstring = fuzzyScore('${'x' * 5000}abelt', 'belt')!;
      final tightSubsequence = fuzzyScore('bxelt', 'belt')!;
      expect(lateSubstring, greaterThan(tightSubsequence));
    });

    test('earlier and tighter matches score higher within a tier', () {
      expect(fuzzyScore('a belt runs', 'belt')!,
          greaterThan(fuzzyScore('a long main belt', 'belt')!));
      expect(fuzzyScore('bel t', 'belt')!,
          greaterThan(fuzzyScore('b e l t', 'belt')!));
    });

    test('shorter text wins on otherwise equal matches', () {
      expect(fuzzyScore('belt', 'bel')!, greaterThan(fuzzyScore('belter', 'bel')!));
    });

    test('multi-word queries AND their words in any order', () {
      expect(fuzzyScore('arrow upward', 'up arrow'), isNotNull);
      expect(fuzzyScore('arrow upward', 'up circle'), isNull);
    });
  });

  group('fuzzyScoreFields', () {
    test('each word may match a different field', () {
      expect(fuzzyScoreFields(['plc1', 'motor.temp'], 'plc1 temp'), isNotNull);
      expect(fuzzyScoreFields(['plc1', 'motor.temp'], 'plc2 temp'), isNull);
    });

    test('takes the best field per word', () {
      final both = fuzzyScoreFields(['belt', 'unrelated'], 'belt')!;
      expect(both, fuzzyScore('belt', 'belt'));
    });
  });

  group('fuzzyFilter', () {
    test('returns all items in original order for empty query', () {
      final items = ['b', 'a', 'c'];
      expect(fuzzyFilter<String>(items, '', [(s) => s]), same(items));
    });

    test('ranks best matches first', () {
      final items = [
        'main.conveyor.belt.speed',
        'belt',
        'boiler.outlet.temp',
        'freezer.belt.speed',
      ];
      final result = fuzzyFilter<String>(items, 'belt', [(s) => s]);
      expect(result.first, 'belt');
      // Word-boundary matches beat the pure subsequence match.
      expect(result.last, 'boiler.outlet.temp');
      expect(result, hasLength(4));
    });

    test('is case-insensitive', () {
      expect(fuzzyFilter<String>(['Main Belt'], 'BELT', [(s) => s]), ['Main Belt']);
    });

    test('drops non-matching items', () {
      expect(fuzzyFilter<String>(['gate', 'belt'], 'belt', [(s) => s]), ['belt']);
    });

    test('preserves input order for equal scores', () {
      final result = fuzzyFilter<String>(['z.belt', 'a.belt'], 'belt', [(s) => s]);
      expect(result, ['z.belt', 'a.belt']);
    });

    test('matches any field', () {
      final items = [('key1', 'temperature'), ('key2', 'pressure')];
      final result = fuzzyFilter<(String, String)>(
          items, 'tmp', [(i) => i.$1, (i) => i.$2]);
      expect(result, [('key1', 'temperature')]);
    });
  });
}

import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/cache/ttl_cache.dart';

void main() {
  group('TtlCache', () {
    late TtlCache<String, String> cache;

    setUp(() {
      cache = TtlCache<String, String>(defaultTtl: const Duration(minutes: 5));
    });

    test('returns null for missing key', () {
      expect(cache.get('missing'), isNull);
    });

    test('stores and retrieves value', () {
      cache.set('key1', 'value1');
      expect(cache.get('key1'), equals('value1'));
    });

    test('returns null after TTL expires', () async {
      final shortCache = TtlCache<String, String>(
        defaultTtl: const Duration(milliseconds: 10),
      );
      shortCache.set('key1', 'value1');
      expect(shortCache.get('key1'), equals('value1'));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(shortCache.get('key1'), isNull);
    });

    test('invalidate removes specific key', () {
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      cache.invalidate('key1');

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear removes all entries', () {
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3');

      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.get('key3'), isNull);
      expect(cache.length, equals(0));
    });

    test('fresh value replaces expired one', () async {
      final shortCache = TtlCache<String, String>(
        defaultTtl: const Duration(milliseconds: 10),
      );
      shortCache.set('key1', 'old');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Expired
      expect(shortCache.get('key1'), isNull);

      // Set new value
      shortCache.set('key1', 'new');
      expect(shortCache.get('key1'), equals('new'));
    });

    test('length reports entry count', () {
      expect(cache.length, equals(0));
      cache.set('a', '1');
      cache.set('b', '2');
      expect(cache.length, equals(2));
    });

    test('custom TTL per entry overrides default', () async {
      cache.set('short', 'value', ttl: const Duration(milliseconds: 10));
      cache.set('long', 'value', ttl: const Duration(seconds: 10));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cache.get('short'), isNull);
      expect(cache.get('long'), equals('value'));
    });

    test('evicts oldest entries when maxEntries exceeded', () {
      final smallCache = TtlCache<String, String>(
        defaultTtl: const Duration(minutes: 5),
        maxEntries: 3,
      );

      smallCache.set('a', '1');
      smallCache.set('b', '2');
      smallCache.set('c', '3');
      // This should evict 'a' (oldest by insertion order)
      smallCache.set('d', '4');

      expect(smallCache.get('a'), isNull);
      expect(smallCache.get('b'), equals('2'));
      expect(smallCache.get('c'), equals('3'));
      expect(smallCache.get('d'), equals('4'));
    });

    test('evicts expired entries before oldest on overflow', () async {
      final smallCache = TtlCache<String, String>(
        defaultTtl: const Duration(minutes: 5),
        maxEntries: 3,
      );

      smallCache.set('expire-soon', 'x',
          ttl: const Duration(milliseconds: 10));
      smallCache.set('b', '2');
      smallCache.set('c', '3');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Adding 'd' should evict expired 'expire-soon', not 'b'
      smallCache.set('d', '4');

      expect(smallCache.get('expire-soon'), isNull);
      expect(smallCache.get('b'), equals('2'));
      expect(smallCache.get('c'), equals('3'));
      expect(smallCache.get('d'), equals('4'));
    });
  });

  group('TtlCache.getOrCompute', () {
    late TtlCache<String, String> cache;

    setUp(() {
      cache = TtlCache<String, String>(defaultTtl: const Duration(minutes: 5));
    });

    test('calls compute on cache miss', () async {
      var computeCalled = false;
      final result = await cache.getOrCompute('key1', () async {
        computeCalled = true;
        return 'computed';
      });

      expect(computeCalled, isTrue);
      expect(result, equals('computed'));
    });

    test('returns cached value without calling compute', () async {
      cache.set('key1', 'cached');

      var computeCalled = false;
      final result = await cache.getOrCompute('key1', () async {
        computeCalled = true;
        return 'computed';
      });

      expect(computeCalled, isFalse);
      expect(result, equals('cached'));
    });

    test('calls compute after TTL expires', () async {
      final shortCache = TtlCache<String, String>(
        defaultTtl: const Duration(milliseconds: 10),
      );
      shortCache.set('key1', 'old');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = await shortCache.getOrCompute('key1', () async {
        return 'recomputed';
      });

      expect(result, equals('recomputed'));
    });

    test('caches computed value for subsequent calls', () async {
      var computeCount = 0;
      Future<String> compute() async {
        computeCount++;
        return 'value-$computeCount';
      }

      final first = await cache.getOrCompute('key1', compute);
      final second = await cache.getOrCompute('key1', compute);

      expect(first, equals('value-1'));
      expect(second, equals('value-1'));
      expect(computeCount, equals(1));
    });
  });

  group('TtlCache nullable values', () {
    late TtlCache<String, Map<String, dynamic>?> cache;

    setUp(() {
      cache = TtlCache<String, Map<String, dynamic>?>(
        defaultTtl: const Duration(minutes: 5),
      );
    });

    test('caches null value correctly', () async {
      var computeCount = 0;
      final result = await cache.getOrCompute('missing-key', () async {
        computeCount++;
        return null;
      });

      expect(result, isNull);
      expect(computeCount, equals(1));

      // Second call should use cached null, not recompute
      final result2 = await cache.getOrCompute('missing-key', () async {
        computeCount++;
        return {'found': true};
      });

      expect(result2, isNull);
      expect(computeCount, equals(1));
    });

    test('has() returns true for cached null', () async {
      await cache.getOrCompute('null-key', () async => null);
      expect(cache.has('null-key'), isTrue);
    });

    test('has() returns false for missing key', () {
      expect(cache.has('no-such-key'), isFalse);
    });

    test('has() returns false for expired key', () async {
      final shortCache = TtlCache<String, String?>(
        defaultTtl: const Duration(milliseconds: 10),
      );
      shortCache.set('key1', null);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(shortCache.has('key1'), isFalse);
    });
  });
}

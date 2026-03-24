import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/services/trend_service.dart';
import '../helpers/test_database.dart';

void main() {
  group('TrendBucket', () {
    test('toText formats a single bucket as human-readable line', () {
      final bucket = TrendBucket(
        bucket: DateTime.utc(2026, 1, 1, 14, 0, 0),
        minVal: 1.2,
        avgVal: 1.5,
        maxVal: 1.8,
        sampleCount: 60,
      );
      final text = bucket.toText();
      expect(text, contains('2026-01-01T14:00:00'));
      expect(text, contains('min=1.2'));
      expect(text, contains('avg=1.5'));
      expect(text, contains('max=1.8'));
      expect(text, contains('samples=60'));
    });
  });

  group('TrendResult', () {
    test('toText with buckets returns formatted header + lines', () {
      final result = TrendResult(
        key: 'pump3.speed',
        buckets: [
          TrendBucket(
            bucket: DateTime.utc(2026, 1, 1, 14, 0, 0),
            minVal: 1.2,
            avgVal: 1.5,
            maxVal: 1.8,
            sampleCount: 60,
          ),
          TrendBucket(
            bucket: DateTime.utc(2026, 1, 1, 14, 5, 0),
            minVal: 1.3,
            avgVal: 1.6,
            maxVal: 1.9,
            sampleCount: 55,
          ),
        ],
        bucketInterval: '300000 milliseconds',
      );
      final text = result.toText();
      expect(text, contains('pump3.speed'));
      expect(text, contains('2 buckets'));
      expect(text, contains('300000 milliseconds'));
      expect(text, contains('2026-01-01T14:00:00'));
      expect(text, contains('2026-01-01T14:05:00'));
    });

    test('toText with error returns error message', () {
      final result = TrendResult(
        key: 'pump3.speed',
        buckets: [],
        bucketInterval: '',
        error: 'No trend data table found for key "pump3.speed"',
      );
      final text = result.toText();
      expect(text, contains('No trend data table'));
      expect(text, contains('pump3.speed'));
    });

    test('toText with empty buckets returns no-data message', () {
      final result = TrendResult(
        key: 'pump3.speed',
        buckets: [],
        bucketInterval: '300000 milliseconds',
      );
      final text = result.toText();
      expect(text, contains('No data'));
    });

    test('token budget: 100 buckets produce under 5000 chars', () {
      final buckets = List.generate(
        100,
        (i) => TrendBucket(
          bucket: DateTime.utc(2026, 1, 1, 0, 0, 0)
              .add(Duration(minutes: i * 5)),
          minVal: 10.0 + i * 0.1,
          avgVal: 15.0 + i * 0.1,
          maxVal: 20.0 + i * 0.1,
          sampleCount: 60,
        ),
      );
      final result = TrendResult(
        key: 'some.long.key.name.here',
        buckets: buckets,
        bucketInterval: '300000 milliseconds',
      );
      final text = result.toText();
      expect(text.length, lessThan(10000));
    });
  });

  group('TrendService.calculateBucketInterval', () {
    test('1 hour range produces bucket interval under 100 buckets', () {
      final from = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final to = DateTime.utc(2026, 1, 1, 13, 0, 0);
      final intervalMs = TrendService.calculateBucketIntervalMs(from, to);
      // 1 hour = 3,600,000 ms / 100 = 36,000 ms per bucket
      expect(intervalMs, equals(36000));
    });

    test('24 hour range produces bucket interval under 100 buckets', () {
      final from = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final to = DateTime.utc(2026, 1, 2, 0, 0, 0);
      final intervalMs = TrendService.calculateBucketIntervalMs(from, to);
      // 24 hours = 86,400,000 ms / 100 = 864,000 ms per bucket
      expect(intervalMs, equals(864000));
    });

    test('very short range (1 minute) still produces positive interval', () {
      final from = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final to = DateTime.utc(2026, 1, 1, 12, 1, 0);
      final intervalMs = TrendService.calculateBucketIntervalMs(from, to);
      // 1 min = 60,000 ms / 100 = 600 ms per bucket
      expect(intervalMs, equals(600));
    });
  });

  group('TrendService with database', () {
    late ServerDatabase db;
    late TrendService service;

    setUp(() async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');
      service = TrendService(db, isPostgres: false);
    });

    tearDown(() async {
      await db.close();
    });

    test('queryTrend with non-existent table returns error TrendResult',
        () async {
      final result = await service.queryTrend(
        key: 'pump3.speed',
        from: DateTime.utc(2026, 1, 1, 12, 0, 0),
        to: DateTime.utc(2026, 1, 1, 13, 0, 0),
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('pump3.speed'));
      expect(result.buckets, isEmpty);
    });

    test('queryTrend with existing table but no data returns empty buckets',
        () async {
      // Create a table matching the timeseries schema
      await db.customStatement(
        'CREATE TABLE "pump3.speed" (time TEXT NOT NULL, value REAL)',
      );

      final result = await service.queryTrend(
        key: 'pump3.speed',
        from: DateTime.utc(2026, 1, 1, 12, 0, 0),
        to: DateTime.utc(2026, 1, 1, 13, 0, 0),
      );
      expect(result.error, isNull);
      expect(result.buckets, isEmpty);
    });

    test('tableExists returns false for non-existent table', () async {
      final exists = await service.tableExists('nonexistent_table');
      expect(exists, isFalse);
    });

    test('tableExists returns true for existing table', () async {
      await db.customStatement(
        'CREATE TABLE "pump3.speed" (time TEXT NOT NULL, value REAL)',
      );
      final exists = await service.tableExists('pump3.speed');
      expect(exists, isTrue);
    });
  });
}

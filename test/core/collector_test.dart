import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/collector.dart';

void main() {
  group('Collector Tests', () {
    group('CollectEntry', () {
      test('should create with required fields', () {
        final entry = CollectEntry(key: 'test_key');
        expect(entry.key, 'test_key');
        expect(entry.name, 'test_key'); // Default name should be key
        expect(entry.retention, const Duration(days: 365));
        expect(entry.sampleInterval, null);
      });

      test('should create with all fields', () {
        final entry = CollectEntry(
          key: 'test_key',
          name: 'Custom Name',
          sampleInterval: const Duration(microseconds: 100000),
        );
        expect(entry.key, 'test_key');
        expect(entry.name, 'Custom Name');
        expect(entry.sampleInterval, const Duration(microseconds: 100000));
      });

      test('should serialize and deserialize correctly', () {
        final entry = CollectEntry(
          key: 'test_key',
          name: 'Test Name',
          sampleInterval: const Duration(microseconds: 50000),
        );

        final json = entry.toJson();
        final deserialized = CollectEntry.fromJson(json);

        expect(deserialized.key, entry.key);
        expect(deserialized.name, entry.name);
        expect(deserialized.retention, entry.retention);
        expect(deserialized.sampleInterval, entry.sampleInterval);
      });

      test('should handle custom retention period', () {
        final entry = CollectEntry(key: 'test_key');
        expect(entry.retention, const Duration(days: 365));
      });
    });

    group('CollectTable', () {
      test('should create with required fields', () {
        final table = CollectTable(
          name: 'test_table',
          entries: [CollectEntry(key: 'test_key')],
        );
        expect(table.name, 'test_table');
        expect(table.entries.length, 1);
        expect(table.retention, const Duration(days: 365));
      });

      test('should serialize and deserialize correctly', () {
        final table = CollectTable(
          name: 'test_table',
          entries: [
            CollectEntry(key: 'key1', name: 'Key 1'),
            CollectEntry(key: 'key2', name: 'Key 2'),
          ],
        );

        final jsonString = jsonEncode(table.toJson());
        final deserialized = CollectTable.fromJson(jsonDecode(jsonString));

        expect(deserialized.name, table.name);
        expect(deserialized.retention, table.retention);
        expect(deserialized.entries.length, table.entries.length);
        expect(deserialized.entries[0].key, table.entries[0].key);
        expect(deserialized.entries[1].key, table.entries[1].key);
      });
    });

    group('CollectorConfig', () {
      test('should create with tables', () {
        final config = CollectorConfig(tables: [
          CollectTable(
            name: 'table1',
            entries: [CollectEntry(key: 'key1')],
          ),
          CollectTable(
            name: 'table2',
            entries: [CollectEntry(key: 'key2')],
          ),
        ]);

        expect(config.tables.length, 2);
        expect(config.tables[0].name, 'table1');
        expect(config.tables[1].name, 'table2');
      });

      test('should serialize and deserialize correctly', () {
        final config = CollectorConfig(tables: [
          CollectTable(
            name: 'test_table',
            entries: [CollectEntry(key: 'test_key')],
          ),
        ]);

        final jsonString = jsonEncode(config.toJson());
        final deserialized = CollectorConfig.fromJson(jsonDecode(jsonString));

        expect(deserialized.tables.length, config.tables.length);
        expect(deserialized.tables[0].name, config.tables[0].name);
        expect(deserialized.tables[0].entries[0].key,
            config.tables[0].entries[0].key);
      });
    });
  });
}

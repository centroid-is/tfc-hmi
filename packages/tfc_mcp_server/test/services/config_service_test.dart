import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/services/config_service.dart';
import '../helpers/test_database.dart';

void main() {
  group('ConfigService', () {
    late ServerDatabase db;
    late ConfigService service;

    /// Sample page_editor_data JSON with 3 pages.
    final pageEditorData = {
      'overview': {
        'title': 'Overview',
        'key': 'overview',
        'widgets': [
          {'type': 'gauge', 'key': 'pump3.speed'},
        ],
      },
      'conveyor': {
        'title': 'Conveyor Control',
        'key': 'conveyor',
        'widgets': [
          {'type': 'display', 'key': 'conveyor.speed'},
        ],
      },
      'mixer': {
        'title': 'Mixer Station',
        'key': 'mixer',
        'widgets': [],
      },
    };

    /// Sample key_mappings JSON with OPC UA entries.
    final keyMappings = {
      'nodes': {
        'pump3.speed': {
          'opcua_node': {'namespace': 2, 'identifier': 'Pump3.Speed'},
          'collect': {'enabled': true},
        },
        'pump3.current': {
          'opcua_node': {'namespace': 2, 'identifier': 'Pump3.Current'},
          'collect': {'enabled': true},
        },
        'conveyor.speed': {
          'opcua_node': {'namespace': 2, 'identifier': 'Conv.Speed'},
          'collect': {'enabled': false},
        },
      },
    };

    /// Sample key_mappings JSON with mixed protocols.
    final mixedKeyMappings = {
      'nodes': {
        'pump3.speed': {
          'opcua_node': {'namespace': 2, 'identifier': 'Pump3.Speed'},
        },
        'tank.level': {
          'modbus_node': {
            'register_type': 'holdingRegister',
            'address': 100,
            'data_type': 'uint16',
            'poll_group': 'fast',
            'server_alias': 'plc1',
          },
        },
        'weigher.batch': {
          'm2400_node': {
            'record_type': 'BATCH',
            'field': 'weight',
            'server_alias': 'jbtm1',
          },
        },
        'pump3.dual': {
          'opcua_node': {'namespace': 2, 'identifier': 'Pump3.Dual'},
          'modbus_node': {
            'register_type': 'inputRegister',
            'address': 200,
            'data_type': 'float32',
            'poll_group': 'default',
          },
        },
      },
    };

    setUp(() async {
      db = createTestDatabase();
      // Ensure tables are created
      await db.customStatement('SELECT 1');
      service = ConfigService(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insertPreference(String key, dynamic value) async {
      await db.into(db.serverFlutterPreferences).insert(
            ServerFlutterPreferencesCompanion.insert(
              key: key,
              value: Value(jsonEncode(value)),
              type: 'String',
            ),
          );
    }

    Future<void> insertAlarm({
      required String uid,
      String? key,
      required String title,
      required String description,
      String rules = '[]',
    }) async {
      await db.into(db.serverAlarm).insert(
            ServerAlarmCompanion.insert(
              uid: uid,
              key: key != null ? Value(key) : const Value.absent(),
              title: title,
              description: description,
              rules: rules,
            ),
          );
    }

    group('listPages', () {
      test('returns page key+title summaries from page_editor_data', () async {
        await insertPreference('page_editor_data', pageEditorData);

        final pages = await service.listPages();

        expect(pages, hasLength(3));
        // Should contain key and title for each page
        final keys = pages.map((p) => p['key']).toSet();
        expect(keys, containsAll(['overview', 'conveyor', 'mixer']));
        final titles = pages.map((p) => p['title']).toSet();
        expect(titles, containsAll(
            ['Overview', 'Conveyor Control', 'Mixer Station']));
      });

      test('returns empty list when no page_editor_data exists', () async {
        final pages = await service.listPages();
        expect(pages, isEmpty);
      });

      test('respects limit parameter', () async {
        await insertPreference('page_editor_data', pageEditorData);

        final pages = await service.listPages(limit: 2);
        expect(pages, hasLength(2));
      });
    });

    group('listAssets', () {
      test('returns asset summaries from page_editor_data', () async {
        await insertPreference('page_editor_data', pageEditorData);

        final assets = await service.listAssets();

        expect(assets, hasLength(3));
        final keys = assets.map((a) => a['key']).toSet();
        expect(keys, containsAll(['overview', 'conveyor', 'mixer']));
      });

      test('returns empty list when no data exists', () async {
        final assets = await service.listAssets();
        expect(assets, isEmpty);
      });
    });

    group('getAssetDetail', () {
      test('returns full page config for given page key', () async {
        await insertPreference('page_editor_data', pageEditorData);

        final detail = await service.getAssetDetail('overview');

        expect(detail, isNotNull);
        expect(detail!['key'], equals('overview'));
        expect(detail['title'], equals('Overview'));
        expect(detail['widgets'], isList);
        expect((detail['widgets'] as List), hasLength(1));
      });

      test('returns null for nonexistent page key', () async {
        await insertPreference('page_editor_data', pageEditorData);

        final detail = await service.getAssetDetail('nonexistent');
        expect(detail, isNull);
      });
    });

    group('listKeyMappings', () {
      test('returns OPC UA key-to-node pairs from key_mappings', () async {
        await insertPreference('key_mappings', keyMappings);

        final mappings = await service.listKeyMappings();

        expect(mappings, hasLength(3));
        final keys = mappings.map((m) => m['key']).toSet();
        expect(keys,
            containsAll(['pump3.speed', 'pump3.current', 'conveyor.speed']));
        // Each mapping should have protocol, identifier, namespace
        for (final m in mappings) {
          expect(m['protocol'], equals('opcua'));
          expect(m['identifier'], isA<String>());
          expect(m['namespace'], isA<int>());
        }
      });

      test('returns empty list when no key_mappings exists', () async {
        final mappings = await service.listKeyMappings();
        expect(mappings, isEmpty);
      });

      test('respects limit parameter', () async {
        await insertPreference('key_mappings', keyMappings);

        final mappings = await service.listKeyMappings(limit: 2);
        expect(mappings, hasLength(2));
      });

      test('supports fuzzy filter', () async {
        await insertPreference('key_mappings', keyMappings);

        final mappings = await service.listKeyMappings(filter: 'pump');
        expect(mappings, hasLength(2));
        for (final m in mappings) {
          expect((m['key'] as String).toLowerCase(), contains('pump'));
        }
      });

      test('returns modbus mappings with register info', () async {
        await insertPreference('key_mappings', mixedKeyMappings);

        final mappings = await service.listKeyMappings(filter: 'tank');
        expect(mappings, hasLength(1));
        final m = mappings.first;
        expect(m['key'], equals('tank.level'));
        expect(m['protocol'], equals('modbus'));
        expect(m['register_type'], equals('holdingRegister'));
        expect(m['address'], equals(100));
        expect(m['data_type'], equals('uint16'));
        expect(m['poll_group'], equals('fast'));
        expect(m['server_alias'], equals('plc1'));
      });

      test('returns m2400 mappings with record info', () async {
        await insertPreference('key_mappings', mixedKeyMappings);

        final mappings = await service.listKeyMappings(filter: 'weigher');
        expect(mappings, hasLength(1));
        final m = mappings.first;
        expect(m['key'], equals('weigher.batch'));
        expect(m['protocol'], equals('m2400'));
        expect(m['record_type'], equals('BATCH'));
        expect(m['field'], equals('weight'));
        expect(m['server_alias'], equals('jbtm1'));
      });

      test('returns multiple mappings for dual-protocol keys', () async {
        await insertPreference('key_mappings', mixedKeyMappings);

        final mappings = await service.listKeyMappings(filter: 'pump3.dual');
        expect(mappings, hasLength(2));
        final protocols = mappings.map((m) => m['protocol']).toSet();
        expect(protocols, containsAll(['opcua', 'modbus']));
      });

      test('returns all protocols in mixed key_mappings', () async {
        await insertPreference('key_mappings', mixedKeyMappings);

        // 4 nodes but pump3.dual has 2 protocols = 5 entries
        final mappings = await service.listKeyMappings();
        expect(mappings, hasLength(5));
        final protocols = mappings.map((m) => m['protocol']).toSet();
        expect(protocols, containsAll(['opcua', 'modbus', 'm2400']));
      });
    });

    group('listAlarmDefinitions', () {
      test('returns alarm uid/title/description summaries', () async {
        await insertAlarm(
          uid: 'alarm-1',
          key: 'pump3.temp',
          title: 'Pump 3 High Temperature',
          description: 'Temperature exceeds 80C',
        );
        await insertAlarm(
          uid: 'alarm-2',
          key: 'conveyor.speed',
          title: 'Conveyor Overspeed',
          description: 'Conveyor belt speed above limit',
        );

        final alarms = await service.listAlarmDefinitions();

        expect(alarms, hasLength(2));
        final uids = alarms.map((a) => a['uid']).toSet();
        expect(uids, containsAll(['alarm-1', 'alarm-2']));
        expect(alarms.first['title'], isA<String>());
        expect(alarms.first['description'], isA<String>());
      });

      test('respects limit parameter', () async {
        for (var i = 0; i < 10; i++) {
          await insertAlarm(
            uid: 'alarm-$i',
            title: 'Alarm $i',
            description: 'Description $i',
          );
        }

        final alarms = await service.listAlarmDefinitions(limit: 5);
        expect(alarms, hasLength(5));
      });

      test('supports fuzzy filter', () async {
        await insertAlarm(
          uid: 'alarm-1',
          title: 'Pump 3 High Temperature',
          description: 'Temperature exceeds 80C',
        );
        await insertAlarm(
          uid: 'alarm-2',
          title: 'Conveyor Overspeed',
          description: 'Belt speed above limit',
        );

        final alarms = await service.listAlarmDefinitions(filter: 'pump');
        expect(alarms, hasLength(1));
        expect(alarms.first['title'], contains('Pump'));
      });
    });
  });
}

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/services/alarm_service.dart';
import 'package:tfc_mcp_server/src/tools/alarm_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

void main() {
  group('Alarm tools integration', () {
    late ServerDatabase db;
    late MockAlarmReader alarmReader;
    late McpServer mcpServer;
    late MockMcpClient client;

    final now = DateTime.utc(2026, 3, 6, 12, 0, 0);
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    final threeHoursAgo = now.subtract(const Duration(hours: 3));

    setUp(() async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');

      alarmReader = MockAlarmReader();
      alarmReader.addAlarmConfig({
        'uid': 'alarm-1',
        'key': 'pump3.overcurrent',
        'title': 'Pump 3 Overcurrent',
        'description': 'Current exceeds 15A threshold',
        'rules': '[]',
      });
      alarmReader.addAlarmConfig({
        'uid': 'alarm-2',
        'key': 'tank1.highlevel',
        'title': 'Tank 1 High Level',
        'description': 'Level exceeds 95% capacity',
        'rules': '[]',
      });

      // Insert alarm configs into serverAlarm table (FK integrity).
      await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
            uid: 'alarm-1',
            title: 'Pump 3 Overcurrent',
            description: 'Current exceeds 15A threshold',
            rules: '[]',
          ));
      await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
            uid: 'alarm-2',
            title: 'Tank 1 High Level',
            description: 'Level exceeds 95% capacity',
            rules: '[]',
          ));

      // Insert alarm history.
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: true,
              pendingAck: true,
              createdAt: oneHourAgo,
            ),
          );
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-2',
              alarmTitle: 'Tank 1 High Level',
              alarmDescription: 'Level exceeds 95% capacity',
              alarmLevel: 'warning',
              active: true,
              pendingAck: false,
              createdAt: twoHoursAgo,
            ),
          );
      // Inactive record.
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: false,
              pendingAck: false,
              createdAt: threeHoursAgo,
              deactivatedAt: Value(twoHoursAgo),
            ),
          );

      final alarmService = AlarmService(alarmReader: alarmReader, db: db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerAlarmTools(registry, alarmService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    group('list_alarms', () {
      test('returns formatted active alarm list', () async {
        final result = await client.callTool('list_alarms', {});

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, contains('Pump 3 Overcurrent'));
        expect(text, contains('critical'));
        expect(text, contains('Tank 1 High Level'));
        expect(text, contains('warning'));
      });

      test('with no active alarms returns "No active alarms."', () async {
        // Deactivate all.
        await (db.update(db.serverAlarmHistory)
              ..where((t) => t.active.equals(true)))
            .write(ServerAlarmHistoryCompanion(
          active: const Value(false),
          deactivatedAt: Value(now),
        ));

        final result = await client.callTool('list_alarms', {});

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, equals('No active alarms.'));
      });
    });

    group('get_alarm_detail', () {
      test('with valid uid returns alarm config info', () async {
        final result =
            await client.callTool('get_alarm_detail', {'uid': 'alarm-1'});

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, contains('Pump 3 Overcurrent'));
        expect(text, contains('pump3.overcurrent'));
        expect(text, contains('alarm-1'));
      });

      test('with invalid uid returns isError=true', () async {
        final result = await client
            .callTool('get_alarm_detail', {'uid': 'nonexistent'});

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text, contains('nonexistent'));
      });
    });

    group('query_alarm_history', () {
      test('with after/before params returns filtered results', () async {
        final result = await client.callTool('query_alarm_history', {
          'after': twoHoursAgo.toIso8601String(),
          'before': now.toIso8601String(),
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        // Should include records at oneHourAgo and twoHoursAgo but not
        // threeHoursAgo.
        expect(text, contains('Pump 3 Overcurrent'));
        expect(text, contains('Tank 1 High Level'));
      });

      test('with alarm_uid param returns filtered results', () async {
        final result = await client.callTool('query_alarm_history', {
          'alarm_uid': 'alarm-1',
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, contains('Pump 3 Overcurrent'));
        // Should not contain alarm-2 data.
        expect(text, isNot(contains('Tank 1 High Level')));
      });

      test('enforces limit parameter', () async {
        final result = await client.callTool('query_alarm_history', {
          'limit': 1,
        });

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        // With limit 1, only the most recent record.
        // Count the number of entries by looking for the separator pattern.
        // The most recent active record is alarm-1 at oneHourAgo.
        expect(text, contains('Pump 3 Overcurrent'));
        // Should NOT contain the second entry.
        expect(text, isNot(contains('Tank 1 High Level')));
      });
    });
  });
}

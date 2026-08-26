// PreferencesWatcher against a real Postgres: the keyed trigger, the shared
// LISTEN/NOTIFY connection, and the server-side digest query.
//
// The large-value save is a regression guard for the pg_notify payload cap:
// NOTIFY payloads max out at 8000 bytes and the cap fails the *statement that
// fired the trigger*. A row-payload trigger (enableNotificationChannel) on
// flutter_preferences would therefore make every save of a big key_mappings
// row error out — the keyed trigger must keep such saves working.
@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/preferences_watch.dart';

import 'docker_compose.dart';

void main() {
  group('PreferencesWatcher integration', () {
    late Database database;
    late pg.Connection editor;

    setUpAll(() async {
      await stopDockerCompose();
      await startDockerCompose();
      await waitForDatabaseReady();
      database = await connectToDatabase();
      // A separate raw connection playing the part of an HMI station saving
      // config — its writes must be visible to the watcher, which is exactly
      // what Preferences.onPreferencesChanged cannot do.
      editor = await getTestConnection();
    });

    tearDownAll(() async {
      await editor.close();
      await database.close();
      await stopDockerCompose();
    });

    Future<void> save(String key, String value) async {
      await editor.execute(
        pg.Sql.named(
            'INSERT INTO flutter_preferences (key, value, type) VALUES '
            "(@key, @value, 'String') "
            'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value'),
        parameters: {'key': key, 'value': value},
      );
    }

    test('edits from another connection are noticed via NOTIFY alone',
        () async {
      await save('key_mappings', '{"nodes":{}}');

      final watcher = PreferencesWatcher.forDatabase(
        database,
        keys: {'key_mappings', 'alarm_man_config'},
        // Deliberately never fires during the test: every event asserted on
        // below can only have come from LISTEN/NOTIFY.
        pollInterval: const Duration(hours: 1),
      );
      addTearDown(watcher.close);
      final seen = <String>[];
      watcher.changes.listen(seen.add);
      await watcher.start();

      // LISTEN registration is asynchronous; prove the channel is live before
      // asserting on it, by saving fresh values until the first event lands.
      var warm = 0;
      final warmDeadline = DateTime.now().add(const Duration(seconds: 20));
      while (seen.isEmpty) {
        if (DateTime.now().isAfter(warmDeadline)) {
          fail('LISTEN never became live: no event after ${warm} warm-up '
              'saves');
        }
        await save('key_mappings', '{"warm":${warm++}}');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      // Let events from the remaining warm-up saves finish trickling in.
      var quietSince = seen.length;
      while (true) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (seen.length == quietSince) break;
        quietSince = seen.length;
      }

      // A save whose content is a *huge* value: must neither fail the INSERT
      // (pg_notify payload cap) nor go unnoticed.
      final baseCount = seen.length;
      final big = '{"nodes":{"pad":"${'x' * 100000}"}}';
      await save('key_mappings', big);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (seen.length == baseCount) {
        if (DateTime.now().isAfter(deadline)) {
          fail('large-value change was never emitted');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(seen.last, 'key_mappings');

      // Re-saving the identical value fires the trigger but must not emit.
      final noopBase = seen.length;
      await save('key_mappings', big);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(seen.length, noopBase,
          reason: 'identical re-save must not count as a change');

      // A different watched key emits under its own name.
      await save('alarm_man_config', '{"alarms":[]}');
      final alarmDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (!seen.contains('alarm_man_config')) {
        if (DateTime.now().isAfter(alarmDeadline)) {
          fail('alarm_man_config change was never emitted');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
  });
}

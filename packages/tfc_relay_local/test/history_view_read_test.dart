/// The eleven history-view methods against a **real TimescaleDB** — the second
/// `db`-tagged leg.
///
/// 8b's `db` lane, not a third one: the same tag, the same env-addressed
/// fixture, the same CI step, exactly as `timeseries_read_test.dart` joined it.
///
/// ## Why these cases need a real server and cannot be faked
///
/// Every one of the four mismatches this file exists to pin is a property of
/// what the *database* does with a value, not of what the store does with a
/// row:
///
///  * a `DateTime` written as `timestamp with time zone` and read back — the
///    microseconds and the `isUtc` flag are the database driver's answer, and
///    a fake would answer whatever the fake's author expected;
///  * `ON DELETE CASCADE` on three foreign keys, which is why upstream's
///    four-statement delete has not yet left a half-deleted view behind;
///  * `timescaledb_information.jobs`, which only exists where TimescaleDB does
///    and is the whole subject of the retention horizon;
///  * a `text` column that is NULL versus one holding the empty string, which
///    is a distinction only the server can be asked about.
///
/// ## Cleanup, and why it is by id rather than by table
///
/// The timeseries leg gives every *table* a per-run suffix. It cannot be done
/// here: the four history tables are named by drift's schema, shared with the
/// application's own HMI and with any 8b case that runs against the same
/// server. So every view this file creates is remembered and deleted in
/// `tearDownAll`, and the delete cascades to its keys, graphs and periods.
/// Nothing here touches a row it did not write.
@TestOn('vm')
@Tags(['db'])
@Timeout(Duration(minutes: 5))
library;

import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_relay_local/src/data/history_view_store.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart'
    show HistoryViewGraphRecord, HistoryViewKeyRecord;

import 'support/timescale_fixture.dart';

late TimescaleFixture fx;
late pg.Connection admin;
late Database writer;
late HistoryViewStore store;

/// Everything written through [store], deleted in `tearDownAll`.
final Set<int> createdViews = <int>{};

/// Every message the store logged, in order. Cleared per case.
final List<String> notices = <String>[];

DatabaseConfig dbConfig() => DatabaseConfig(
      postgres: pg.Endpoint(
        host: fx.host,
        port: fx.port,
        database: fx.database,
        username: fx.username,
        password: fx.password,
      ),
      sslMode: pg.SslMode.disable,
      connectTimeout: const Duration(seconds: 5),
      queryTimeout: const Duration(seconds: 5),
      applicationName: 'relay-history-test',
    );

Future<Database> openWriter() async {
  final db = Database(await AppDatabase.create(dbConfig()));
  await db.open();
  return db;
}

/// Creates a view through the store and remembers it for teardown.
Future<int> newView(String name, List<String> keys,
    [Map<String, HistoryViewKeyRecord>? keyConfigs,
    Map<int, HistoryViewGraphRecord>? graphConfigs]) async {
  final id = await store.createHistoryView(name, keys, keyConfigs, graphConfigs);
  createdViews.add(id);
  return id;
}

Future<int> countRows(String table, String column, int value) async {
  final result = await admin
      .execute(pg.Sql.named('SELECT count(*) FROM "$table" WHERE "$column" = @v'),
          parameters: {'v': value});
  return (result.first.first! as int);
}

void main() {
  setUpAll(() async {
    fx = await TimescaleFixture.start();
    admin = await fx.connect();
    writer = await openWriter();
    store = HistoryViewStore(
      database: () => writer,
      log: notices.add,
    );
  });

  setUp(notices.clear);

  tearDownAll(() async {
    for (final id in createdViews) {
      await admin.execute(
          pg.Sql.named('DELETE FROM history_view WHERE id = @id'),
          parameters: {'id': id});
    }
    try {
      await writer.close();
    } catch (_) {
      // A writer a case already closed on purpose is not a failure here.
    }
    await admin.close();
    await fx.stop();
  });

  group('a created view', () {
    test('the view, its keys and its graphs are all readable afterwards',
        () async {
      final id = await newView(
        'Frystir — vakt 1',
        ['Line1.Motor1', 'Line1.Temp1'],
        {
          'Line1.Motor1': const HistoryViewKeyRecord(
              key: 'Line1.Motor1',
              alias: 'Færiband 1',
              useSecondYAxis: true,
              graphIndex: 1),
          'Line1.Temp1': const HistoryViewKeyRecord(key: 'Line1.Temp1'),
        },
        {
          1: const HistoryViewGraphRecord(
              graphIndex: 1, name: 'Hraði', yAxisUnit: 'rpm', yAxis2Unit: '°C'),
        },
      );

      expect(id, greaterThan(0),
          reason: 'the id is what every later call addresses the view by; a '
              'view without one cannot be opened, edited or deleted');

      final views = await store.selectHistoryViews();
      final saved = views.singleWhere((v) => v.id == id);
      expect(saved.name, 'Frystir — vakt 1',
          reason: 'the view came back under a different name than it was '
              'saved with');
      expect(saved.createdAt.isUtc, isTrue,
          reason: 'drift stamps createdAt with a clientDefault of '
              'DateTime.now() — a LOCAL instant. Every DateTime on this wire '
              'is UTC epoch milliseconds (state_man_api.dart:302), and a '
              'local-flagged instant is not == to the UTC one it decodes to');

      final keys = await store.getHistoryViewKeys(id);
      expect(keys.keys, containsAll(['Line1.Motor1', 'Line1.Temp1']));
      expect(keys['Line1.Motor1']!.alias, 'Færiband 1');
      expect(keys['Line1.Motor1']!.useSecondYAxis, isTrue);
      expect(keys['Line1.Motor1']!.graphIndex, 1);

      final graphs = await store.getHistoryViewGraphs(id);
      expect(graphs[1]!.name, 'Hraði');
      expect(graphs[1]!.yAxisUnit, 'rpm');
      expect(graphs[1]!.yAxis2Unit, '°C');
    });

    test('a graph map keyed {0, 7, 12} comes back with all three entries',
        () async {
      // Non-contiguous ON PURPOSE. An implementation that renumbered — or one
      // that iterated 0..n and stopped at the first gap — would pass a
      // {0, 1, 2} case and fail this one. And drift's own createHistoryView
      // reads the map's keys with int.tryParse and SILENTLY SKIPS whatever
      // fails, so a chart configured with four graphs would come back with
      // three and nothing anywhere would say which one went.
      final id = await newView('Þrjú línurit', const [], null, {
        0: const HistoryViewGraphRecord(graphIndex: 0, yAxisUnit: 'rpm'),
        7: const HistoryViewGraphRecord(graphIndex: 7, yAxisUnit: 'bar'),
        12: const HistoryViewGraphRecord(graphIndex: 12, yAxisUnit: '°C'),
      });

      final graphs = await store.getHistoryViewGraphs(id);
      expect(graphs.keys.toList()..sort(), [0, 7, 12],
          reason: 'a graph entry that vanished on the way down is a chart the '
              'operator configured and will not see again');
      expect(graphs[7]!.yAxisUnit, 'bar',
          reason: 'index 7 came back carrying another graph\'s units, which '
              'is a renumbering wearing a round trip');
    });
  });

  group('updateHistoryView', () {
    test('replaces the keys and the graphs, and none of the old set survives',
        () async {
      final id = await newView(
        'Fyrir',
        ['old.a', 'old.b'],
        {'old.a': const HistoryViewKeyRecord(key: 'old.a', alias: 'Gamalt')},
        {0: const HistoryViewGraphRecord(graphIndex: 0, name: 'Gamalt')},
      );

      await store.updateHistoryView(
        id,
        'Eftir',
        ['new.a'],
        {'new.a': const HistoryViewKeyRecord(key: 'new.a', alias: 'Nýtt')},
        {3: const HistoryViewGraphRecord(graphIndex: 3, name: 'Nýtt')},
      );

      final keys = await store.getHistoryViewKeys(id);
      expect(keys.keys, ['new.a'],
          reason: 'a key removed from a view in the editor and still plotted '
              'after a reload is the edit not having happened');
      expect(keys['new.a']!.alias, 'Nýtt');

      final graphs = await store.getHistoryViewGraphs(id);
      expect(graphs.keys, [3]);
      expect(graphs[0], isNull,
          reason: 'the replaced graph configuration outlived the replacement');

      final views = await store.selectHistoryViews();
      final saved = views.singleWhere((v) => v.id == id);
      expect(saved.name, 'Eftir');
      expect(saved.updatedAt, isNotNull,
          reason: 'updateHistoryView stamps updatedAt; null after an edit is '
              'a view that reads as never edited');
      expect(saved.updatedAt!.isUtc, isTrue,
          reason: 'drift writes DateTime.now() here too — a LOCAL instant');
    });
  });

  group('deleteHistoryView', () {
    test('takes the view, its keys, its graphs and its periods with it',
        () async {
      final id = await newView(
        'Til eyðingar',
        ['k1'],
        {'k1': const HistoryViewKeyRecord(key: 'k1')},
        {0: const HistoryViewGraphRecord(graphIndex: 0, name: 'G')},
      );
      await store.addHistoryViewPeriod(id, 'Vakt', DateTime.utc(2026, 8, 12, 6),
          DateTime.utc(2026, 8, 12, 14));

      // Seeded, and asserted seeded: a delete case that runs against an empty
      // view proves nothing at all.
      expect(await countRows('history_view_key', 'view_id', id), 1);
      expect(await countRows('history_view_graph', 'view_id', id), 1);
      expect(await countRows('history_view_period', 'view_id', id), 1);

      await store.deleteHistoryView(id);

      // Queried, not trusted. The FK cascade is what makes upstream's four
      // separate un-transacted deletes total on Postgres, and a cascade that
      // was not created — a schema built by a migration path that skipped it,
      // or a SQLite deployment with foreign_keys off — is invisible until a
      // deleted view comes back as a partial one after a restart.
      expect(await countRows('history_view', 'id', id), 0,
          reason: 'the deleted view is still in the picker');
      expect(await countRows('history_view_key', 'view_id', id), 0,
          reason: 'the view was deleted and its plotted keys outlived it');
      expect(await countRows('history_view_graph', 'view_id', id), 0,
          reason: 'the graph configuration outlived the view it configured');
      expect(await countRows('history_view_period', 'view_id', id), 0,
          reason: 'the saved shift windows outlived the view they were saved '
              'on, and nothing can reach them to delete them now');
    });
  });

  group('selectHistoryViews', () {
    test('lists every saved view, and says nothing about their keys', () async {
      final a = await newView('Picker A', ['k']);
      final b = await newView('Picker B', ['k']);

      final views = await store.selectHistoryViews();
      expect(views.map((v) => v.id), containsAll([a, b]));
      expect(views.singleWhere((v) => v.id == a).name, 'Picker A');
      expect(views.singleWhere((v) => v.id == b).updatedAt, isNull,
          reason: 'updatedAt is null until the view has been edited, and a '
              'never-edited view reading as edited-at-the-epoch is worse than '
              'a null the picker can render as a dash');
    });
  });
}

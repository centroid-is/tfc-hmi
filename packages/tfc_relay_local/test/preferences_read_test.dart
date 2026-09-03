/// The fifteen preference members against a **real Postgres** — the third
/// `db`-tagged leg.
///
/// 8b's `db` lane, not a fourth one: the same tag, the same env-addressed
/// fixture, the same CI step, exactly as `timeseries_read_test.dart` and
/// `history_view_read_test.dart` joined it.
///
/// ## Why these cases need a real server and cannot be faked
///
/// The subject is a **shared table**, and every property worth pinning is a
/// property of what is on disk rather than of what is in a Dart map:
///
///  * `getKeys` reads an in-memory cache that `Preferences.create` fills from
///    Postgres (Trap 8). A fake would answer from whatever the fake's author
///    seeded, which is precisely the mistake being guarded against;
///  * `remove` and `clear` have to take the ROW out, not the cache entry —
///    upstream's `clear` does not, and only a `SELECT` can tell;
///  * a 518 KiB value is a real driver's parameter binding and a real column,
///    and it is the value most likely to break;
///  * a value written by **another connection** is the whole subject of the
///    change feed next door.
///
/// ## Cleanup, and why it is by key prefix
///
/// `flutter_preferences` is keyed by string, named by drift's schema, and
/// shared with the application's own HMI and with any 8b case running against
/// the same server. So every key this file writes carries a per-run prefix and
/// `tearDownAll` deletes exactly those rows. **Nothing here calls `clear()`
/// without an allow-list**: an unrestricted clear would empty a table this
/// suite does not own, and the reach of that call is argued at the store
/// instead of demonstrated against somebody else's rows.
@TestOn('vm')
@Tags(['db'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/state_man.dart' show KeyMappingEntry, KeyMappings;
import 'package:tfc_relay_local/src/data/preference_store.dart';
import 'package:tfc_relay_local/tfc_relay_local.dart';

import 'support/timescale_fixture.dart';

late TimescaleFixture fx;
late pg.Connection admin;
late Database writer;
late PreferenceStore store;

/// Every key this run writes starts with this, so teardown can find them and
/// no case can collide with a neighbour suite's rows.
final String ns = 'relay1009_${DateTime.now().microsecondsSinceEpoch}_';

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
      applicationName: 'relay-prefs-test',
    );

Future<Database> openWriter() async {
  final db = Database(await AppDatabase.create(dbConfig()));
  await db.open();
  return db;
}

/// A store that has never read anything, over the same connection.
///
/// The point of a *fresh* store is Trap 8: whatever it answers, it answers
/// from a cache it filled itself.
PreferenceStore freshStore() =>
    PreferenceStore(database: () => writer, log: notices.add);

/// Writes a row the way another process would: straight at the table, through
/// a connection this gateway does not own.
Future<void> writeBehindTheStore(String key, String value,
    [String type = 'String']) async {
  await admin.execute(
    pg.Sql.named('INSERT INTO flutter_preferences (key, value, type) '
        'VALUES (@k, @v, @t) ON CONFLICT (key) DO UPDATE SET '
        'value = EXCLUDED.value, type = EXCLUDED.type'),
    parameters: {'k': key, 'v': value, 't': type},
  );
}

Future<int> rowCount(String key) async {
  final result = await admin.execute(
      pg.Sql.named('SELECT count(*) FROM flutter_preferences WHERE key = @k'),
      parameters: {'k': key});
  return result.first.first! as int;
}

/// A JSON document shaped and sized like SVN's live `key_mappings` row.
///
/// Measured from `svn-prefs-live-20260811.csv` on 2026-08-11: four rows,
/// 675,890 bytes in total, of which `key_mappings` is **530,287** and
/// `page_editor_data` is 145,405. This builder reproduces the size and the
/// quote density — the escaping is what makes the encoded frame bigger than
/// the value — rather than the plant's actual tag names.
String keyMappingsSized() {
  final buffer = StringBuffer('{"nodes":{');
  var i = 0;
  while (buffer.length < 530287 - 64) {
    if (i > 0) buffer.write(',');
    buffer.write('"CN${i.toString().padLeft(4, '0')}.SPD":'
        '{"name":"AREA01.CNV${i.toString().padLeft(2, '0')}.SUB01",'
        '"type":"opcua","server":"ST101","unit":"rpm","collect":true}');
    i++;
  }
  buffer.write('}');
  while (buffer.length < 530287 - 1) {
    buffer.write(' ');
  }
  buffer.write('}');
  return buffer.toString();
}

void main() {
  setUpAll(() async {
    // The gateway never asks for secret material (SEC-01), and a test process
    // must not be the place that discovers a keychain prompt.
    SecureStorage.setInstance(const NoSecretStorage());
    fx = await TimescaleFixture.start();
    admin = await fx.connect();
    writer = await openWriter();
    store = freshStore();
  });

  setUp(notices.clear);

  tearDownAll(() async {
    await store.close();
    await admin.execute(
        pg.Sql.named("DELETE FROM flutter_preferences WHERE key LIKE @p"),
        parameters: {'p': '$ns%'});
    try {
      await writer.close();
    } catch (_) {
      // A writer a case already closed on purpose is not a failure here.
    }
    await admin.close();
    await fx.stop();
  });

  group('the fifteen members over the shared table', () {
    test('a bool round-trips and containsKey agrees with it', () async {
      final key = '${ns}flag';
      expect(await store.containsKey(key), isFalse,
          reason: 'a key nobody has written must not be reported as present, '
              'or every settings page reads a default as a stored choice');

      await store.setBool(key, true);

      expect(await store.getBool(key), isTrue);
      expect(await store.containsKey(key), isTrue);
      expect(await rowCount(key), 1,
          reason: 'the value has to be in the shared table, not only in this '
              'process: the pipe is not the only writer of this store and a '
              'gateway restart must not undo an operator\'s setting');
    });

    test('an int, a double, a string and a string list all round-trip',
        () async {
      await store.setInt('${ns}i', -7);
      await store.setDouble('${ns}d', 1.5);
      await store.setString('${ns}s', 'Frystir — vakt 1');
      await store.setStringList('${ns}l', ['a', 'b', 'c']);

      expect(await store.getInt('${ns}i'), -7);
      expect(await store.getDouble('${ns}d'), 1.5);
      expect(await store.getString('${ns}s'), 'Frystir — vakt 1');
      expect(await store.getStringList('${ns}l'), ['a', 'b', 'c']);
    });

    test('remove takes the row out of the database, not just the cache',
        () async {
      final key = '${ns}doomed';
      await store.setString(key, 'here');
      expect(await rowCount(key), 1);

      await store.remove(key);

      expect(await store.containsKey(key), isFalse);
      expect(await rowCount(key), 0,
          reason: 'a remove that only clears the memory cache comes back on '
              'the next reconnect, because the cache is refilled from this '
              'table — the delete would undo itself and nothing would say so');
    });

    test('clear over an allow-list takes those rows out of the database',
        () async {
      await store.setString('${ns}c1', 'one');
      await store.setString('${ns}c2', 'two');
      await store.setString('${ns}keep', 'three');

      await store.clear(allowList: {'${ns}c1', '${ns}c2'});

      expect(await rowCount('${ns}c1'), 0);
      expect(await rowCount('${ns}c2'), 0);
      expect(await rowCount('${ns}keep'), 1,
          reason: 'an allow-list that is not honoured is a settings page '
              'wiping the gateway\'s own routing configuration');
      expect(await store.getString('${ns}keep'), 'three');
    });

    test('clearing many keys announces them in ONE turn, not one frame each',
        () async {
      final keys = <String>{for (var i = 0; i < 8; i++) '${ns}burst$i'};
      for (final key in keys) {
        await store.setString(key, 'x');
      }
      // `data_handlers._scheduleFlush`'s exact mechanism, reproduced here
      // rather than described: a `Timer.run` one-shot, which runs only after
      // the microtask queue has drained, so everything announced in one turn
      // of the event loop lands in one frame. 10-05 chose Timer.run over
      // scheduleMicrotask for this reason and measured the alternative at
      // five hundred frames for a five-hundred-key clear (T-10-19), which
      // `relay_session.dart:416-424` turns into close(4004) — a settings page
      // evicting every panel in the plant and reporting it as backpressure.
      final flushes = <List<String>>[];
      var pending = <String>[];
      var scheduled = false;
      final sub = store.onPreferencesChanged.listen((key) {
        pending.add(key);
        if (scheduled) return;
        scheduled = true;
        Timer.run(() {
          flushes.add(pending);
          pending = <String>[];
          scheduled = false;
        });
      });
      addTearDown(sub.cancel);
      // Let the SEEDING writes' own announcements drain before measuring,
      // and let them fall out of the de-duplication window — otherwise the
      // first flush is the tail of the setString loop above, and the clear's
      // own events for those same keys would be suppressed as duplicates of
      // it. Neither is what this case is about.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      flushes.clear();
      pending = <String>[];

      await store.clear(allowList: keys);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(flushes, hasLength(1),
          reason: 'one frame for the burst. A clear that awaited a round trip '
              'per key would yield to the event loop between them, the flush '
              'timer would fire in each gap, and the coalescing 10-05 built '
              'would be defeated by the caller rather than by the mechanism');
      expect(flushes.single, unorderedEquals(keys));
      for (final key in keys) {
        expect(await rowCount(key), 0,
            reason: 'and the rows still have to be gone');
      }
    });

    test('getAll answers the values that are in the table', () async {
      await store.setString('${ns}all1', 'x');
      await store.setInt('${ns}all2', 42);

      final all = await freshStore().getAll();

      expect(all['${ns}all1'], 'x');
      expect(all['${ns}all2'], 42);
    });
  });

  group('trap 8: the cache has to have been loaded', () {
    test('a freshly constructed store answers the keys that are in the '
        'database', () async {
      final key = '${ns}trap8';
      await writeBehindTheStore(key, 'written by somebody else');

      final keys = await freshStore().getKeys();

      expect(keys, isNotEmpty,
          reason: 'TRAP 8. getKeys and getAll read the in-memory cache '
              '(preferences.dart:267-274), and only Preferences.create fills '
              'it (`:233`, loadFromPostgres). A store that built its '
              'Preferences by hand answers "no keys" to a table holding four '
              'rows and 660 KiB — and the first symptom is a settings page '
              'that looks empty rather than an error anybody would report');
      expect(keys, contains(key));
    });

    test('a value another connection wrote is readable through a fresh store',
        () async {
      final key = '${ns}otherwriter';
      await writeBehindTheStore(key, 'from the HMI station');

      expect(await freshStore().getString(key), 'from the HMI station',
          reason: 'an HMI station writes this table directly today; a store '
              'that could not see those rows would serve the plant a '
              'configuration nobody is editing');
    });
  });

  group('a getter against a stored value of the wrong type', () {
    test('throws the TypeError the interface promises', () async {
      final key = '${ns}mistyped';
      await store.setString(key, 'not a bool');

      await expectLater(store.getBool(key), throwsA(isA<TypeError>()),
          reason: 'PreferencesApi promises a TypeError, the gateway maps it '
              'to -32010 and 10-01 taught the client to read that code. An '
              'implementation that answered null instead would turn a '
              'mistyped read into a silent default');
    });

    test('the refusal is a rejected future, not a synchronous throw',
        () async {
      final key = '${ns}mistyped2';
      await store.setString(key, 'not an int');

      Object? caught;
      // Deliberately NOT inside a try: a method that throws synchronously
      // from a Future-returning signature is invisible to this, which is the
      // bug 10-08 shipped twice.
      await store.getInt(key).catchError((Object e) {
        caught = e;
        return null;
      });

      expect(caught, isA<TypeError>(),
          reason: 'a synchronous throw out of a Future-returning method is '
              'invisible to .catchError and to any caller holding the future '
              'to combine later (10-08 deviation 1, twice)');
    });
  });

  group('the largest real value in the live store', () {
    test('a key_mappings-sized setString round-trips byte for byte', () async {
      final key = '${ns}key_mappings';
      final value = keyMappingsSized();
      final rawBytes = utf8.encode(value).length;
      final encodedBytes = utf8.encode(jsonEncode(value)).length;
      const maxFrameBytes = 1024 * 1024;

      printOnFailure('raw value bytes    = $rawBytes');
      printOnFailure('JSON-encoded bytes = $encodedBytes');
      // ignore: avoid_print
      print('MEASURED key_mappings-sized value: raw=$rawBytes B, '
          'jsonEncode=$encodedBytes B, '
          '${(encodedBytes * 100 / maxFrameBytes).toStringAsFixed(1)}% of '
          'maxFrameBytes ($maxFrameBytes B)');

      await store.setString(key, value);
      final read = await freshStore().getString(key);

      expect(read, isNotNull);
      expect(read!.length, value.length,
          reason: 'a truncated key_mappings is a routing table missing its '
              'tail, which reads as "those tags do not exist"');
      expect(read, value,
          reason: 'byte-for-byte, because a value that survives its length '
              'and loses a character is a JSON document that no longer '
              'parses and a gateway that will not route');

      await store.remove(key);
    });
  });

  group('through the composer, end to end', () {
    test('a second-connection write is heard through '
        'LocalStateMan.preferences', () async {
      final owned = freshStore();
      final man = LocalStateMan(
        links: const <UpstreamLink>[],
        router: KeyRouter.overLinks(const <UpstreamLink>[],
            mappings: KeyMappings(nodes: <String, KeyMappingEntry>{})),
        preferences: owned,
      );
      addTearDown(man.dispose);

      final seen = <String>[];
      // Through the COMPOSER's getter, not through the store variable: the
      // wiring is the subject. If `preferences` answered a bare `Preferences`
      // — or the store's local stream instead of the merged feed — the
      // cross-process half built in task 2 would be unreachable from the wire
      // and the whole task would be decoration.
      final sub = man.preferences.onPreferencesChanged.listen(seen.add);
      addTearDown(sub.cancel);
      final ready = DateTime.now().add(const Duration(seconds: 15));
      while (!owned.feed.channelUp && DateTime.now().isBefore(ready)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(owned.feed.channelUp, isTrue);

      final key = '${ns}endtoend';
      await writeBehindTheStore(key, 'from the HMI station');

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!seen.contains(key) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(seen, contains(key),
          reason: 'this is DB-03 end to end: an edit made by a process this '
              'gateway does not own, reaching the member a session '
              'subscribes to. relay_session.dart:899 attaches to exactly '
              'this stream');
      expect(await man.preferences.getString(key), 'from the HMI station',
          reason: 'and the read that follows the notification has to answer '
              'the new value, or the notification sent every panel to fetch '
              'what it already had');
    });
  });
}

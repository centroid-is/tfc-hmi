import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:drift/drift.dart' show Value;
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'package:tfc/core/server_config_db.dart';
import 'package:tfc/pages/server_config.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/state_man.dart';

import '../helpers/test_helpers.dart';

/// Wraps [ImportExportCard] alone — the store/load-database flows never touch
/// the server sections, and the full [ServerConfigBody] just slows the test.
/// [prefs] is shared with the test body so it can assert what got persisted.
Widget _buildCard({
  Database? database,
  Preferences? prefs,
}) {
  return ProviderScope(
    overrides: [
      preferencesProvider
          .overrideWith((ref) async => prefs ?? await createTestPreferences()),
      databaseProvider.overrideWith((ref) async => database),
      stateManProvider
          .overrideWith((ref) => throw StateError('No StateMan in tests')),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ImportExportCard())),
    ),
  );
}

Future<StoredServerConfig?> _storedRow(AppDatabase db) =>
    ServerConfigDb.fetch(db);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SecureStorage.setInstance(FakeSecureStorage());
    // Production-strength PBKDF2 takes tens of seconds per derivation in the
    // debug-mode test VM; the round-trip logic under test is unchanged.
    SecureEnvelope.kdfIterationsForTest = 10;
  });

  group('StoredServerConfig', () {
    test('serializes and parses metadata and envelope', () {
      final saved = StoredServerConfig(
        savedAt: DateTime(2026, 8, 18, 12, 30),
        savedBy: 'station-1',
        envelope: {'version': 1, 'ciphertext_b64': 'abc'},
      );
      final parsed = StoredServerConfig.fromJson(
          jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>);
      expect(parsed.savedAt, DateTime(2026, 8, 18, 12, 30));
      expect(parsed.savedBy, 'station-1');
      expect(parsed.envelope['ciphertext_b64'], 'abc');
    });

    test('tolerates missing metadata', () {
      final parsed = StoredServerConfig.fromJson({
        'envelope': {'version': 1},
      });
      expect(parsed.savedAt, isNull);
      expect(parsed.savedBy, isNull);
      expect(parsed.envelope['version'], 1);
    });
  });

  group('ServerConfigDb', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemoryForTest();
    });

    tearDown(() async {
      await db.close();
    });

    test('fetch returns null when nothing stored', () async {
      expect(await ServerConfigDb.fetch(db), isNull);
    });

    test('publish/fetch round-trips, publish overwrites', () async {
      await ServerConfigDb.publish(
        db,
        StoredServerConfig(
          savedAt: DateTime(2026, 1, 1),
          savedBy: 'a',
          envelope: {'version': 1, 'ciphertext_b64': 'first'},
        ),
      );
      await ServerConfigDb.publish(
        db,
        StoredServerConfig(
          savedAt: DateTime(2026, 2, 2),
          savedBy: 'b',
          envelope: {'version': 1, 'ciphertext_b64': 'second'},
        ),
      );

      final stored = await ServerConfigDb.fetch(db);
      expect(stored, isNotNull);
      expect(stored!.savedBy, 'b');
      expect(stored.envelope['ciphertext_b64'], 'second');
    });

    test('remove deletes the stored config', () async {
      await ServerConfigDb.publish(
          db, StoredServerConfig(envelope: {'version': 1}));
      await ServerConfigDb.remove(db);
      expect(await ServerConfigDb.fetch(db), isNull);
    });

    test('fetch throws on a corrupt row instead of reporting nothing stored',
        () async {
      await db.into(db.flutterPreferences).insertOnConflictUpdate(
            const FlutterPreferencesCompanion(
              key: Value(ServerConfigDb.prefsKey),
              value: Value('not json at all'),
              type: Value('String'),
            ),
          );
      await expectLater(ServerConfigDb.fetch(db), throwsFormatException);
    });
  });

  group('SecureEnvelope with a user password', () {
    test('decrypts with the right password, rejects the wrong one', () async {
      final envelope = await SecureEnvelope.encrypt(
        jsonConfig: {
          'opcua': [
            {'endpoint': 'opc.tcp://10.0.0.1:4840', 'password': 'plc secret'}
          ],
        },
        compiledPrefix: 'prefix:',
        exportPostfix: 'hunter22',
      );

      // The database only ever sees the envelope — the secret must not
      // appear anywhere in its JSON.
      expect(jsonEncode(envelope), isNot(contains('plc secret')));

      final decrypted = await SecureEnvelope.decrypt(
        envelope: envelope,
        compiledPrefix: 'prefix:',
        postfix: 'hunter22',
      );
      expect(decrypted['opcua'][0]['password'], 'plc secret');

      await expectLater(
        SecureEnvelope.decrypt(
          envelope: envelope,
          compiledPrefix: 'prefix:',
          postfix: 'wrong-password',
        ),
        throwsA(anything),
      );
    });
  });

  group('ImportExportCard database buttons', () {
    testWidgets('renders store and load buttons', (tester) async {
      await pumpAndLoad(tester, _buildCard());
      expect(find.text('Store in Database'), findsOneWidget);
      expect(find.text('Load from Database'), findsOneWidget);
      expect(find.text('Import File'), findsOneWidget);
      expect(find.text('Export File'), findsOneWidget);
    });

    testWidgets('store without a database connection shows an error',
        (tester) async {
      await pumpAndLoad(tester, _buildCard());
      await tester.tap(find.text('Store in Database'));
      await settle(tester);
      expect(find.textContaining('No database connection'), findsOneWidget);
    });

    testWidgets('load with an empty database reports nothing stored',
        (tester) async {
      final appDb = AppDatabase.inMemoryForTest();
      final db = Database(appDb);
      addTearDown(() async => appDb.close());

      await pumpAndLoad(tester, _buildCard(database: db));
      await tester.tap(find.text('Load from Database'));
      await settle(tester);
      expect(find.textContaining('No config stored'), findsOneWidget);

      // Cancel the wrapper's periodic flush timer before the framework's
      // pending-timer check at the end of the test body.
      await db.dispose();
    });

    testWidgets('store flow validates the password dialog and stores a row',
        (tester) async {
      final appDb = AppDatabase.inMemoryForTest();
      final db = Database(appDb);
      addTearDown(() async => appDb.close());

      final prefs = await createTestPreferences(
        stateManConfig: StateManConfig(opcua: [
          OpcUAConfig()
            ..endpoint = 'opc.tcp://10.0.0.1:4840'
            ..serverAlias = 'plc1'
            ..username = 'operator'
            ..password = 'plc secret',
        ]),
      );

      await pumpAndLoad(tester, _buildCard(database: db, prefs: prefs));
      await tester.tap(find.text('Store in Database'));
      await settle(tester);
      expect(find.text('Store config in database'), findsOneWidget);

      // Too short.
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'abc');
      await tester.tap(find.text('Store'));
      await settle(tester);
      expect(
          find.text('Password must be at least 6 characters.'), findsOneWidget);

      // Mismatch.
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'hunter22');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'hunter23');
      await tester.tap(find.text('Store'));
      await settle(tester);
      expect(find.text('Passwords do not match.'), findsOneWidget);

      // Valid.
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'hunter22');
      await tester.tap(find.text('Store'));
      await settle(tester);

      expect(find.text('Store config in database'), findsNothing);
      final stored = await _storedRow(appDb);
      expect(stored, isNotNull);
      expect(stored!.savedBy, isNotNull);
      // Ciphertext only — the PLC credential must not leak into the row.
      expect(jsonEncode(stored.envelope), isNot(contains('plc secret')));

      final decrypted = await SecureEnvelope.decrypt(
        envelope: stored.envelope,
        compiledPrefix: 'Flottur köttur:',
        postfix: 'hunter22',
      );
      expect(decrypted['opcua'][0]['password'], 'plc secret');

      await db.dispose();
    });

    testWidgets(
        'load flow rejects a wrong password, applies config on the right one',
        (tester) async {
      final appDb = AppDatabase.inMemoryForTest();
      final db = Database(appDb);
      addTearDown(() async => appDb.close());

      final envelope = await SecureEnvelope.encrypt(
        jsonConfig: {
          'opcua': [
            {
              'endpoint': 'opc.tcp://10.9.9.9:4840',
              'server_alias': 'imported_plc',
            }
          ],
        },
        compiledPrefix: 'Flottur köttur:',
        exportPostfix: 'hunter22',
      );
      await ServerConfigDb.publish(
        appDb,
        StoredServerConfig(
          savedAt: DateTime(2026, 8, 18),
          savedBy: 'station-2',
          envelope: envelope,
        ),
      );

      final prefs = await createTestPreferences();
      await pumpAndLoad(tester, _buildCard(database: db, prefs: prefs));
      await tester.tap(find.text('Load from Database'));
      await settle(tester);
      expect(find.text('Load config from database'), findsOneWidget);
      expect(find.textContaining('station-2'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'wrong-password');
      await tester.tap(find.text('Decrypt & import'));
      await settle(tester);
      // Wrong password keeps the dialog open for a retry.
      expect(find.text('Incorrect password.'), findsOneWidget);
      expect(find.text('Load config from database'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'hunter22');
      await tester.tap(find.text('Decrypt & import'));
      await settle(tester);

      expect(find.text('Load config from database'), findsNothing);
      expect(
          find.textContaining('Config imported from database'), findsOneWidget);

      // The imported config is now the saved one.
      final saved = await StateManConfig.fromPrefs(prefs);
      expect(saved.opcua.single.serverAlias, 'imported_plc');
      expect(saved.opcua.single.endpoint, 'opc.tcp://10.9.9.9:4840');

      await db.dispose();
    });
  });
}

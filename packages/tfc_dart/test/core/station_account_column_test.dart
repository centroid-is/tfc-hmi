/// Schema v8: `app_user.station_account` — the flag that lets a panel PC
/// live signed in as its area account.
///
/// A boolean on the USER, not the station: the freezer display's account
/// never expires anywhere, while a human signing in on the very same panel
/// keeps the inactivity window. Compare the device-local
/// `access.inactivity_timeout_disabled`, which is the station-wide blunt
/// instrument; this is the per-identity precise one.
///
/// Written RED first, against schema v7.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

Future<List<String>> _userColumns(AppDatabase db) async {
  final rows =
      await db.customSelect("PRAGMA table_info('app_user')").get();
  return rows.map((r) => r.read<String>('name')).toList();
}

void main() {
  test('a fresh install carries station_account, defaulting false', () async {
    final db = AppDatabase.inMemoryForTest();
    addTearDown(() => db.close());
    await db.customSelect('SELECT 1').getSingle();

    expect(await _userColumns(db), contains('station_account'));

    await db.customStatement(
      "INSERT INTO app_user (username, role_name, password_hash, salt, "
      "created_at) VALUES ('jon', 'Engineering', 'x', 'y', '2026-09-02')",
    );
    final row = await db
        .customSelect(
            "SELECT station_account FROM app_user WHERE username = 'jon'")
        .getSingle();
    expect(row.read<bool>('station_account'), isFalse,
        reason: 'every existing account is a person until somebody says '
            'otherwise — the default must not mint immortal sessions');
  });

  test('schema version is 8', () async {
    final db = AppDatabase.inMemoryForTest();
    addTearDown(() => db.close());
    expect(db.schemaVersion, 8);
  });

  group('upgrading a v7 database', () {
    late File dbFile;

    setUp(() async {
      dbFile = File(
          '${Directory.systemTemp.createTempSync('v8-mig').path}/db.sqlite');
    });

    tearDown(() {
      final dir = dbFile.parent;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// A database exactly as v7 left it: the v8 column dropped and the
    /// version pinned back, the same simulation the v5 suite uses.
    Future<void> makeV7Database() async {
      final db = AppDatabase.forTest(
        DatabaseConfig(),
        NativeDatabase(dbFile, logStatements: false),
      );
      await db.customSelect('SELECT 1').getSingle();
      await db.customStatement(
          "INSERT INTO app_user (username, role_name, password_hash, salt, "
          "created_at) VALUES ('omar', 'Engineering', 'x', 'y', '2026-09-01')");
      await db
          .customStatement('ALTER TABLE app_user DROP COLUMN station_account');
      await db.customStatement('PRAGMA user_version = 7');
      await db.close();
    }

    Future<AppDatabase> reopen() async {
      final db = AppDatabase.forTest(
        DatabaseConfig(),
        NativeDatabase(dbFile, logStatements: false),
      );
      await db.customSelect('SELECT 1').getSingle();
      return db;
    }

    test('gains the column with existing accounts defaulting false', () async {
      await makeV7Database();
      final db = await reopen();
      addTearDown(() => db.close());

      expect(await _userColumns(db), contains('station_account'));
      final row = await db
          .customSelect(
              "SELECT station_account FROM app_user WHERE username = 'omar'")
          .getSingle();
      expect(row.read<bool>('station_account'), isFalse,
          reason: 'an account created before v8 is a person');
    });
  });
}

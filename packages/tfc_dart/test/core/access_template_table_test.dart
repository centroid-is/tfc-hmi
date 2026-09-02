// Schema v7 — `access_template`, `access_key_binding` and the migration that
// creates them.
//
// **SQLite only, and that is a coverage statement rather than a scoping one.**
// An in-memory or temp-file `NativeDatabase` is the only backend a test in
// `test/core/` can open, so everything below exercises the `native` arm of the
// `from < 7` branch. What is therefore *not* covered here:
//
// - the Postgres arm's raw `CREATE TABLE IF NOT EXISTS` DDL for both tables —
//   no test in this package executes it, exactly as Phase 1's
//   `deferred-items.md` §1 recorded on 2026-08-28 for the `from < 6` arm,
//   which is still uncovered today;
// - the `CREATE INDEX IF NOT EXISTS` on Postgres, same reason;
// - two stations running the branch against one shared database, which is the
//   deployment the `IF NOT EXISTS` spelling exists for.
//
// `access_key_binding_table_test.dart` holds the source-derived column-parity
// tests that stand in for the missing execution, and says in its own reason
// strings what they do and do not prove.
//
// TODO(phase-4): the live-Postgres migration assertion belongs in
// `test/integration/database_integration_test.dart`, beside the one
// `access_schema_test.dart` has been asking for since Phase 1 — open a v6
// database, upgrade it, and assert `access_template` and `access_key_binding`
// exist with the binding index.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart' show DatabaseConfig;
import 'package:tfc_dart/core/database_drift.dart'
    show AppDatabase, AccessKeyBindingTableCompanion;

/// The set of user table names in [db].
Future<Set<String>> _tableNames(GeneratedDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

/// The set of index names in [db].
Future<Set<String>> _indexNames(GeneratedDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

/// The two tables added by the v6→v7 migration, in one list because one
/// branch creates them: there is no state in which one exists and the other
/// does not.
const _v7Tables = ['access_template', 'access_key_binding'];

/// The `access_key_binding` index. `keysBoundTo` runs on every template delete
/// and on every render of the key repository's bound-key counts.
const _bindingIndex = 'idx_access_key_binding_template_name';

/// A rules JSON blob shaped like the one `AccessTemplate.encodeRules()`
/// produces: struct member -> `AccessGroup` name.
const _conveyorRules =
    '{"p_cmd_JogFwd":"operate","p_cfg_ManualFreq":"setpoints"}';

void main() {
  group('fresh install', () {
    test('creates access_template and access_key_binding', () async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() => db.close());
      await db.customSelect('SELECT 1').getSingle();

      final tables = await _tableNames(db);
      for (final table in _v7Tables) {
        expect(tables, contains(table),
            reason: 'v7 table "$table" should exist on a fresh install');
      }
    });

    test('schema version is 8', () async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() => db.close());
      // Read off an open database rather than grepped out of the source: the
      // value the migrator actually compares `from` against.
      expect(db.schemaVersion, 8);
    });

    test('creates the access_key_binding template_name index', () async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() => db.close());
      await db.customSelect('SELECT 1').getSingle();

      final indexes = await _indexNames(db);
      expect(indexes, contains(_bindingIndex),
          reason: 'without it, every template delete and every bound-key count '
              'is a table scan of access_key_binding');
    });
  });

  group('rows', () {
    test('a template row survives a round trip verbatim', () async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() => db.close());
      await db.customSelect('SELECT 1').getSingle();

      await db.customStatement(
        'INSERT INTO access_template (name, rules, updated_at) '
        "VALUES ('conveyor', '$_conveyorRules', '2026-08-30T09:00:00.000')",
      );

      final rows = await db.customSelect('SELECT * FROM access_template').get();
      expect(rows, hasLength(1));
      expect(rows.first.read<String>('name'), 'conveyor');
      expect(rows.first.read<String>('rules'), _conveyorRules,
          reason: 'the rules column is opaque JSON — the database must not '
              'reinterpret what AccessTemplate.encodeRules wrote');
    });

    test('a binding row survives a round trip verbatim', () async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() => db.close());
      await db.customSelect('SELECT 1').getSingle();

      await db.customStatement(
        'INSERT INTO access_key_binding (key_name, template_name, updated_at) '
        "VALUES ('CN04.MOTOR01', 'conveyor', '2026-08-30T09:00:00.000')",
      );

      final rows =
          await db.customSelect('SELECT * FROM access_key_binding').get();
      expect(rows, hasLength(1));
      expect(rows.first.read<String>('key_name'), 'CN04.MOTOR01');
      expect(rows.first.read<String>('template_name'), 'conveyor');
    });

    test('a second binding for the same key replaces rather than duplicates',
        () async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() => db.close());
      await db.customSelect('SELECT 1').getSingle();

      await db.into(db.accessKeyBindingTable).insertOnConflictUpdate(
            AccessKeyBindingTableCompanion.insert(
              keyName: 'CN04.MOTOR01',
              templateName: 'conveyor',
              updatedAt: DateTime.utc(2026, 8, 30, 9),
            ),
          );
      await db.into(db.accessKeyBindingTable).insertOnConflictUpdate(
            AccessKeyBindingTableCompanion.insert(
              keyName: 'CN04.MOTOR01',
              templateName: 'conveyor-strict',
              updatedAt: DateTime.utc(2026, 8, 30, 10),
            ),
          );

      final rows =
          await db.customSelect('SELECT * FROM access_key_binding').get();
      expect(rows, hasLength(1),
          reason: 'key_name is the primary key, so "explicit, per key, always" '
              'is structural: a key cannot carry two answers');
      expect(rows.first.read<String>('template_name'), 'conveyor-strict');
    });

    test('template_name carries no foreign key to access_template', () async {
      final db = AppDatabase.inMemoryForTest();
      addTearDown(() => db.close());
      await db.customStatement('PRAGMA foreign_keys = ON');
      await db.customSelect('SELECT 1').getSingle();

      // Deliberate: 04-01's resolver treats a binding naming a missing
      // template as *unbound* and 04-08 surfaces it. A database-level
      // constraint would make a template delete fail with a driver error
      // instead of TemplateInUseException's named key list.
      await db.customStatement(
        'INSERT INTO access_key_binding (key_name, template_name, updated_at) '
        "VALUES ('CN04.MOTOR01', 'no-such-template', '2026-08-30T09:00:00.000')",
      );

      final rows =
          await db.customSelect('SELECT * FROM access_key_binding').get();
      expect(rows, hasLength(1),
          reason: 'a dangling binding must be storable — it is how a deleted '
              'template shows up as an unbound key rather than as an error');
    });
  });

  group('v6 -> v7 upgrade', () {
    // A temp *file* database, not an in-memory one: the upgrade has to survive
    // a close and a reopen, and `NativeDatabase.memory()` hands out a new empty
    // database every open. Same reconstruction trick as
    // `access_schema_test.dart` — build the current schema, drop what v7 added
    // and rewind `user_version`, rather than checking in a v6 file that would
    // rot the first time an unrelated table changed.
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tfc_access_template_test');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// Builds a database at v6: the v7 tables and index removed, and
    /// `user_version` rewound so the next open runs `onUpgrade(6, 7)`.
    Future<void> makeV6Database() async {
      final db = AppDatabase.forTest(
        DatabaseConfig(),
        NativeDatabase(dbFile, logStatements: false),
      );
      await db.customSelect('SELECT 1').getSingle();

      // Rows from the v6 world that must survive: an alarm, an audit entry,
      // an app_user, and an app_role edited away from its seeded value.
      await db.customStatement(
        "INSERT INTO alarm (uid, title, description, rules) "
        "VALUES ('pre-v7', 'CN04 jam', 'Belt CN04 jammed', '[]')",
      );
      await db.customStatement(
        "UPDATE app_role SET groups = '[\"operate\",\"setpoints\"]' "
        "WHERE name = 'Operator'",
      );
      await db.customStatement(
        "INSERT INTO app_user (username, role_name, password_hash, salt, created_at) "
        "VALUES ('jon', 'Engineering', 'hash', 'salt', '2026-08-30T08:00:00.000')",
      );
      await db.customStatement(
        "INSERT INTO audit_entry (at, who, station, role_name, surface, "
        "item_key, group_required, allowed, action_id) "
        "VALUES ('2026-08-30T08:00:00.000', 'jon', 'SVN-NES-OT-CL02', "
        "'Engineering', 'auth', 'session.login', 'operate', 1, 'a1')",
      );

      await db.customStatement('DROP INDEX $_bindingIndex');
      await db.customStatement('DROP TABLE access_key_binding');
      await db.customStatement('DROP TABLE access_template');
      await db.customStatement('PRAGMA user_version = 6');
      await db.close();
    }

    /// Reopens the same file, forcing the migration to run.
    Future<AppDatabase> reopen() async {
      final db = AppDatabase.forTest(
        DatabaseConfig(),
        NativeDatabase(dbFile, logStatements: false),
      );
      await db.customSelect('SELECT 1').getSingle();
      return db;
    }

    test('gains both tables', () async {
      await makeV6Database();
      final db = await reopen();
      addTearDown(() => db.close());

      final tables = await _tableNames(db);
      for (final table in _v7Tables) {
        expect(tables, contains(table),
            reason: 'v7 table "$table" should be created by the upgrade');
      }
    });

    test('gains the binding index', () async {
      await makeV6Database();
      final db = await reopen();
      addTearDown(() => db.close());

      expect(await _indexNames(db), contains(_bindingIndex));
    });

    test('both new tables are empty — Phase 4 ships no templates', () async {
      await makeV6Database();
      final db = await reopen();
      addTearDown(() => db.close());

      for (final table in _v7Tables) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        expect(rows, isEmpty,
            reason: '"$table" ships empty; the user creates the templates');
      }
    });

    test('keeps every pre-existing row', () async {
      await makeV6Database();
      final db = await reopen();
      addTearDown(() => db.close());

      final alarms = await db
          .customSelect("SELECT * FROM alarm WHERE uid = 'pre-v7'")
          .get();
      expect(alarms, hasLength(1));
      expect(alarms.first.read<String>('title'), 'CN04 jam');

      final users = await db.customSelect('SELECT * FROM app_user').get();
      expect(users, hasLength(1));
      expect(users.first.read<String>('username'), 'jon');

      final audit = await db.customSelect('SELECT * FROM audit_entry').get();
      expect(audit, hasLength(1),
          reason: 'the trail is append-only and never pruned; a migration is '
              'not an exception');
      expect(audit.first.read<String>('item_key'), 'session.login');
    });

    test('does not re-seed the roles', () async {
      await makeV6Database();
      final db = await reopen();
      addTearDown(() => db.close());

      final roles = await db.customSelect('SELECT * FROM app_role').get();
      expect(roles, hasLength(4));
      final operator =
          roles.firstWhere((r) => r.read<String>('name') == 'Operator');
      expect(operator.read<String>('groups'), '["operate","setpoints"]',
          reason: '_seedAccessRoles() belongs to the from < 6 branch. Calling '
              'it again from from < 7 is how a commissioned role gets reset '
              'back to the seed under an operator who never touched it');
    });

    test('leaves schema version at 7', () async {
      await makeV6Database();
      final db = await reopen();
      addTearDown(() => db.close());

      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.read<int>('user_version'), 8);
    });
  });
}

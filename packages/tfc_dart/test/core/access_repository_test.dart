// AccessRepository — roles, the Operator guard, anonymous group resolution and
// the first-user window.
//
// SQLite only, against a real in-memory `AppDatabase`. The two rules this file
// exists to pin down are the ones that are easy to write down and easy to get
// wrong:
//
//  * the `Operator` row cannot be deleted or renamed, enforced in code rather
//    than documented in a comment somewhere;
//  * a user can be created only while `app_user` is empty, and the check that
//    makes that true lives *inside* the transaction.
//
// `PRAGMA foreign_keys = ON` is issued per database opened here rather than in
// `AppDatabase` itself. The pragma is per-connection and off by default in
// SQLite, so without it the referential test below would pass vacuously.
// Turning it on globally would change the behaviour of every other tfc_dart
// test that writes rows, so it is enabled in this file only.

import 'dart:convert';

// `isNull` / `isNotNull` are matchers here, not drift's SQL expressions of the
// same names.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
import 'package:tfc_dart/core/database_drift.dart' show AppDatabase;

/// Opens an in-memory database with the schema created and foreign keys on.
///
/// The `SELECT 1` is what forces drift to run the migration: opening the
/// database is lazy, so without it the first assertion would race the schema.
Future<AppDatabase> _openDb() async {
  final db = AppDatabase.inMemoryForTest();
  await db.customSelect('SELECT 1').getSingle();
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}

/// The groups of the role named [name], read with raw SQL.
///
/// Deliberately not through [AccessRepository]: a test that asserts on the
/// repository's own read of the row it just wrote can pass while the row is
/// wrong.
Future<Set<AccessGroup>?> _rawGroups(AppDatabase db, String name) async {
  final rows = await db.customSelect(
    'SELECT groups FROM app_role WHERE name = ?',
    variables: [Variable<String>(name)],
  ).get();
  if (rows.isEmpty) return null;
  return AccessRole.decodeGroups(rows.first.read<String>('groups'));
}

Future<Set<String>> _rawRoleNames(AppDatabase db) async {
  final rows = await db.customSelect('SELECT name FROM app_role').get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<int> _rawUserCount(AppDatabase db) async {
  final rows =
      await db.customSelect('SELECT COUNT(*) AS c FROM app_user').get();
  return rows.first.read<int>('c');
}

/// Inserts a user row directly, without going through the first-user window.
///
/// The referential tests need a user that holds a role; they are about
/// `deleteRole` and `renameRole`, not about how the row got there.
Future<void> _rawInsertUser(
  AppDatabase db, {
  required String username,
  required String roleName,
}) =>
    db.customStatement(
      'INSERT INTO app_user '
      '(username, role_name, password_hash, salt, created_at) '
      "VALUES ('$username', '$roleName', 'hash', 'salt', "
      "'2026-08-28T00:00:00Z')",
    );

void main() {
  late AppDatabase db;
  late AccessRepository repo;

  setUp(() async {
    // 10 iterations, not 200000. A real derivation measures ~660 ms in the test
    // VM and the first-user group below performs a dozen of them; without this
    // hook the file becomes unrunnable rather than merely slow.
    Pbkdf2Kdf.iterationsForTest = 10;
    db = await _openDb();
    repo = AccessRepository(db);
  });

  tearDown(() async {
    Pbkdf2Kdf.iterationsForTest = null;
    await db.close();
  });

  group('roles', () {
    test('a fresh database returns the four seed roles, all seeded', () async {
      final roles = await repo.roles();

      expect(roles.map((r) => r.name).toSet(), {
        'Operator',
        'Shift Leader',
        'Maintenance',
        'Engineering',
      });
      expect(roles.every((r) => r.seeded), isTrue,
          reason: 'every row written by the v6 seed carries seeded = true');
    });

    test('role("Maintenance") holds operate, setpoints, device and force',
        () async {
      final role = await repo.role('Maintenance');

      expect(role, isNotNull);
      expect(role!.groups, {
        AccessGroup.operate,
        AccessGroup.setpoints,
        AccessGroup.device,
        AccessGroup.force,
      });
    });

    test('role() on an unknown name returns null', () async {
      expect(await repo.role('Nonexistent'), isNull);
    });
  });

  group('anonymous group resolution', () {
    test('a fresh database resolves anonymous to {operate}', () async {
      expect(await repo.anonymousGroups(), {AccessGroup.operate});
    });

    test('editing the Operator row changes what a logged-out panel may do',
        () async {
      // The deliberate footgun, asserted so it cannot be "fixed" by accident:
      // ticking setpoints on Operator grants it to every panel on the floor
      // with nobody signed in.
      await repo.upsertRole(const AccessRole(
        name: kOperatorRoleName,
        groups: {AccessGroup.operate, AccessGroup.setpoints},
      ));

      expect(await repo.anonymousGroups(),
          {AccessGroup.operate, AccessGroup.setpoints});
    });

    test('an empty Operator row means anonymous can do nothing', () async {
      // Allowed on purpose. Refusing an empty Operator would be a policy
      // decision, and this layer has no standing to make one — a site that
      // wants a panel that does nothing until somebody signs in is entitled
      // to have it.
      await repo
          .upsertRole(const AccessRole(name: kOperatorRoleName, groups: {}));

      expect(await repo.anonymousGroups(), isEmpty);
    });

    test('a missing Operator row falls back to the seeded {operate}', () async {
      // Simulates the row being deleted out from under the app in psql. A
      // logged-out panel that cannot jog because somebody ran a DELETE is a
      // stopped line; the seeded set is the conservative floor.
      await db.customStatement("DELETE FROM app_role WHERE name = 'Operator'");
      expect(await _rawGroups(db, kOperatorRoleName), isNull,
          reason: 'the row really is gone, so the fallback is what answers');

      expect(await repo.anonymousGroups(), {AccessGroup.operate});
    });

    test('a failing query falls back to the seeded {operate}', () async {
      // The other half of the same guarantee: the database being unreachable
      // must not cost a logged-out panel its ability to jog either.
      await db.close();

      expect(await repo.anonymousGroups(), {AccessGroup.operate});

      // Re-open so tearDown's close() has something valid to close.
      db = await _openDb();
    });
  });

  group('the Operator guard', () {
    test('deleteRole("Operator") throws and leaves the row present', () async {
      await expectLater(
        () => repo.deleteRole(kOperatorRoleName),
        throwsA(isA<ProtectedRoleError>()),
      );

      expect(await _rawRoleNames(db), contains(kOperatorRoleName));
    });

    test('deleteRole("operator") throws — the guard is case-insensitive',
        () async {
      await expectLater(
        () => repo.deleteRole('operator'),
        throwsA(isA<ProtectedRoleError>()),
      );

      expect(await _rawRoleNames(db), contains(kOperatorRoleName));
    });

    test('deleteRole(" Operator ") throws — and whitespace-tolerant', () async {
      await expectLater(
        () => repo.deleteRole(' Operator '),
        throwsA(isA<ProtectedRoleError>()),
      );

      expect(await _rawRoleNames(db), contains(kOperatorRoleName));
    });

    test('renameRole away from Operator throws and leaves the name alone',
        () async {
      await expectLater(
        () => repo.renameRole(kOperatorRoleName, 'Ops'),
        throwsA(isA<ProtectedRoleError>()),
      );

      final names = await _rawRoleNames(db);
      expect(names, contains(kOperatorRoleName));
      expect(names, isNot(contains('Ops')));
    });

    test('renameRole onto the Operator name throws too', () async {
      // The mirror image of the guard above: renaming another role *to*
      // Operator while Operator exists is a primary-key collision, and while
      // Operator is missing it would silently reassign the anonymous identity.
      await expectLater(
        () => repo.renameRole('Shift Leader', 'Operator'),
        throwsA(isA<ProtectedRoleError>()),
      );

      expect(await _rawRoleNames(db), contains('Shift Leader'));
    });

    test('Engineering is an ordinary row and deletes', () async {
      await repo.deleteRole('Engineering');

      expect(await _rawRoleNames(db), isNot(contains('Engineering')));
    });

    test('renaming an ordinary role succeeds and the old name is gone',
        () async {
      await repo.renameRole('Shift Leader', 'Team Lead');

      final names = await _rawRoleNames(db);
      expect(names, contains('Team Lead'));
      expect(names, isNot(contains('Shift Leader')));
      expect((await repo.role('Team Lead'))!.groups,
          {AccessGroup.operate, AccessGroup.setpoints});
    });

    test('renaming a role a user holds carries the user with it', () async {
      await _rawInsertUser(db, username: 'jon', roleName: 'Engineering');

      await repo.renameRole('Engineering', 'Controls');

      final rows = await db
          .customSelect("SELECT role_name FROM app_user WHERE username = 'jon'")
          .get();
      expect(rows.first.read<String>('role_name'), 'Controls',
          reason: 'a rename must not orphan the users pointing at the role');
    });

    test('renaming a role that does not exist names the missing role',
        () async {
      await expectLater(
        () => repo.renameRole('Ghost', 'Spectre'),
        throwsA(isA<MissingRoleError>()
            .having((e) => e.toString(), 'message', contains('Ghost'))),
      );
    });

    test('renaming onto a name that already exists is refused', () async {
      await expectLater(
        () => repo.renameRole('Shift Leader', 'Maintenance'),
        throwsA(isA<ArgumentError>()),
      );

      final names = await _rawRoleNames(db);
      expect(names, contains('Shift Leader'));
      expect(await _rawGroups(db, 'Maintenance'), {
        AccessGroup.operate,
        AccessGroup.setpoints,
        AccessGroup.device,
        AccessGroup.force,
      });
    });
  });

  group('upsertRole', () {
    test('a new name inserts', () async {
      await repo.upsertRole(const AccessRole(
        name: 'Line Lead',
        groups: {AccessGroup.operate, AccessGroup.setpoints},
      ));

      expect(await _rawGroups(db, 'Line Lead'),
          {AccessGroup.operate, AccessGroup.setpoints});
    });

    test('an existing name updates the groups in place and keeps seeded',
        () async {
      await repo.upsertRole(const AccessRole(
        name: 'Shift Leader',
        groups: {AccessGroup.operate},
        // Passed as false on purpose: an edit must not clear the flag that
        // says where the row came from.
        seeded: false,
      ));

      final role = await repo.role('Shift Leader');
      expect(role!.groups, {AccessGroup.operate});
      expect(role.seeded, isTrue);
      expect(await _rawRoleNames(db), hasLength(4),
          reason: 'an update, not a second row');
    });

    test('a role created through upsertRole is not marked seeded', () async {
      await repo.upsertRole(const AccessRole(name: 'Line Lead', groups: {}));

      expect((await repo.role('Line Lead'))!.seeded, isFalse);
    });

    test('a blank role name is refused', () async {
      // A row whose primary key is whitespace is unselectable from any screen
      // that trims its input, and there is no legitimate way to reach it.
      await expectLater(
        () => repo.upsertRole(const AccessRole(name: '  ', groups: {})),
        throwsA(isA<ArgumentError>()),
      );

      expect(await _rawRoleNames(db), hasLength(4));
    });

    test('renaming to a blank name is refused', () async {
      await expectLater(
        () => repo.renameRole('Shift Leader', '   '),
        throwsA(isA<ArgumentError>()),
      );

      expect(await _rawRoleNames(db), contains('Shift Leader'));
    });
  });

  group('referential integrity', () {
    test('deleting a role a user still holds fails and the user survives',
        () async {
      await _rawInsertUser(db, username: 'jon', roleName: 'Engineering');

      await expectLater(
        () => repo.deleteRole('Engineering'),
        // Message-matched rather than isA<Exception>(): a typo'd table name
        // would also throw and would pass a bare type check.
        throwsA(isA<Object>().having(
          (e) => e.toString().toUpperCase(),
          'message',
          contains('FOREIGN KEY'),
        )),
      );

      expect(await _rawUserCount(db), 1,
          reason: 'the user must not be orphaned by a refused delete');
      expect(await _rawRoleNames(db), contains('Engineering'));
    });
  });

  group('first user window', () {
    test('isUserTableEmpty is true on a fresh database', () async {
      expect(await repo.isUserTableEmpty, isTrue);
      expect(await repo.userCount(), 0);
    });

    test('isUserTableEmpty is false once a user exists', () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');

      expect(await repo.isUserTableEmpty, isFalse);
      expect(await repo.userCount(), 1);
    });

    test('createFirstUser on an empty table inserts exactly one row', () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');

      expect(await _rawUserCount(db), 1);
      expect((await repo.user('jon'))!.username, 'jon');
    });

    test('the first account is forced to Engineering', () async {
      // There is no role parameter to pass, which is the point: the first
      // account cannot ask to be something narrower or something else.
      await repo.createFirstUser(username: 'jon', password: 'hunter2');

      expect((await repo.user('jon'))!.roleName, 'Engineering');
    });

    test('the stored row holds a hash and a salt, not the password', () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');

      final row = (await repo.user('jon'))!;
      expect(row.passwordHash, isNot(contains('hunter2')));
      expect(row.salt, isNotEmpty);
      expect(row.passwordHash, startsWith('pbkdf2-sha256\$'));
      expect(row.createdAt, isNotNull);
    });

    test('the stored hash verifies against the password it was made from',
        () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');

      final row = (await repo.user('jon'))!;
      final decoded = decodeStoredHash(row.passwordHash, saltB64: row.salt)!;

      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: decoded.hashB64,
          saltB64: decoded.saltB64,
          iterations: decoded.iterations,
        ),
        isTrue,
      );
      expect(
        await PasswordHasher.verify(
          password: 'wrong',
          hashB64: decoded.hashB64,
          saltB64: decoded.saltB64,
          iterations: decoded.iterations,
        ),
        isFalse,
      );
    });

    test('a second createFirstUser throws and inserts nothing', () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');

      await expectLater(
        () => repo.createFirstUser(username: 'eve', password: 'letmein'),
        throwsA(isA<FirstUserWindowClosedError>()),
      );

      expect(await _rawUserCount(db), 1);
      expect(await repo.user('eve'), isNull);
    });

    test('two concurrent createFirstUser calls leave exactly one row',
        () async {
      // Both futures are created before either is awaited — that is what makes
      // this a race rather than two sequential calls. If the emptiness check
      // sat outside the transaction, both would see an empty table and both
      // would insert.
      final a = repo.createFirstUser(username: 'jon', password: 'hunter2');
      final b = repo.createFirstUser(username: 'eve', password: 'letmein');

      final outcomes = await Future.wait<Object?>([
        a.then<Object?>((_) => null, onError: (Object e) => e),
        b.then<Object?>((_) => null, onError: (Object e) => e),
      ]);

      expect(outcomes.whereType<FirstUserWindowClosedError>(), hasLength(1),
          reason: 'exactly one of the two must be refused');
      expect(outcomes.where((o) => o == null), hasLength(1),
          reason: 'exactly one of the two must succeed');
      expect(await _rawUserCount(db), 1);
    });

    test('an empty username throws ArgumentError and inserts nothing',
        () async {
      await expectLater(
        () => repo.createFirstUser(username: '  ', password: 'hunter2'),
        throwsA(isA<ArgumentError>()),
      );

      expect(await _rawUserCount(db), 0);
    });

    test('an empty password throws ArgumentError and inserts nothing',
        () async {
      await expectLater(
        () => repo.createFirstUser(username: 'jon', password: ''),
        throwsA(isA<ArgumentError>()),
      );

      expect(await _rawUserCount(db), 0);
    });

    test('the empty-password error does not quote the password', () async {
      // `ArgumentError.value(password, ...)` would put the credential in the
      // message and from there into whatever logs it.
      try {
        await repo.createFirstUser(username: 'jon', password: '');
        fail('expected an ArgumentError');
      } on ArgumentError catch (e) {
        expect(e.toString(), isNot(contains('hunter2')));
        expect(e.invalidValue, isNull);
      }
    });

    test('a missing Engineering role is named, not reported as a foreign key',
        () async {
      await repo.deleteRole('Engineering');

      await expectLater(
        () => repo.createFirstUser(username: 'jon', password: 'hunter2'),
        throwsA(isA<MissingRoleError>()
            .having((e) => e.toString(), 'message', contains('Engineering'))),
      );

      expect(await _rawUserCount(db), 0);
    });

    test('usernames are case-sensitive, matching the primary key', () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');

      expect(await repo.user('jon'), isNotNull);
      expect(await repo.user('JON'), isNull,
          reason: 'a decision, not an accident: the PK is case-sensitive TEXT');
    });

    test('touchLastLogin writes the timestamp', () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');
      expect((await repo.user('jon'))!.lastLoginAt, isNull);

      final at = DateTime.utc(2026, 8, 28, 9, 30);
      await repo.touchLastLogin('jon', at);

      expect((await repo.user('jon'))!.lastLoginAt!.toUtc(), at);
    });

    test('no password, hash or salt reaches flutter_preferences', () async {
      await repo.createFirstUser(username: 'jon', password: 'hunter2');
      final row = (await repo.user('jon'))!;

      final prefs = await db
          .customSelect('SELECT key, value FROM flutter_preferences')
          .get();
      for (final pref in prefs) {
        final value = pref.read<String?>('value') ?? '';
        for (final secret in ['hunter2', row.passwordHash, row.salt]) {
          expect(value, isNot(contains(secret)),
              reason: 'flutter_preferences is synced between stations and read '
                  'by the backend config watcher; credentials live in app_user '
                  'and nowhere else (key "${pref.read<String>('key')}")');
        }
      }
    });
  });

  group('stored hash encoding', () {
    test('round-trips through encodeStoredHash / decodeStoredHash', () async {
      final hash = await PasswordHasher.hash('hunter2');

      final decoded =
          decodeStoredHash(encodeStoredHash(hash), saltB64: hash.saltB64);

      expect(decoded, hash);
      expect(decoded!.iterations, 10, reason: 'the test hook value travels');
    });

    test('the encoded form carries the iteration count it was made with',
        () async {
      final hash = await PasswordHasher.hash('hunter2');
      final stored = encodeStoredHash(hash);

      expect(stored, 'pbkdf2-sha256\$10\$${hash.hashB64}');

      // Raising the ambient default must not change how an existing row reads.
      // That is the whole reason the count is stored rather than assumed.
      Pbkdf2Kdf.iterationsForTest = 99;
      expect(decodeStoredHash(stored, saltB64: hash.saltB64)!.iterations, 10);
      Pbkdf2Kdf.iterationsForTest = 10;
    });

    test('a legacy bare-base64 value decodes at the default count', () {
      final legacy = base64Encode(List<int>.filled(32, 7));

      final decoded = decodeStoredHash(legacy, saltB64: 'c2FsdA==');

      expect(decoded, isNotNull);
      expect(decoded!.hashB64, legacy);
      expect(decoded.iterations, Pbkdf2Kdf.iterations);
    });

    test('a mangled value decodes to null rather than throwing', () {
      expect(decodeStoredHash(r'scrypt$1$abc', saltB64: 'c2FsdA=='), isNull);
      expect(
        decodeStoredHash(r'pbkdf2-sha256$notanumber$abc', saltB64: 'c2FsdA=='),
        isNull,
      );
    });
  });
}

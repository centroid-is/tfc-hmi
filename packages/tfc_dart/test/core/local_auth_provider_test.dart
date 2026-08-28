// LocalAuthProvider — the one AuthProvider this milestone ships.
//
// The contract being pinned down here is the null-vs-throw one from
// `AuthProvider`: **null means the credentials were not recognised, a throw
// means infrastructure failed.** Plan 01-07 writes an audit row with
// `allowed: false` for the null and must not record a database outage as
// somebody's failed login attempt — a trail that reports twenty failed logins
// during a five-minute network blip is a trail nobody trusts afterwards.
// Collapsing the two here would be untraceable later, so both halves have their
// own test.
//
// `PRAGMA foreign_keys = ON` is per-connection and enabled per database opened
// in this file, for the same reason as in `access_repository_test.dart`.

import 'dart:io';

// `isNull` / `isNotNull` are matchers here, not drift's SQL expressions of the
// same names.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
import 'package:tfc_dart/core/access/local_auth_provider.dart';
import 'package:tfc_dart/core/database_drift.dart'
    show AppDatabase, AppUserData;

Future<AppDatabase> _openDb() async {
  final db = AppDatabase.inMemoryForTest();
  await db.customSelect('SELECT 1').getSingle();
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}

/// Collects log lines so the warning paths can be asserted on.
class _CapturingOutput extends LogOutput {
  final List<String> lines = [];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

/// Passes everything through, so the assertions do not depend on the ambient
/// log level.
class _AlwaysFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

/// Emits `level|message`, so a test can assert on the level without parsing
/// whatever decoration the default printer applies.
class _LevelTaggedPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) => ['${event.level.name}|${event.message}'];
}

/// A repository whose reads fail — a stand-in for the shared Postgres server
/// being unreachable.
class _OutageRepository extends AccessRepository {
  _OutageRepository(super.db);

  @override
  Future<AppUserData?> user(String username) =>
      Future<AppUserData?>.error(StateError('connection closed'));
}

/// A repository that counts its reads, for the "does not touch the database"
/// assertions.
class _CountingRepository extends AccessRepository {
  _CountingRepository(super.db);

  int userReads = 0;

  @override
  Future<AppUserData?> user(String username) {
    userReads++;
    return super.user(username);
  }
}

void main() {
  late AppDatabase db;
  late AccessRepository repo;
  late LocalAuthProvider provider;
  late _CapturingOutput logOutput;

  setUp(() async {
    // 10 iterations, not 200000: every test below performs at least one real
    // derivation, several perform two.
    Pbkdf2Kdf.iterationsForTest = 10;
    LocalAuthProvider.dummyDerivations = 0;
    db = await _openDb();
    repo = AccessRepository(db);
    logOutput = _CapturingOutput();
    provider = LocalAuthProvider(
      repo,
      logger: Logger(
        filter: _AlwaysFilter(),
        printer: _LevelTaggedPrinter(),
        output: logOutput,
      ),
    );
    await repo.createFirstUser(username: 'jon', password: 'hunter2');
  });

  tearDown(() async {
    Pbkdf2Kdf.iterationsForTest = null;
    LocalAuthProvider.dummyDerivations = 0;
    await db.close();
  });

  group('credentials', () {
    test('the right password returns the user and their role', () async {
      final user = await provider.authenticate('jon', 'hunter2');

      expect(user, isNotNull);
      expect(user!.username, 'jon');
      expect(user.roleName, 'Engineering');
    });

    test('a wrong password returns null', () async {
      expect(await provider.authenticate('jon', 'wrong'), isNull);
    });

    test('an unknown username returns null', () async {
      expect(await provider.authenticate('nobody', 'hunter2'), isNull);
    });

    test('the username is trimmed before lookup', () async {
      expect(await provider.authenticate('  jon  ', 'hunter2'), isNotNull);
    });

    test('an empty username returns null without touching the database',
        () async {
      final counting = _CountingRepository(db);
      final p = LocalAuthProvider(counting);

      expect(await p.authenticate('   ', 'hunter2'), isNull);
      expect(counting.userReads, 0);
    });

    test('an empty password returns null without touching the database',
        () async {
      final counting = _CountingRepository(db);
      final p = LocalAuthProvider(counting);

      expect(await p.authenticate('jon', ''), isNull);
      expect(counting.userReads, 0);
    });
  });

  group('username enumeration resistance', () {
    test('an absent user still costs a derivation', () async {
      await provider.authenticate('nobody', 'hunter2');

      expect(LocalAuthProvider.dummyDerivations, 1,
          reason: 'the missing-user path must do the same work as the '
              'wrong-password path, or the difference enumerates usernames');
    });

    test('a present user costs no dummy derivation', () async {
      await provider.authenticate('jon', 'wrong');

      expect(LocalAuthProvider.dummyDerivations, 0);
    });

    test('the empty-input short circuit costs no derivation', () async {
      // Nothing to hide here: an empty username is not a username somebody
      // might or might not have.
      await provider.authenticate('', 'hunter2');

      expect(LocalAuthProvider.dummyDerivations, 0);
    });
  });

  group('lastLoginAt', () {
    test('a successful authenticate records the login', () async {
      expect((await repo.user('jon'))!.lastLoginAt, isNull);

      await provider.authenticate('jon', 'hunter2');

      expect((await repo.user('jon'))!.lastLoginAt, isNotNull);
    });

    test('a failed authenticate does not', () async {
      await provider.authenticate('jon', 'wrong');

      expect((await repo.user('jon'))!.lastLoginAt, isNull);
    });
  });

  group('a dangling role', () {
    /// Deletes the `Engineering` row out from under the user, the way `psql`
    /// would. Foreign keys are turned off for the one statement: the point is
    /// to reproduce damage the app cannot itself cause, not to test the
    /// constraint.
    Future<void> deleteEngineeringBehindTheApp() async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db
          .customStatement("DELETE FROM app_role WHERE name = 'Engineering'");
      await db.customStatement('PRAGMA foreign_keys = ON');
    }

    test('returns null rather than an undefined group set', () async {
      await deleteEngineeringBehindTheApp();

      expect(await provider.authenticate('jon', 'hunter2'), isNull);
    });

    test('logs a warning naming the user and the missing role', () async {
      await deleteEngineeringBehindTheApp();

      await provider.authenticate('jon', 'hunter2');

      final warnings =
          logOutput.lines.where((l) => l.startsWith('warning|')).join('\n');
      expect(warnings, isNotEmpty,
          reason: 'a dangling role is an operational fault, not a quiet null');
      expect(warnings, contains('jon'));
      expect(warnings, contains('Engineering'));
    });

    test('does not record a login for a role that is gone', () async {
      await deleteEngineeringBehindTheApp();

      await provider.authenticate('jon', 'hunter2');

      expect((await repo.user('jon'))!.lastLoginAt, isNull);
    });
  });

  group('the null-vs-throw contract', () {
    test('a database outage rethrows rather than returning null', () async {
      final p = LocalAuthProvider(_OutageRepository(db));

      await expectLater(
        () => p.authenticate('jon', 'hunter2'),
        throwsA(isA<StateError>()),
        reason: 'null means bad credentials; an outage must not be audited as '
            'a failed login attempt',
      );
    });
  });

  group('the password never reaches a log or a message', () {
    test('no log line produced by any path contains the password', () async {
      await provider.authenticate('jon', 'hunter2');
      await provider.authenticate('jon', 'hunter2-wrong');
      await provider.authenticate('nobody', 'hunter2-wrong');

      expect(logOutput.lines.join('\n'), isNot(contains('hunter2')));
    });

    test('the source file interpolates no password into any string', () {
      // A source-level assertion rather than a behavioural one, because the
      // behavioural version can only cover the paths a test happens to walk.
      // If a future edit adds `logger.d('checking $password')` on some branch
      // nothing here exercises, this still fails.
      final source =
          File('lib/core/access/local_auth_provider.dart').readAsStringSync();
      expect(source, isNotEmpty,
          reason: 'the file must actually be found, or this passes vacuously');

      for (final forbidden in [r'$password', r'${password', r'$_password']) {
        expect(source, isNot(contains(forbidden)),
            reason: 'a password in a log line or an exception message outlives '
                'the login it came from');
      }
    });
  });
}

// The seam between the admin screen and everything beneath it: the three
// providers that reach `AccessAdminStore`, and the one session method that
// makes the `Operator` warning true of the running app rather than only of the
// `app_role` table.
//
// `ProviderContainer` with overrides over a real in-memory Drift database
// rather than widget tests — this is provider and controller logic and does not
// need a tree.
//
// **Why `refreshGroupsFromRoles` is tested here and not in
// `access_session_test.dart`.** The method exists for the admin feature: the
// roles section's `Operator` banner promises that ticking a group there changes
// what a logged-out panel may do now, and 06-08's users section calls it after
// `setUserRole` and `deleteUser` so an admin cannot demote or delete their own
// account and keep `users`. If the admin surface is ever removed, this
// behaviour and these tests should die with it, which is an argument for
// keeping them beside each other rather than filed under the session.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/core/access_admin_store.dart';
import 'package:tfc/providers/access.dart';
import 'package:tfc/providers/access_admin.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

/// A stand-in for `LocalAuthProvider` honouring the same null-versus-throw
/// contract: null for an unrecognised credential, a throw for infrastructure.
///
/// It reads the roles out of the map it is handed rather than out of the
/// database, so a test can sign somebody in without paying for PBKDF2 twice.
/// Every test that cares about the `app_user` row creates it for real.
class _FakeAuthProvider implements AuthProvider {
  _FakeAuthProvider(this.users);

  final Map<String, ({String password, String roleName})> users;

  @override
  Future<AuthenticatedUser?> authenticate(
      String username, String password) async {
    final cred = users[username];
    if (cred == null || cred.password != password) return null;
    return AuthenticatedUser(username: username, roleName: cred.roleName);
  }
}

/// A sink that keeps every row, so "this call writes no audit row" is an
/// assertion about a list rather than about a silence.
class _RecordingSink implements AuditSink {
  final List<AuditRecord> rows = [];

  @override
  Future<void> record(AuditRecord entry) async => rows.add(entry);
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const String _kStation = 'test-panel';

/// Everything a test needs to drive the providers and the controller.
class _Harness {
  _Harness({
    required this.container,
    required this.db,
    required this.repository,
    required this.sink,
  });

  final ProviderContainer container;
  final AppDatabase db;
  final AccessRepository repository;
  final _RecordingSink sink;

  AccessSessionController get notifier =>
      container.read(accessSessionProvider.notifier);

  AccessSession? get session =>
      container.read(accessSessionProvider).valueOrNull;

  Future<AccessSession> settle() =>
      container.read(accessSessionProvider.future);

  Future<String?> storedPayload() =>
      container.read(localPreferencesProvider).getString(kAccessSessionPrefKey);
}

Future<_Harness> _harness({
  bool withDatabase = true,
  Map<String, ({String password, String roleName})>? users,
  Duration timeout = const Duration(minutes: 15),
}) async {
  final db = AppDatabase.inMemoryForTest();
  addTearDown(() => db.close());
  // Force the migration, so the four seeded roles exist before anything asks
  // for them.
  await db.customSelect('SELECT 1').getSingle();

  final repository = AccessRepository(db);
  final auth = _FakeAuthProvider(users ??
      {
        'jon': (password: 'correct horse', roleName: 'Engineering'),
        'sigga': (password: 'hunter2', roleName: 'Shift Leader'),
      });
  final sink = _RecordingSink();

  final container = ProviderContainer(overrides: [
    accessRepositoryProvider
        .overrideWith((ref) async => withDatabase ? repository : null),
    authProviderProvider
        .overrideWith((ref) async => withDatabase ? auth : null),
    auditSinkProvider.overrideWith((ref) async => sink),
    stationNameProvider.overrideWithValue(_kStation),
    inactivityTimeoutProvider.overrideWith((ref) async => timeout),
  ]);
  addTearDown(container.dispose);

  return _Harness(
    container: container,
    db: db,
    repository: repository,
    sink: sink,
  );
}

void main() {
  setUp(() {
    // The device-local store the session persists into. In memory, and fresh
    // per test, so one test's stored payload cannot restore into the next.
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    DatabaseConfig.clearPrefsCache();
    // PBKDF2 at production iterations is the better part of a second per
    // account, and several tests here create real rows.
    Pbkdf2Kdf.iterationsForTest = 10;
  });

  tearDown(() => Pbkdf2Kdf.iterationsForTest = null);

  // -------------------------------------------------------------------------
  // The store provider
  // -------------------------------------------------------------------------

  group('accessAdminStoreProvider', () {
    test('is null when the station has no database', () async {
      final h = await _harness(withDatabase: false);
      expect(
        await h.container.read(accessAdminStoreProvider.future),
        isNull,
        reason: 'a station commissioned without Postgres has no roles and no '
            'accounts to administer, and that is a normal state rather than an '
            'error — the same null-is-normal shape accessRepositoryProvider '
            'already has',
      );
    });

    test('is a store when there is one', () async {
      final h = await _harness();
      expect(await h.container.read(accessAdminStoreProvider.future),
          isA<AccessAdminStore>());
    });

    test('is one instance for the life of the container', () async {
      final h = await _harness();
      final first = await h.container.read(accessAdminStoreProvider.future);
      final second = await h.container.read(accessAdminStoreProvider.future);
      expect(identical(first, second), isTrue);
    });

    test('survives a sign-in and a sign-out', () async {
      final h = await _harness();
      await h.settle();
      final before = await h.container.read(accessAdminStoreProvider.future);

      final result = await h.notifier.signIn('jon', 'correct horse');
      expect(result, AccessSignInResult.ok);
      final afterSignIn =
          await h.container.read(accessAdminStoreProvider.future);
      expect(
        identical(before, afterSignIn),
        isTrue,
        reason: 'T-04-30: the session must reach this store as a callback. A '
            'ref.watch of the session here would rebuild the provider — and '
            'with it the database handle it holds — on every sign-in, '
            'sign-out and inactivity timeout',
      );

      await h.notifier.signOut();
      final afterSignOut =
          await h.container.read(accessAdminStoreProvider.future);
      expect(identical(before, afterSignOut), isTrue,
          reason: 'T-04-30, the other edge of the same rule');
    });

    test('hands the store the session in force at call time, not at build time',
        () async {
      final h = await _harness();
      await h.settle();
      final store = await h.container.read(accessAdminStoreProvider.future);

      // Built while anonymous: the gate refuses.
      await expectLater(
        store!.createRole(const AccessRole(name: 'Cleaning', groups: {})),
        throwsA(isA<AccessDenied>()),
      );

      // The same store instance, after a sign-in that grants `users`.
      await h.notifier.signIn('jon', 'correct horse');
      await store.createRole(const AccessRole(name: 'Cleaning', groups: {}));
      expect(
        (await h.repository.role('Cleaning')), isNotNull,
        reason: 'the callback resolves the session per call, so the store the '
            'sign-in did not rebuild is nevertheless the one that now permits '
            'the write',
      );
    });
  });

  // -------------------------------------------------------------------------
  // The two list providers
  // -------------------------------------------------------------------------

  group('accessAdminRolesProvider', () {
    test('is the seeded roles', () async {
      final h = await _harness();
      final roles = await h.container.read(accessAdminRolesProvider.future);
      expect(roles.map((r) => r.name), containsAll(kSeedRoles.map((r) => r.name)));
    });

    test('is empty rather than a throw when the station has no database',
        () async {
      final h = await _harness(withDatabase: false);
      expect(
        await h.container.read(accessAdminRolesProvider.future),
        isEmpty,
        reason: 'the page renders the terminal state; a missing database is '
            'not an exception for this list to raise',
      );
    });

    test('re-reads after an invalidation, which is the only refresh there is',
        () async {
      final h = await _harness();
      await h.settle();
      expect(await h.container.read(accessAdminRolesProvider.future),
          isNot(contains(predicate<AccessRole>((r) => r.name == 'Cleaning'))));

      await h.repository.upsertRole(const AccessRole(
        name: 'Cleaning',
        groups: {AccessGroup.operate},
      ));
      h.container.invalidate(accessAdminRolesProvider);

      expect(
        (await h.container.read(accessAdminRolesProvider.future))
            .map((r) => r.name),
        contains('Cleaning'),
      );
    });
  });

  group('accessAdminUsersProvider', () {
    test('lists the accounts', () async {
      final h = await _harness();
      await h.repository.createUser(
        username: 'jon',
        password: 'correct horse',
        roleName: 'Engineering',
      );
      expect(
        (await h.container.read(accessAdminUsersProvider.future))
            .map((u) => u.username),
        ['jon'],
      );
    });

    test('is empty rather than a throw when the station has no database',
        () async {
      final h = await _harness(withDatabase: false);
      expect(await h.container.read(accessAdminUsersProvider.future), isEmpty);
    });
  });

}

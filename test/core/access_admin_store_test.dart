// The one gate over `app_role` and `app_user`.
//
// The write-path sweep §3.3 records `AccessRepository` writing both tables
// through raw Drift as the one write path deliberately left open, with "Phase 6
// gates it on `users`" as the closing condition. `AccessAdminStore` is that
// closure, and this file is what makes the claim checkable.
//
// The `configure`-only session is the important fixture here. It is the
// engineer who may edit pages and key mappings and who must **not** be able to
// grant themselves `users` and from there everything — and it is exactly the
// case `docs/access-control-deployment.md` §4 gets wrong when it calls user
// management an `administer` screen. Driving that session into every write is
// the difference between a gate that is checked and a gate that is remembered.
//
// Every "it did not happen" assertion reads the tables back through the
// repository rather than counting calls on a mock: the claim is that no
// statement was issued, and only the database can answer that. Where a claim is
// about *which repository method the store reached for*, a subclass of the real
// repository logs the call — the doctrine `_RecordingStore` and `_RacingStore`
// establish in `test/pages/access_templates_section_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/access_admin_store.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
import 'package:tfc_dart/core/database_drift.dart';

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

class _RecordingSink implements AuditSink {
  final List<AuditRecord> rows = [];

  @override
  Future<void> record(AuditRecord entry) async => rows.add(entry);
}

/// A sink that fails every write, for the "the trail is not the write path"
/// tests.
class _ThrowingSink implements AuditSink {
  int calls = 0;

  @override
  Future<void> record(AuditRecord entry) async {
    calls++;
    throw StateError('the audit database blinked');
  }
}

/// The real repository, with a log of which methods the store reached for.
///
/// Subclassed rather than faked, for the reason `_RecordingStore` gives: the
/// claims about *what happened* are read back from the tables, and only the
/// claim about which method was called needs a log. A hand-written fake would
/// let "the repository is not called on a denial" pass while the store quietly
/// asked the database something else.
class _RecordingRepository extends AccessRepository {
  _RecordingRepository(super.db);

  final List<String> calls = [];

  @override
  Future<void> upsertRole(AccessRole role) {
    calls.add('upsertRole:${role.name}');
    return super.upsertRole(role);
  }

  @override
  Future<void> deleteRole(String name) {
    calls.add('deleteRole:$name');
    return super.deleteRole(name);
  }

  @override
  Future<void> renameRole(String from, String to) {
    calls.add('renameRole:$from->$to');
    return super.renameRole(from, to);
  }

  @override
  Future<void> createUser({
    required String username,
    required String password,
    required String roleName,
  }) {
    calls.add('createUser:$username');
    return super.createUser(
        username: username, password: password, roleName: roleName);
  }

  @override
  Future<void> deleteUser(String username) {
    calls.add('deleteUser:$username');
    return super.deleteUser(username);
  }

  @override
  Future<void> setRole(String username, String roleName) {
    calls.add('setRole:$username->$roleName');
    return super.setRole(username, roleName);
  }

  @override
  Future<void> setPassword(String username, String password) {
    calls.add('setPassword:$username');
    return super.setPassword(username, password);
  }
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// Nobody signed in. Anonymous is Operator by construction (Phase 1).
AccessSession _anonymous() =>
    AccessSession.anonymous(const {AccessGroup.operate});

/// The engineer who can edit pages and key mappings — and must not be able to
/// decide who may do what.
///
/// This is the session the `users` gate exists for. `configure` is the highest
/// group a page editor needs, and every one of the eight writes in this store
/// must refuse it. It is also the session
/// `docs/access-control-deployment.md` §4 describes wrongly: it calls the
/// screen that creates users an `administer` screen, and this fixture holds
/// neither `administer` nor `users`, so the two spellings cannot be confused
/// by accident here.
AccessSession _configureOnly() => const AccessSession(
      user: AuthenticatedUser(username: 'engineer', roleName: 'Engineering'),
      groups: {
        AccessGroup.operate,
        AccessGroup.setpoints,
        AccessGroup.device,
        AccessGroup.configure,
      },
    );

/// The administrator who holds `users`.
AccessSession _withUsers() => const AccessSession(
      user: AuthenticatedUser(username: 'admin', roleName: 'Administrator'),
      groups: {AccessGroup.operate, AccessGroup.configure, AccessGroup.users},
    );

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

AccessRole _shiftLead() => const AccessRole(
      name: 'Line Lead',
      groups: {AccessGroup.operate, AccessGroup.setpoints},
    );

void main() {
  late AppDatabase db;
  late _RecordingRepository repository;
  late _RecordingSink sink;
  late List<AccessDenied> denials;
  late AccessSession session;

  AccessAdminStore buildStore({AuditSink? audit}) => AccessAdminStore(
        repository: repository,
        session: () => session,
        audit: audit ?? sink,
        station: 'SVN-NES-OT-CL02',
        onDenied: denials.add,
      );

  Future<int> roleRowCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM app_role')
        .getSingle();
    return row.read<int>('c');
  }

  setUp(() async {
    // PBKDF2 at production iteration counts costs the better part of a second
    // per account; these tests create several.
    Pbkdf2Kdf.iterationsForTest = 10;
    db = AppDatabase.inMemoryForTest();
    // Force the schema — and with it the four seeded roles — to exist before
    // the first store call, so a row count read back on the deny path is
    // reading a real table rather than failing to find one.
    await db.customSelect('SELECT 1').getSingle();
    repository = _RecordingRepository(db);
    sink = _RecordingSink();
    denials = [];
    session = _withUsers();
  });

  tearDown(() async {
    Pbkdf2Kdf.iterationsForTest = null;
    await db.close();
  });

  // -------------------------------------------------------------------------
  // The constant
  // -------------------------------------------------------------------------

  group('kAccessAdminGroup', () {
    test('is users, and is the only group this store names', () {
      expect(
        kAccessAdminGroup,
        AccessGroup.users,
        reason: 'spec §1 gates role and user management on `users`. '
            "docs/access-control-deployment.md §4 says \"screens behind the "
            '`administer` group, including the screen that creates users\", '
            'which is a factual error in the doc — plan 06-05 fixes the '
            'sentence and this assertion is what the code says instead. '
            'Lowering this line to `configure` would let anybody who can edit '
            'a page grant themselves `users`, and from there everything, '
            'which is the exact confusion the group split exists to prevent.',
      );
    });

    test('every row this store writes names it as the group required',
        () async {
      final store = buildStore();
      await store.createRole(_shiftLead());
      expect(sink.rows.single.groupRequired, AccessGroup.users.name);
    });
  });

  // -------------------------------------------------------------------------
  // The file itself
  // -------------------------------------------------------------------------

  group('the store owns no queries', () {
    test('imports no Drift', () {
      final source = File('lib/core/access_admin_store.dart').readAsStringSync();
      expect(
        source.contains('package:drift'),
        isFalse,
        reason: 'the transaction and every invariant that must run inside it '
            'live in AccessRepository. A method here that needs a Value() or '
            'a Companion belongs one layer down.',
      );
    });

    test('builds no bare AuditRecord', () {
      final source = File('lib/core/access_admin_store.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        RegExp(r'AuditRecord\(').hasMatch(source),
        isFalse,
        reason: 'the eight named constructors fix the itemKey vocabulary in '
            'one place; a ninth row shape invented here is the vocabulary '
            'drifting on day one.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  group('reads', () {
    test('roles returns the seeded rows and records nothing, anonymous',
        () async {
      session = _anonymous();
      final store = buildStore();

      final roles = await store.roles();

      expect(roles.map((r) => r.name), containsAll(kSeedRoles.map((r) => r.name)));
      expect(sink.rows, isEmpty,
          reason: 'a row per render would bury the writes that matter, and '
              'the route gate is the enforcement for reads.');
      expect(denials, isEmpty);
    });

    test('listUsers returns the accounts and records nothing, anonymous',
        () async {
      await repository.createUser(
          username: 'jon', password: 'hunter2!', roleName: 'Engineering');
      session = _anonymous();
      final store = buildStore();

      final users = await store.listUsers();

      expect(users.map((u) => u.username), ['jon']);
      expect(sink.rows, isEmpty);
      expect(denials, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // The gate, through the first write
  // -------------------------------------------------------------------------

  group('the gate', () {
    test('a users holder is let through and one allowed row is recorded',
        () async {
      final store = buildStore();

      await store.createRole(_shiftLead(), reason: 'new line');

      final row = sink.rows.single;
      expect(row.allowed, isTrue);
      expect(row.surface, 'admin');
      expect(row.itemKey, 'role.create');
      expect(row.member, 'Line Lead');
      expect(row.who, 'admin');
      expect(row.station, 'SVN-NES-OT-CL02');
      expect(row.roleName, 'Administrator');
      expect(row.reason, 'new line');
      expect(row.origin, 'operator');
      expect(row.newValue, _shiftLead().encodeGroups());
      expect(await repository.role('Line Lead'), isNotNull);
    });

    test('a configure-only session is refused, and nothing is written',
        () async {
      session = _configureOnly();
      final store = buildStore();
      final before = await roleRowCount();

      await expectLater(
        () => store.createRole(_shiftLead()),
        throwsA(isA<AccessDenied>()
            .having((d) => d.itemKey, 'itemKey', 'role.create')
            .having((d) => d.required, 'required', AccessGroup.users)),
      );

      expect(await roleRowCount(), before);
      expect(repository.calls, isEmpty,
          reason: 'the gate runs before the repository is reached at all.');
    });

    test('the deny row is recorded before the throw', () async {
      session = _configureOnly();
      final store = buildStore();

      await expectLater(
          () => store.createRole(_shiftLead()), throwsA(isA<AccessDenied>()));

      final row = sink.rows.single;
      expect(row.allowed, isFalse);
      expect(row.itemKey, 'role.create');
      expect(row.member, 'Line Lead');
      expect(row.who, 'engineer');
      expect(row.roleName, 'Engineering');
      expect(row.groupRequired, AccessGroup.users.name);
    });

    test('the deny row exists by the time onDenied fires', () async {
      session = _configureOnly();
      var rowsWhenNotified = -1;
      final store = AccessAdminStore(
        repository: repository,
        session: () => session,
        audit: sink,
        station: 'SVN-NES-OT-CL02',
        onDenied: (_) => rowsWhenNotified = sink.rows.length,
      );

      await expectLater(
          () => store.createRole(_shiftLead()), throwsA(isA<AccessDenied>()));

      expect(rowsWhenNotified, 1,
          reason: 'a deny row is the only evidence the guard fired, so it is '
              'recorded before anything else can swallow the refusal.');
    });

    test('an onDenied listener that throws does not change what the caller sees',
        () async {
      session = _configureOnly();
      final store = AccessAdminStore(
        repository: repository,
        session: () => session,
        audit: sink,
        station: 'SVN-NES-OT-CL02',
        onDenied: (_) => throw StateError('the prompt blew up'),
      );

      await expectLater(
          () => store.createRole(_shiftLead()), throwsA(isA<AccessDenied>()));
      expect(sink.rows.single.allowed, isFalse);
    });

    test('the session is read at the moment of the call, not at construction',
        () async {
      session = _withUsers();
      final store = buildStore();
      // The inactivity monitor drops the operator back to anonymous while the
      // page is still open. A captured session would keep granting `users`.
      session = _anonymous();

      await expectLater(
          () => store.createRole(_shiftLead()), throwsA(isA<AccessDenied>()));
      expect(sink.rows.single.who, 'anonymous');
      expect(sink.rows.single.roleName, kOperatorRoleName);
    });
  });

  // -------------------------------------------------------------------------
  // The sink is not the write path
  // -------------------------------------------------------------------------

  group('a failing audit sink', () {
    test('AUDIT ROW LOST: the permitted write still succeeds', () async {
      final throwing = _ThrowingSink();
      final store = buildStore(audit: throwing);

      await store.createRole(_shiftLead());

      expect(throwing.calls, 1);
      expect(await repository.role('Line Lead'), isNotNull,
          reason: 'a lost row is a log line, never a failed write.');
    });

    test('AUDIT ROW LOST: the refusal is still an AccessDenied', () async {
      session = _configureOnly();
      final throwing = _ThrowingSink();
      final store = buildStore(audit: throwing);

      await expectLater(
          () => store.createRole(_shiftLead()), throwsA(isA<AccessDenied>()));

      expect(throwing.calls, 1);
      expect(denials, hasLength(1),
          reason: 'a sink failure must not skip onDenied and leave the '
              'operator with a control that did nothing and no explanation.');
    });
  });
}

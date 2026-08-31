/// The administration page's roles section (spec §1, 06-CONTEXT "Roles
/// Screen").
///
/// 06-03's store already drives every write through a `configure`-only session
/// and reads the rows back from the tables, so the claims here are the ones
/// only a rendered screen can make:
///
///  * the four terminal states cannot render as each other — "still loading",
///    "the store errored", "this station has no database" and "the list came
///    back empty" are four different sentences and only one of them is ever
///    true,
///  * the `Operator` row carries neither a Rename nor a Delete affordance, and
///    the predicate deciding that is `isProtectedRoleName` rather than a string
///    comparison, so a row stored as `operator` is protected too,
///  * a session without `users` sees every control, may press every one of
///    them, and reaches the shared `AccessDeniedPrompt` — nothing is greyed,
///  * a duplicate name is refused inside the dialog, before the store is asked,
///    because a typo is not an authorization event.
///
/// The store is real, over a real in-memory database, so "the role was created"
/// is read back from `app_role` rather than from a mock's call log. The
/// recording subclass exists for the one claim a table cannot answer: which
/// methods the section reached for.
///
/// **Two sessions, on purpose.** The store's gate reads the `session` variable
/// below; `accessSessionProvider` is the real controller and stays anonymous
/// unless a test signs in. On a station those are the same session. Splitting
/// them here is what lets one test assert that a logged-out panel gains a group
/// the moment `Operator` is saved **with no sign-in and no sign-out anywhere in
/// the test** — the store has to permit the write for the write to happen at
/// all, and signing in to arrange that would destroy the claim being made.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/core/access_admin_store.dart';
import 'package:tfc/pages/access_roles_section.dart';
import 'package:tfc/providers/access.dart';
import 'package:tfc/providers/access_admin.dart';
import 'package:tfc/providers/access_policy.dart';
import 'package:tfc/widgets/access_admin_notice.dart';
import 'package:tfc/widgets/access_denied_prompt.dart';
import 'package:tfc/widgets/panes/standard_dialog.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

/// A stand-in for `LocalAuthProvider` honouring the same null-versus-throw
/// contract. Only the two tests that sign somebody in reach it.
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

class _RecordingSink implements AuditSink {
  final List<AuditRecord> rows = [];

  @override
  Future<void> record(AuditRecord entry) async => rows.add(entry);
}

/// The real store, over the real tables, with a call log.
///
/// Subclassed rather than faked, for the reason
/// `access_templates_section_test.dart` gives: what *happened* is read back
/// from the tables, and only "which methods did the section reach for" needs a
/// log. A hand-written fake would have let the one-roster-read test pass while
/// the section quietly asked the database something per row.
class _RecordingStore extends AccessAdminStore {
  _RecordingStore({
    required super.repository,
    required super.session,
    required super.audit,
    required super.station,
    super.onDenied,
  });

  final List<String> calls = [];

  @override
  Future<List<AccessRole>> roles() {
    calls.add('roles');
    return super.roles();
  }

  @override
  Future<List<AppUserData>> listUsers() {
    calls.add('listUsers');
    return super.listUsers();
  }

  @override
  Future<void> createRole(AccessRole role,
      {String origin = 'operator', String? reason}) {
    calls.add('createRole:${role.name}');
    return super.createRole(role, origin: origin, reason: reason);
  }

  @override
  Future<void> updateRole(AccessRole role,
      {String origin = 'operator', String? reason}) {
    calls.add('updateRole:${role.name}:${role.encodeGroups()}');
    return super.updateRole(role, origin: origin, reason: reason);
  }

  @override
  Future<void> deleteRole(String name,
      {String origin = 'operator', String? reason}) {
    calls.add('deleteRole:$name');
    return super.deleteRole(name, origin: origin, reason: reason);
  }

  @override
  Future<void> renameRole(String from, String to,
      {String origin = 'operator', String? reason}) {
    calls.add('renameRole:$from:$to');
    return super.renameRole(from, to, origin: origin, reason: reason);
  }
}

/// The `users` gate the composed page puts over this section, in miniature.
///
/// Only the part that matters to one claim here: when the session in force
/// loses `users`, the subtree is swapped out and the section is disposed.
/// `AccessGate` itself brings a locked page, its own scaffold and a sign-in
/// opener, none of which this claim needs — and standing all of that up would
/// make the test about the gate rather than about what runs after the await.
class _UsersGate extends ConsumerWidget {
  const _UsersGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(accessSessionProvider).valueOrNull;
    if (session == null || !session.can(AccessGroup.users)) {
      return const Text('locked');
    }
    return child;
  }
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

AccessSession _anonymous() =>
    AccessSession.anonymous(const {AccessGroup.operate});

/// The engineer the `users` gate exists for: they may edit a page and must not
/// be able to re-scope who may write what. Spec §1 separates `users` from
/// `configure` for exactly this person.
AccessSession _configureOnly() => const AccessSession(
      user: AuthenticatedUser(username: 'engineer', roleName: 'Engineering'),
      groups: {
        AccessGroup.operate,
        AccessGroup.setpoints,
        AccessGroup.device,
        AccessGroup.configure,
      },
    );

AccessSession _withUsers() => const AccessSession(
      user: AuthenticatedUser(username: 'admin', roleName: 'Engineering'),
      groups: {AccessGroup.operate, AccessGroup.configure, AccessGroup.users},
    );

const String _kStation = 'SVN-NES-OT-CL02';

void main() {
  late AppDatabase db;
  late AccessRepository repository;
  late _RecordingSink sink;
  late AccessSession session;
  late _FakeAuthProvider auth;
  _RecordingStore? store;
  ProviderContainer? container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    DatabaseConfig.clearPrefsCache();
    // PBKDF2 at production iterations is the better part of a second per
    // account, and several tests here create real rows.
    Pbkdf2Kdf.iterationsForTest = 10;

    db = AppDatabase.inMemoryForTest();
    // Force the migration, so the four seeded roles exist before anything asks
    // for them.
    await db.customSelect('SELECT 1').getSingle();
    repository = AccessRepository(db);
    sink = _RecordingSink();
    session = _withUsers();
    auth = _FakeAuthProvider({
      'admin': (password: 'correct horse', roleName: 'Engineering'),
      'keeper': (password: 'correct horse', roleName: 'Access Admin'),
    });
    store = null;
    container = null;
  });

  tearDown(() async {
    Pbkdf2Kdf.iterationsForTest = null;
    await db.close();
  });

  /// The same wiring the real providers do. `accessRepositoryProvider` is
  /// shared by the store and by `AccessSessionController`, which is what makes
  /// `refreshGroupsFromRoles` observe the row the section just wrote.
  List<Override> overrides({
    bool noDatabase = false,
    Object? storeError,
    bool storeNeverResolves = false,
    Future<List<AccessRole>>? roles,
  }) =>
      [
        accessRepositoryProvider.overrideWith((ref) async => repository),
        authProviderProvider.overrideWith((ref) async => auth),
        auditSinkProvider.overrideWith((ref) async => sink),
        stationNameProvider.overrideWithValue(_kStation),
        inactivityTimeoutProvider
            .overrideWith((ref) async => const Duration(minutes: 15)),
        accessAdminStoreProvider.overrideWith((ref) async {
          if (storeNeverResolves) {
            return Completer<AccessAdminStore?>().future;
          }
          if (storeError != null) throw storeError;
          if (noDatabase) return null;
          return store = _RecordingStore(
            repository: repository,
            session: () => session,
            audit: sink,
            station: _kStation,
            // Exactly what the real provider does, so a refusal here reaches
            // the shared prompt as it does on a station.
            onDenied: (denial) => reportAccessDenial(ref, denial),
          );
        }),
        // Overridden only where a test needs a list the seeded database cannot
        // produce — see the empty-list terminal state.
        if (roles != null) accessAdminRolesProvider.overrideWith((ref) => roles),
      ];

  /// The section on its own, under a real [AccessDeniedPrompt] — the prompt a
  /// refusal has to reach, rather than a listener of the test's own.
  ///
  /// An explicit container rather than a plain `ProviderScope`, so a test can
  /// read the real `accessSessionProvider` and assert what a logged-out panel
  /// may do after a save. [gated] additionally puts the section behind the
  /// `users` gate the composed page puts it behind, which is what makes a save
  /// that narrows the caller's own role unmount the widget mid-await.
  Widget host(List<Override> o, {bool gated = false}) {
    final c = ProviderContainer(overrides: o);
    container = c;
    addTearDown(c.dispose);
    return UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: AccessDeniedPrompt(
            child: SingleChildScrollView(
              child: gated
                  ? const _UsersGate(child: AccessRolesSection())
                  : const AccessRolesSection(),
            ),
          ),
        ),
      ),
    );
  }

  AccessSession? sessionInForce() =>
      container!.read(accessSessionProvider).valueOrNull;

  /// Signs [username] in on the **real** controller, so the session in force is
  /// elevated and the `users` gate above the section is open.
  Future<void> signIn(WidgetTester tester, String username) async {
    final result = await container!
        .read(accessSessionProvider.notifier)
        .signIn(username, 'correct horse');
    expect(result, AccessSignInResult.ok);
    await tester.pumpAndSettle();
  }

  /// Cleanup, not part of any claim: an elevated session arms the inactivity
  /// monitor, and a timer still pending when the test body ends fails the test
  /// on its way out.
  Future<void> signOut(WidgetTester tester) async {
    await container!.read(accessSessionProvider.notifier).signOut();
    await tester.pumpAndSettle();
  }

  Future<AccessRole?> roleNamed(String name) => repository.role(name);

  Future<void> makeUser(String username, String roleName) =>
      repository.createUser(
        username: username,
        password: 'correct horse',
        roleName: roleName,
      );

  /// Opens the editor for [name] by tapping its row.
  Future<void> openEditor(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(kAccessRoleTileKey(name)));
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------------------
  // The four terminal states
  // -------------------------------------------------------------------------

  group('the four terminal states', () {
    testWidgets('still loading renders nothing — not a spinner that flashes',
        (tester) async {
      await tester.pumpWidget(host(overrides(storeNeverResolves: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessRolesSectionKey), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'this is one section on a page; the page owns the spinner, '
              'and a spinner that appears for a frame on every station is the '
              'flash AccessLockBadge refuses to draw');
      expect(find.byKey(kAccessRolesUnavailableKey), findsNothing);
      expect(find.byKey(kAccessRolesNoDatabaseKey), findsNothing);
      expect(find.byKey(kAccessRolesEmptyKey), findsNothing);
    });

    testWidgets('the store errored says the list is untrustworthy',
        (tester) async {
      await tester.pumpWidget(
          host(overrides(storeError: StateError('no connection'))));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessRolesUnavailableKey), findsOneWidget);
      expect(find.text(kAccessRolesUnavailableNote), findsOneWidget);
      expect(find.byKey(kAccessRolesNoDatabaseKey), findsNothing);
      expect(find.byKey(kAccessRolesEmptyKey), findsNothing);
    });

    testWidgets('no database says why, rather than showing an empty list',
        (tester) async {
      await tester.pumpWidget(host(overrides(noDatabase: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessRolesNoDatabaseKey), findsOneWidget);
      expect(find.text(kAccessRolesNoDatabaseNote), findsOneWidget);
      expect(find.byKey(kAccessRolesEmptyKey), findsNothing,
          reason: '"there are no roles" is a different claim from "this '
              'station cannot tell you", and only one of them is true here');
      expect(find.byKey(kAccessRolesCreateKey), findsNothing,
          reason: 'there is no table to create into — and that is not a '
              'permission decision, so nothing is greyed either');
    });

    testWidgets('an empty list says a seeded database cannot be empty',
        (tester) async {
      // The one state the real loader cannot produce: the v6 migration seeds
      // four roles and `Operator` cannot be deleted. Overridden here precisely
      // because the copy's claim is that reaching it means something is wrong.
      await tester.pumpWidget(
          host(overrides(roles: Future.value(const <AccessRole>[]))));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessRolesEmptyKey), findsOneWidget);
      expect(find.text(kAccessRolesEmptyNote), findsOneWidget);
      expect(find.byKey(kAccessRolesNoDatabaseKey), findsNothing);
      expect(find.byKey(kAccessRolesUnavailableKey), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // The list
  // -------------------------------------------------------------------------

  group('the list', () {
    testWidgets('names every seeded role and what it grants, by label',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(find.text(kAccessRolesHeadline), findsOneWidget);
      for (final role in kSeedRoles) {
        expect(find.text(role.name), findsOneWidget);
      }
      expect(
        find.text(kAccessRoleSummary({AccessGroup.operate}, 0)),
        findsOneWidget,
        reason: 'the Operator row: one group, nobody holds it',
      );
      expect(
        find.textContaining(AccessGroup.force.label),
        findsAtLeastNWidgets(1),
        reason: 'the summary reads by label, not by enum name — "force" tells '
            'a commissioning engineer nothing',
      );
    });

    testWidgets('the holder counts come from one roster read, not one query '
        'per row', (tester) async {
      await makeUser('admin', 'Engineering');
      await makeUser('sigga', 'Shift Leader');
      await makeUser('gunna', 'Shift Leader');

      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(store!.calls.where((c) => c == 'listUsers').length, 1,
          reason: 'four roles on a seeded station, one roster read — a count '
              'per row would be one round trip per role per rebuild');
      expect(
        find.text(kAccessRoleSummary(
            {AccessGroup.operate, AccessGroup.setpoints}, 2)),
        findsOneWidget,
        reason: 'Shift Leader is held by two accounts',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Operator: protected in the UI as well as in the repository
  // -------------------------------------------------------------------------

  group('Operator', () {
    testWidgets('the Operator row offers no Rename and no Delete at all',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessRoleRenameKey(kOperatorRoleName)), findsNothing,
          reason: 'absent, not disabled: an unauthenticated panel resolves to '
              'this row and no session can change that, so a control that is '
              'present and always refuses would teach a second press');
      expect(find.byKey(kAccessRoleDeleteKey(kOperatorRoleName)), findsNothing);

      // By count rather than by looking for a disabled one: the other three
      // seeded roles have both controls, so the totals pin that exactly one
      // row is missing them.
      expect(find.byType(IconButton),
          findsNWidgets((kSeedRoles.length - 1) * 2));
    });

    testWidgets("a row stored as ' operator ' is protected too — the UI uses "
        'isProtectedRoleName, not a string comparison', (tester) async {
      // Inserted through drift rather than through the repository, because
      // `upsertRole` trims: the whitespace variant is only reachable as stored
      // data written by something older or by hand. The predicate is
      // whitespace-tolerant and case-insensitive precisely for this row.
      await db.into(db.appRole).insert(
            AppRoleCompanion.insert(name: ' operator ', groups: '["operate"]'),
          );

      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessRoleTileKey(' operator ')), findsOneWidget);
      expect(find.byKey(kAccessRoleRenameKey(' operator ')), findsNothing);
      expect(find.byKey(kAccessRoleDeleteKey(' operator ')), findsNothing);
      expect(find.byType(IconButton),
          findsNWidgets((kSeedRoles.length - 1) * 2),
          reason: 'the extra row added no controls: five rows, three of them '
              'renameable and deletable');
    });
  });

  // -------------------------------------------------------------------------
  // Create and rename
  // -------------------------------------------------------------------------

  group('create', () {
    testWidgets('a users session creates a role and the list shows it',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAccessRolesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(kAccessRoleNameFieldKey), 'Line Supervisor');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text('Line Supervisor'), findsOneWidget);
      final created = await roleNamed('Line Supervisor');
      expect(created, isNotNull);
      expect(created!.groups, isEmpty,
          reason: 'a new role grants nothing until a box is ticked');
    });

    testWidgets('a duplicate name is refused inside the dialog, without the '
        'store being called', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      store!.calls.clear();

      await tester.tap(find.byKey(kAccessRolesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessRoleNameFieldKey), 'Maintenance');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessRoleDuplicateNameNote), findsOneWidget);
      expect(find.byKey(kAccessRoleNameFieldKey), findsOneWidget,
          reason: 'the dialog stays open with the text in it — a typo must not '
              'cost the whole entry');
      expect(store!.calls.where((c) => c.startsWith('createRole')), isEmpty,
          reason: 'a typo is not an authorization event, and putting a '
              'sign-in prompt in front of one teaches the operator to ignore '
              'the prompt');
    });

    testWidgets('a blank name is refused inside the dialog', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      store!.calls.clear();

      await tester.tap(find.byKey(kAccessRolesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessRoleNameFieldKey), '   ');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessRoleInvalidNameNote), findsOneWidget);
      expect(store!.calls.where((c) => c.startsWith('createRole')), isEmpty);
    });

    testWidgets('a name that is a capitalisation of Operator is refused '
        'inside the dialog', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      store!.calls.clear();

      await tester.tap(find.byKey(kAccessRolesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessRoleNameFieldKey), 'operator');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessRoleProtectedNameNote), findsOneWidget,
          reason: 'a second row the UI would render with no controls, and '
              'which nothing could then delete, is worse than a refusal here');
      expect(store!.calls.where((c) => c.startsWith('createRole')), isEmpty);
    });

    testWidgets('a configure-only session is refused, reaches the shared '
        'prompt, and the list is unchanged', (tester) async {
      session = _configureOnly();
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      final create =
          tester.widget<OutlinedButton>(find.byKey(kAccessRolesCreateKey));
      expect(create.onPressed, isNotNull,
          reason: 'nothing on this section is greyed for lack of a permission '
              '— it is pressed, and then explained');

      await tester.tap(find.byKey(kAccessRolesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessRoleNameFieldKey), 'Cleaner');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessDeniedBodyKey), findsOneWidget);
      expect(find.text(kAccessDeniedGroupNote(AccessGroup.users)),
          findsOneWidget,
          reason: 'spec §1: somebody who may edit a page must not be able to '
              're-scope who may write what');
      expect(await roleNamed('Cleaner'), isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('rename', () {
    testWidgets('a users session renames a role and its holders come with it',
        (tester) async {
      await makeUser('sigga', 'Shift Leader');
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAccessRoleRenameKey('Shift Leader')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessRoleNameFieldKey), 'Line Lead');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text('Line Lead'), findsOneWidget);
      expect(find.text('Shift Leader'), findsNothing);
      expect((await repository.user('sigga'))!.roleName, 'Line Lead');
    });

    testWidgets('the rename dialog refuses a name already taken, without the '
        'store being called', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      store!.calls.clear();

      await tester.tap(find.byKey(kAccessRoleRenameKey('Shift Leader')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(kAccessRoleNameFieldKey), 'Maintenance');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessRoleDuplicateNameNote), findsOneWidget);
      expect(store!.calls.where((c) => c.startsWith('renameRole')), isEmpty);
    });
  });


  // -------------------------------------------------------------------------
  // The seven checkboxes
  // -------------------------------------------------------------------------

  group('the seven checkboxes', () {
    testWidgets('are generated from AccessGroup.values, in that order, with '
        'the label as title and the description as subtitle', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Maintenance');

      final tiles = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();

      expect(tiles.length, AccessGroup.values.length,
          reason: 'seven, and generated — a hand-written list of seven is how '
              'an eighth group silently fails to appear');
      expect(
        [for (final tile in tiles) (tile.title! as Text).data],
        [for (final group in AccessGroup.values) group.label],
        reason: 'the enum is declared in increasing privilege and '
            'tfc_access/test/access_group_test.dart pins that order precisely '
            'so consumers can rely on it',
      );
      expect(
        [for (final tile in tiles) (tile.subtitle! as Text).data],
        [for (final group in AccessGroup.values) group.description],
        reason: 'AccessGroupInfo.description, verbatim — one wording shared '
            'with the MCP tools, sourced from the enum\'s own doc comments',
      );
    });

    testWidgets('start ticked exactly where the role grants, and Cancel '
        'discards without writing', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Shift Leader');
      store!.calls.clear();

      CheckboxListTile boxFor(AccessGroup group) => tester
          .widget<CheckboxListTile>(
              find.byKey(kAccessRoleGroupKey('Shift Leader', group)));

      expect(boxFor(AccessGroup.operate).value, isTrue);
      expect(boxFor(AccessGroup.setpoints).value, isTrue);
      expect(boxFor(AccessGroup.force).value, isFalse);

      await tester.tap(
          find.byKey(kAccessRoleGroupKey('Shift Leader', AccessGroup.force)));
      await tester.pumpAndSettle();
      expect(boxFor(AccessGroup.force).value, isTrue,
          reason: 'the tick is local — the editor holds a draft and does not '
              'write on every box');
      expect(store!.calls.where((c) => c.startsWith('updateRole')), isEmpty);

      await tester.tap(find.byKey(kAccessRoleCancelKey('Shift Leader')));
      await tester.pumpAndSettle();
      expect((await roleNamed('Shift Leader'))!.groups,
          {AccessGroup.operate, AccessGroup.setpoints});
      expect(store!.calls.where((c) => c.startsWith('updateRole')), isEmpty);
    });

    testWidgets('one Save writes one role.update however many boxes moved',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Shift Leader');
      store!.calls.clear();

      for (final group in [AccessGroup.device, AccessGroup.force]) {
        await tester
            .tap(find.byKey(kAccessRoleGroupKey('Shift Leader', group)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(kAccessRoleSaveKey('Shift Leader')));
      await tester.pumpAndSettle();

      expect(store!.calls.where((c) => c.startsWith('updateRole')).length, 1,
          reason: 'two boxes, one write, one audit row');
      expect((await roleNamed('Shift Leader'))!.groups, {
        AccessGroup.operate,
        AccessGroup.setpoints,
        AccessGroup.device,
        AccessGroup.force,
      });
    });
  });

  // -------------------------------------------------------------------------
  // Warning one of two: the persistent inline banner
  // -------------------------------------------------------------------------

  group('the Operator banner', () {
    testWidgets('is rendered the whole time the protected row is open',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessOperatorWarningKey), findsNothing,
          reason: 'nothing is open yet');

      await openEditor(tester, kOperatorRoleName);
      expect(find.byKey(kAccessOperatorWarningKey), findsOneWidget);
      expect(find.text(kAccessOperatorBannerNote), findsOneWidget,
          reason: 'access_repository.dart:90-96 asks for the warning "at the '
              'point of edit, not in a help page"');

      // Still up after a tick, and after another. A banner that vanished the
      // moment the operator started editing would be a banner about nothing.
      await tester.tap(find.byKey(
          kAccessRoleGroupKey(kOperatorRoleName, AccessGroup.setpoints)));
      await tester.pumpAndSettle();
      expect(find.byKey(kAccessOperatorWarningKey), findsOneWidget);
      await tester.tap(find.byKey(
          kAccessRoleGroupKey(kOperatorRoleName, AccessGroup.device)));
      await tester.pumpAndSettle();
      expect(find.byKey(kAccessOperatorWarningKey), findsOneWidget);
    });

    testWidgets('is not rendered for any other role', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      for (final name in ['Shift Leader', 'Maintenance', 'Engineering']) {
        await openEditor(tester, name);
        expect(find.byKey(kAccessOperatorWarningKey), findsNothing,
            reason: '$name is an ordinary role; a warning shown everywhere is '
                'a warning nobody reads');
        await openEditor(tester, name);
      }
    });

    testWidgets('the Operator row is marked as the anonymous identity',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessRoleAnonymousTagKey), findsOneWidget);
      expect(find.text(kAccessRoleAnonymousTag), findsOneWidget,
          reason: 'the row is legible as the anonymous identity rather than '
              'merely as the row with no controls');
    });
  });

  // -------------------------------------------------------------------------
  // Warning two of two: the confirmation on save
  // -------------------------------------------------------------------------

  group('the Operator save confirmation', () {
    testWidgets('names the groups being added by label, and cancelling it '
        'writes nothing', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, kOperatorRoleName);
      store!.calls.clear();

      for (final group in [AccessGroup.setpoints, AccessGroup.force]) {
        await tester
            .tap(find.byKey(kAccessRoleGroupKey(kOperatorRoleName, group)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(kAccessRoleSaveKey(kOperatorRoleName)));
      await tester.pumpAndSettle();

      expect(find.text(kAccessOperatorConfirmTitle), findsOneWidget);
      expect(
        find.text(kAccessOperatorConfirmMessage(
            const [AccessGroup.setpoints, AccessGroup.force])),
        findsOneWidget,
      );
      expect(find.textContaining(AccessGroup.force.label), findsOneWidget,
          reason: 'by label. AccessGroup.force.name is "force", which is '
              'exactly the word 06-01 exists to stop the screen using');
      expect(find.byKey(kAccessOperatorWarningKey), findsOneWidget,
          reason: 'both halves at once — the banner does not go away because '
              'the dialog arrived');

      await tester.tap(find.descendant(
          of: find.byType(StandardDialog), matching: find.text('Cancel')));
      await tester.pumpAndSettle();

      expect(store!.calls.where((c) => c.startsWith('updateRole')), isEmpty);
      expect(
          (await roleNamed(kOperatorRoleName))!.groups, {AccessGroup.operate});
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(
                kAccessRoleGroupKey(kOperatorRoleName, AccessGroup.force)))
            .value,
        isTrue,
        reason: 'the draft is left as the operator left it, so a second Save '
            'does not need the boxes ticked again',
      );
    });

    testWidgets('a save that only removes groups shows the banner and no '
        'confirmation', (tester) async {
      await repository.upsertRole(const AccessRole(
        name: kOperatorRoleName,
        groups: {AccessGroup.operate, AccessGroup.setpoints},
        seeded: true,
      ));
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, kOperatorRoleName);

      expect(find.byKey(kAccessOperatorWarningKey), findsOneWidget);

      await tester.tap(find.byKey(
          kAccessRoleGroupKey(kOperatorRoleName, AccessGroup.setpoints)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessRoleSaveKey(kOperatorRoleName)));
      await tester.pumpAndSettle();

      expect(find.text(kAccessOperatorConfirmTitle), findsNothing,
          reason: 'narrowing is the safe direction, and a confirm on every '
              'save is a confirm nobody reads');
      expect(
          (await roleNamed(kOperatorRoleName))!.groups, {AccessGroup.operate});
    });

    testWidgets('an ordinary role shows neither warning on save',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Maintenance');

      await tester.tap(find
          .byKey(kAccessRoleGroupKey('Maintenance', AccessGroup.configure)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessRoleSaveKey('Maintenance')));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessOperatorWarningKey), findsNothing);
      expect(find.text(kAccessOperatorConfirmTitle), findsNothing);
      expect((await roleNamed('Maintenance'))!.groups,
          contains(AccessGroup.configure));
    });
  });

  // -------------------------------------------------------------------------
  // The change the banner warns about, actually taking effect
  // -------------------------------------------------------------------------

  group('the group change takes effect', () {
    testWidgets('an anonymous session gains setpoints the moment Operator is '
        'saved with it — no sign-in and no sign-out', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(sessionInForce()!.isElevated, isFalse);
      expect(sessionInForce()!.can(AccessGroup.setpoints), isFalse);

      await openEditor(tester, kOperatorRoleName);
      await tester.tap(find.byKey(
          kAccessRoleGroupKey(kOperatorRoleName, AccessGroup.setpoints)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessRoleSaveKey(kOperatorRoleName)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kAccessOperatorConfirmLabel));
      await tester.pumpAndSettle();

      expect(
        sessionInForce()!.can(AccessGroup.setpoints),
        isTrue,
        reason: 'T-06-65: the banner promises that ticking a group here '
            'changes what a logged-out panel may do. Without '
            'refreshGroupsFromRoles it is a promise the app does not keep '
            'until something else happens to rebuild the session',
      );
      expect(sessionInForce()!.isElevated, isFalse,
          reason: 'still logged out — that is the whole point');
    });

    testWidgets('a rename re-resolves the session in force too, so the write '
        'path does not refresh only after an Operator edit', (tester) async {
      await makeUser('admin', 'Engineering');
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await signIn(tester, 'admin');
      expect(sessionInForce()!.user!.roleName, 'Engineering');

      await tester.tap(find.byKey(kAccessRoleRenameKey('Engineering')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(kAccessRoleNameFieldKey), 'Controls Engineering');
      await tester.tap(find.byKey(kAccessRoleNameConfirmKey));
      await tester.pumpAndSettle();

      expect(
        sessionInForce()!.user!.roleName,
        'Controls Engineering',
        reason: 'the refresh runs after all four role writes, not only after '
            'an Operator update — the session was carrying a role name that '
            'no longer exists',
      );

      await signOut(tester);
    });
  });

  // -------------------------------------------------------------------------
  // The lockout invariant, surfaced rather than re-implemented
  // -------------------------------------------------------------------------

  group('the lockout refusal', () {
    testWidgets('unticking users from the only granting role is refused '
        'inline, names the holders, and shows no snackbar', (tester) async {
      await makeUser('admin', 'Engineering');
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Engineering');

      await tester.tap(
          find.byKey(kAccessRoleGroupKey('Engineering', AccessGroup.users)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessRoleSaveKey('Engineering')));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessAdminRefusalKey), findsOneWidget);
      expect(find.byKey(kAccessAdminNoticeNameKey('admin')), findsOneWidget,
          reason: 'naming the remaining holder is what makes the fix obvious');
      expect(find.text(kAccessAdminBreakGlassNote), findsOneWidget,
          reason: 'there is no override, and there is a documented way back');
      expect(find.byType(SnackBar), findsNothing,
          reason: 'a refusal naming accounts must not be in something that '
              'disappears while it is being read');
      expect(find.byKey(kAccessDeniedBodyKey), findsNothing,
          reason: 'this is not an AccessDenied: the account that hits it '
              'already holds users, so no sign-in resolves it');

      expect((await roleNamed('Engineering'))!.groups,
          contains(AccessGroup.users));
      expect(
        tester
            .widget<CheckboxListTile>(find
                .byKey(kAccessRoleGroupKey('Engineering', AccessGroup.users)))
            .value,
        isFalse,
        reason: 'the boxes are left as the operator left them, so they can '
            'see what they tried',
      );
    });

    testWidgets('there is no override anywhere on the refused editor',
        (tester) async {
      await makeUser('admin', 'Engineering');
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Engineering');
      await tester.tap(
          find.byKey(kAccessRoleGroupKey('Engineering', AccessGroup.users)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessRoleSaveKey('Engineering')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
            of: find.byKey(kAccessAdminRefusalKey),
            matching: find.byType(TextField)),
        findsNothing,
        reason: '06-CONTEXT rejects a typed-confirmation lockout override by '
            'name: "no destructive override is offered"',
      );
      expect(
        find.descendant(
            of: find.byKey(kAccessAdminRefusalKey),
            matching: find.byType(ButtonStyleButton)),
        findsNothing,
      );
    });

    testWidgets(
        'narrowing the caller\'s own role while a second granting role is '
        'still held unmounts the section mid-save and throws nothing',
        (tester) async {
      // Route (c) is *permitted* here: a second role grants `users` and
      // somebody holds it, so the repository does not refuse — the refresh
      // simply drops the caller below the gate this section sits behind.
      await repository.upsertRole(
          const AccessRole(name: 'Access Admin', groups: {AccessGroup.users}));
      await makeUser('admin', 'Engineering');
      await makeUser('keeper', 'Access Admin');

      await tester.pumpWidget(host(overrides(), gated: true));
      await tester.pumpAndSettle();
      await signIn(tester, 'admin');
      expect(find.byKey(kAccessRolesSectionKey), findsOneWidget);

      await openEditor(tester, 'Engineering');
      await tester.tap(
          find.byKey(kAccessRoleGroupKey('Engineering', AccessGroup.users)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessRoleSaveKey('Engineering')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the refresh goes last and everything after the await is '
              'guarded, so the unmount is a non-event — an invalidate or a '
              'setState sequenced after it would run on a disposed element');
      expect(find.text('locked'), findsOneWidget,
          reason: 'the caller narrowed their own role and the gate closed, '
              'which is exactly what the call is for');
      expect((await roleNamed('Engineering'))!.groups,
          isNot(contains(AccessGroup.users)));

      await signOut(tester);
    });
  });

  // -------------------------------------------------------------------------
  // A sanity check on the shared notice frame: the section renders neither
  // block until it has something to say.
  // -------------------------------------------------------------------------

  testWidgets('no warning and no refusal is rendered by a list at rest',
      (tester) async {
    await tester.pumpWidget(host(overrides()));
    await tester.pumpAndSettle();

    expect(find.byKey(kAccessOperatorWarningKey), findsNothing);
    expect(find.byKey(kAccessAdminRefusalKey), findsNothing);

    // The editor is closed, so no checkbox is on screen either.
    expect(find.byType(CheckboxListTile), findsNothing);
    await openEditor(tester, 'Maintenance');
    expect(find.byType(CheckboxListTile), findsNWidgets(AccessGroup.values.length));
  });
}

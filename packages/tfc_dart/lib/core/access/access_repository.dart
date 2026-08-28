import 'package:drift/drift.dart';
import 'package:logger/logger.dart';
import 'package:tfc_access/tfc_access.dart';

import '../database_drift.dart';

/// The role the first account is forced into.
///
/// Not a parameter of [AccessRepository.createFirstUser] on purpose — see the
/// comment there. Written once, here, so the two places that need the name
/// cannot drift apart.
const String kFirstUserRoleName = 'Engineering';

/// Thrown when [AccessRepository.createFirstUser] is called after the window
/// has closed.
///
/// An [Error] rather than an [Exception]: the caller is expected to have asked
/// [AccessRepository.isUserTableEmpty] first, so reaching this means either a
/// defect or a genuine race — and in the race case the loser must not be
/// tempted to "handle" it by retrying.
class FirstUserWindowClosedError extends Error {
  FirstUserWindowClosedError();

  @override
  String toString() =>
      'FirstUserWindowClosedError: a user already exists, so no further user '
      'may be created. Users are added by an account holding the users group.';
}

/// Thrown when an operation names a role that is not in `app_role`.
///
/// Exists so a missing role reads as a missing role. Without it, deleting
/// `Engineering` before commissioning would surface as
/// `SqliteException(787): FOREIGN KEY constraint failed` on the first-user
/// screen, which tells the person standing at the panel nothing at all.
class MissingRoleError extends Error {
  MissingRoleError(this.roleName);

  /// The role that was expected and is not there.
  final String roleName;

  @override
  String toString() => 'MissingRoleError: there is no role named "$roleName".';
}

/// The stored form of a password hash, for `AppUser.passwordHash`.
///
/// Thin wrappers over [PasswordHash.encode] / [PasswordHash.tryDecode], which
/// live in `tfc_access` beside the value type so the relay can read a stored
/// hash without pulling in Drift. They are re-exposed here because this is the
/// layer that reads and writes the column, and a caller should not have to know
/// which package the encoding lives in.
///
/// The format is `pbkdf2-sha256$<iterations>$<hash_b64>`, with the raw base64
/// salt in the separate `salt` column. The iteration count travels *with* the
/// hash because the `AppUser` table (spec §2, quoted as final) has no
/// iterations column and is not getting one: a later change to
/// [Pbkdf2Kdf.defaultIterations] would otherwise silently invalidate every
/// password already stored, and the self-describing form leaves room for a
/// second algorithm later without another migration.
String encodeStoredHash(PasswordHash hash) => hash.encode();

/// Parse an `AppUser.passwordHash` value, or null if it is unreadable.
///
/// A bare base64 value with no `$` is a legacy hash written before this
/// encoding existed; it decodes at the ambient [Pbkdf2Kdf.iterations] rather
/// than throwing. Null means the column was mangled — by hand in `psql`, most
/// likely — and the login path treats that as a failed credential rather than
/// crashing the login screen.
PasswordHash? decodeStoredHash(String stored, {required String saltB64}) =>
    PasswordHash.tryDecode(stored, saltB64: saltB64);

/// Reads and writes for `app_role` and `app_user`.
///
/// Pure data layer: an [AppDatabase] and nothing else. No Riverpod, no Flutter,
/// no policy. Gating is not this class's job and is not this phase's job —
/// Phase 1 records and resolves, Phase 3 enforces.
///
/// ## The Operator footgun
///
/// Anonymous **is** the role named [kOperatorRoleName]. A session with nobody
/// signed in resolves to that row, by construction rather than through a
/// configurable pointer.
///
/// Two things follow, and both are enforced here rather than documented
/// somewhere and hoped for:
///
///  * [deleteRole] and [renameRole] refuse that name. A logged-out panel would
///    otherwise lose the identity it resolves to.
///  * **Editing the Operator row changes what an *unauthenticated* panel may
///    do.** Ticking `setpoints` on Operator silently grants it to every panel
///    on the floor with nobody signed in. That is allowed — it is the knob a
///    site turns when it wants a permissive line — but it is the one footgun
///    this simplification creates, and **the Phase 6 roles screen must say so
///    at the point of edit**, not in a help page. This sentence is here so
///    whoever writes that screen finds it.
class AccessRepository {
  AccessRepository(this.db, {Logger? logger}) : _logger = logger ?? Logger();

  final AppDatabase db;
  final Logger _logger;

  /// The groups seeded onto `Operator`, used as the fallback in
  /// [anonymousGroups].
  static final Set<AccessGroup> _seededOperatorGroups =
      kSeedRoles.firstWhere((r) => r.name == kOperatorRoleName).groups;

  // ---------------------------------------------------------------------
  // Roles
  // ---------------------------------------------------------------------

  /// Every row in `app_role`.
  Future<List<AccessRole>> roles() async {
    final rows = await db.select(db.appRole).get();
    return rows.map(_toRole).toList(growable: false);
  }

  /// The role named [name], or null when there is no such row.
  Future<AccessRole?> role(String name) async {
    final row = await (db.select(db.appRole)
          ..where((t) => t.name.equals(name)))
        .getSingleOrNull();
    return row == null ? null : _toRole(row);
  }

  /// The groups a session with nobody signed in currently holds.
  ///
  /// Reads the row named [kOperatorRoleName] — whatever it says today, which
  /// is the point (see the class comment's footgun note).
  ///
  /// Falls back to the seeded `{operate}` when the row is missing or the query
  /// throws. Both cases are real: an operator can delete the row in `psql`, and
  /// the shared Postgres server can be unreachable for a minute. Neither should
  /// cost a logged-out panel its ability to jog a conveyor — a panel that goes
  /// dead because the database blinked is a stopped line. The seeded set is the
  /// conservative floor rather than a guess: it is the narrowest thing Operator
  /// has ever been.
  Future<Set<AccessGroup>> anonymousGroups() async {
    try {
      final operator = await role(kOperatorRoleName);
      if (operator == null) {
        _logger.w(
          'No "$kOperatorRoleName" role in app_role — falling back to the '
          'seeded anonymous groups. Someone has deleted the row that an '
          'unauthenticated panel resolves to.',
        );
        return {..._seededOperatorGroups};
      }
      return operator.groups;
    } on Object catch (e) {
      _logger.w(
        'Could not read the "$kOperatorRoleName" role — falling back to the '
        'seeded anonymous groups: $e',
      );
      return {..._seededOperatorGroups};
    }
  }

  /// Insert [role], or update the groups of an existing row with that name.
  ///
  /// A rename is not expressible here — the name is the primary key, so
  /// changing it is an insert plus a delete, which is [renameRole]. That is why
  /// the protected-name guard lives on [deleteRole] and [renameRole] and not on
  /// this method: this method cannot remove a name.
  ///
  /// `seeded` is left as it was on an update. It records where the row came
  /// from, and editing a seeded role does not make it stop having been seeded.
  Future<void> upsertRole(AccessRole role) async {
    final name = role.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(role.name, 'role.name', 'must not be blank');
    }
    await db.transaction(() async {
      final existing = await (db.select(db.appRole)
            ..where((t) => t.name.equals(name)))
          .getSingleOrNull();
      if (existing == null) {
        await db.into(db.appRole).insert(
              AppRoleCompanion.insert(
                name: name,
                groups: role.encodeGroups(),
                seeded: Value(role.seeded),
              ),
            );
      } else {
        await (db.update(db.appRole)..where((t) => t.name.equals(name)))
            .write(AppRoleCompanion(groups: Value(role.encodeGroups())));
      }
    });
  }

  /// Delete the role named [name].
  ///
  /// Throws [ProtectedRoleError] for [kOperatorRoleName] — case-insensitively
  /// and whitespace-tolerantly, via [isProtectedRoleName], so neither
  /// `operator` nor `' Operator '` slips past.
  ///
  /// A role that a user still holds is refused by the foreign key rather than
  /// orphaning the user, provided the connection has foreign keys enabled.
  Future<void> deleteRole(String name) async {
    if (isProtectedRoleName(name)) throw ProtectedRoleError(name);
    await (db.delete(db.appRole)..where((t) => t.name.equals(name))).go();
  }

  /// Rename the role [from] to [to], carrying its users with it.
  ///
  /// Throws [ProtectedRoleError] when either end is the protected name:
  /// renaming *away* from it would leave an unauthenticated panel with no role
  /// to resolve to, and renaming *onto* it would either collide with the
  /// primary key or silently hand the anonymous identity to a different set of
  /// groups.
  ///
  /// `app_user.role_name` references `app_role.name` with no `ON UPDATE
  /// CASCADE`, so this is an insert, a repoint and a delete inside one
  /// transaction rather than an `UPDATE app_role SET name = ...`, which the
  /// foreign key would refuse the moment any user held the role.
  Future<void> renameRole(String from, String to) async {
    if (isProtectedRoleName(from)) throw ProtectedRoleError(from);
    if (isProtectedRoleName(to)) throw ProtectedRoleError(to);
    final target = to.trim();
    if (target.isEmpty) {
      throw ArgumentError.value(to, 'to', 'must not be blank');
    }
    await db.transaction(() async {
      final existing = await (db.select(db.appRole)
            ..where((t) => t.name.equals(from)))
          .getSingleOrNull();
      if (existing == null) throw MissingRoleError(from);

      final collision = await (db.select(db.appRole)
            ..where((t) => t.name.equals(target)))
          .getSingleOrNull();
      if (collision != null) {
        throw ArgumentError.value(
          to,
          'to',
          'a role named "$target" already exists',
        );
      }

      await db.into(db.appRole).insert(
            AppRoleCompanion.insert(
              name: target,
              groups: existing.groups,
              seeded: Value(existing.seeded),
            ),
          );
      await (db.update(db.appUser)..where((t) => t.roleName.equals(from)))
          .write(AppUserCompanion(roleName: Value(target)));
      await (db.delete(db.appRole)..where((t) => t.name.equals(from))).go();
    });
  }

  // ---------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------

  /// Whether the first-user window is still open.
  ///
  /// A convenience for the login surface, and **not** the guard. The real check
  /// is the one inside [createFirstUser]'s transaction; this one is what the UI
  /// asks in order to decide which screen to show.
  Future<bool> get isUserTableEmpty async => await userCount() == 0;

  /// The number of rows in `app_user`.
  Future<int> userCount() async {
    final count = db.appUser.username.count();
    final row = await (db.selectOnly(db.appUser)..addColumns([count]))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// The row for [username], or null.
  ///
  /// Case-sensitive, because `app_user.username` is a case-sensitive TEXT
  /// primary key. `user('JON')` does not find `jon`. That is a decision rather
  /// than an accident: case-folding usernames means picking a locale to fold
  /// in, and `İ` in Turkish is exactly the sort of thing that turns a login
  /// screen into a support call.
  Future<AppUserData?> user(String username) => (db.select(db.appUser)
        ..where((t) => t.username.equals(username)))
      .getSingleOrNull();

  /// Record that [username] signed in at [at].
  Future<void> touchLastLogin(String username, DateTime at) async {
    await (db.update(db.appUser)..where((t) => t.username.equals(username)))
        .write(AppUserCompanion(lastLoginAt: Value(at)));
  }

  /// Create the first account, but only while `app_user` is empty.
  ///
  /// Roles are seeded, users are not, so without this the login screen would
  /// ship with nobody able to pass it. The first person to open a freshly
  /// commissioned station creates the first account and **the door closes
  /// behind them** — no default password to forget to change, no bootstrap flag
  /// to leave switched on.
  ///
  /// There is deliberately **no role parameter**. The first account is
  /// Engineering ([kFirstUserRoleName]); a caller cannot ask for something
  /// else, so there is no way to commission a station whose only account cannot
  /// create the next one.
  ///
  /// The emptiness check runs **inside** the transaction, immediately before
  /// the insert. Checking beforehand is a check-then-act race, and while two
  /// people commissioning the same station in the same instant is unlikely,
  /// this is the one window in the design that must not have a hole in it —
  /// "the door closes behind them" is the whole rule, and a rule with a race in
  /// it is a rule that occasionally does not apply.
  ///
  /// The hash is derived before the transaction opens. PBKDF2 at production
  /// iteration counts takes the better part of a second, and holding a write
  /// transaction open across it would block every other writer on the shared
  /// Postgres server for that whole time. Nothing is decided by the derivation,
  /// so nothing is lost by doing it early — the loser of a race simply throws
  /// away a hash it computed.
  Future<void> createFirstUser({
    required String username,
    required String password,
  }) async {
    final name = username.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(username, 'username', 'must not be blank');
    }
    if (password.isEmpty) {
      // Deliberately not `ArgumentError.value(password, ...)`: that puts the
      // credential into the message, and from there into whatever logs it.
      throw ArgumentError('password must not be empty');
    }

    final hash = await PasswordHasher.hash(password);

    await db.transaction(() async {
      final existing = await userCount();
      if (existing != 0) throw FirstUserWindowClosedError();

      final role = await (db.select(db.appRole)
            ..where((t) => t.name.equals(kFirstUserRoleName)))
          .getSingleOrNull();
      if (role == null) throw MissingRoleError(kFirstUserRoleName);

      await db.into(db.appUser).insert(
            AppUserCompanion.insert(
              username: name,
              roleName: kFirstUserRoleName,
              passwordHash: encodeStoredHash(hash),
              salt: hash.saltB64,
              createdAt: DateTime.now().toUtc(),
            ),
          );
    });

    _logger.i('First user "$name" created as $kFirstUserRoleName — the '
        'first-user window is now closed.');
  }

  AccessRole _toRole(AppRoleData row) => AccessRole.fromDb(
        name: row.name,
        groupsJson: row.groups,
        seeded: row.seeded,
      );
}

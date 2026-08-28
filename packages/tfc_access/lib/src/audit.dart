import 'dart:math';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'access_role.dart';

/// One row of the audit trail.
///
/// The field list mirrors the `AuditEntry` table in spec §2 **one for one**, in
/// column order. Plan 01-05 maps them straight across into the Drift row with
/// no translation layer, precisely so there is nothing in between to drift out
/// of sync when a column is added.
///
/// ## The auth surface
///
/// Spec §2 enumerates `surface` as `'tag' | 'pref' | 'route'` — the three
/// *write* surfaces. Phase 1 has no writes to audit; its done-condition is that
/// login, logout and failed attempts land in the table. So `'auth'` is a fourth
/// surface value, with its own itemKey vocabulary:
///
///     login | login.failed | logout | session.timeout
///
/// and an **empty** [groupRequired], because signing in is not gated on a
/// group. The named constructors below are what fix that vocabulary, so no
/// consumer has to invent column values and the Phase 5 trail viewer has
/// something exact to filter on.
///
/// ## What must not be in here
///
/// No auth constructor takes a password, a hash or a salt, and none ever
/// should. [toString] withholds [oldValue] and [newValue] for auth rows for the
/// same reason — a trail that leaks credentials is worse than no trail.
@immutable
class AuditRecord {
  const AuditRecord({
    required this.at,
    required this.who,
    required this.station,
    required this.roleName,
    required this.surface,
    required this.itemKey,
    this.member,
    this.oldValue,
    this.newValue,
    required this.groupRequired,
    required this.allowed,
    this.origin = 'operator',
    required this.actionId,
    this.reason,
  });

  /// A successful sign-in.
  ///
  /// [roleName] is the role resolved for the new session; it is repeated in
  /// [newValue] so the trail reads as a transition without a join.
  factory AuditRecord.login({
    required String who,
    required String station,
    required String roleName,
    required String actionId,
    DateTime? at,
    String? reason,
  }) =>
      AuditRecord(
        at: at ?? clock.now(),
        who: who,
        station: station,
        roleName: roleName,
        surface: _authSurface,
        itemKey: 'login',
        newValue: roleName,
        groupRequired: '',
        allowed: true,
        actionId: actionId,
        reason: reason,
      );

  /// A rejected sign-in attempt.
  ///
  /// Denials are recorded, not only successes — a refused attempt is the more
  /// interesting audit line. [who] is whatever was typed into the username
  /// field, so it is untrusted input and is truncated to
  /// [maxAttemptedUsernameLength]; a login form accepts a paste, and a pasted
  /// megabyte must not become a row.
  ///
  /// The role is [kOperatorRoleName] because nobody was signed in: anonymous
  /// resolves to Operator by construction.
  factory AuditRecord.loginFailed({
    required String who,
    required String station,
    required String actionId,
    DateTime? at,
    String? reason,
  }) =>
      AuditRecord(
        at: at ?? clock.now(),
        who: who.length > maxAttemptedUsernameLength
            ? who.substring(0, maxAttemptedUsernameLength)
            : who,
        station: station,
        roleName: kOperatorRoleName,
        surface: _authSurface,
        itemKey: 'login.failed',
        groupRequired: '',
        allowed: false,
        actionId: actionId,
        reason: reason,
      );

  /// A deliberate sign-out. [roleName] is the elevated role being left, and is
  /// repeated in [oldValue].
  factory AuditRecord.logout({
    required String who,
    required String station,
    required String roleName,
    required String actionId,
    DateTime? at,
    String? reason,
  }) =>
      AuditRecord(
        at: at ?? clock.now(),
        who: who,
        station: station,
        roleName: roleName,
        surface: _authSurface,
        itemKey: 'logout',
        oldValue: roleName,
        groupRequired: '',
        allowed: true,
        actionId: actionId,
        reason: reason,
      );

  /// A session dropped by the inactivity timer.
  ///
  /// `allowed: true` — the session ending is the system working, not a denial.
  /// [reason] carries what tripped it (the configured idle interval), which is
  /// what makes a wall of timeout rows readable a month later.
  factory AuditRecord.sessionTimeout({
    required String who,
    required String station,
    required String roleName,
    required String actionId,
    DateTime? at,
    String? reason,
  }) =>
      AuditRecord(
        at: at ?? clock.now(),
        who: who,
        station: station,
        roleName: roleName,
        surface: _authSurface,
        itemKey: 'session.timeout',
        oldValue: roleName,
        groupRequired: '',
        allowed: true,
        actionId: actionId,
        reason: reason,
      );

  /// The `surface` value shared by every auth row.
  static const String _authSurface = 'auth';

  /// The cap applied to the attempted username on a failed login.
  static const int maxAttemptedUsernameLength = 64;

  /// When it happened.
  final DateTime at;

  /// Username, or `'anonymous'`.
  final String who;

  /// Hostname of the station the action came from.
  final String station;

  /// The role in force at the time.
  final String roleName;

  /// `'tag' | 'pref' | 'route' | 'auth'`.
  final String surface;

  /// The tag, preference key, route or auth event.
  final String itemKey;

  /// Dotted path within a struct, for member-level tag writes.
  final String? member;

  /// Value before the write.
  final String? oldValue;

  /// Value after the write.
  final String? newValue;

  /// Name of the `AccessGroup` the action required — empty for auth rows.
  final String groupRequired;

  /// False for a denial. Denials are recorded too; a denied write is how you
  /// find a role configured too tightly.
  final bool allowed;

  /// `'operator'` by default, on purpose — see the class doc and spec §2. An
  /// unmarked machine caller lands in the trail loudly rather than escaping it
  /// silently.
  final String origin;

  /// Correlation id. One human action is one [actionId] with N rows beneath it,
  /// so a recipe apply reads as one action rather than N unrelated rows.
  final String actionId;

  /// Free text captured on `configure` and `administer` writes. Reason is what
  /// turns a log into an audit trail.
  final String? reason;

  /// True when this row describes an authentication event rather than a write.
  bool get isAuthEvent => surface == _authSurface;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditRecord &&
          other.at == at &&
          other.who == who &&
          other.station == station &&
          other.roleName == roleName &&
          other.surface == surface &&
          other.itemKey == itemKey &&
          other.member == member &&
          other.oldValue == oldValue &&
          other.newValue == newValue &&
          other.groupRequired == groupRequired &&
          other.allowed == allowed &&
          other.origin == origin &&
          other.actionId == actionId &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(
        at,
        who,
        station,
        roleName,
        surface,
        itemKey,
        member,
        oldValue,
        newValue,
        groupRequired,
        allowed,
        origin,
        actionId,
        reason,
      );

  /// Diagnostic form.
  ///
  /// [oldValue] and [newValue] are withheld for auth rows. Nothing should ever
  /// put a credential in them, but this string ends up in log files that live
  /// longer and travel further than the database does, and the cost of the
  /// precaution is one branch.
  @override
  String toString() {
    final values = isAuthEvent ? '<withheld>' : '$oldValue -> $newValue';
    return 'AuditRecord($at $who@$station as $roleName, '
        '$surface:$itemKey${member == null ? '' : '.$member'}, '
        '$values, allowed: $allowed, origin: $origin, action: $actionId)';
  }
}

final Random _actionIdRandom = Random.secure();

/// A fresh correlation id: 16 random bytes as 32 lowercase hex characters.
///
/// One human action gets one id, and every row that action produces carries it
/// — so a recipe apply reads as one action with N member rows beneath it rather
/// than N unrelated rows.
///
/// `Random.secure()` rather than a `uuid` dependency: 128 bits is already more
/// than enough to make ids non-colliding and unguessable, and this package
/// stays free of third-party packages that would follow it into the relay.
String newActionId() {
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer
        .write(_actionIdRandom.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Where audit rows go.
///
/// Implementations are **append-only**. Never update, never delete: the trail's
/// only value is that nothing has been removed from it. Retention policies must
/// not touch the audit table — spec §8 asks for that to be asserted in a test,
/// because the collector's `registerRetentionPolicy` would happily sweep it.
///
/// A sink whose write fails **must not take its caller down with it.** The
/// caller is a login flow, and refusing to sign somebody in because the audit
/// database blinked is worse than a gap in the trail. But the failure must be
/// logged loudly, because an absent audit row is the one defect nobody ever
/// notices.
abstract class AuditSink {
  /// Append [entry]. Completes when the row is durable, or when the failure has
  /// been logged — never by throwing at a login flow.
  Future<void> record(AuditRecord entry);
}

/// An [AuditSink] that discards everything.
///
/// Not test-only, so not `@visibleForTesting`: it is the legitimate sink during
/// the boot window before the database is open, and in any build that runs
/// without one. Anything using it is knowingly running with no trail.
class NullAuditSink implements AuditSink {
  const NullAuditSink();

  @override
  Future<void> record(AuditRecord entry) async {}
}

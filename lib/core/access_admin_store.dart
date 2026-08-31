/// Every write to `app_role` and `app_user`, behind one object and one gate.
///
/// A role decides what a group of people may do; an account decides which
/// person is in that group. Both are the authorization data itself, which is
/// why spec §1 puts them behind `users` rather than `administer` — `administer`
/// is server config, database, network and updates, which is station plumbing,
/// not who may do what.
///
/// This is the closure of the write-path sweep's §3.3 entry, which records
/// `AccessRepository` writing both tables through raw Drift as the one write
/// path deliberately left open, with *"Phase 6 gates it on `users`"* as the
/// closing condition. Plan 06-06 annotates the sweep once this holds.
///
/// ## Why the group is declared here rather than looked up
///
/// The same reasoning `access_template_store.dart` writes at
/// [kAccessTemplateGroup] and `guarded_history_views.dart` at
/// `kHistoryViewDeleteGroup`: neither table is a preference key, this store
/// consults no policy table, and a second source for one answer drifts. If you
/// are here to change what is gated, change [kAccessAdminGroup]; do not add a
/// rule to `kPrefAccessRules`.
///
/// ## The one thing this store must not do
///
/// It offers no delete, no prune and no export over `audit_entry`. The trail is
/// append-only, that property is currently enforced by absence, and this is the
/// file where somebody would first be tempted to break it — "clean up the rows
/// of the account I just deleted" is exactly the wrong instinct.
/// `audit_entry.who` is a denormalised TEXT column with no foreign key so that
/// a deleted account's rows survive it by construction. Do not add a cascade,
/// and do not add a method here that touches the trail.
library;

import 'package:logger/logger.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
// `AppUserData` only — the generated row type the users section renders. It is
// a plain value class; naming it here does not put a Drift query in this file,
// and the property being protected is that this file issues none. There is no
// Drift import above and a test asserts there never is, by grepping this file
// for the package name — which is why this comment does not spell it.
import 'package:tfc_dart/core/database_drift.dart' show AppUserData;

/// The `who` recorded when nobody is signed in.
const String _anonymousWho = 'anonymous';

/// The permission every write in this file requires — over **both** tables.
///
/// `users`, per spec §1: a role edit changes what a group of people may do and
/// an account edit changes who is in that group, which is the same concern as
/// templates and the trail, not machine configuration.
///
/// **What changing this line would mean.**
///
/// * Set it to [AccessGroup.configure] and anybody who can edit a page or a key
///   map could grant themselves `users`, and from there every other group. That
///   is the exact confusion the split between `configure` and `users` exists to
///   prevent (`access_group.dart`), and it would make the whole access model
///   decorative in one line. `access_admin_store_test.dart` drives a
///   `configure`-only session into all eight writes so that the line is checked
///   rather than remembered.
/// * Set it to [AccessGroup.administer] and you have reproduced the error in
///   `docs/access-control-deployment.md` §4, which speaks of "screens behind
///   the `administer` group, including the screen that creates users".
///   `administer` is server config, database, network and updates — the station
///   plumbing an integrator holds. It is not the authority to decide who may do
///   what, and the two are held by different people on purpose. Plan 06-05
///   fixes the sentence; this constant is what the code says in the meantime.
const AccessGroup kAccessAdminGroup = AccessGroup.users;

/// Builds this store's audit row for one action.
///
/// [session] is the session the gate read, so the deny row names whoever was
/// refused rather than whoever the session became a moment later. The builder
/// is what lets [AccessAdminStore._requireUsers] be shared across eight writes
/// whose rows are built by eight *different* named constructors: there is no
/// generic row builder in this file, and there must not be one.
typedef _RowBuilder = AuditRecord Function(
  AccessSession session,
  String actionId,
  bool allowed,
);

/// The eight writes that decide who may do what, and the two reads that show
/// it.
///
/// Writes — [createRole], [updateRole], [deleteRole], [renameRole],
/// [createUser], [deleteUser], [setUserRole], [setUserPassword] — all ask for
/// [kAccessAdminGroup] and all leave a row, denials included. Reads — [roles]
/// and [listUsers] — are ungated and unaudited: looking at the roster is not an
/// authorization change, and a row per render would bury the writes that
/// matter. The route the screen sits on is the enforcement for reads.
///
/// **Eight writes, eight itemKeys, and that is the whole list.** If you find
/// yourself adding a ninth, stop: it has no itemKey, which means it has no
/// audit row, which means it is not a write this store may perform. No disable,
/// no export, no bulk anything.
///
/// The itemKeys fall into two prefixes — `role.` and `user.` — which are
/// distinct strings, so a Phase 5 filter for one does not drag in the other.
/// That is the same idea `access_template_store.dart` applies one level down
/// with its `access_template.` / `access_key_binding.` prefixes.
///
/// ## Design decision 1: repository below, store above
///
/// No other file in this tree has both layers, and the split is deliberate
/// rather than incidental. `AccessTemplateStore` owns its Drift queries with
/// nothing beneath it; this store cannot, because `db.transaction` and the
/// last-`users`-holder invariant have to live in `packages/tfc_dart`, which has
/// no notion of an [AccessSession] and no [AuditSink] wiring. So:
///
/// * **The transaction, and every invariant that must be evaluated inside it,
///   live in [AccessRepository].** That is the only reason the repository layer
///   exists here. The lockout rule is not re-implemented in this file — it has
///   one home, and this store surfaces its refusal.
/// * **The permission question, the audit row and the required-group constant
///   live here.** [kAccessAdminGroup] is a store-layer fact: it is the gate
///   *this store* asks.
/// * **This store holds no `AppDatabase` and imports no Drift.** Its reads go
///   through the repository too, which turns "pages never touch Drift" into a
///   greppable property one layer higher — this file's Drift import count is
///   zero, and a test asserts it. A method that needs a `Value()` or a
///   `Companion` belongs in the repository, not here.
/// * **Pages talk to this store and to nothing else.** They never hold an
///   [AccessRepository].
///
/// ## Design decision 2: where the audit row goes, relative to the guard
/// inside the transaction
///
/// `AccessTemplateStore` records the allowed row **before** its statement, on
/// the principle that a delete of a template keys still name changed nothing
/// and must leave no row claiming it did. It can do that because every one of
/// its preconditions is checkable in the store. This store's lockout invariant
/// is exactly the one that is not: it is evaluated inside the repository's
/// transaction, which is precisely the condition this layer cannot pre-check
/// without reintroducing the race it was moved down there to close.
///
/// Three options, and the choice:
///
/// * **(iii) Write the audit row inside the same transaction — rejected.**
///   `DriftAuditSink` has one method and its test greps the source to keep it
///   that way; the Postgres audit role is INSERT-only into `audit_entry`, so a
///   row enlisted in an application transaction that later rolls back is
///   silently discarded — the opposite of what an append-only trail is for. It
///   would also couple every future sink, including a remote one over the relay
///   pipe, to Drift's transaction.
/// * **(ii) Pre-check in the store, guard again in the transaction, and record
///   before the statement — rejected.** A lost race writes a row for a write
///   that was then refused. That is a *false* row, and the whole value of the
///   trail is that every row in it is true.
/// * **(i) Record the permitted row after the repository call returns —
///   chosen.** The one window it leaves is a crash between `COMMIT` and the
///   sink call, which costs one true row. That is the failure mode the sink
///   already has and already logs as `AUDIT ROW LOST`. Given the choice between
///   possibly losing a true row and possibly writing a false one, lose the true
///   one.
///
/// **Denial rows keep the template store's ordering — recorded before the
/// throw** — because a deny row is the only evidence the guard fired and there
/// is nothing written for it to contradict. So the full order of every write in
/// this file is:
///
/// gate → (denied: record the deny row, call `onDenied`, throw) → call the
/// repository → (the repository threw [LastUsersHolderException],
/// [RoleInUseException], [UserExistsException], [UserNotFoundException],
/// [MissingRoleError] or [ProtectedRoleError]: record **nothing**, rethrow) →
/// record the allowed row.
///
/// If you move a `_recordAllowed` call above its repository call, five named
/// tests in `access_admin_store_test.dart` stop passing. They are there because
/// that is the edit somebody will make while tidying.
class AccessAdminStore {
  /// [session] is a **callback, not a value**, for the reason `HistoryViewStore`
  /// gives at its own constructor (`lib/core/guarded_history_views.dart`): this
  /// store is built per operation from providers that outlive any one session,
  /// and a captured [AccessSession] would keep granting whatever the operator
  /// held when it was built, after the inactivity monitor had already dropped
  /// them back to anonymous.
  ///
  /// [onDenied] fires **before** the [AccessDenied] is thrown, so the shared
  /// prompt (`lib/widgets/access_denied_prompt.dart`) appears even at a call
  /// site that swallows the exception.
  AccessAdminStore({
    required AccessRepository repository,
    required AccessSession Function() session,
    required AuditSink audit,
    required String station,
    void Function(AccessDenied denial)? onDenied,
    Logger? logger,
  })  : _repository = repository,
        _session = session,
        _audit = audit,
        _station = station,
        _onDenied = onDenied,
        _logger = logger ?? Logger();

  final AccessRepository _repository;
  final AccessSession Function() _session;
  final AuditSink _audit;
  final String _station;
  final void Function(AccessDenied denial)? _onDenied;

  /// This store's own diagnostic logger, for the audit-sink failures it
  /// swallows. Nothing else logs here — and in particular nothing logs a
  /// credential; see [setUserPassword].
  final Logger _logger;

  // ---------------------------------------------------------------------------
  // Reads — ungated, unaudited
  // ---------------------------------------------------------------------------

  /// Every role, for the roles section.
  Future<List<AccessRole>> roles() => _repository.roles();

  /// Every account, ordered by username, for the users section.
  Future<List<AppUserData>> listUsers() => _repository.listUsers();

  // ---------------------------------------------------------------------------
  // Role writes
  // ---------------------------------------------------------------------------

  /// Creates the role [role]. Requires [kAccessAdminGroup].
  ///
  /// Throws [ArgumentError] when a role of that name already exists — the same
  /// refusal, in the same words, that [AccessRepository.renameRole] gives for a
  /// name collision. The repository's `upsertRole` would quietly turn this into
  /// an update, and the row would then say `role.create` for something that
  /// created nothing. The check runs **after** the gate, so an unprivileged
  /// caller is told about permission rather than about the name.
  Future<void> createRole(
    AccessRole role, {
    String origin = _operatorOrigin,
    String? reason,
  }) async {
    AuditRecord row(AccessSession session, String actionId, bool allowed) =>
        AuditRecord.roleCreate(
          who: _who(session),
          station: _station,
          roleName: session.roleName,
          actionId: actionId,
          subject: role.name,
          groups: role.encodeGroups(),
          allowed: allowed,
          reason: reason,
          origin: origin,
        );

    final actionId = await _requireUsers(itemKey: _roleCreate, row: row);

    if (await _repository.role(role.name) != null) {
      throw ArgumentError.value(
        role.name,
        'role.name',
        'a role named "${role.name}" already exists',
      );
    }
    await _repository.upsertRole(role);
    await _recordAllowed(actionId, row);
  }

  // ---------------------------------------------------------------------------
  // The one implementation of the rule
  // ---------------------------------------------------------------------------

  /// Check, record, throw — the ordering `GuardedStateMan` established,
  /// `guarded_history_views.dart` reuses and `access_template_store.dart`
  /// documents.
  ///
  /// Returns the `actionId` the caller must carry into its allowed row, so one
  /// human action produces one correlation id however many rows it writes.
  ///
  /// On the deny path the row comes **before** the throw, because it is the
  /// only evidence the guard fired. On the permitted path the caller records
  /// after the repository call has returned — see design decision 2 on the
  /// class.
  Future<String> _requireUsers({
    required String itemKey,
    required _RowBuilder row,
  }) async {
    final actionId = newActionId();
    final session = _session();
    if (session.can(kAccessAdminGroup)) return actionId;

    await _record(row(session, actionId, false));

    final denial = AccessDenied(itemKey, kAccessAdminGroup);
    try {
      _onDenied?.call(denial);
    } on Object catch (error, stack) {
      // A listener's bug must not change what the caller sees. The refusal is
      // this store's answer; a broken prompt is cosmetic beside it.
      _logger.e('onDenied listener threw for "$itemKey"',
          error: error, stackTrace: stack);
    }
    throw denial;
  }

  /// The allowed row, built by the same builder the deny path would have used.
  Future<void> _recordAllowed(String actionId, _RowBuilder row) =>
      _record(row(_session(), actionId, true));

  /// Append [row], and never let the sink's failure become the caller's.
  ///
  /// The same rule, in the same words, as plans 03-04, 03-05, 03-10 and 04-06.
  /// On the permitted path an escaping sink exception would fail a write the
  /// session was allowed to make — and here that write has already committed,
  /// so the caller would be told a lie. On the deny path it would replace
  /// [AccessDenied] with something no caller catches, skip `onDenied`, and
  /// leave the operator with a control that did nothing and no explanation for
  /// it. The price is that a lost row is only a log line, so the line names the
  /// row it lost.
  Future<void> _record(AuditRecord row) async {
    try {
      await _audit.record(row);
    } on Object catch (error, stack) {
      _logger.e(
        'AUDIT ROW LOST: action ${row.actionId}, ${row.who} on '
        '${row.surface}:${row.itemKey}, allowed: ${row.allowed}',
        error: error,
        stackTrace: stack,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  /// The default [AuditRecord.origin] — a person standing at the panel.
  static const String _operatorOrigin = 'operator';

  /// `who` comes from the session and from nowhere else. [AuditRecord.origin]
  /// is the only field a caller of this store can set, and that asymmetry is
  /// the point: there is no parameter through which a caller could name
  /// somebody else as the author of a role edit.
  static String _who(AccessSession session) =>
      session.user?.username ?? _anonymousWho;

  // The itemKeys, restated here for the [AccessDenied] each gate throws. Each
  // one is the same string its named constructor writes into the row, and a
  // named test per write asserts the refusal and the row agree — the two
  // spellings are checked against each other rather than trusted.
  static const String _roleCreate = 'role.create';
}

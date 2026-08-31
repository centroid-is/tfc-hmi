/// The administration page's users section — 06-CONTEXT "Users Screen".
///
/// A roster of accounts with the four columns `AppUser` actually has, four
/// capabilities and no fifth, and the two lockout routes that run through this
/// table refused where the operator can read why. Composed onto a page beside
/// the roles section; this file renders a card and owns no route.
///
/// ## Four columns, and every one of them a real column
///
/// Username, role, created, last login. Those are the four `AppUser` carries
/// (`database_drift.dart`), and the list shows exactly them. A display name is
/// a schema v7 → v8 migration for cosmetics and 06-CONTEXT declines it; so is a
/// `disabled` flag, which is why there is no disable here either — it would be
/// a migration *plus* a change to the login path. What the screen can do is
/// create an account, change its role, reset its password and delete it.
///
/// ## The one rule this file has that the roles section does not
///
/// `access_templates_section.dart`'s `_showProblem` renders the exception in a
/// snackbar, and that is right almost everywhere. It is not right in the two
/// dialogs here that take a typed password. `lib/pages/first_user.dart` refuses
/// to do it on exactly that screen and says why: an `ArgumentError` raised on a
/// bad credential can carry the credential in its message, and a screen where
/// the password is in hand would then put it into a screenshot of a
/// commissioning session. 06-02 made `AccessRepository` throw a bare
/// `ArgumentError` without the value for that reason, and defence in depth here
/// costs one `catch` clause.
///
/// So, explicitly:
///
///  * **The create dialog and the set-password dialog** follow
///    `first_user.dart`: the failure goes to `Logger().e` with a fixed message
///    and the screen shows a fixed sentence of its own. Neither ever renders an
///    exception object.
///  * **Everywhere else in this file** — the role change and the delete, which
///    never hold a credential — uses `_showProblem`, the shared shape the rest
///    of the milestone uses.
///
/// Nothing in this file reads, passes, logs or renders a stored hash or its
/// salt. The password travels from a controller straight to the store and stops
/// there.
///
/// ## Usernames are compared exactly
///
/// `app_user.username` is a case-sensitive TEXT primary key and
/// `AccessRepository.user` documents why: case-folding means picking a locale,
/// and Turkish dotted I turns a login screen into a support call. Nothing in
/// this file folds a username — the duplicate check in the create dialog
/// compares exactly, so a dialog cannot refuse a name the database would have
/// accepted.
///
/// ## A user write is not finished when the row is written
///
/// `ref.invalidate(accessAdminUsersProvider)` refreshes the *roster*. What the
/// running app permits is re-resolved by
/// `AccessSessionController.refreshGroupsFromRoles`, and this section calls it
/// after **every** `setUserRole` and **every** `deleteUser` — never inside an
/// "is this the signed-in account?" conditional. With two `users` holders the
/// invariant permits an admin to move their own account onto a role without
/// `users`, or to delete it outright, and without the call they keep the groups
/// that account gave them until they sign out. That is privilege retention in
/// the phase whose job is administering privileges (T-06-77).
///
/// `createUser` and `setUserPassword` do **not** get the call: a new account
/// holds no session and a password change alters no privilege, so neither can
/// change the caller's own groups.
///
/// **That call goes last, and the ordering is load-bearing.** See [_afterWrite].
///
/// ## The refusal, and the trail
///
/// Trip routes (a) and (b) — deleting the last `users` holder, and moving them
/// onto a role that does not grant it — are refused by `AccessRepository`
/// inside the transaction that would otherwise perform the write. That rule is
/// **not** re-implemented here; this section renders what the transaction threw,
/// through the shared `AccessAdminRefusal`, so its wording and the roles
/// section's cannot drift. There is no override, and none may be added.
///
/// Deleting an account does not touch its audit rows. `audit_entry.who` is a
/// denormalised TEXT column with no foreign key, so the trail outlives the
/// account by construction — and because the obvious assumption is the
/// opposite, the delete confirmation says so out loud.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
import 'package:tfc_dart/core/database_drift.dart' show AppUserData;

import '../core/access_admin_store.dart';
import '../providers/access.dart';
import '../providers/access_admin.dart';
import '../widgets/access_admin_notice.dart';
import '../widgets/panes/pane_chrome.dart';
import '../widgets/panes/standard_dialog.dart';

// ---------------------------------------------------------------------------
// Copy
//
// Kept at the top of the file, in the `access_gate.dart` /
// `access_templates_section.dart` idiom, so the tests assert against the string
// the widget renders rather than one they supply.
// ---------------------------------------------------------------------------

/// The section's title.
const String kAccessUsersHeadline = 'Accounts';

/// One line under the title. Says what an account is and what holding one
/// means, before a list of names arrives.
const String kAccessUsersSubtitle =
    'An account is a username, a password and exactly one role. What it may do '
    'is whatever that role grants, and changing the role changes it at once.';

/// The read failed, or the store could not be built.
///
/// Says the roster is untrustworthy rather than that there are no accounts:
/// people are still signed in against rows this station currently cannot read,
/// and an empty list here would be a claim about the table it cannot make.
const String kAccessUsersUnavailableNote =
    'The accounts could not be read. Anybody already signed in stays signed in, '
    'but this list may be out of date.';

/// No database — which is **not** "no accounts".
///
/// Names no cause, for the reason `kAccessTemplatesNoDatabaseNote` gives: a
/// station that was never configured and one whose Postgres will not answer are
/// the same resolved null from here, and the next step is the same either way.
const String kAccessUsersNoDatabaseNote =
    'Accounts live in the database, and this station has no reachable one — so '
    'this is "cannot tell you", not "there are none". The connection is set up '
    'in Server Config.';

/// A database that answered, with nothing in `app_user`.
///
/// Deliberately not "no users yet". An empty account table is the state in
/// which the first-user window stands open, and a freshly deployed station is
/// then claimable by whoever reaches it first — which is a far more urgent fact
/// than the absence of a list. `first_user.dart` says the same thing on the
/// screen that acts on it.
const String kAccessUsersEmptyNote =
    'No accounts at all, which means the first-user window is still open: this '
    'station is claimable by whoever reaches the first-account screen first. '
    'Create the first account now, at commissioning.';

/// The four column headings, as constants so a test asserts the heading the
/// screen renders.
const String kAccessUsersColumnUsername = 'Username';
const String kAccessUsersColumnRole = 'Role';
const String kAccessUsersColumnCreated = 'Created';
const String kAccessUsersColumnLastLogin = 'Last login';

/// What stands in for a null `lastLoginAt`.
///
/// A word rather than an empty cell. An account that has never been used is a
/// fact worth seeing — a stale commissioning account nobody signs into is
/// exactly what a roster is read to find — and a blank cell reads as a
/// rendering bug.
const String kAccessUserNever = 'never';

/// A timestamp as this repo already renders one.
///
/// `yyyy-MM-dd HH:mm` through `intl`, the pattern `plc_detail_panel.dart` and
/// `tech_doc_library_section.dart` already use; no new dependency and no fourth
/// spelling of a date. Local time, because the person reading it is standing in
/// front of the panel.
String kAccessUserWhen(DateTime? at) => at == null
    ? kAccessUserNever
    : DateFormat('yyyy-MM-dd HH:mm').format(at.toLocal());

/// The change-role dialog's title.
String kAccessUserRoleDialogTitle(String username) =>
    'Move "$username" to another role';

/// The change-role dialog's affirmative. Says what happens rather than "OK".
const String kAccessUserRoleConfirmLabel = 'Move';

/// One line in the change-role dialog. States the consequence, which is
/// immediate and is the whole reason this screen is gated.
const String kAccessUserRoleDialogNote =
    'The account holds exactly one role. Moving it changes what that person may '
    'do the moment it is saved, without them signing out and back in.';

/// The picker had nothing to offer. Should not be reachable — the migration
/// seeds four roles — so it says that rather than pretending it is normal.
const String kAccessUserRoleDialogEmptyNote =
    'No roles could be read, so there is nothing to move this account onto. '
    'The roles section above says why.';

/// What a role grants, by [AccessGroupInfo.label] and in [AccessGroup.values]
/// order, so two roles granting the same set read identically.
String kAccessUserRoleGrants(Set<AccessGroup> groups) => groups.isEmpty
    ? 'Grants nothing'
    : AccessGroup.values.where(groups.contains).map((g) => g.label).join(' · ');

/// The delete confirmation's title.
String kAccessUserDeleteTitle(String username) => 'Delete "$username"?';

/// The delete confirmation's body.
///
/// It states that the audit history is **not** deleted with the account,
/// because the obvious assumption is the opposite and the property is worth
/// telling the operator: `audit_entry.who` is denormalised TEXT with no foreign
/// key, so the trail survives by construction and no cascade may ever be added.
String kAccessUserDeleteMessage(String username) =>
    'The account "$username" is removed and signing in as "$username" stops '
    'working immediately. Everything it did stays in the audit trail — deleting '
    'an account does not delete its history.';

/// The delete confirmation's affirmative.
const String kAccessUserDeleteConfirmLabel = 'Delete account';

/// The roster was stale: somebody else removed the account between this list
/// being read and the write being attempted.
///
/// A fixed sentence rather than the exception, and it names the account so the
/// operator knows which row went away under them.
String kAccessUserVanishedNote(String username) =>
    'There is no account named "$username" any more — somebody else removed it. '
    'The list has been refreshed.';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// The section itself, so a test can tell "rendered nothing" from "rendered an
/// empty roster".
const Key kAccessUsersSectionKey = Key('access-users-section');

/// The could-not-read line.
const Key kAccessUsersUnavailableKey = Key('access-users-unavailable');

/// The no-database line.
const Key kAccessUsersNoDatabaseKey = Key('access-users-no-database');

/// The nothing-at-all line, which is a different claim from the one above.
const Key kAccessUsersEmptyKey = Key('access-users-empty');

/// The column headings row.
const Key kAccessUsersHeaderKey = Key('access-users-header');

/// One account's row.
Key kAccessUserRowKey(String username) => Key('access-user-row-$username');

/// The four cells, one key each, so a test asserts the *column* rather than
/// some text that happens to be on screen.
Key kAccessUserNameKey(String username) => Key('access-user-name-$username');
Key kAccessUserRoleKey(String username) => Key('access-user-role-$username');
Key kAccessUserCreatedKey(String username) =>
    Key('access-user-created-$username');
Key kAccessUserLastLoginKey(String username) =>
    Key('access-user-last-login-$username');

/// One account's change-role control.
Key kAccessUserChangeRoleKey(String username) =>
    Key('access-user-change-role-$username');

/// One account's delete control.
Key kAccessUserDeleteKey(String username) =>
    Key('access-user-delete-$username');

/// One role in the picker. A function of the role name, following
/// `access_templates_section.dart`'s discipline: a test asserts that *this*
/// role was offered, not that some row at some index was.
Key kAccessUserRoleChoiceKey(String roleName) =>
    Key('access-user-role-choice-$roleName');

/// The change-role dialog's confirming action.
const Key kAccessUserRoleConfirmKey = Key('access-user-role-confirm');

// ---------------------------------------------------------------------------
// The section
// ---------------------------------------------------------------------------

/// The account roster and the controls that change one.
///
/// A [ConsumerWidget] with no state of its own: the accounts come from
/// `accessAdminUsersProvider`, the roles the picker offers from
/// `accessAdminRolesProvider`, and every change goes through
/// [AccessAdminStore] and then invalidates the roster. A row keeps its own
/// refusal — see [_UserTile].
///
/// It is deliberately unbounded and unscrolled, and there is no search field
/// and no sort control: a station has a handful of accounts, and the page
/// composing this section owns the scroll view.
class AccessUsersSection extends ConsumerWidget {
  const AccessUsersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(accessAdminStoreProvider);

    // Nothing while the store handle resolves. Not a spinner: this is one
    // section on a page that owns its own loading affordance, and a spinner
    // that appears for a frame on every station is the flash `AccessLockBadge`
    // and `AccessStatusAction` both refuse to draw.
    if (!storeAsync.hasValue && !storeAsync.hasError) {
      return const SizedBox.shrink();
    }

    if (storeAsync.hasError) {
      return _frame(
        context,
        child: _note(context, kAccessUsersUnavailableNote,
            key: kAccessUsersUnavailableKey),
      );
    }

    final store = storeAsync.requireValue;
    if (store == null) {
      return _frame(
        context,
        child: _note(context, kAccessUsersNoDatabaseNote,
            key: kAccessUsersNoDatabaseKey),
      );
    }

    final usersAsync = ref.watch(accessAdminUsersProvider);
    if (!usersAsync.hasValue && !usersAsync.hasError) {
      return const SizedBox.shrink();
    }
    if (usersAsync.hasError && !usersAsync.hasValue) {
      return _frame(
        context,
        child: _note(context, kAccessUsersUnavailableNote,
            key: kAccessUsersUnavailableKey),
      );
    }

    final users = usersAsync.requireValue;

    // The roles the picker may offer. Read once for the whole section rather
    // than per row, and empty rather than null when the roster of roles cannot
    // be read — the picker then says so instead of offering nothing without
    // explanation.
    final roles =
        ref.watch(accessAdminRolesProvider).valueOrNull ?? const <AccessRole>[];

    return _frame(
      context,
      child: users.isEmpty
          ? _note(context, kAccessUsersEmptyNote, key: kAccessUsersEmptyKey)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                for (final user in users)
                  _UserTile(
                    // Keyed by username so a row keeps its inline refusal
                    // across the rebuild every write triggers.
                    key: ValueKey('access-user-${user.username}'),
                    user: user,
                    roles: roles,
                    store: store,
                  ),
              ],
            ),
    );
  }

  /// The card and its header.
  Widget _frame(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      key: kAccessUsersSectionKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.people_outline,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(kAccessUsersHeadline,
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _note(context, kAccessUsersSubtitle),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  /// The four column headings, in the order the cells render them.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      key: kAccessUsersHeaderKey,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              flex: _kNameFlex,
              child: Text(kAccessUsersColumnUsername, style: style)),
          Expanded(
              flex: _kRoleFlex,
              child: Text(kAccessUsersColumnRole, style: style)),
          Expanded(
              flex: _kWhenFlex,
              child: Text(kAccessUsersColumnCreated, style: style)),
          Expanded(
              flex: _kWhenFlex,
              child: Text(kAccessUsersColumnLastLogin, style: style)),
          const SizedBox(width: _kActionsWidth),
        ],
      ),
    );
  }
}

/// The column widths, declared once so the headings and the cells cannot drift
/// apart.
const int _kNameFlex = 3;
const int _kRoleFlex = 3;
const int _kWhenFlex = 3;
const double _kActionsWidth = 96;

// ---------------------------------------------------------------------------
// One row
// ---------------------------------------------------------------------------

/// One account: four cells, the controls that change it, and the refusal the
/// last attempt came back with.
class _UserTile extends ConsumerStatefulWidget {
  const _UserTile({
    super.key,
    required this.user,
    required this.roles,
    required this.store,
  });

  final AppUserData user;

  /// Every role the picker may offer, from `accessAdminRolesProvider`, so it
  /// cannot offer one that does not exist.
  final List<AccessRole> roles;

  final AccessAdminStore store;

  @override
  ConsumerState<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends ConsumerState<_UserTile> {
  /// The lockout refusal the last write came back with, rendered inline in
  /// place of a snackbar so the operator can read the holders' names without
  /// racing something that disappears.
  ///
  /// The rule it reports is **not** re-implemented here. It lives in
  /// `AccessRepository`, inside the transaction that would otherwise perform
  /// the write; this field only holds what that transaction threw.
  LastUsersHolderException? _refusal;

  /// Re-entry guard. Deliberately not rendered as a disabled button: a control
  /// this file draws is never greyed for lack of a permission, and a second tap
  /// during the round trip is simply ignored.
  bool _busy = false;

  AppUserData get user => widget.user;

  @override
  Widget build(BuildContext context) {
    final refusal = _refusal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: kAccessUserRowKey(user.username),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                flex: _kNameFlex,
                child: Text(user.username, key: kAccessUserNameKey(user.username)),
              ),
              Expanded(
                flex: _kRoleFlex,
                child: Text(user.roleName, key: kAccessUserRoleKey(user.username)),
              ),
              Expanded(
                flex: _kWhenFlex,
                child: Text(kAccessUserWhen(user.createdAt),
                    key: kAccessUserCreatedKey(user.username)),
              ),
              Expanded(
                flex: _kWhenFlex,
                // Never blank: a null renders as [kAccessUserNever].
                child: Text(kAccessUserWhen(user.lastLoginAt),
                    key: kAccessUserLastLoginKey(user.username)),
              ),
              SizedBox(
                width: _kActionsWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: kAccessUserChangeRoleKey(user.username),
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      tooltip: 'Change role',
                      onPressed: _changeRole,
                    ),
                    IconButton(
                      key: kAccessUserDeleteKey(user.username),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete account',
                      onPressed: _delete,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (refusal != null) ...[
          const SizedBox(height: 4),
          // The exception goes straight to the shared widget; this file builds
          // no sentence of its own, which is what keeps this section's wording
          // and the roles section's identical.
          AccessAdminRefusal.lastUsersHolder(refusal),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// Moves the account onto another role.
  ///
  /// The ordering below is the rule, not an accident — see [_afterWrite].
  Future<void> _changeRole() async {
    if (_busy) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _RolePickerDialog(
        username: user.username,
        current: user.roleName,
        roles: widget.roles,
      ),
    );
    // Choosing the role already held writes nothing: a no-op move would still
    // leave an audit row claiming a change that did not happen.
    if (chosen == null || chosen == user.roleName || !mounted) return;

    _busy = true;
    final wrote = await _write(
      context,
      ref,
      () => widget.store.setUserRole(user.username, chosen),
      onRefused: _showRefusal,
      vanished: user.username,
    );
    _busy = false;
    if (!wrote) return;

    // Everything that needs this widget happens first…
    if (mounted) setState(() => _refusal = null);
    // …and the session refresh last, because it can unmount this subtree. It is
    // called for **every** move, not only the caller's own: a call site
    // conditional on "is this me?" is a call site that gets the comparison
    // wrong once and then holds a stale privilege forever (T-06-77).
    await _afterWrite(ref);
  }

  /// Deletes the account, after a confirmation that says the trail survives.
  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: kAccessUserDeleteTitle(user.username),
      message: kAccessUserDeleteMessage(user.username),
      confirmLabel: kAccessUserDeleteConfirmLabel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    _busy = true;
    final wrote = await _write(
      context,
      ref,
      () => widget.store.deleteUser(user.username),
      onRefused: _showRefusal,
      vanished: user.username,
    );
    _busy = false;
    if (!wrote) return;

    // Nothing else needs this widget: `_write` has already invalidated the
    // roster and `showConfirmDialog` popped itself before the write began…
    //
    // …so the session refresh is all that is left, and it goes last. A
    // self-delete drops the session to anonymous while this callback is still
    // running, and the page above is `users`-gated — the section is unmounted
    // mid-await, which is a non-event precisely because nothing follows.
    // Unconditional, for the same reason as in [_changeRole] (T-06-77).
    await _afterWrite(ref);
  }

  /// Renders the transaction's refusal beside the row that caused it.
  void _showRefusal(Object refusal) {
    if (refusal is LastUsersHolderException && mounted) {
      setState(() => _refusal = refusal);
    }
  }
}

// ---------------------------------------------------------------------------
// The write path
// ---------------------------------------------------------------------------

/// Runs one store write and refreshes the roster.
///
/// ## The `AccessDenied` arm — read this once, it is referenced by the rest
///
/// A refusal is **not handled here**, on purpose. [AccessAdminStore] calls
/// `onDenied` before it throws, which publishes onto `accessDenialsProvider`,
/// which is what `AccessDeniedPrompt` is already listening to — so by the time
/// this catch runs, the prompt naming the `users` group is on screen. A message
/// of this file's own would be two things saying one thing, and they would
/// drift the first time the wording changed. So: swallow, change nothing, and
/// do not refresh — nothing moved.
///
/// Copied from `access_templates_section.dart` with its doc, rather than
/// rewritten "better": that file is the reference the rest of the milestone
/// points back to, and a second variant is a second behaviour. The roles
/// section holds its own copy for the same reason; hoisting the two into a
/// shared file is not this plan's to do.
///
/// ## The two arms above `on Object`
///
/// [LastUsersHolderException] is neither an `AccessDenied` nor an ordinary
/// failure. No sign-in resolves it — the account that hits it already holds
/// `users` — so it must not reach the shared prompt, and a snackbar would put
/// the holders' names in something that disappears while they are being read.
/// [onRefused] hands it to the row that caused it.
///
/// [UserNotFoundException] means the roster was stale: somebody else removed
/// the account between this list being read and the write being attempted. The
/// list is refreshed and a **fixed sentence** naming the account is shown —
/// never the exception, which is a habit worth keeping in a file where two
/// other paths hold a credential.
Future<bool> _write(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() write, {
  void Function(Object refusal)? onRefused,
  String? vanished,
}) async {
  try {
    await write();
  } on LastUsersHolderException catch (refusal) {
    if (onRefused != null) {
      onRefused(refusal);
    } else if (context.mounted) {
      _showProblem(context, refusal);
    }
    return false;
  } on UserNotFoundException {
    ref.invalidate(accessAdminUsersProvider);
    if (context.mounted && vanished != null) {
      _showMessage(context, kAccessUserVanishedNote(vanished));
    }
    return false;
  } on AccessDenied {
    return false;
  } on Object catch (error) {
    // Not an authorization event and not a credential path — a role that went
    // away underneath us, a database that stopped answering mid-write. The
    // operator gets the reason rather than a control that did nothing.
    if (context.mounted) _showProblem(context, error);
    return false;
  }
  // There is no listener over `app_user` and nothing else notices. This
  // invalidate is the single refresh trigger for the roster.
  ref.invalidate(accessAdminUsersProvider);
  return true;
}

/// Re-resolves the session in force against the rows that were just written.
///
/// **This is the last thing any write path does, and the ordering is the rule.**
///
/// Invalidate the roster, close whatever dialog is open and finish every
/// `setState` **before** awaiting this; guard anything that must happen after
/// it with `context.mounted`. The reason is that this section can unmount
/// itself mid-await. Deleting the caller's own account, or moving it onto a
/// role without `users`, is *permitted* whenever a second holder remains — only
/// the last-holder case throws — so the refresh drops the caller below the
/// `users` gate while this widget is still inside its own async callback. The
/// page is `users`-gated, so `AccessGate` swaps the subtree out and the section
/// is disposed; a `ref.invalidate`, a `setState` or a `ScaffoldMessenger` call
/// sequenced after this would then run on a disposed element.
///
/// Doing it **last** makes the unmount a non-event: everything that needed the
/// widget has already happened, and the one thing left is the session drop,
/// which is the point of the call. Nothing in this file touches `ref` or
/// `context` after awaiting it.
///
/// It is called after **every** `setUserRole` and **every** `deleteUser`, and
/// never inside an "is this the signed-in account?" conditional. Such a
/// conditional would make a lifecycle exception go away by not making the call,
/// and the call is the only thing that stops an admin who has just demoted
/// themselves from keeping the groups they removed — T-06-77, which fails open.
///
/// The other half of the fix is in `refreshGroupsFromRoles` itself: its
/// elevated arm re-reads the `app_user` row, so a changed `role_name` is
/// observed and a vanished row drops the session to anonymous. The call here is
/// useless without that, and 06-04 specifies it.
///
/// The notifier is read synchronously, before the await, so a caller that is
/// disposed by the refresh never reaches back into `ref`.
Future<void> _afterWrite(WidgetRef ref) {
  final controller = ref.read(accessSessionProvider.notifier);
  return controller.refreshGroupsFromRoles();
}

/// A snackbar carrying the failure.
///
/// **This is the everywhere-else arm of the rule in the library doc.** It is
/// used by the role change and the delete, neither of which ever holds a
/// credential. The create and set-password dialogs must not reach it — see
/// their own docs.
void _showProblem(BuildContext context, Object error) {
  _showMessage(context, '$error');
}

/// A snackbar carrying a sentence this file wrote.
void _showMessage(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// Pick the role an account holds.
///
/// The choices are the roles the store returned and nothing else: a picker that
/// could offer a role that does not exist would produce an account pointing at
/// a missing row, which the repository refuses anyway — but refusing it after a
/// dialog closed is worse than not offering it (T-06-76).
///
/// It returns the chosen name and performs no write. The row does that, so the
/// refusal it can come back with is rendered beside the row rather than in
/// something that closes.
class _RolePickerDialog extends StatefulWidget {
  const _RolePickerDialog({
    required this.username,
    required this.current,
    required this.roles,
  });

  final String username;
  final String current;
  final List<AccessRole> roles;

  @override
  State<_RolePickerDialog> createState() => _RolePickerDialogState();
}

class _RolePickerDialogState extends State<_RolePickerDialog> {
  late String _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    return StandardDialogFrame(
      title: kAccessUserRoleDialogTitle(widget.username),
      showClose: false,
      actions: [
        PaneAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PaneAction.primary(
          label: kAccessUserRoleConfirmLabel,
          buttonKey: kAccessUserRoleConfirmKey,
          onPressed: () => Navigator.of(context).pop(_selected),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _note(context, kAccessUserRoleDialogNote),
          const SizedBox(height: 8),
          if (widget.roles.isEmpty)
            _note(context, kAccessUserRoleDialogEmptyNote),
          for (final role in widget.roles)
            ListTile(
              key: kAccessUserRoleChoiceKey(role.name),
              dense: true,
              contentPadding: EdgeInsets.zero,
              selected: role.name == _selected,
              leading: Icon(
                role.name == _selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              title: Text(role.name),
              // What the role grants, by label rather than by the persisted
              // identifier: 06-01 exists because two of the seven group names
              // tell a commissioning engineer nothing on their own.
              subtitle: Text(kAccessUserRoleGrants(role.groups)),
              onTap: () => setState(() => _selected = role.name),
            ),
        ],
      ),
    );
  }
}

/// A secondary line, never ellipsised. Every explanatory sentence in this file
/// goes through here so none of them can quietly become one clipped line —
/// `find.text` passing is not the same as the operator being able to read it.
Widget _note(BuildContext context, String text, {Key? key}) {
  final theme = Theme.of(context);
  return Text(
    text,
    key: key,
    maxLines: null,
    overflow: TextOverflow.visible,
    style: theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
  );
}

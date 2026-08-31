/// The administration page's roles section — 06-CONTEXT "Roles Screen".
///
/// A list of roles, an editor with one labelled checkbox per group, and two
/// refusals that offer no way past themselves. Composed onto a page beside the
/// users section; this file renders a card and owns no route.
///
/// ## It is `users`-gated, and the gate is not in this file
///
/// Every write goes through [AccessAdminStore], which asks for
/// [kAccessAdminGroup] and records the answer either way. There is no second
/// path and no second gate. What this widget owes is legibility **before** the
/// operator presses anything, in the shape this milestone has used everywhere
/// else: visible, tappable, explained, never greyed. A control is not disabled
/// because the session may not use it — it is pressed, and the shared
/// `AccessDeniedPrompt` says which group to go and get.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';

import '../core/access_admin_store.dart';
import '../providers/access_admin.dart';
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
const String kAccessRolesHeadline = 'Roles';

/// One line under the title. Says what a role is before a list of names
/// arrives, and names the two things a row carries: a set of groups, and the
/// accounts holding it.
const String kAccessRolesSubtitle =
    'A role is a name and the permission groups it grants. Every account holds '
    'exactly one, and a panel with nobody signed in holds "Operator".';

/// The read failed, or the store could not be built.
///
/// Says the list is untrustworthy rather than that there are no roles: the
/// guards on the panel are still resolving against whatever the session already
/// holds, and an empty list here would be a claim about the tables that this
/// station cannot currently make.
const String kAccessRolesUnavailableNote =
    'The roles could not be read. Whatever the panel already resolved is still '
    'in force, but this list may be out of date.';

/// No database — which is **not** "no roles".
///
/// Names no cause, for the reason `kAccessTemplatesNoDatabaseNote` gives: a
/// station that was never configured and one whose Postgres will not answer are
/// the same resolved null from here, and the next step is the same either way.
const String kAccessRolesNoDatabaseNote =
    'Roles live in the database, and this station has no reachable one — so '
    'this is "cannot tell you", not "there are none". The connection is set up '
    'in Server Config.';

/// A database that answered, with nothing in it.
///
/// Deliberately not "no roles yet". The schema-v6 migration seeds four, and
/// `Operator` cannot be deleted, so an empty list is not a state a commissioned
/// station reaches — it means the migration did not run, or something emptied
/// the table underneath.
const String kAccessRolesEmptyNote =
    'No roles at all, which should not be possible: a migrated database is '
    'seeded with four and "Operator" cannot be deleted. Check that the '
    'database this station is pointed at is the one that was migrated.';

/// `n account` / `n accounts`, with the number in the sentence.
///
/// Local rather than shared with `access_admin_notice.dart`'s private helper of
/// the same shape: this one is part of a row's summary, that one is part of a
/// refusal, and a single helper across two files would be one import for one
/// pluralisation.
String _accounts(int n) => '$n account${n == 1 ? '' : 's'}';

/// A role's one-line summary: what it grants, and how many accounts hold it.
///
/// The groups read by [AccessGroupInfo.label] and in [AccessGroup.values]
/// order, so two roles granting the same set read identically. [holders] is
/// null when the roster could not be read — the count is then omitted rather
/// than rendered as zero, because "nobody holds it" is a claim and "cannot
/// tell" is not.
String kAccessRoleSummary(Set<AccessGroup> groups, int? holders) {
  final grants = groups.isEmpty
      ? 'Grants nothing'
      : AccessGroup.values.where(groups.contains).map((g) => g.label).join(' · ');
  if (holders == null) return grants;
  return '$grants — held by ${_accounts(holders)}';
}

/// Beside the protected row's name, so the row is legible as the anonymous
/// identity rather than merely as the row with no controls.
const String kAccessRoleAnonymousTag = 'Logged-out panels';

/// Shown in the create dialog. A role with no groups grants nothing, and saying
/// so beats somebody moving an account onto it and wondering why every control
/// stayed locked.
const String kAccessRoleNewNote =
    'A new role grants nothing until a group is ticked, and nobody holds it '
    'until an account is moved onto it.';

/// The name was blank, padded, or too long for the column.
const String kAccessRoleInvalidNameNote =
    'Use a name with no leading or trailing spaces, at most 64 characters.';

/// A role of that name is already there. Caught here so the store is never
/// called with a name that cannot succeed.
const String kAccessRoleDuplicateNameNote =
    'A role with that name already exists.';

/// The name is a capitalisation of the protected name.
///
/// Refused here rather than left to the repository, which guards its own delete
/// and rename but lets a *second* row take a case variant of the name. Such a
/// row would render with no Rename and no Delete — [isProtectedRoleName] is
/// case-insensitive — and nothing on this screen could then remove it.
const String kAccessRoleProtectedNameNote =
    '"Operator" is the role a panel with nobody signed in resolves to, so no '
    'other role may take that name in any capitalisation.';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// The section itself, so a test can tell "rendered nothing" from "rendered an
/// empty list".
const Key kAccessRolesSectionKey = Key('access-roles-section');

/// The could-not-read line.
const Key kAccessRolesUnavailableKey = Key('access-roles-unavailable');

/// The no-database line.
const Key kAccessRolesNoDatabaseKey = Key('access-roles-no-database');

/// The nothing-at-all line, which is a different claim from the one above.
const Key kAccessRolesEmptyKey = Key('access-roles-empty');

/// The create control. Present and enabled for every session that has a table
/// to create into.
const Key kAccessRolesCreateKey = Key('access-roles-create');

/// The name field, shared by the create and rename dialogs.
const Key kAccessRoleNameFieldKey = Key('access-role-name-field');

/// The name dialog's confirming action. One key rather than two: only one of
/// these dialogs is ever on screen.
const Key kAccessRoleNameConfirmKey = Key('access-role-name-confirm');

/// The protected row's inline banner.
///
/// Its own key rather than `kAccessAdminWarningKey`, so a test meaning "the
/// Operator banner is up" cannot pass on some other warning.
const Key kAccessOperatorWarningKey = Key('access-role-operator-warning');

/// One role's row.
Key kAccessRoleTileKey(String name) => Key('access-role-tile-$name');

/// One role's rename control. Absent on the protected row.
Key kAccessRoleRenameKey(String name) => Key('access-role-rename-$name');

/// One role's delete control. Absent on the protected row.
Key kAccessRoleDeleteKey(String name) => Key('access-role-delete-$name');

/// The protected row's marker beside its name.
const Key kAccessRoleAnonymousTagKey = Key('access-role-anonymous-tag');

/// One checkbox in one role's editor.
///
/// Keyed by role as well as by group because more than one editor may be open:
/// the tiles keep their own state and nothing here closes a sibling.
Key kAccessRoleGroupKey(String roleName, AccessGroup group) =>
    Key('access-role-group-$roleName-${group.name}');

/// One editor's Save.
Key kAccessRoleSaveKey(String name) => Key('access-role-save-$name');

/// One editor's Cancel.
Key kAccessRoleCancelKey(String name) => Key('access-role-cancel-$name');

// ---------------------------------------------------------------------------
// The section
// ---------------------------------------------------------------------------

/// The role list, the create control, and the dialogs that change a role.
///
/// A [ConsumerWidget] with no state of its own: the roles come from
/// `accessAdminRolesProvider`, the holder counts from `accessAdminUsersProvider`
/// and every change goes through [AccessAdminStore] and then invalidates both.
/// The editors keep their own draft, one per row — see [_RoleTile].
///
/// It is deliberately unbounded and unscrolled. There are four roles on a
/// seeded station and a site might add two, so there is no search box, no sort
/// control and no pagination; the page composing this section owns the scroll
/// view.
class AccessRolesSection extends ConsumerWidget {
  const AccessRolesSection({super.key});

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
        child: _note(context, kAccessRolesUnavailableNote,
            key: kAccessRolesUnavailableKey),
      );
    }

    final store = storeAsync.requireValue;
    if (store == null) {
      // No create control, and that is not a permission decision: there is no
      // table to create into. The "never greyed" rule exists so a *permission*
      // refusal is explained rather than hidden — see the note at
      // [_DeleteRoleDialog], which draws the same distinction.
      return _frame(
        context,
        child: _note(context, kAccessRolesNoDatabaseNote,
            key: kAccessRolesNoDatabaseKey),
      );
    }

    final rolesAsync = ref.watch(accessAdminRolesProvider);
    if (!rolesAsync.hasValue && !rolesAsync.hasError) {
      return const SizedBox.shrink();
    }
    if (rolesAsync.hasError && !rolesAsync.hasValue) {
      return _frame(
        context,
        onCreate: () => _create(context, ref, store, const []),
        child: _note(context, kAccessRolesUnavailableNote,
            key: kAccessRolesUnavailableKey),
      );
    }

    final roles = rolesAsync.requireValue;
    final names = [for (final role in roles) role.name];

    // The holder counts, from **one** roster read for the whole section rather
    // than a query per row. `accessAdminUsersProvider` is already loaded for
    // the users section beside this one, so on the composed page this costs
    // nothing at all. Null while it is loading or if it failed: the summary
    // then omits the count, because "nobody holds it" is a claim and "cannot
    // tell" is not.
    final roster = ref.watch(accessAdminUsersProvider).valueOrNull;
    final Map<String, int>? holders = roster == null
        ? null
        : {
            for (final role in roles)
              role.name: roster.where((u) => u.roleName == role.name).length,
          };

    return _frame(
      context,
      onCreate: () => _create(context, ref, store, names),
      child: roles.isEmpty
          ? _note(context, kAccessRolesEmptyNote, key: kAccessRolesEmptyKey)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final role in roles)
                  _RoleTile(
                    // Keyed by name so that an open editor stays open across
                    // the rebuild every write triggers — otherwise saving one
                    // role would collapse the row being edited.
                    key: ValueKey('access-role-${role.name}'),
                    role: role,
                    otherNames: [
                      for (final n in names)
                        if (n != role.name) n,
                    ],
                    holders: holders?[role.name],
                    store: store,
                  ),
              ],
            ),
    );
  }

  /// The card, its header and the create control.
  Widget _frame(
    BuildContext context, {
    required Widget child,
    VoidCallback? onCreate,
  }) {
    final theme = Theme.of(context);
    return Card(
      key: kAccessRolesSectionKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(kAccessRolesHeadline,
                      style: theme.textTheme.titleSmall),
                ),
                if (onCreate != null)
                  OutlinedButton.icon(
                    key: kAccessRolesCreateKey,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New role'),
                    onPressed: onCreate,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _note(context, kAccessRolesSubtitle),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    AccessAdminStore store,
    List<String> taken,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RoleNameDialog(
        title: 'New role',
        confirmLabel: 'Create',
        initial: '',
        taken: taken.toSet(),
        footnote: kAccessRoleNewNote,
      ),
    );
    if (name == null || !context.mounted) return;
    await _write(
      context,
      ref,
      () => store.createRole(AccessRole(name: name, groups: const {})),
    );
  }
}

// ---------------------------------------------------------------------------
// One row
// ---------------------------------------------------------------------------

/// One role: its name, what it grants, who holds it — and, when it is open, the
/// seven checkboxes.
class _RoleTile extends ConsumerStatefulWidget {
  const _RoleTile({
    super.key,
    required this.role,
    required this.otherNames,
    required this.holders,
    required this.store,
  });

  final AccessRole role;

  /// Every other role's name, for the duplicate check the rename dialog makes
  /// before the store is called.
  final List<String> otherNames;

  /// How many accounts hold this role, or null when the roster is not readable.
  final int? holders;

  final AccessAdminStore store;

  @override
  ConsumerState<_RoleTile> createState() => _RoleTileState();
}

class _RoleTileState extends ConsumerState<_RoleTile> {
  /// The editor's draft, or null while the row is closed.
  ///
  /// A local set, not a write per tick: ticking six boxes must be one audit row
  /// and one `role.update`, not six — and Cancel must be able to mean it.
  Set<AccessGroup>? _draft;

  /// Re-entry guard. Deliberately not rendered as a disabled button: a control
  /// this file draws is never greyed, and a second tap during the round trip is
  /// simply ignored.
  bool _saving = false;

  AccessRole get role => widget.role;
  AccessAdminStore get store => widget.store;

  /// The same predicate the repository uses — case-insensitive and
  /// whitespace-tolerant. A `==` against the constant here would let a row
  /// stored as `operator` render a Delete the repository would then refuse with
  /// a `ProtectedRoleError`, which is an `Error`: a screen bug, not a
  /// condition.
  bool get _protected => isProtectedRoleName(role.name);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _draft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: kAccessRoleTileKey(role.name),
          dense: true,
          contentPadding: EdgeInsets.zero,
          onTap: _toggle,
          leading: Icon(
              draft == null ? Icons.expand_more : Icons.expand_less,
              size: 18),
          title: Row(
            children: [
              Flexible(child: Text(role.name)),
              if (_protected) ...[
                const SizedBox(width: 8),
                Icon(Icons.no_accounts_outlined,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  kAccessRoleAnonymousTag,
                  key: kAccessRoleAnonymousTagKey,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          subtitle: Text(kAccessRoleSummary(role.groups, widget.holders)),
          // Neither control on the protected row: absent, not disabled. See
          // [_protected].
          trailing: _protected
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: kAccessRoleRenameKey(role.name),
                      icon: const Icon(Icons.drive_file_rename_outline,
                          size: 18),
                      tooltip: 'Rename',
                      onPressed: _rename,
                    ),
                    IconButton(
                      key: kAccessRoleDeleteKey(role.name),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete',
                      onPressed: _delete,
                    ),
                  ],
                ),
        ),
        if (draft != null) _editor(context, draft),
      ],
    );
  }

  void _toggle() => setState(() {
        if (_draft == null) {
          _draft = {...role.groups};
        } else {
          _draft = null;
        }
      });

  /// The groups, one checkbox each, plus whichever of the two notices applies.
  ///
  /// The boxes are **generated from [AccessGroup.values]** and never written
  /// out: the enum's declaration order is increasing privilege and
  /// `tfc_access/test/access_group_test.dart` pins it, so an eighth group would
  /// appear here automatically rather than silently not.
  ///
  /// Nothing here is gated. A session without `users` may open this editor and
  /// tick boxes; Save is what asks, and the refusal reaches the shared prompt —
  /// signing in from there and pressing Save again is the intended flow.
  Widget _editor(BuildContext context, Set<AccessGroup> draft) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in AccessGroup.values)
            CheckboxListTile(
              key: kAccessRoleGroupKey(role.name, group),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              // The label and the description come from 06-01's extension and
              // from nowhere else. Nothing in this file writes a group's
              // display text of its own — the UI and the MCP tools share one
              // wording, sourced from the enum's own doc comments.
              title: Text(group.label),
              subtitle: Text(group.description),
              value: draft.contains(group),
              onChanged: (ticked) => setState(() {
                if (ticked ?? false) {
                  draft.add(group);
                } else {
                  draft.remove(group);
                }
              }),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: kAccessRoleCancelKey(role.name),
                onPressed: _toggle,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: kAccessRoleSaveKey(role.name),
                onPressed: () => _save(draft),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Writes the draft as one `role.update`.
  Future<void> _save(Set<AccessGroup> draft) async {
    if (_saving) return;
    _saving = true;
    final wrote = await _write(
      context,
      ref,
      () => store.updateRole(
          AccessRole(name: role.name, groups: draft, seeded: role.seeded)),
    );
    _saving = false;
    if (!wrote) return;
    if (mounted) setState(() => _draft = null);
  }

  Future<void> _rename() async {
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _RoleNameDialog(
        title: 'Rename role',
        confirmLabel: 'Rename',
        initial: role.name,
        taken: widget.otherNames.toSet(),
      ),
    );
    if (to == null || to == role.name || !mounted) return;
    await _write(context, ref, () => store.renameRole(role.name, to));
  }

  Future<void> _delete() async {
    await _write(context, ref, () => store.deleteRole(role.name));
  }
}

// ---------------------------------------------------------------------------
// The write path
// ---------------------------------------------------------------------------

/// Runs one store write and refreshes both lists.
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
/// points back to, and a second variant is a second behaviour.
///
/// ## The two refusal arms above `on Object`
///
/// [LastUsersHolderException] and [RoleInUseException] are neither
/// `AccessDenied` nor ordinary failures. No sign-in resolves either — the
/// account that hits the first already holds `users`, and an Engineering user
/// holding every group gets the second — so they must not reach the shared
/// prompt, and a snackbar would put the holders' names in something that
/// disappears while they are being read. [onRefused] hands the exception to
/// whichever widget can render it beside the control that caused it; a caller
/// that has nowhere to put it falls back to [_showProblem], which is still
/// better than silence.
Future<bool> _write(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() write, {
  void Function(Object refusal)? onRefused,
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
  } on RoleInUseException catch (refusal) {
    if (onRefused != null) {
      onRefused(refusal);
    } else if (context.mounted) {
      _showProblem(context, refusal);
    }
    return false;
  } on AccessDenied {
    return false;
  } on Object catch (error) {
    // Not an authorization event — a duplicate name that appeared underneath
    // us, a database that went away mid-write. The operator gets the reason
    // rather than a control that did nothing.
    if (context.mounted) _showProblem(context, error);
    return false;
  }
  // There is no listener over `app_role` and nothing else notices. These two
  // invalidates are the single refresh trigger for both lists.
  ref.invalidate(accessAdminRolesProvider);
  ref.invalidate(accessAdminUsersProvider);
  return true;
}

void _showProblem(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(SnackBar(content: Text('$error')));
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// Create and rename: a name, validated before the store is asked.
///
/// The two share one widget because they differ in exactly two things — the
/// starting text and the title — following `_TemplateNameDialog`'s stated
/// reason: two nearly identical dialogs is how two validation rules start
/// disagreeing.
class _RoleNameDialog extends StatefulWidget {
  const _RoleNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.taken,
    this.footnote,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  /// Names already in use, from the loaded list. The duplicate is refused
  /// **here**, before the store is called: an exception surfaced as a snackbar
  /// after the dialog closed would make the operator retype the whole thing.
  final Set<String> taken;

  final String? footnote;

  @override
  State<_RoleNameDialog> createState() => _RoleNameDialogState();
}

class _RoleNameDialogState extends State<_RoleNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _controller.text;
    // Validation before the gate, for the reason the store checks the name
    // after it: a typo is not an authorization event, and putting a sign-in
    // prompt in front of one would teach the operator to ignore the prompt.
    if (name.trim().isEmpty || name.trim() != name || name.length > 64) {
      setState(() => _error = kAccessRoleInvalidNameNote);
      return;
    }
    if (isProtectedRoleName(name)) {
      setState(() => _error = kAccessRoleProtectedNameNote);
      return;
    }
    if (widget.taken.contains(name)) {
      setState(() => _error = kAccessRoleDuplicateNameNote);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return StandardDialogFrame(
      title: widget.title,
      showClose: false,
      actions: [
        PaneAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PaneAction.primary(
          label: widget.confirmLabel,
          buttonKey: kAccessRoleNameConfirmKey,
          onPressed: _confirm,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: kAccessRoleNameFieldKey,
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _error,
              errorMaxLines: 4,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _confirm(),
          ),
          if (widget.footnote != null) ...[
            const SizedBox(height: 12),
            _note(context, widget.footnote!),
          ],
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

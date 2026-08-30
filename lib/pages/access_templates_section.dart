/// The key repository's access-templates section — spec §7d.
///
/// MCP does the plant in a pass (spec §7c); this is where somebody works out
/// what the rules should *be*, and where the one-off change happens. Both
/// front ends edit the same two tables through the same store, and this
/// section is the one that has to make those tables legible.
///
/// ## It is `users`-gated inside a `configure`-gated route
///
/// `/advanced/key-repository` is behind `AccessGate` with `configure`, so
/// everybody who can see this section can already edit key mappings. That does
/// not mean they may re-scope authorization: spec §7c puts templates behind
/// `users` precisely so that somebody who can edit a page cannot grant
/// themselves everything. `AccessTemplateStore` enforces it — every write here
/// goes through it, and there is no other path — and this widget's job is to
/// make the boundary legible **before** the operator presses anything, in the
/// shape this milestone has used everywhere else: visible, tappable,
/// explained, never greyed.
///
/// ## Where each number comes from, and why it matters
///
/// Two different questions look identical and are not:
///
///  * **How many keys does this template govern?** — answered from
///    `TagBindingResolver.keysBoundTo`, the in-memory snapshot 04-05 loads. It
///    is a render-time number, asked once per template per frame, and asking
///    the database for it would put one round trip per template behind every
///    repaint (T-04-41's sibling).
///  * **May this template be deleted?** — answered from
///    `AccessTemplateStore.keysBoundTo`, which reads `access_key_binding`
///    directly. A decision that unrestricts keys must not rest on a snapshot
///    that may be a second stale, and the list the dialog *shows* has to be
///    the list the block *uses*, or the operator is reading one thing while
///    the store decides on another.
///
/// The delete dialog is the only place in this file that asks the database a
/// question of its own.
///
/// ## This file never writes a binding
///
/// Not on delete, not on rename, and there is deliberately no "clean up the
/// dangling keys" button. `AccessTemplateStore.bind` and `unbind` sit behind
/// the same `users` gate, so such a button would be *permitted* — which is
/// exactly why the prohibition is written down rather than assumed. Spec §7d
/// says block rather than silently unbind, and a bulk re-point after a rename
/// is the same silent change with a friendlier label. Binding is per key, on
/// the key's own card, one at a time (04-08).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_access/tfc_access.dart';

import '../core/access_template_store.dart';
import '../providers/access_templates.dart';
import '../providers/state_man.dart';
import '../widgets/panes/pane_chrome.dart';
import '../widgets/panes/standard_dialog.dart';

// ---------------------------------------------------------------------------
// Copy
//
// Kept at the top of the file, in the `access_gate.dart` / `first_user.dart`
// idiom, so the tests assert against the string the widget renders rather than
// one they supply.
// ---------------------------------------------------------------------------

/// The section's title.
const String kAccessTemplatesHeadline = 'Access templates';

/// One line under the title, so somebody who has never seen this section knows
/// what a template is for before reading a list of names.
const String kAccessTemplatesSubtitle =
    'A template says which permission each struct member of a key needs. Keys '
    'are bound to one on the key\'s own card.';

/// No database — which is **not** "no templates".
///
/// Names no cause, for the reason `kAccessLockedNoDatabaseNote` gives: a
/// station that was never configured and one whose Postgres will not answer
/// are the same resolved null from here, and the next step is the same either
/// way.
const String kAccessTemplatesNoDatabaseNote =
    'Templates live in the database, and this station has no reachable one — '
    'so this is "cannot tell you", not "there are none". Nothing is gated '
    'until it connects. The connection is set up in Server Config.';

/// A database that answered, with nothing in it. A different claim, and true.
const String kAccessTemplatesEmptyNote =
    'No templates yet. Until a key is bound to one, every key is unrestricted.';

/// The read failed. The rules already loaded stay in force (04-05 refuses to
/// drop the snapshot on a blink), so this says the list is untrustworthy
/// rather than that nothing is gated.
const String kAccessTemplatesUnavailableNote =
    'The templates could not be read. Whatever was already loaded is still in '
    'force, but this list may be out of date.';

/// A template's one-line summary: its rules, and the keys it governs.
String kAccessTemplateSummary(int rules, int keys) =>
    '${_count(rules, 'rule')} · ${_count(keys, 'key')} bound';

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// Shown in the create dialog. A template with no rules gates nothing, and
/// saying so beats a person binding keys to it and wondering why the controls
/// stayed open.
const String kAccessTemplateNewNote =
    'A new template has no rules, so it restricts nothing until one is added.';

/// The name was not one `AccessTemplate.isValidTemplateName` accepts.
const String kAccessTemplateInvalidNameNote =
    'Use a name with no leading or trailing spaces, at most 64 characters.';

/// A template of that name is already there. Caught here so the store is never
/// called with a name that cannot succeed.
const String kAccessTemplateDuplicateNameNote =
    'A template with that name already exists.';

/// The rename warning. **Do not soften this sentence.**
///
/// 04-03's store deliberately does not re-point bindings on a rename, so every
/// bound key is left naming a template that no longer exists — and 04-01's
/// resolver reports a dangling binding as *unbound*, which is fail-open. That
/// is a real, silent unrestriction, and since the 2026-08-30 ruling moved
/// bindings into their own table nothing else carries the old name and nothing
/// else will mention it. This dialog and 04-08's unbound-key surface are the
/// whole of the warning.
String kAccessTemplateRenameWarning(String from, int keys) =>
    'Renaming "$from" does not move the ${_count(keys, 'key')} bound to it. '
    'They will name a template that no longer exists, which reads as no '
    'restriction at all — so every one of them becomes unrestricted until it '
    'is bound again:';

/// The delete block (spec §7d). Says which keys, and what to do instead.
String kAccessTemplateDeleteBlockedNote(String name, int keys) =>
    'Deleting "$name" would leave the ${_count(keys, 'key')} still bound to it '
    'unrestricted, so it is not offered. Bind them to another template, or '
    'clear them, and then delete this one:';

/// Nothing is bound, so the delete costs nothing.
const String kAccessTemplateDeleteFreeNote =
    'No key is bound to this template, so deleting it changes nothing about '
    'what anybody may write.';

/// While the one database question this file asks is in flight.
const String kAccessTemplateDeleteCheckingNote =
    'Checking which keys are bound to this template…';

/// The question could not be asked. "Cannot tell" must not read as "nothing is
/// bound", so the delete is not offered here either.
const String kAccessTemplateDeleteUnknownNote =
    'Could not read which keys are bound to this template, so deleting it is '
    'not offered — it might unrestrict keys nobody can currently see.';

/// How `kWholeKeyMember` is shown to a person.
///
/// `*` is a storage sentinel, chosen because it cannot collide with an
/// IEC 61131-3 identifier. It is not a word, and a row reading "*" beside six
/// member names is the kind of thing an operator reads as a bug.
const String kWholeKeyMemberLabel = 'The whole key';

/// An expanded template with nothing in it. Says what that costs.
const String kAccessTemplateNoRulesNote =
    'No rules, so this template restricts nothing — a key bound to it stays '
    'open.';

/// Above the suggestion chips.
const String kAccessTemplateSuggestionsNote =
    'Pick a member, or type one below:';

/// No suggestions, and why. Not an error: a template written before the PLC is
/// on the network is the normal commissioning order.
const String kAccessTemplateNoSuggestionsNote =
    'No members to offer — nothing is bound to this template yet, or the bound '
    'key could not be read. Type the member name exactly as the PLC spells it.';

/// The new rule's group picker, before anything is chosen.
const String kAccessTemplateGroupHint = 'Choose the permission';

const String kAccessTemplateMemberRequiredNote =
    'Name the member, or pick one above.';

const String kAccessTemplateMemberExistsNote =
    'That member already has a rule. Change it in the list instead.';

/// Deliberately no default group. A rule that quietly defaulted to the
/// weakest permission would be a foot-gun in the one file whose whole purpose
/// is deciding what a member needs.
const String kAccessTemplateGroupRequiredNote =
    'Choose the permission this member needs.';

/// A member name as a person should read it.
String memberLabel(String member) =>
    member == kWholeKeyMember ? kWholeKeyMemberLabel : member;

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// The section itself, so a test can tell "rendered nothing" from "rendered an
/// empty list".
const Key kAccessTemplatesSectionKey = Key('access-templates-section');

/// The no-database line, so its absence and its presence are both assertable.
const Key kAccessTemplatesNoDatabaseKey = Key('access-templates-no-database');

/// The could-not-read line.
const Key kAccessTemplatesUnavailableKey =
    Key('access-templates-unavailable');

/// The create control. Present and enabled for every session.
const Key kAccessTemplatesCreateKey = Key('access-templates-create');

/// The name field, shared by the create and rename dialogs.
const Key kAccessTemplateNameFieldKey = Key('access-template-name-field');

/// The confirming action of whichever dialog is open. One key rather than
/// three: only one of these dialogs is ever on screen.
const Key kAccessTemplateConfirmKey = Key('access-template-confirm');

/// The rename dialog's warning block.
const Key kAccessTemplateRenameWarningKey =
    Key('access-template-rename-warning');

/// The delete dialog's blocked body — the keys, and why the action is absent.
const Key kAccessTemplateDeleteBlockedKey =
    Key('access-template-delete-blocked');

/// One template's row.
Key kAccessTemplateTileKey(String name) => Key('access-template-tile-$name');

/// One template's rename control.
Key kAccessTemplateRenameKey(String name) =>
    Key('access-template-rename-$name');

/// One template's delete control.
Key kAccessTemplateDeleteKey(String name) =>
    Key('access-template-delete-$name');

/// One template's "add rule" control, inside its expanded body.
Key kAccessTemplateAddRuleKey(String name) =>
    Key('access-template-add-rule-$name');

/// One rule row's group picker.
Key kAccessTemplateRuleGroupKey(String member) =>
    Key('access-template-rule-group-$member');

/// One option inside one rule row's group picker.
///
/// Keyed per member as well as per group because a `DropdownButton` keeps
/// every item in the tree (in an `IndexedStack`) whether the menu is open or
/// not, so options shared by several rows would be indistinguishable.
Key kAccessTemplateRuleGroupOptionKey(String member, AccessGroup group) =>
    Key('access-template-rule-group-$member-${group.name}');

/// One rule row's remove control.
Key kAccessTemplateRuleRemoveKey(String member) =>
    Key('access-template-rule-remove-$member');

/// One suggested member in the add-rule dialog.
Key kAccessTemplateSuggestionKey(String member) =>
    Key('access-template-suggestion-$member');

/// The add-rule dialog's member field. Free text, always.
const Key kAccessTemplateMemberFieldKey = Key('access-template-member-field');

/// The add-rule dialog's group picker.
const Key kAccessTemplateNewRuleGroupKey = Key('access-template-new-rule-group');

/// One option in the add-rule dialog's group picker.
Key kAccessTemplateNewRuleGroupOptionKey(AccessGroup group) =>
    Key('access-template-new-rule-group-option-${group.name}');

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// The tallest the template list itself is allowed to get.
///
/// Bounded because this section sits in a `Column` beside a key list that
/// takes the rest: an unbounded list of templates would push the key list off
/// a small panel. Past this it scrolls on its own.
const double kAccessTemplatesListMaxHeight = 168;

/// The tallest the whole section gets, card chrome included.
///
/// Recorded rather than used: `KeyRepositoryContent`'s
/// `kKeyRepositoryChromeHeight` is a **measured** figure for that page's whole
/// chrome, this section included, because a sum of guessed parts was how the
/// old `minContentHeight` came to be a height at which the page did not
/// actually fit. This number is here so that a later change to
/// [kAccessTemplatesListMaxHeight] carries a visible reminder that the page's
/// constant was measured with the old value.
const double kAccessTemplatesSectionMaxHeight =
    kAccessTemplatesListMaxHeight + 76;

/// The list, the create control, and the four dialogs that change a template.
///
/// A `ConsumerWidget` with no state of its own: everything it shows comes from
/// `accessTemplatesProvider` (the templates) and `tagBindingResolverProvider`
/// (which keys name them), and every change it makes goes through the store
/// and then invalidates the loader — the single refresh trigger 04-05 left.
class AccessTemplatesSection extends ConsumerStatefulWidget {
  const AccessTemplatesSection({super.key});

  @override
  ConsumerState<AccessTemplatesSection> createState() =>
      _AccessTemplatesSectionState();
}

class _AccessTemplatesSectionState
    extends ConsumerState<AccessTemplatesSection> {
  /// The template list's own controller, so the scrollbar beside it has
  /// something to attach to. The list is bounded (see
  /// [kAccessTemplatesListMaxHeight]) and a bounded list with no scrollbar
  /// reads as a list that ends where it was cut.
  final ScrollController _listController = ScrollController();

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(accessTemplateStoreProvider);

    // Nothing while the database handle resolves. Not a spinner: this section
    // is one card on a page the operator came to for something else, and a
    // spinner that appears for a frame on every station is the flash
    // `AccessLockBadge` and `AccessStatusAction` both refuse to draw.
    if (!storeAsync.hasValue && !storeAsync.hasError) {
      return const SizedBox.shrink();
    }

    if (storeAsync.hasError) {
      return _frame(
        context,
        child: _note(context, kAccessTemplatesUnavailableNote,
            key: kAccessTemplatesUnavailableKey),
      );
    }

    final store = storeAsync.requireValue;
    if (store == null) {
      // No create control here, and that is not a permission decision: there
      // is no table to create into. The "never greyed" rule exists so a
      // *permission* refusal is explained rather than hidden — see the note at
      // the delete dialog, which draws the same distinction.
      return _frame(
        context,
        child: _note(context, kAccessTemplatesNoDatabaseNote,
            key: kAccessTemplatesNoDatabaseKey),
      );
    }

    final templatesAsync = ref.watch(accessTemplatesProvider);
    if (!templatesAsync.hasValue && !templatesAsync.hasError) {
      return const SizedBox.shrink();
    }
    if (templatesAsync.hasError && !templatesAsync.hasValue) {
      return _frame(
        context,
        onCreate: () => _create(context, ref, store, const []),
        child: _note(context, kAccessTemplatesUnavailableNote,
            key: kAccessTemplatesUnavailableKey),
      );
    }

    final templates = templatesAsync.requireValue;
    final names = [for (final t in templates) t.name];
    final resolver = ref.watch(tagBindingResolverProvider);

    return _frame(
      context,
      onCreate: () => _create(context, ref, store, names),
      child: templates.isEmpty
          ? _note(context, kAccessTemplatesEmptyNote)
          : ConstrainedBox(
              constraints: const BoxConstraints(
                  maxHeight: kAccessTemplatesListMaxHeight),
              child: Scrollbar(
                controller: _listController,
                thumbVisibility: true,
                child: ListView.builder(
                controller: _listController,
                shrinkWrap: true,
                primary: false,
                padding: const EdgeInsets.only(right: 8),
                itemCount: templates.length,
                itemBuilder: (context, index) => _TemplateTile(
                  // Keyed by name so that an expanded template stays expanded
                  // across the rebuild every write triggers — otherwise
                  // changing one rule would collapse the rules being edited.
                  key: ValueKey('access-template-${templates[index].name}'),
                  template: templates[index],
                  otherNames: [
                    for (final n in names)
                      if (n != templates[index].name) n,
                  ],
                  // The render-time count, from memory. See the library doc for
                  // why this is not the store's method of the same name.
                  boundKeys: resolver.keysBoundTo(templates[index].name),
                  store: store,
                ),
                ),
              ),
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
      key: kAccessTemplatesSectionKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(kAccessTemplatesHeadline,
                      style: theme.textTheme.titleSmall),
                ),
                if (onCreate != null)
                  OutlinedButton.icon(
                    key: kAccessTemplatesCreateKey,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New template'),
                    onPressed: onCreate,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _note(context, kAccessTemplatesSubtitle),
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
    AccessTemplateStore store,
    List<String> taken,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TemplateNameDialog(
        title: 'New template',
        confirmLabel: 'Create',
        initial: '',
        taken: taken.toSet(),
        footnote: kAccessTemplateNewNote,
      ),
    );
    if (name == null || !context.mounted) return;
    await _write(context, ref,
        () => store.create(AccessTemplate(name: name, rules: const {})));
  }
}

/// One template: its name, what it says, how many keys it governs — and, when
/// it is expanded, its rules.
class _TemplateTile extends ConsumerStatefulWidget {
  const _TemplateTile({
    super.key,
    required this.template,
    required this.otherNames,
    required this.boundKeys,
    required this.store,
  });

  final AccessTemplate template;

  /// Every other template's name, for the duplicate check the dialogs make
  /// before the store is called.
  final List<String> otherNames;

  /// The keys bound to this template **according to the snapshot**. Sorted.
  final Set<String> boundKeys;

  final AccessTemplateStore store;

  @override
  ConsumerState<_TemplateTile> createState() => _TemplateTileState();
}

class _TemplateTileState extends ConsumerState<_TemplateTile> {
  bool _expanded = false;

  AccessTemplate get template => widget.template;
  Set<String> get boundKeys => widget.boundKeys;
  List<String> get otherNames => widget.otherNames;
  AccessTemplateStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: kAccessTemplateTileKey(template.name),
          dense: true,
          contentPadding: EdgeInsets.zero,
          onTap: () => setState(() => _expanded = !_expanded),
          leading: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18),
          title: Text(template.name),
          subtitle: Text(
              kAccessTemplateSummary(template.rules.length, boundKeys.length)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: kAccessTemplateRenameKey(template.name),
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                tooltip: 'Rename',
                onPressed: () => _rename(context, ref),
              ),
              IconButton(
                key: kAccessTemplateDeleteKey(template.name),
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                onPressed: () => _delete(context, ref),
              ),
            ],
          ),
        ),
        if (_expanded) _rules(context),
      ],
    );
  }

  /// The rules, whole-key row first.
  ///
  /// Every control here changes authorization and therefore goes through
  /// `AccessTemplateStore.update` — one call, one audit row, one gate. None of
  /// them is disabled for a session that may not use it; see [_write].
  Widget _rules(BuildContext context) {
    final members = template.rules.keys.toList()
      ..sort((a, b) {
        // The whole-key row is the template's default and reads first: every
        // other row is an exception to it.
        if (a == kWholeKeyMember) return -1;
        if (b == kWholeKeyMember) return 1;
        return a.compareTo(b);
      });

    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (members.isEmpty) _note(context, kAccessTemplateNoRulesNote),
          for (final member in members) _ruleRow(context, member),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: kAccessTemplateAddRuleKey(template.name),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add rule'),
              onPressed: _addRule,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleRow(BuildContext context, String member) {
    final group = template.rules[member]!;
    return Row(
      children: [
        Expanded(
          child: Text(
            memberLabel(member),
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DropdownButton<AccessGroup>(
          key: kAccessTemplateRuleGroupKey(member),
          value: group,
          isDense: true,
          underline: const SizedBox.shrink(),
          // All seven, and nothing else. Labelled by `AccessGroup.name`, which
          // is the same word the roles screen grants and the same word
          // `kAccessDeniedGroupNote` names when the write is refused — three
          // screens, one vocabulary.
          items: [
            for (final option in AccessGroup.values)
              DropdownMenuItem<AccessGroup>(
                key: kAccessTemplateRuleGroupOptionKey(member, option),
                value: option,
                child: Text(option.name),
              ),
          ],
          onChanged: (next) {
            if (next == null || next == group) return;
            _saveRules(
                Map<String, AccessGroup>.from(template.rules)..[member] = next);
          },
        ),
        IconButton(
          key: kAccessTemplateRuleRemoveKey(member),
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          tooltip: 'Remove rule',
          onPressed: () => _saveRules(
              Map<String, AccessGroup>.from(template.rules)..remove(member)),
        ),
      ],
    );
  }

  Future<void> _saveRules(Map<String, AccessGroup> rules) => _write(
        context,
        ref,
        () => store.update(AccessTemplate(name: template.name, rules: rules)),
      );

  Future<void> _addRule() async {
    final rule = await showDialog<MapEntry<String, AccessGroup>>(
      context: context,
      builder: (_) => _AddRuleDialog(
        existingMembers: template.rules.keys.toSet(),
        suggestions: _memberSuggestions,
      ),
    );
    if (rule == null || !mounted) return;
    await _saveRules(
        Map<String, AccessGroup>.from(template.rules)..[rule.key] = rule.value);
  }

  /// The members already seen on a key bound to this template.
  ///
  /// **One key is read, not all of them.** The members are the same across
  /// keys sharing a template — that is what a template *means* — and reading
  /// forty of them would put a PLC round trip per bound key behind a `+`
  /// button (T-04-41). So this reads the first bound key and stops.
  ///
  /// **Everything that can go wrong here returns an empty list, quietly.** No
  /// bound key, a `stateMan` that never resolved, a key the PLC will not
  /// answer for, a scalar value with no members at all: none of them is an
  /// error the operator can act on, and all of them leave the same plain text
  /// field. The suggestion list is a convenience over free text, never a
  /// gate — a member no key has reported yet is still a legal rule, because a
  /// commissioning engineer writes the template before the PLC is on the
  /// network.
  Future<List<String>> _memberSuggestions() async {
    if (boundKeys.isEmpty) return const [];
    final stateMan = await ref.read(stateManProvider.future);
    final value = await stateMan.read(boundKeys.first);
    if (!value.isObject) return const [];
    return [for (final entry in value.entries) entry.key]..sort();
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _TemplateNameDialog(
        title: 'Rename "${template.name}"',
        confirmLabel: 'Rename',
        initial: template.name,
        taken: otherNames.toSet(),
        // A warning, never a block: the operator may have a good reason, and
        // 04-08 surfaces the keys afterwards. What must not happen is that it
        // goes unsaid.
        warningKeys: boundKeys.toList(),
        warningText: boundKeys.isEmpty
            ? null
            : kAccessTemplateRenameWarning(template.name, boundKeys.length),
      ),
    );
    if (to == null || to == template.name || !context.mounted) return;
    await _write(context, ref, () => store.rename(template.name, to));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _DeleteTemplateDialog(name: template.name, store: store),
    );
    // The dialog performs the delete itself, because it is the only widget
    // that can re-render with the bound keys a losing race hands back. All the
    // caller owes is the refresh.
    if (deleted == true) ref.invalidate(accessTemplatesProvider);
  }
}

// ---------------------------------------------------------------------------
// The write path
// ---------------------------------------------------------------------------

/// Runs one store write and refreshes the snapshot.
///
/// ## The `AccessDenied` arm — read this once, it is referenced by the rest
///
/// A refusal is **not handled here**, on purpose. `AccessTemplateStore` calls
/// `onDenied` before it throws, which publishes onto `accessDenialsProvider`,
/// which is what `AccessDeniedPrompt` is already listening to — so by the time
/// this catch runs, the prompt naming the `users` group is on screen. A
/// message of this file's own would be two things saying one thing, and they
/// would drift the first time the wording changed. So: swallow, change
/// nothing, and do not refresh — nothing moved.
///
/// Every other catch clause in this file points back at this paragraph rather
/// than restating it.
Future<bool> _write(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() write,
) async {
  try {
    await write();
  } on AccessDenied {
    return false;
  } on Object catch (error) {
    // Not an authorization event — a duplicate name that appeared underneath
    // us, a database that went away mid-write. The operator gets the reason
    // rather than a control that did nothing.
    if (context.mounted) _showProblem(context, error);
    return false;
  }
  // 04-05: there is no listener and nothing else notices. This invalidate is
  // the single refresh trigger for both tables.
  ref.invalidate(accessTemplatesProvider);
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
/// starting text and whether there is a warning — and a second nearly
/// identical dialog is how two validation rules start disagreeing.
class _TemplateNameDialog extends StatefulWidget {
  const _TemplateNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.taken,
    this.warningText,
    this.warningKeys = const [],
    this.footnote,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  /// Names already in use. The duplicate is refused **here**, before the store
  /// is called: a `TemplateExistsException` surfaced as a snackbar after the
  /// dialog closed would make the operator retype the whole thing.
  final Set<String> taken;

  final String? warningText;
  final List<String> warningKeys;
  final String? footnote;

  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
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
    // Validation before the gate, for the reason 04-03's store checks the name
    // before the gate too: a typo is not an authorization event, and putting a
    // sign-in prompt in front of one would teach the operator to ignore it.
    if (!AccessTemplate.isValidTemplateName(name)) {
      setState(() => _error = kAccessTemplateInvalidNameNote);
      return;
    }
    if (widget.taken.contains(name)) {
      setState(() => _error = kAccessTemplateDuplicateNameNote);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final warning = widget.warningText;
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
          buttonKey: kAccessTemplateConfirmKey,
          onPressed: _confirm,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: kAccessTemplateNameFieldKey,
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _error,
              errorMaxLines: 3,
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
          if (warning != null) ...[
            const SizedBox(height: 16),
            _WarningBlock(
              blockKey: kAccessTemplateRenameWarningKey,
              text: warning,
              keys: widget.warningKeys,
            ),
          ],
        ],
      ),
    );
  }
}

/// One new rule: a member name and the permission it needs.
///
/// Spec §7d: "Adding a row offers the members already seen on keys bound to
/// that template, so it is picking from a list rather than typing PLC
/// identifiers from memory." That sentence is this dialog, and the reason it
/// matters is that the alternative — typing `p_cfg_ManualFreq` from memory
/// into a field where a typo silently means *no restriction* — is a fail-open
/// hole with no symptom (T-04-39).
///
/// **The list is not authoritative and the text field never goes away.** A
/// member no key has yet reported is still a legal rule. The residual is
/// stated rather than closed: a typo here still reads as no restriction, and
/// 04-08's unbound/dangling surface is what makes such a gap findable.
class _AddRuleDialog extends StatefulWidget {
  const _AddRuleDialog({
    required this.existingMembers,
    required this.suggestions,
  });

  /// Members that already have a rule. Offered nowhere — re-scoping one is
  /// what the row's own picker is for, and a second way in would let the
  /// operator "add" a rule that silently replaced another.
  final Set<String> existingMembers;

  /// Reads the members off the equipment. Injected rather than read from a
  /// provider here so this dialog has no opinion about how many keys that
  /// costs; see `_TemplateTileState._memberSuggestions`.
  final Future<List<String>> Function() suggestions;

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  final TextEditingController _member = TextEditingController();
  AccessGroup? _group;
  String? _memberError;
  String? _groupError;

  List<String> _suggested = const [];

  /// Whether the load has finished, however it finished.
  ///
  /// Nothing is rendered about suggestions until it has — not a spinner, and
  /// not the "no members to offer" line, which would otherwise appear for a
  /// frame and then be replaced by chips.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _member.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<String> members;
    try {
      members = await widget.suggestions();
    } on Object {
      // Quietly. See `_memberSuggestions` for why none of these failures is
      // something to put in front of the operator.
      members = const [];
    }
    if (!mounted) return;
    setState(() {
      _suggested = members;
      _loaded = true;
    });
  }

  void _confirm() {
    final member = _member.text.trim();
    if (member.isEmpty) {
      setState(() => _memberError = kAccessTemplateMemberRequiredNote);
      return;
    }
    if (widget.existingMembers.contains(member)) {
      setState(() => _memberError = kAccessTemplateMemberExistsNote);
      return;
    }
    final group = _group;
    if (group == null) {
      setState(() => _groupError = kAccessTemplateGroupRequiredNote);
      return;
    }
    Navigator.of(context).pop(MapEntry(member, group));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The whole-key row is always offered: it is the one member name nobody
    // can type, since `*` is a sentinel rather than something the PLC reports.
    final offered = <String>[
      if (!widget.existingMembers.contains(kWholeKeyMember)) kWholeKeyMember,
      for (final member in _suggested)
        if (!widget.existingMembers.contains(member)) member,
    ];

    return StandardDialogFrame(
      title: 'Add rule',
      showClose: false,
      actions: [
        PaneAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PaneAction.primary(
          label: 'Add',
          buttonKey: kAccessTemplateConfirmKey,
          onPressed: _confirm,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loaded && _suggested.isEmpty) ...[
            _note(context, kAccessTemplateNoSuggestionsNote),
            const SizedBox(height: 12),
          ],
          if (offered.isNotEmpty) ...[
            _note(context, kAccessTemplateSuggestionsNote),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final member in offered)
                  ActionChip(
                    key: kAccessTemplateSuggestionKey(member),
                    label: Text(memberLabel(member)),
                    onPressed: () {
                      _member.text = member;
                      setState(() => _memberError = null);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            key: kAccessTemplateMemberFieldKey,
            controller: _member,
            decoration: InputDecoration(
              labelText: 'Member',
              errorText: _memberError,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_memberError != null) setState(() => _memberError = null);
            },
          ),
          const SizedBox(height: 16),
          DropdownButton<AccessGroup>(
            key: kAccessTemplateNewRuleGroupKey,
            value: _group,
            isExpanded: true,
            hint: const Text(kAccessTemplateGroupHint),
            items: [
              for (final option in AccessGroup.values)
                DropdownMenuItem<AccessGroup>(
                  key: kAccessTemplateNewRuleGroupOptionKey(option),
                  value: option,
                  child: Text(option.name),
                ),
            ],
            onChanged: (next) => setState(() {
              _group = next;
              _groupError = null;
            }),
          ),
          if (_groupError != null)
            Text(
              _groupError!,
              maxLines: null,
              overflow: TextOverflow.visible,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}

/// Delete: the bound keys **first**, and no confirming action while there are
/// any.
///
/// ## Why the action is absent rather than present-and-refusing
///
/// This is the one exception in this milestone to "never greyed", and it needs
/// its reason in writing.
///
/// That rule exists so that a **permission** refusal is explained rather than
/// hidden: an operator who cannot do something must still see the control,
/// press it, and be told which permission to go and get. A blocked delete is
/// not a permission refusal — 04-03 made `TemplateInUseException` a separate
/// type from `AccessDenied` for exactly this reason, and an Engineering user
/// holding every group including `users` gets it too. No sign-in resolves it,
/// nothing the operator can be told to fetch resolves it, and the only thing
/// that does is dealt with by editing the keys.
///
/// A control that is present and always refuses teaches the operator to press
/// it twice (T-04-40). So the keys and the instruction take the action's
/// place.
class _DeleteTemplateDialog extends StatefulWidget {
  const _DeleteTemplateDialog({required this.name, required this.store});

  final String name;
  final AccessTemplateStore store;

  @override
  State<_DeleteTemplateDialog> createState() => _DeleteTemplateDialogState();
}

class _DeleteTemplateDialogState extends State<_DeleteTemplateDialog> {
  /// Null until the one database question this file asks comes back.
  List<String>? _boundKeys;

  /// The question could not be asked at all.
  bool _unreadable = false;

  /// Re-entry guard. Deliberately not rendered as a disabled button: a control
  /// this file draws is never greyed, and a second tap during the round trip
  /// is simply ignored.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // The **store's** keysBoundTo, not the resolver's. The list shown here
      // is the list the block will use, and a delete must not be decided from
      // a snapshot that may be a second stale.
      final keys = await widget.store.keysBoundTo(widget.name);
      if (mounted) setState(() => _boundKeys = keys);
    } on Object {
      // "Cannot tell" must not read as "nothing is bound" — that is the
      // distinction 04-03 removed from the store, and it would be a shame to
      // reintroduce it here.
      if (mounted) setState(() => _unreadable = true);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.store.delete(widget.name);
      if (mounted) Navigator.of(context).pop(true);
    } on TemplateInUseException catch (e) {
      // Another station bound a key between the question and the statement.
      // The store just proved the newer list, so the dialog re-renders with it
      // — this is the same dialog telling the operator a truer thing, not an
      // error about a failed operation.
      if (mounted) setState(() => _boundKeys = e.boundKeys);
    } on AccessDenied {
      // See the note at [_write]. The dialog stays open on purpose: the
      // operator can sign in from the prompt and press Delete again.
    } on Object catch (error) {
      if (mounted) _showProblem(context, error);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _boundKeys;
    final blocked = _unreadable || keys == null || keys.isNotEmpty;

    return StandardDialogFrame(
      title: 'Delete "${widget.name}"',
      icon: Icons.warning_amber,
      showClose: false,
      actions: [
        PaneAction(
          label: blocked ? 'Close' : 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (!blocked)
          PaneAction.destructive(
            label: 'Delete',
            buttonKey: kAccessTemplateConfirmKey,
            onPressed: _delete,
          ),
      ],
      child: _body(context, keys),
    );
  }

  Widget _body(BuildContext context, List<String>? keys) {
    if (_unreadable) {
      return _note(context, kAccessTemplateDeleteUnknownNote);
    }
    if (keys == null) {
      return _note(context, kAccessTemplateDeleteCheckingNote);
    }
    if (keys.isEmpty) {
      return _note(context, kAccessTemplateDeleteFreeNote);
    }
    return _WarningBlock(
      blockKey: kAccessTemplateDeleteBlockedKey,
      text: kAccessTemplateDeleteBlockedNote(widget.name, keys.length),
      keys: keys,
    );
  }
}

/// A sentence and the keys it is about.
///
/// Shared by the rename warning and the delete block because they are the same
/// shape and the same stakes: a list of keys that are about to become, or
/// would become, unrestricted.
class _WarningBlock extends StatelessWidget {
  const _WarningBlock({
    required this.blockKey,
    required this.text,
    required this.keys,
  });

  final Key blockKey;
  final String text;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: blockKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // The theme's own warning surface rather than a raw colour: only a
        // fault may be saturated, and this is not a fault.
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_open_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  // Never ellipsised: a warning the eye skips because it was
                  // cut to one line has not been given.
                  maxLines: null,
                  overflow: TextOverflow.visible,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: ListView(
              shrinkWrap: true,
              primary: false,
              padding: EdgeInsets.zero,
              children: [
                for (final key in keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(key, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
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

/// The audit trail's filter bar: five controls, one note, and no state of its
/// own beyond a debounce timer.
///
/// The page owns one [AuditTrailFilters] and hands it down; every control here
/// emits a whole new value through one `ValueChanged<AuditTrailFilters>` and
/// nothing else. That is `AlarmLevelFilterChips`' shape
/// (`lib/widgets/alarm.dart:102`), and it is what lets the bar be pumped in a
/// widget test without a database, a provider or a session.
///
/// ## The one default exclusion, and why it is on screen
///
/// The ROADMAP names exactly one default exclusion: `operate`. A jog button
/// pressed four hundred times an hour would otherwise be the whole page.
/// CONTEXT then rules that the exclusion is a **visible control** — a normal
/// group chip rendered deselected, with a one-line note — because hidden
/// behaviour reads as a bug and the row count would otherwise be inexplicable.
/// That note is [kAuditTrailOperateNote] and it renders whether or not
/// `operate` is currently selected.
///
/// Two other exclusions were offered and rejected: defaulting to denials-only,
/// and default-hiding `origin: 'system'`. The MCP reconnect noise is real, and
/// hiding it by default would make the page lie about what the station did.
/// Neither is implemented here, and neither should be added without reopening
/// that decision.
///
/// ## Nothing here queries anything
///
/// The `who` options are a parameter, the result summary is a parameter, and
/// the refresh affordance is a callback. The bar issues no statement, reads no
/// provider and starts no periodic timer. Its single timer is the keystroke
/// debounce below, which is one-shot and dies in `dispose`.
library;

import 'package:flutter/material.dart';
import 'package:tfc_access/tfc_access.dart';

import '../core/audit_trail_store.dart';

// ---------------------------------------------------------------------------
// Copy and keys
//
// Kept at the top of the file in the `access_gate.dart` / `audit_trail_row.dart`
// idiom, so a test asserts against the string the widget renders rather than
// one it supplies. Each `Key` is separate from the copy beside it: the copy is
// what a reader sees and may be rewritten, the key is what a test finds and
// must not change when the wording does.
// ---------------------------------------------------------------------------

/// The one line that explains the page's one default exclusion.
///
/// It exists because the exclusion is otherwise invisible. The ROADMAP names
/// `operate` as the single default exclusion; a page that quietly drops the
/// noisiest group is a page whose row count cannot be reconciled with the
/// table, and an unexplained gap in an audit trail is the one thing an audit
/// trail must never have.
///
/// The wording says both halves on purpose — **what** is hidden and **how to
/// get it back** — so the note doubles as the instruction for undoing it. It
/// renders in both selection states: a note that vanishes the moment you change
/// the thing it explains cannot be read a second time.
const String kAuditTrailOperateNote =
    'Operate writes are hidden by default — tap the Operate chip to include '
    'them.';

/// The eighth chip's label. Auth rows are not a group; see [AuditGroupChips].
const String kAuditTrailAuthChipLabel = 'Auth';

/// The `who` dropdown's null entry: every author, which is the default.
const String kAuditTrailAnyoneLabel = 'Anyone';

/// What the date chip says when no explicit range is set, which is also the
/// name of [kAuditTrailDefaultWindow].
const String kAuditTrailDefaultRangeLabel = 'Last 7 days';

/// What the result summary says when the query escaped the time bound.
const String kAuditTrailWholeTableLabel = 'All time';

/// The button that returns the page to the state it opened in.
const String kAuditTrailClearFiltersLabel = 'Clear filters';

/// The affordance that drops an explicit range without touching anything else.
const String kAuditTrailClearRangeTooltip = 'Clear range';

/// The bar's refresh affordance. There is no timer; see [AuditTrailFilterBar].
const String kAuditTrailRefreshTooltip = 'Refresh';

/// The prefix field's hint. It names what is searched and how far the search
/// reaches, because both are the point of the control.
const String kAuditTrailPrefixHint = 'Search all keys, e.g. CN04';

/// The three outcome segments, in the order they render.
const String kAuditTrailOutcomeAnyLabel = 'All';
const String kAuditTrailOutcomeAllowedLabel = 'Allowed';
const String kAuditTrailOutcomeDeniedLabel = 'Denied';

/// The chip for one [AccessGroup], found by its `name` rather than its label so
/// a reworded label does not break a test about behaviour.
Key auditGroupChipKey(String groupName) =>
    ValueKey<String>('audit-group-chip-$groupName');

/// The eighth chip.
const Key kAuditTrailAuthChipKey = ValueKey<String>('audit-auth-chip');

/// The line carrying [kAuditTrailOperateNote].
const Key kAuditTrailOperateNoteKey = ValueKey<String>('audit-operate-note');

/// What one [AccessGroup]'s chip says.
///
/// Derived from the enum's own `name` rather than a lookup table, so an eighth
/// group gets a label the day it is declared instead of a blank chip or a
/// missing one. `AccessGroup`'s doc calls an eighth value "a decision, not an
/// edit"; this file must not be one of the places that decision has to be
/// repeated.
String auditGroupChipLabel(AccessGroup group) {
  final name = group.name;
  if (name.isEmpty) return name;
  return name[0].toUpperCase() + name.substring(1);
}

// ---------------------------------------------------------------------------
// The group chips
// ---------------------------------------------------------------------------

/// One chip per [AccessGroup], then one for auth rows, then the note.
///
/// ## Why there are eight chips and not seven
///
/// Auth rows — `login`, `login.failed`, `logout`, `session.timeout` — carry an
/// **empty** `group_required`, because signing in is not gated on a group. A
/// bare `group_required IN (...)` would therefore drop every sign-in from the
/// page. CONTEXT rejected putting auth rows on a separate tab precisely because
/// interleaving is what preserves "who signed in right before this write", so
/// the rows have to stay in the list; the eighth chip is what makes them
/// *filterable* rather than unconditional. `AuditTrailStore.entries` ORs the
/// `surface = 'auth'` leg in for it.
///
/// ## Selection semantics: what is shared with `AlarmLevelFilterChips`
///
/// **Shared, and locked.** Nothing selected means no constraint — every group,
/// every row. CONTEXT's words: *"Filters combine: AND across dimensions, OR
/// within a multi-select dimension, empty selection = no constraint. Identical
/// to `AlarmLevelFilterChips` (`lib/widgets/alarm.dart:96-101`), so the
/// semantics are already learned."* It reads backwards on first encounter —
/// deselect everything, see everything — and the next reader's instinct will be
/// to "fix" it into "empty means nothing matches". That inversion was proposed
/// once in this phase, labelled a documented divergence, and reverted. This
/// widget therefore does not block the empty state and does not helpfully
/// re-select anything to prevent it.
///
/// **Not shared: the *initial* set.** `AlarmLevelFilterChips` starts empty;
/// this one starts with the six non-`operate` groups plus auth selected
/// ([kAuditTrailDefaultGroupNames]). That single difference — a non-empty
/// default rather than an empty one — is the entire mechanism by which
/// `operate` is excluded on open, and it is the only reason the row count
/// differs from an unfiltered table. It is also why [kAuditTrailOperateNote]
/// has to be beside these chips.
///
/// ## No counts
///
/// `AlarmLevelFilterChips` puts a count on each chip and can, because it
/// filters in memory over a list it already holds. Every filter here is pushed
/// into SQL, so a chip could not state how many rows it would add without a
/// second query per chip, and a count over the loaded window would be a number
/// that looks authoritative and is not. The result count is stated once, above
/// the list, labelled with the window it came from.
class AuditGroupChips extends StatelessWidget {
  const AuditGroupChips({
    super.key,
    required this.filters,
    required this.onChanged,
  });

  /// The state the parent owns. This widget holds none of its own.
  final AuditTrailFilters filters;

  /// The one way anything leaves this widget.
  final ValueChanged<AuditTrailFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = filters.groupNames.toSet();
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap, not Row: the bar sits above a full-width list and can be
        // narrow, so the chips have to fold onto a second line rather than
        // overflow it.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final group in AccessGroup.values)
              _chip(
                context,
                key: auditGroupChipKey(group.name),
                label: auditGroupChipLabel(group),
                isSelected: selected.contains(group.name),
                onSelected: (keep) => _toggleGroup(group, keep),
              ),
            _chip(
              context,
              key: kAuditTrailAuthChipKey,
              label: kAuditTrailAuthChipLabel,
              isSelected: filters.includeAuth,
              onSelected: (keep) => onChanged(filters.copyWith(includeAuth: keep)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          kAuditTrailOperateNote,
          key: kAuditTrailOperateNoteKey,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// The chip mechanics of `AlarmLevelFilterChips._chip`, minus its avatar and
  /// its count. No colour is named here at all: a selected chip takes the
  /// theme's own selection fill, because these chips carry no severity and a
  /// filter bar painted eight colours stops distinguishing anything.
  Widget _chip(
    BuildContext context, {
    required Key key,
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) =>
      FilterChip(
        key: key,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        showCheckmark: false,
        label: Text(label),
        selected: isSelected,
        onSelected: onSelected,
      );

  /// Adds or removes one group name, keeping the list in [AccessGroup]
  /// declaration order.
  ///
  /// Rebuilt from the enum rather than appended to, so two filter states that
  /// differ only in the order the operator tapped their chips compare equal —
  /// `AuditQuery` sorts anyway, but a provider family keyed on the *filters*
  /// would otherwise miss its cache on a re-tap.
  ///
  /// Names the enum does not know are carried through untouched rather than
  /// dropped. `group_required` is an open vocabulary: a station running a newer
  /// build can have written a group this one has never heard of, and silently
  /// deleting it from the filter on an unrelated tap would change what the
  /// query returns for a reason the operator never asked for.
  void _toggleGroup(AccessGroup group, bool keep) {
    final selected = filters.groupNames.toSet();
    if (keep) {
      selected.add(group.name);
    } else {
      selected.remove(group.name);
    }

    final known = {for (final value in AccessGroup.values) value.name};
    final next = <String>[
      for (final value in AccessGroup.values)
        if (selected.contains(value.name)) value.name,
      for (final name in filters.groupNames)
        if (!known.contains(name) && selected.contains(name)) name,
    ];
    onChanged(filters.copyWith(groupNames: next));
  }
}

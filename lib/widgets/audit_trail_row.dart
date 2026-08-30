/// The audit trail list item: one row, and one human action, rendered the way
/// an engineer reads them.
///
/// Two widgets live here. [AuditEntryLine] draws one `AuditEntryData` — the
/// collapsed line, and also every child of an expanded action, so a member row
/// and a scalar row cannot drift apart. `AuditActionTile` (plan 05-04 task 3)
/// draws one `AuditAction` on top of it.
///
/// ## Why red is almost never on this page
///
/// Spec §2 says a denied write is the more interesting audit line, and that it
/// is how a role configured too tightly gets found. Finding the refusals has to
/// be fast, which means the other rows must be quiet: a denial carries a
/// leading bar in `HmiStateColors.red` and an allowed row carries **no** colour
/// at all. A page of allowed writes therefore holds exactly as much red as it
/// holds denials.
///
/// `lib/pages/key_repository.dart` reaches into Material's raw colour palette
/// directly for its red. That is a known violation of the colour convention
/// that predates it — every colour in this file comes from
/// `HmiStateColors.of(context)`, and a test in
/// `test/widgets/audit_trail_row_test.dart` reads this file's source and fails
/// if the word before `.red` is ever the palette's rather than the theme
/// extension's. The grep it runs is literal, so the offending spelling does not
/// appear anywhere in this file, comments included.
///
/// ## The open surface vocabulary
///
/// **1. `surface` has four values today and the list is open.** They are `tag`,
/// `pref`, `route` and `auth` (`kKnownAuditSurfaces` in
/// `lib/core/audit_trail_grouping.dart`, which is a change-detector and not a
/// whitelist). Phase 6 adds a fifth, `admin`, for role and user administration:
/// `itemKey`s `role.create` / `role.update` / `role.delete` / `role.rename` and
/// `user.create` / `user.delete` / `user.role` / `user.password`, all carrying
/// `groupRequired: 'users'`. That is confirmed, scheduled work, not a
/// hypothetical, and Phase 5 ships first.
///
/// **2. This widget therefore branches on `isAuthEntry` and on nothing else.**
/// There is no exhaustive switch over `surface`, no `default: throw`, no
/// `assert(false)`. An unrecognised surface takes the write shape and renders.
/// A row is data from a database several stations write to; refusing to draw
/// one is how a page goes blank on the day somebody upgrades one panel, and an
/// audit trail that lies by omission is the one failure mode it cannot have.
/// Phase 6 needs only to add its surface to `kKnownAuditSurfaces` and one
/// filter entry — no new chip either, because `admin` rows carry
/// `groupRequired: 'users'` and the existing `users` chip already covers them.
///
/// **3. The transition columns are the writer's problem, not this widget's.**
/// An `admin` row has no `old → new` pair in the ordinary sense — a role's
/// group set changing *is* the value — so the Phase 6 **writer** puts a
/// human-readable summary in `oldValue` and `newValue` (a `role.update` writes
/// something like `"operate, users"` → `"operate"`), and this widget renders
/// whatever is there, applying the same em-dash rule when either is null. The
/// alternative — teaching this widget what `role.*` keys mean by switching on
/// `itemKey` prefixes — is the exact coupling the open-vocabulary rule exists
/// to prevent. A Phase 6 executor who finds these columns empty should fix the
/// writer, not this file.
library;

import 'package:flutter/material.dart';
import 'package:tfc_dart/core/database_drift.dart';

import '../core/audit_trail_grouping.dart';
import '../theme.dart';
import 'base_scaffold.dart' show formatTimestamp;

// ---------------------------------------------------------------------------
// Copy and keys
//
// Kept at the top of the file in the `access_gate.dart` idiom, so the tests
// assert against the string the widget renders rather than one they supply.
// Each `Key` is separate from the copy beside it on purpose: the copy is what a
// reader sees and may be rewritten, the key is what a test finds and must not
// change when the wording does.
// ---------------------------------------------------------------------------

/// The glyph between the old and the new value.
///
/// One constant rather than a literal in three places, because a test asserts
/// an auth row renders *no* arrow and that assertion has to be about the same
/// character the write shape draws.
const String kAuditTransitionArrow = '→';

/// What stands in for a null `oldValue` or `newValue`: an em dash.
///
/// Not the word `null`. A literal `null` on screen is a value an operator will
/// try to interpret — as a tag that read back empty, as a cleared setpoint, as
/// a fault — and the trail's job is to be readable at a glance rather than to
/// expose the storage. The column being null means "there was nothing here",
/// and an em dash is how a table says that.
const String kAuditValueMissing = '—';

/// The leading bar on a refused row. Present only when `allowed` is false.
const Key kAuditDenialMarkKey = Key('audit-denial-mark');

/// The invisible stand-in the mark slot holds on every other row.
///
/// It exists so allowed and denied rows line up. Without it the timestamp
/// column would start four pixels further left on every allowed row and the eye
/// would have to re-find it on each one, which costs far more than the space it
/// saves.
const Key kAuditMarkPlaceholderKey = Key('audit-mark-placeholder');

/// The leading bar on a sign-in.
///
/// Orange, because orange already means an elevated session in
/// `AccessStatusAction` — the page is reusing an established meaning rather
/// than adding a colour.
const Key kAuditAuthMarkKey = Key('audit-auth-mark');

/// The `itemKey` of a successful sign-in, one of the four the named
/// constructors in `packages/tfc_access/lib/src/audit.dart` pin.
///
/// Named because it is the only auth event this widget treats differently from
/// the other three, and an exact comparison is what keeps `login.failed` out of
/// it.
const String kAuditAuthLoginItemKey = 'login';

/// The inline origin chip. Absent on a hand-made write.
const Key kAuditOriginChipKey = Key('audit-origin-chip');

/// The `origin` a hand-made write carries, and the only one that renders no
/// chip.
///
/// `AuditEntry.origin` defaults to this in the schema
/// (`database_drift.dart`), on purpose: an unmarked future machine caller lands
/// *in* the trail loudly rather than escaping it silently.
const String kAuditOriginDefault = 'operator';

/// The widest an origin chip is allowed to get before it ellipsises.
const double kAuditOriginChipMaxWidth = 140;

/// A human label for an [AuditEntry.origin], or the string itself.
///
/// **The vocabulary is not closed and this function must not pretend it is.**
/// The only two origins written anywhere in this codebase today are
/// `kAuditOriginDefault` and `'system'`
/// (`packages/tfc_dart/lib/core/access/guarded_preferences.dart`). `'mcp'` is
/// *planned* — `lib/core/access_template_store.dart` records that 04-09 will
/// pass it — and nothing writes it yet, so it is listed here for the day it
/// starts rather than because it exists. `origin` is a plain `TextColumn` with
/// a default, several SVN stations write to one database, and a station running
/// a newer build will write a word this one has never heard of. An exhaustive
/// switch here would be a page that breaks on an upgrade, so anything
/// unrecognised comes back verbatim and the operator reads what the database
/// actually holds.
String auditOriginLabel(String origin) => switch (origin) {
      'system' => 'system',
      'mcp' => 'MCP',
      _ => origin,
    };

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// The height of one collapsed line.
///
/// Fixed, and every string in the line is capped at one line inside it, so a
/// two-thousand-character value pasted into a setpoint cannot make one row
/// taller than its neighbours and break the scan down the list.
const double kAuditRowHeight = 32;

/// The width of the mark slot, occupied on every row whether it is coloured or
/// not.
const double kAuditMarkWidth = 4;

/// The height of the mark itself inside [kAuditRowHeight].
const double kAuditMarkHeight = 20;

/// The timestamp column. Wide enough for `dd-MM-yyyy HH:mm:ss`.
const double kAuditTimeColumnWidth = 150;

/// The `who (role)` column.
const double kAuditWhoColumnWidth = 160;

/// The gap between columns.
const double kAuditColumnGap = 12;

// ---------------------------------------------------------------------------
// AuditEntryLine
// ---------------------------------------------------------------------------

/// One audit row, collapsed: the mark slot, the time, who did it and as what,
/// the key, and the value transition.
///
/// The same widget draws the flat single-row case and every child of an
/// expanded action. One implementation, so a member row and a scalar row read
/// alike.
class AuditEntryLine extends StatelessWidget {
  const AuditEntryLine({super.key, required this.row});

  /// The row to draw. Rendered whatever its `surface` says — see the
  /// open-vocabulary contract in the library doc.
  final AuditEntryData row;

  /// The key as one string: `itemKey` for a scalar write, `itemKey.member` for
  /// a member of a struct write.
  ///
  /// One string rather than two columns, because a member row read on its own —
  /// which is what an expanded child is — has to say which key it belongs to.
  String get _itemLabel =>
      row.member == null ? row.itemKey : '${row.itemKey}.${row.member}';

  /// `old → new`, with an em dash standing in for either side when it is null.
  String get _transitionLabel =>
      '${row.oldValue ?? kAuditValueMissing} $kAuditTransitionArrow '
      '${row.newValue ?? kAuditValueMissing}';

  /// True when this row records an authentication event rather than a write.
  ///
  /// The predicate, never the string. `isAuthEntry` is asked here, in the
  /// filter bar and in the golden fixture, and three copies of a literal would
  /// be three places to typo it — a typo that renders a login as a write with
  /// an empty transition instead of failing loudly.
  bool get _isAuth => isAuthEntry(row);

  /// The mark slot.
  ///
  /// Only fault red may be saturated in this repo, and a fully coloured list
  /// stops distinguishing anything — so a refusal gets a red bar and every
  /// other row gets an equally sized transparent placeholder rather than a
  /// green one. That is the whole ruling: a page of allowed writes has exactly
  /// as much red in it as it has denials, which is what makes one glance down
  /// the list enough to find the refusals.
  ///
  /// Red is asked first, so a `login.failed` — which is a refusal like any
  /// other, with `allowed` false — is marked red rather than orange. Red beats
  /// orange when both would apply: the sign-in did not happen, and that is the
  /// more urgent of the two facts.
  Widget _mark(BuildContext context) {
    if (!row.allowed) {
      return SizedBox(
        width: kAuditMarkWidth,
        height: kAuditMarkHeight,
        child: ColoredBox(
          key: kAuditDenialMarkKey,
          color: HmiStateColors.of(context).red,
        ),
      );
    }

    if (_isAuth && row.itemKey == kAuditAuthLoginItemKey) {
      return SizedBox(
        width: kAuditMarkWidth,
        height: kAuditMarkHeight,
        child: ColoredBox(
          key: kAuditAuthMarkKey,
          color: HmiStateColors.of(context).orange,
        ),
      );
    }

    return const SizedBox(
      key: kAuditMarkPlaceholderKey,
      width: kAuditMarkWidth,
      height: kAuditMarkHeight,
    );
  }

  /// The inline origin chip, or nothing at all on a hand-made write.
  ///
  /// `station`, `actionId` and `reason` belong in the expanded detail; the
  /// origin is the one exception, because twelve `system` rows land in the trail
  /// on every database reconnect and picking them out must not cost twelve
  /// taps.
  ///
  /// Decoration only: it carries the scheme's own container colour and never a
  /// state colour, so it cannot compete with the red that means refused.
  Widget _originChip(BuildContext context) {
    if (row.origin == kAuditOriginDefault) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: kAuditColumnGap),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: kAuditOriginChipMaxWidth),
        child: Container(
          key: kAuditOriginChipKey,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            auditOriginLabel(row.origin),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.textTheme.bodySmall;
    final secondary = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return SizedBox(
      height: kAuditRowHeight,
      child: Row(
        children: [
          _mark(context),
          const SizedBox(width: kAuditColumnGap),
          SizedBox(
            width: kAuditTimeColumnWidth,
            child: Text(
              formatTimestamp(row.at),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: secondary,
            ),
          ),
          const SizedBox(width: kAuditColumnGap),
          SizedBox(
            width: kAuditWhoColumnWidth,
            child: Text(
              '${row.who} (${row.roleName})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: secondary,
            ),
          ),
          const SizedBox(width: kAuditColumnGap),
          Expanded(
            flex: 3,
            child: Text(
              _itemLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: primary,
            ),
          ),
          // No transition on an auth row — not an empty one, not two em
          // dashes, nothing. `audit.dart` withholds `oldValue` and `newValue`
          // on auth rows deliberately, because a trail that leaks credentials
          // is worse than no trail. Rendering an empty transition here would
          // leave a slot on screen and invite somebody to "fix" it by filling
          // it in.
          if (!_isAuth) ...[
            const SizedBox(width: kAuditColumnGap),
            Expanded(
              flex: 2,
              child: Text(
                _transitionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: primary,
              ),
            ),
          ],
          _originChip(context),
        ],
      ),
    );
  }
}

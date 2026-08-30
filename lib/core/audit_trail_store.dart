/// The first reader of `audit_entry`: one filter value type, the two-mode rule
/// that decides how far back a query reaches, and one store object that turns
/// the result into one bounded newest-first statement.
///
/// Nothing in the tree selected from `audit_entry` before this file. The table
/// has had exactly one writer since Phase 1 — `DriftAuditSink` — and this is
/// its counterpart on the read side.
///
/// ## Why the query is built here rather than as a method on `AppDatabase`
///
/// Pages never touch Drift, and neither does anything else outside a store —
/// that was Phase 3's bypass-4 defect (`history_view.dart:1108`). Putting the
/// query on `AppDatabase` would put a second place to look for it and would
/// spend a `tfc_dart` release on a statement only this page issues. The typed
/// builder compiles to SQLite and Postgres alike, so the in-memory test
/// exercises the real statement rather than a stand-in for it.
///
/// ## Why the reads are ungated and unaudited
///
/// `access_template_store.dart`'s class doc is the binding precedent: *"Reads …
/// are ungated and unaudited: looking at the rules is not an authorization
/// change, and a row per render would bury the writes that matter."* That
/// applies with more force here. A store-level guard on this read would write a
/// row into the trail every time somebody scrolled the trail, and the trail
/// would fill with people looking at it.
///
/// The enforcement is the **route** gate —
/// `kRaisedRoutes['/advanced/audit-trail'] = AccessGroup.users`.
/// [kAuditTrailGroup] exists in this file so that the route and the store name
/// the same word once.
library;

import 'package:tfc_access/tfc_access.dart';

/// The permission the audit trail route requires.
///
/// `users`, the highest group, and for the **data** the page shows rather than
/// for anything it writes — it writes nothing at all.
///
/// **What lowering this line would mean.** Set it to `AccessGroup.configure`
/// and every setpoint change anybody ever made, with its old and new values,
/// its author and its station, is in front of anyone who can edit a page or
/// import a key map. The trail is a complete history of what the plant was told
/// to do and by whom; spec §2 keeps denials in it precisely because a denied
/// write is how you find a role configured too tightly, which is the same
/// sentence read the other way round — the page is a window on the
/// authorization model, so it sits at the authorization model's own gate.
///
/// **This constant is not the enforcement.** The route gate is: the store below
/// takes no session, holds no `AuditSink` and cannot refuse a caller. This
/// constant is the one word the route is spelled from, and plan 05-07 adds the
/// test that `kRaisedRoutes['/advanced/audit-trail']` and this line agree.
const AccessGroup kAuditTrailGroup = AccessGroup.users;

/// How far back the page reaches when nobody has asked for anything else.
const Duration kAuditTrailDefaultWindow = Duration(days: 7);

/// The most rows any single query returns, in either mode.
///
/// The whole-table search escapes the *time* bound and never this one. A year
/// of rows must not come back in one statement.
const int kAuditTrailRowLimit = 500;

/// The group names selected when the page opens: every group except `operate`,
/// in [AccessGroup] declaration order.
///
/// Derived from `AccessGroup.values` rather than typed out, so an eighth group
/// arrives selected rather than silently missing. The ROADMAP names exactly one
/// exclusion and no others — `operate` is excluded because a jog button pressed
/// four hundred times an hour would be the whole page.
///
/// The exclusion is a **visible control**: 05-05 renders `operate` as a normal
/// chip, deselected, with a one-line note. Hidden behaviour reads as a bug, and
/// the row count would otherwise be inexplicable.
final List<String> kAuditTrailDefaultGroupNames = List.unmodifiable(
  AccessGroup.values
      .where((group) => group != AccessGroup.operate)
      .map((group) => group.name),
);

/// The allow/deny segmented control's three states.
enum AuditOutcomeFilter {
  /// Allowed and denied rows alike — the default.
  any,

  /// Only rows the guard let through.
  allowedOnly,

  /// Only denials. Spec §2: a denied write is the more interesting audit line,
  /// and it is how you find a role configured too tightly.
  deniedOnly,
}

/// A closed time interval over `audit_entry.at`.
///
/// Flutter's `DateTimeRange` is the obvious type and is deliberately not used:
/// there is no `flutter/` import anywhere in `lib/core/`, and one here would
/// make this file unusable from a pure-Dart context and would drag the widget
/// layer's conventions into the query layer. The filter bar in 05-05 converts
/// from `DateTimeRange` at its own boundary.
///
/// Value equality matters more here than it looks. This type is a field on
/// [AuditQuery], which keys a provider family; a window with reference equality
/// would make every rebuild a cache miss and every cache miss a database round
/// trip.
class AuditWindow {
  const AuditWindow({required this.start, required this.end});

  /// Inclusive lower bound.
  final DateTime start;

  /// Inclusive upper bound.
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'AuditWindow($start .. $end)';
}

/// What the four filter controls hold, as one value.
///
/// The page owns one of these and rebuilds it through [copyWith]; [toQuery] is
/// the only thing that turns it into something the database sees.
class AuditTrailFilters {
  const AuditTrailFilters({
    this.keyPrefix = '',
    this.who,
    List<String>? groupNames,
    this.includeAuth = true,
    this.outcome = AuditOutcomeFilter.any,
    this.range,
  }) : _groupNames = groupNames;

  /// Matched against `item_key` as a prefix. Empty means no key constraint.
  final String keyPrefix;

  /// An exact `who`, chosen from [AuditTrailStore.distinctWho]. Null means
  /// everybody.
  final String? who;

  /// Null means "whatever the page opens with" — see [groupNames].
  final List<String>? _groupNames;

  /// Whether auth rows — sign-ins, sign-outs, failed attempts and timeouts —
  /// are shown.
  ///
  /// Its own flag rather than a group name, because auth rows carry an **empty**
  /// `group_required` and so cannot be named by one.
  final bool includeAuth;

  /// Allowed, denied, or both.
  final AuditOutcomeFilter outcome;

  /// An explicitly chosen window. Null means [toQuery] decides — which is the
  /// whole of the two-mode rule.
  final AuditWindow? range;

  /// The selected `group_required` values.
  ///
  /// **Empty means no group constraint at all**, exactly as
  /// `AlarmLevelFilterChips` behaves (`lib/widgets/alarm.dart:96-101`) — the
  /// semantics the operator has already learned. It reads backwards on first
  /// encounter, and it is the locked decision; see [AuditTrailStore.entries]
  /// for the query-side half and the reason it is written down twice.
  List<String> get groupNames => _groupNames ?? kAuditTrailDefaultGroupNames;

  /// True once the operator has asked a question about a key or a person.
  ///
  /// This is what flips [toQuery] into whole-table mode. A whitespace-only
  /// [keyPrefix] does not count: a stray space in the search field must not
  /// silently drop the seven-day bound.
  bool get isSearching => keyPrefix.trim().isNotEmpty || who != null;

  /// True of the value a freshly opened page holds.
  ///
  /// 05-05's "Clear filters" button is shown when this is false, and the empty
  /// state's copy differs depending on it.
  bool get isDefault =>
      keyPrefix.trim().isEmpty &&
      who == null &&
      range == null &&
      includeAuth &&
      outcome == AuditOutcomeFilter.any &&
      _sameStrings(groupNames, kAuditTrailDefaultGroupNames);

  /// The default filters — the same value a freshly opened page holds.
  AuditTrailFilters cleared() => const AuditTrailFilters();

  /// A copy with only the named fields replaced.
  ///
  /// [who] and [range] are nullable, so a bare parameter cannot say "set this
  /// to null" — passing null is indistinguishable from omitting it. The filter
  /// bar needs both meanings (clearing the `who` dropdown is not the same
  /// gesture as changing the key prefix), so each nullable field gets a
  /// companion [clearWho] / [clearRange] flag.
  AuditTrailFilters copyWith({
    String? keyPrefix,
    String? who,
    bool clearWho = false,
    List<String>? groupNames,
    bool? includeAuth,
    AuditOutcomeFilter? outcome,
    AuditWindow? range,
    bool clearRange = false,
  }) =>
      AuditTrailFilters(
        keyPrefix: keyPrefix ?? this.keyPrefix,
        who: clearWho ? null : (who ?? this.who),
        groupNames: groupNames ?? _groupNames,
        includeAuth: includeAuth ?? this.includeAuth,
        outcome: outcome ?? this.outcome,
        range: clearRange ? null : (range ?? this.range),
      );

  /// The statement this filter state describes, as of [now].
  ///
  /// ## The two modes, and the user's ruling behind them
  ///
  /// The page must answer two different questions with the same controls.
  /// *"What happened here lately"* is the last seven days, capped at 500 rows.
  /// *"Has anyone **ever** written this key"* is the whole table, capped at 500
  /// rows. The user overrode the original "newest 500, no time bound" proposal
  /// specifically to get both, in these words: searching must answer "has
  /// anyone ever written this key", not "did anyone this week". A search that
  /// silently covered only the default window would be a wrong answer that
  /// looks like a right one.
  ///
  /// ## Precedence, in order
  ///
  /// 1. An explicit [range] wins over everything. The operator asked for that
  ///    window and gets exactly it, search term or not.
  /// 2. Otherwise, [isSearching] drops the time bound entirely — the whole
  ///    table, newest 500 matches. **This is the rule somebody will be tempted
  ///    to "simplify" away**, because confining a search to the loaded window
  ///    is the cheaper implementation and looks identical until the row you
  ///    wanted is eight days old.
  /// 3. Otherwise, [kAuditTrailDefaultWindow] back from [now].
  ///
  /// There is no fourth mode. No "search within the current window" toggle, no
  /// "last 30 days" convenience that quietly becomes the default. Two modes and
  /// one explicit override.
  ///
  /// [before] is the "Load more" cursor and is carried through untouched, so
  /// paging narrows an existing window rather than replacing the rule that
  /// produced it.
  AuditQuery toQuery({required DateTime now, DateTime? before}) {
    final AuditWindow? window;
    if (range != null) {
      window = range;
    } else if (isSearching) {
      window = null;
    } else {
      window = AuditWindow(
        start: now.subtract(kAuditTrailDefaultWindow),
        end: now,
      );
    }

    return AuditQuery(
      window: window,
      before: before,
      keyPrefix: keyPrefix,
      who: who,
      groupNames: groupNames,
      includeAuth: includeAuth,
      outcome: outcome,
      limit: kAuditTrailRowLimit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditTrailFilters &&
          other.keyPrefix == keyPrefix &&
          other.who == who &&
          other.includeAuth == includeAuth &&
          other.outcome == outcome &&
          other.range == range &&
          _sameStrings(other.groupNames, groupNames);

  @override
  int get hashCode => Object.hash(
        keyPrefix,
        who,
        includeAuth,
        outcome,
        range,
        Object.hashAll(groupNames),
      );

  @override
  String toString() => 'AuditTrailFilters(keyPrefix: "$keyPrefix", who: $who, '
      'groups: $groupNames, auth: $includeAuth, outcome: ${outcome.name}, '
      'range: $range)';
}

/// One resolved query: everything [AuditTrailStore.entries] needs and nothing
/// it has to decide.
///
/// A value type with full equality, because 05-04 keys a provider family on it.
/// A family keyed on a broken `==` re-queries the database on every rebuild.
class AuditQuery {
  AuditQuery({
    this.window,
    this.before,
    String keyPrefix = '',
    this.who,
    Iterable<String> groupNames = const [],
    this.includeAuth = true,
    this.outcome = AuditOutcomeFilter.any,
    this.limit = kAuditTrailRowLimit,
  })  : keyPrefix = keyPrefix.trim(),
        groupNames = List.unmodifiable(groupNames.toSet().toList()..sort());

  /// The time bound, or null for **the whole table** — the search escape.
  final AuditWindow? window;

  /// The "Load more" cursor: rows strictly older than this. Composes with
  /// [window] rather than replacing it.
  final DateTime? before;

  /// Trimmed. Empty means no key constraint.
  final String keyPrefix;

  /// Exact match on `who`, or null.
  final String? who;

  /// Sorted and duplicate-free, so equality does not depend on chip tap order.
  final List<String> groupNames;

  /// Whether `surface = 'auth'` rows are OR'd in.
  final bool includeAuth;

  /// Allowed, denied, or both.
  final AuditOutcomeFilter outcome;

  /// Applied after every `WHERE` clause, never instead of one.
  final int limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditQuery &&
          other.window == window &&
          other.before == before &&
          other.keyPrefix == keyPrefix &&
          other.who == who &&
          other.includeAuth == includeAuth &&
          other.outcome == outcome &&
          other.limit == limit &&
          _sameStrings(other.groupNames, groupNames);

  @override
  int get hashCode => Object.hash(
        window,
        before,
        keyPrefix,
        who,
        includeAuth,
        outcome,
        limit,
        Object.hashAll(groupNames),
      );

  @override
  String toString() => 'AuditQuery(window: ${window ?? "whole table"}, '
      'before: $before, keyPrefix: "$keyPrefix", who: $who, '
      'groups: $groupNames, auth: $includeAuth, outcome: ${outcome.name}, '
      'limit: $limit)';
}

/// Element-wise list equality, so the two value types above do not need a
/// `package:collection` import this library otherwise has no use for.
bool _sameStrings(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

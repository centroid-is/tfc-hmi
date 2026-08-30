/// The shape the audit trail page renders: one entry per `actionId`, not one
/// per row.
///
/// `guarded_state_man.dart` writes one row per changed member and shares one
/// `actionId` across them (`auditRecordsForChanges`), so a recipe apply is one
/// human action with N rows underneath it. Rendering those as N unrelated lines
/// is the thing Phase 5 exists to stop.
///
/// Everything here is a pure top-level function over value types, the way
/// `alarmHistoryEntries` (`lib/widgets/alarm.dart`) and
/// `dynamic_value_diff.dart` are built. No widget, no provider, no database:
/// nothing here imports Flutter, a grep asserts it, and nothing here may start
/// to — the moment this file needs a `BuildContext` it has stopped being the
/// transform the page is tested through.
library;

import 'package:tfc_dart/core/database_drift.dart';

/// One human action and the rows of it this query could see.
///
/// Built only by [groupAuditRows], which never produces an empty [rows], so
/// [lead] is always safe.
class AuditAction {
  const AuditAction({
    required this.actionId,
    required this.rows,
    required this.totalRowCount,
  });

  /// The correlation id every row in [rows] shares.
  final String actionId;

  /// The rows of this action that survived the filters, in the order the store
  /// returned them — newest-first, and never re-sorted here.
  final List<AuditEntryData> rows;

  /// How many rows this action has in the table, filters aside.
  ///
  /// Supplied by `AuditTrailStore.memberCountsByAction`, a companion
  /// `COUNT(*) GROUP BY action_id` issued outside the filter predicate
  /// precisely so this number can exist. All filtering happens in SQL, so an
  /// action's non-matching siblings are not in the result set and cannot be
  /// counted from [rows].
  ///
  /// When the store did not supply a total this falls back to `rows.length` —
  /// "we did not ask", not "there are no others". A caller that skips the
  /// companion query therefore degrades to a flat, honest list rather than to a
  /// list claiming every action is complete.
  final int totalRowCount;

  /// The row the collapsed line is drawn from.
  AuditEntryData get lead => rows.first;

  /// How many of this action's rows the filters excluded.
  ///
  /// Clamped at zero: a stale or wrong total must never produce
  /// "-2 members hidden" on a parent row.
  int get hiddenCount {
    final hidden = totalRowCount - rows.length;
    return hidden > 0 ? hidden : 0;
  }

  /// True when this view of the action is incomplete, and the parent row must
  /// say so rather than presenting a subset as the whole record.
  bool get isPartial => hiddenCount > 0;

  /// True when the action gets an expander.
  ///
  /// More than one visible row **or** any hidden sibling. A single visible row
  /// with eight hidden ones still expands, because otherwise the
  /// "8 of 9 members hidden by filters" line has nowhere to live.
  bool get isMulti => rows.length > 1 || hiddenCount > 0;
}

/// A flat newest-first row list as one entry per `actionId`, in the order the
/// actions first appear.
///
/// ## Why this is map-based and not adjacency-based
///
/// `action_id` has no index, so grouping is client-side. Several SVN stations
/// share one database and rows come back ordered by `at`, so another station's
/// write landing between two members of a local struct write is routine rather
/// than exotic. Adjacency grouping would split that action in two, and neither
/// half would say so — it would render as two complete actions that each
/// under-report what happened.
///
/// ## Ordering
///
/// A plain `Map` is used and its iteration order is relied on: Dart's default
/// `Map` is a `LinkedHashMap` and iterates in key-insertion order. That is not
/// incidental — first-appearance order is the whole output contract. The input
/// is newest-first, so the output is newest-action-first, and no sort happens
/// here: the ordering rule lives in the store's `ORDER BY at DESC` and a second
/// copy of it would be a second thing to keep in step.
///
/// ## What this does not do
///
/// It does not filter. It receives what SQL returned and adds nothing back —
/// the reason [totalsByActionId] is passed in at all is that the excluded rows
/// are not available to be re-included.
List<AuditAction> groupAuditRows(
  List<AuditEntryData> rows, {
  Map<String, int> totalsByActionId = const {},
}) {
  final byAction = <String, List<AuditEntryData>>{};
  for (final row in rows) {
    byAction.putIfAbsent(row.actionId, () => <AuditEntryData>[]).add(row);
  }

  return [
    for (final entry in byAction.entries)
      AuditAction(
        actionId: entry.key,
        rows: List.unmodifiable(entry.value),
        // An absent total means the companion query was not run, so the visible
        // rows are all this can claim. Never zero: zero would be a statement
        // about the action rather than the absence of one.
        totalRowCount: totalsByActionId[entry.key] ?? entry.value.length,
      ),
  ];
}

// One human action is one group, wherever its rows landed in the window.
//
// This is a pure-function suite and must stay one. There is no database handle,
// no Drift connection and no `AppDatabase` in this file: `groupAuditRows` takes
// a list and returns a list, so a test that needed a database would be testing
// something other than the function.
//
// Every row is built by the local `row(...)` helper against fixed
// `DateTime.utc(...)` instants. Nothing here reads the clock — an assertion
// computed from `DateTime.now()` cannot fail when the rule it is about changes.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/audit_trail_grouping.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// The instant the rows in this file are dated from.
final DateTime _at = DateTime.utc(2026, 8, 30, 12);

int _nextId = 1;

/// One `audit_entry` row, with only the fields a grouping assertion cares about
/// spelled at the call site.
///
/// `id` is auto-assigned and ascending so two rows built with the same arguments
/// are still distinguishable; nothing in `groupAuditRows` reads it.
AuditEntryData row({
  required String actionId,
  DateTime? at,
  String itemKey = 'CN04.MOT01.Speed',
  String? member,
  String groupRequired = 'setpoints',
  bool allowed = true,
  String surface = 'tag',
  String who = 'olafur',
}) =>
    AuditEntryData(
      id: _nextId++,
      at: at ?? _at,
      who: who,
      station: 'ST101',
      roleName: 'engineer',
      surface: surface,
      itemKey: itemKey,
      member: member,
      oldValue: '1',
      newValue: '2',
      groupRequired: groupRequired,
      allowed: allowed,
      origin: 'operator',
      actionId: actionId,
    );

void main() {
  setUp(() => _nextId = 1);

  // -------------------------------------------------------------------------
  // groupAuditRows
  // -------------------------------------------------------------------------

  group('groupAuditRows', () {
    test('an empty row list yields an empty action list', () {
      expect(groupAuditRows(const []), isEmpty);
    });

    test('groups appear in the order their first row appears in the input', () {
      final actions = groupAuditRows([
        row(actionId: 'c', at: DateTime.utc(2026, 8, 30, 12)),
        row(actionId: 'b', at: DateTime.utc(2026, 8, 30, 11)),
        row(actionId: 'a', at: DateTime.utc(2026, 8, 30, 10)),
      ]);

      expect(actions.map((action) => action.actionId), ['c', 'b', 'a'],
          reason: 'the store returns rows newest-first, so first-appearance '
              'order is newest-action-first. Sorting here would be a second '
              'ordering rule to keep in step with the SQL one.');
    });

    test('interleaved actions are grouped by actionId, not by adjacency', () {
      // A, B, A, B, A - an adjacency implementation produces five groups here,
      // which is exactly the defect this test exists to catch. Another SVN
      // station writing into the same database between two members of a local
      // struct write produces precisely this shape.
      final actions = groupAuditRows([
        row(actionId: 'A', member: 'p_cfg.Freq'),
        row(actionId: 'B', itemKey: 'CN09.MOT01.Speed'),
        row(actionId: 'A', member: 'p_cfg.Ramp'),
        row(actionId: 'B', itemKey: 'CN09.MOT01.Speed', member: 'p_cfg.Freq'),
        row(actionId: 'A', member: 'p_cfg.Accel'),
      ]);

      expect(actions.length, 2,
          reason: 'two actionIds means two actions however far apart another '
              'station pushed their rows');
      expect(actions.map((action) => action.actionId), ['A', 'B']);
      expect(actions.map((action) => action.rows.length), [3, 2]);
    });

    test('rows within a group keep their input order', () {
      final actions = groupAuditRows([
        row(actionId: 'A', member: 'p_cfg.Freq'),
        row(actionId: 'B'),
        row(actionId: 'A', member: 'p_cfg.Ramp'),
        row(actionId: 'A', member: 'p_cfg.Accel'),
      ]);

      expect(actions.first.rows.map((r) => r.member),
          ['p_cfg.Freq', 'p_cfg.Ramp', 'p_cfg.Accel']);
    });

    test('lead is the first row of the group', () {
      final first = row(actionId: 'A', member: 'p_cfg.Freq');
      final actions = groupAuditRows([
        first,
        row(actionId: 'A', member: 'p_cfg.Ramp'),
      ]);

      expect(actions.single.lead, same(first));
    });

    test('totalRowCount comes from totalsByActionId when the id is present',
        () {
      final actions = groupAuditRows(
        [row(actionId: 'A'), row(actionId: 'A')],
        totalsByActionId: const {'A': 9},
      );

      expect(actions.single.totalRowCount, 9);
    });

    test('an absent total falls back to rows.length - "we did not ask"', () {
      final actions = groupAuditRows([row(actionId: 'A'), row(actionId: 'A')]);

      expect(actions.single.totalRowCount, 2,
          reason: 'a caller that skipped the companion count query must '
              'degrade to a flat honest list, not to a claim that six '
              'siblings are missing');
      expect(actions.single.hiddenCount, 0);
      expect(actions.single.isPartial, isFalse);
    });

    test('three visible rows of a nine-row action report six hidden', () {
      final actions = groupAuditRows(
        [row(actionId: 'A'), row(actionId: 'A'), row(actionId: 'A')],
        totalsByActionId: const {'A': 9},
      );

      expect(actions.single.hiddenCount, 6);
      expect(actions.single.isPartial, isTrue);
      expect(actions.single.isMulti, isTrue);
    });

    test('a total smaller than rows.length clamps to zero, never negative', () {
      final actions = groupAuditRows(
        [row(actionId: 'A'), row(actionId: 'A'), row(actionId: 'A')],
        totalsByActionId: const {'A': 1},
      );

      expect(actions.single.hiddenCount, 0,
          reason: 'a stale or wrong total is a bad count, and "-2 members '
              'hidden" on the parent row would be worse than one');
      expect(actions.single.isPartial, isFalse);
    });

    test('a single visible row with hidden siblings is still multi', () {
      final actions = groupAuditRows(
        [row(actionId: 'A')],
        totalsByActionId: const {'A': 9},
      );

      expect(actions.single.isMulti, isTrue,
          reason: 'without an expander the "8 of 9 members hidden by filters" '
              'line has nowhere to live');
      expect(actions.single.hiddenCount, 8);
    });

    test('a single-row action with no total renders flat', () {
      final actions = groupAuditRows([row(actionId: 'A')]);

      expect(actions.single.isMulti, isFalse,
          reason: 'most rows are single writes and an expander on every one is '
              'noise');
      expect(actions.single.isPartial, isFalse);
      expect(actions.single.hiddenCount, 0);
    });

    test('no group is ever empty, so lead is always safe to call', () {
      final actions = groupAuditRows([
        row(actionId: 'A'),
        row(actionId: 'B'),
        row(actionId: 'A'),
      ]);

      expect(actions.every((action) => action.rows.isNotEmpty), isTrue);
      for (final action in actions) {
        expect(action.lead, same(action.rows.first));
      }
    });

    test('totals for actionIds not in the input are ignored', () {
      final actions = groupAuditRows(
        [row(actionId: 'A')],
        totalsByActionId: const {'A': 2, 'ZZ': 400},
      );

      expect(actions.map((action) => action.actionId), ['A'],
          reason: 'the totals map is a lookup, never a source of actions - a '
              'group with no visible rows has nothing to render');
    });
  });
}

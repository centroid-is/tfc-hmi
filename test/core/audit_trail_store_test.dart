// The first reader of `audit_entry`, and the two-mode rule that decides how far
// back it reaches.
//
// The tests in the first group need no database at all: the seven-day default
// and the whole-table search escape are a pure function on a value type, driven
// from a fixed `DateTime.utc(2026, 8, 30, 12)` so the window assertions are
// exact rather than nearly exact.
//
// Every window assertion is written against that fixed instant and never
// against `DateTime.now()`. A test that computes its own expectation from the
// clock cannot fail when the rule it is about changes.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/audit_trail_store.dart';
import 'package:tfc_access/tfc_access.dart';

/// The instant every window assertion is written against.
final DateTime _now = DateTime.utc(2026, 8, 30, 12);

void main() {
  // -------------------------------------------------------------------------
  // The constant
  // -------------------------------------------------------------------------

  group('kAuditTrailGroup', () {
    test('is users, and is the only group this file names', () {
      expect(kAuditTrailGroup, AccessGroup.users,
          reason: 'the trail shows every old and new value anybody ever wrote, '
              'including on keys this reader may not write. Lowering it to '
              'configure would put every setpoint change ever made in front of '
              'anyone who can edit a page. The route gate is the enforcement '
              'and this constant is what the route is spelled from; 05-07 adds '
              'the test that the two agree.');
    });
  });

  // -------------------------------------------------------------------------
  // isSearching — what flips the query into whole-table mode
  // -------------------------------------------------------------------------

  group('AuditTrailFilters.isSearching', () {
    test('is false with no key prefix and no who', () {
      expect(const AuditTrailFilters().isSearching, isFalse);
    });

    test('is true with a key prefix', () {
      expect(const AuditTrailFilters(keyPrefix: 'CN04').isSearching, isTrue);
    });

    test('is true with a who', () {
      expect(const AuditTrailFilters(who: 'engineer').isSearching, isTrue);
    });

    test('treats a whitespace-only key prefix as empty', () {
      expect(const AuditTrailFilters(keyPrefix: '   ').isSearching, isFalse,
          reason: 'a stray space in the search field must not silently drop '
              'the seven-day bound and pull the whole table back.');
    });
  });

  // -------------------------------------------------------------------------
  // toQuery — the two-mode window rule the user overrode for
  // -------------------------------------------------------------------------

  group('toQuery — the last seven days, capped at 500', () {
    test('the default window is exactly now minus seven days, to now', () {
      final query = const AuditTrailFilters().toQuery(now: _now);

      expect(query.window, isNotNull);
      expect(query.window!.start, DateTime.utc(2026, 8, 23, 12));
      expect(query.window!.end, _now);
    });

    test('the default query is capped at 500 rows', () {
      expect(const AuditTrailFilters().toQuery(now: _now).limit, 500);
      expect(kAuditTrailRowLimit, 500);
    });

    test('the default window duration is seven days', () {
      expect(kAuditTrailDefaultWindow, const Duration(days: 7));
    });
  });

  group('toQuery — the whole-table search escape', () {
    test('a key prefix drops the time bound entirely', () {
      final query =
          const AuditTrailFilters(keyPrefix: 'CN04').toQuery(now: _now);

      expect(query.window, isNull,
          reason: 'searching must answer "has anyone ever written this key", '
              'not "did anyone this week". A search confined to the default '
              'window is a wrong answer that looks like a right one.');
    });

    test('a who drops the time bound entirely', () {
      final query =
          const AuditTrailFilters(who: 'engineer').toQuery(now: _now);

      expect(query.window, isNull,
          reason: 'choosing a person asks what that person has ever done, on '
              'the same terms as a key prefix.');
    });

    test('the whole-table search is still capped at 500 rows', () {
      final query =
          const AuditTrailFilters(keyPrefix: 'CN04').toQuery(now: _now);

      expect(query.limit, 500,
          reason: 'the search escapes the time bound and never the row bound; '
              'a year of rows must not come back in one statement.');
    });
  });

  group('toQuery — an explicit range beats both', () {
    final range = AuditWindow(
      start: DateTime.utc(2026, 1, 1),
      end: DateTime.utc(2026, 2, 1),
    );

    test('an explicit range wins over a set key prefix', () {
      final query = AuditTrailFilters(keyPrefix: 'CN04', range: range)
          .toQuery(now: _now);

      expect(query.window, range,
          reason: 'the operator asked for that window and gets exactly it, '
              'search term or not.');
    });

    test('an explicit range wins over the seven-day default', () {
      final query = AuditTrailFilters(range: range).toQuery(now: _now);

      expect(query.window, range);
    });
  });

  group('toQuery — the load-more cursor', () {
    test('before is carried through and changes nothing else', () {
      final cursor = DateTime.utc(2026, 8, 25, 9);
      final plain = const AuditTrailFilters().toQuery(now: _now);
      final paged =
          const AuditTrailFilters().toQuery(now: _now, before: cursor);

      expect(paged.before, cursor);
      expect(plain.before, isNull);
      expect(paged.window, plain.window,
          reason: '"Load more" narrows an existing window rather than '
              'replacing the rule that produced it.');
      expect(paged.limit, plain.limit);
      expect(paged.groupNames, plain.groupNames);
      expect(paged.includeAuth, plain.includeAuth);
      expect(paged.outcome, plain.outcome);
    });
  });

  // -------------------------------------------------------------------------
  // Defaults, cleared() and isDefault
  // -------------------------------------------------------------------------

  group('AuditTrailFilters defaults', () {
    test('selects every group except operate, in enum declaration order', () {
      final expected = AccessGroup.values
          .where((group) => group != AccessGroup.operate)
          .map((group) => group.name)
          .toList();

      expect(const AuditTrailFilters().groupNames, expected,
          reason: 'the ROADMAP names exactly one exclusion and no others. '
              'Derived from AccessGroup.values rather than a hand-typed '
              'literal, so an eighth group cannot slip past this.');
      expect(
          const AuditTrailFilters().groupNames, isNot(contains('operate')));
    });

    test('includes auth rows by default', () {
      expect(const AuditTrailFilters().includeAuth, isTrue,
          reason: 'auth rows carry an empty group_required, so they would be '
              'collateral damage of the group filter unless they are '
              'deliberately included.');
    });

    test('shows allowed and denied alike by default', () {
      expect(const AuditTrailFilters().outcome, AuditOutcomeFilter.any);
    });

    test('cleared() returns the default filters', () {
      final dirty = AuditTrailFilters(
        keyPrefix: 'CN04',
        who: 'engineer',
        groupNames: const ['operate'],
        includeAuth: false,
        outcome: AuditOutcomeFilter.deniedOnly,
        range: AuditWindow(
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 2, 1),
        ),
      );

      expect(dirty.cleared(), const AuditTrailFilters());
      expect(dirty.cleared().isDefault, isTrue);
    });

    test('isDefault is true of a freshly opened page', () {
      expect(const AuditTrailFilters().isDefault, isTrue);
    });

    test('isDefault is false of a key prefix', () {
      expect(const AuditTrailFilters(keyPrefix: 'CN04').isDefault, isFalse);
    });

    test('isDefault is false of a who', () {
      expect(const AuditTrailFilters(who: 'engineer').isDefault, isFalse);
    });

    test('isDefault is false of an explicit range', () {
      expect(
          AuditTrailFilters(
            range: AuditWindow(
              start: DateTime.utc(2026, 1, 1),
              end: DateTime.utc(2026, 2, 1),
            ),
          ).isDefault,
          isFalse);
    });

    test('isDefault is false of a non-any outcome', () {
      expect(
          const AuditTrailFilters(outcome: AuditOutcomeFilter.deniedOnly)
              .isDefault,
          isFalse);
    });

    test('isDefault is false of a different group set', () {
      expect(const AuditTrailFilters(groupNames: []).isDefault, isFalse);
      expect(const AuditTrailFilters(includeAuth: false).isDefault, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // AuditQuery and AuditWindow value semantics
  // -------------------------------------------------------------------------

  group('AuditQuery value semantics', () {
    test('two independently built identical queries are == and hash equal', () {
      final a = AuditQuery(
        window: AuditWindow(start: DateTime.utc(2026, 8, 23), end: _now),
        keyPrefix: 'CN04',
        who: 'engineer',
        groupNames: const ['users', 'device'],
        outcome: AuditOutcomeFilter.deniedOnly,
      );
      final b = AuditQuery(
        window: AuditWindow(start: DateTime.utc(2026, 8, 23), end: _now),
        keyPrefix: 'CN04',
        who: 'engineer',
        groupNames: const ['users', 'device'],
        outcome: AuditOutcomeFilter.deniedOnly,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode,
          reason: 'a provider family keyed on a broken == re-queries the '
              'database on every rebuild.');
    });

    test('groupNames is sorted and duplicate-free however the chips were '
        'tapped', () {
      final tappedOneWay =
          AuditQuery(groupNames: const ['users', 'device', 'users']);
      final tappedAnother = AuditQuery(groupNames: const ['device', 'users']);

      expect(tappedOneWay.groupNames, const ['device', 'users']);
      expect(tappedOneWay, tappedAnother,
          reason: 'equality must not depend on chip tap order.');
      expect(tappedOneWay.hashCode, tappedAnother.hashCode);
    });

    test('a differing field breaks equality', () {
      expect(AuditQuery(keyPrefix: 'CN04'), isNot(AuditQuery(keyPrefix: 'CN05')));
      expect(AuditQuery(limit: 500), isNot(AuditQuery(limit: 100)));
      expect(AuditQuery(includeAuth: true), isNot(AuditQuery(includeAuth: false)));
    });
  });

  group('AuditWindow value semantics', () {
    test('two independently constructed windows with the same bounds are '
        'equal and hash equal', () {
      final a = AuditWindow(
          start: DateTime.utc(2026, 8, 23, 12), end: DateTime.utc(2026, 8, 30, 12));
      final b = AuditWindow(
          start: DateTime.utc(2026, 8, 23, 12), end: DateTime.utc(2026, 8, 30, 12));

      expect(a, b);
      expect(a.hashCode, b.hashCode,
          reason: "AuditQuery's own equality is only as good as this one, "
              'because the window is a field on it — and 05-05 and 05-06 both '
              'build AuditWindow values of their own, so this is a cross-plan '
              'contract rather than an implementation detail.');
    });

    test('a window differing by a microsecond is not equal', () {
      final a = AuditWindow(
          start: DateTime.utc(2026, 8, 23, 12), end: DateTime.utc(2026, 8, 30, 12));
      final b = AuditWindow(
        start: DateTime.utc(2026, 8, 23, 12),
        end: DateTime.utc(2026, 8, 30, 12).add(const Duration(microseconds: 1)),
      );

      expect(a, isNot(b));
    });
  });

  // -------------------------------------------------------------------------
  // copyWith — the filter bar's only mutator
  // -------------------------------------------------------------------------

  group('AuditTrailFilters.copyWith', () {
    final range = AuditWindow(
      start: DateTime.utc(2026, 1, 1),
      end: DateTime.utc(2026, 2, 1),
    );

    test('replaces only the named field', () {
      final before = AuditTrailFilters(
        keyPrefix: 'CN04',
        who: 'engineer',
        groupNames: const ['users'],
        includeAuth: false,
        range: range,
      );

      final after = before.copyWith(outcome: AuditOutcomeFilter.deniedOnly);

      expect(after.outcome, AuditOutcomeFilter.deniedOnly);
      expect(after.keyPrefix, 'CN04');
      expect(after.who, 'engineer');
      expect(after.groupNames, const ['users']);
      expect(after.includeAuth, isFalse);
      expect(after.range, range);
    });

    test('who can be cleared, and omitting it leaves a set value in place', () {
      const before = AuditTrailFilters(who: 'engineer');

      expect(before.copyWith(clearWho: true).who, isNull);
      expect(before.copyWith(keyPrefix: 'CN04').who, 'engineer',
          reason: '"leave it alone" and "set it to null" are different calls; '
              'a bare nullable parameter cannot express the second and the '
              'filter bar needs both.');
      expect(before.copyWith(who: 'admin').who, 'admin');
    });

    test('range can be cleared, and omitting it leaves a set value in place',
        () {
      final before = AuditTrailFilters(range: range);

      expect(before.copyWith(clearRange: true).range, isNull);
      expect(before.copyWith(keyPrefix: 'CN04').range, range);
    });

    test('replaces the group set and the auth flag', () {
      final after = const AuditTrailFilters()
          .copyWith(groupNames: const [], includeAuth: false);

      expect(after.groupNames, isEmpty);
      expect(after.includeAuth, isFalse);
    });
  });
}

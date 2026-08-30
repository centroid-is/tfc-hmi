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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/audit_trail_store.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/drift_audit_sink.dart';
import 'package:tfc_dart/core/database_drift.dart';

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

  // -------------------------------------------------------------------------
  // entries — one statement, every filter in WHERE, the limit last
  // -------------------------------------------------------------------------

  group('AuditTrailStore.entries', () {
    late AppDatabase db;

    AuditTrailStore store() => AuditTrailStore(db: db);

    /// Appends one row through the trail's only writer.
    ///
    /// Going through [DriftAuditSink] rather than inserting a companion
    /// directly is what keeps this fixture honest about column mapping: a
    /// renamed column breaks the seed as well as the query.
    Future<void> seed({
      required DateTime at,
      String who = 'engineer',
      String itemKey = 'CN04.MOT01.p_cmd_Run',
      String? member,
      String groupRequired = 'configure',
      bool allowed = true,
      String surface = 'tag',
      String origin = 'operator',
      String actionId = 'action-a',
    }) =>
        DriftAuditSink(db).record(AuditRecord(
          at: at,
          who: who,
          station: 'SVN-NES-OT-CL02',
          roleName: 'Engineering',
          surface: surface,
          itemKey: itemKey,
          member: member,
          oldValue: '0',
          newValue: '1',
          groupRequired: groupRequired,
          allowed: allowed,
          origin: origin,
          actionId: actionId,
        ));

    Future<List<AuditEntryData>> run(AuditTrailFilters filters) =>
        store().entries(filters.toQuery(now: _now));

    setUp(() async {
      db = AppDatabase.inMemoryForTest();
      // Force the schema before the first store call, so an empty result is a
      // real empty table rather than a missing one.
      await db.customSelect('SELECT 1').getSingle();
    });

    tearDown(() => db.close());

    // -----------------------------------------------------------------------
    // Ordering
    // -----------------------------------------------------------------------

    test('returns rows newest first', () async {
      await seed(at: _now.subtract(const Duration(hours: 3)), itemKey: 'old');
      await seed(at: _now.subtract(const Duration(hours: 1)), itemKey: 'new');

      final rows = await run(const AuditTrailFilters());

      expect(rows.map((r) => r.itemKey), ['new', 'old']);
    });

    test('ties on at resolve by id descending', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, member: 'p_cfg.Freq');
      await seed(at: at, member: 'p_cfg.Ramp');
      await seed(at: at, member: 'p_cfg.Accel');

      final rows = await run(const AuditTrailFilters());

      expect(rows.map((r) => r.id), [3, 2, 1],
          reason: "a struct write's member rows all share an at, so without a "
              'tiebreak the order is whatever the engine felt like.');
    });

    test('the same query run twice returns identical id sequences', () async {
      final at = _now.subtract(const Duration(hours: 1));
      for (var i = 0; i < 5; i++) {
        await seed(at: at, member: 'p_cfg.M$i');
      }
      await seed(at: _now.subtract(const Duration(hours: 2)));

      final first = await run(const AuditTrailFilters());
      final second = await run(const AuditTrailFilters());

      expect(first.map((r) => r.id).toList(),
          second.map((r) => r.id).toList());
    });

    // -----------------------------------------------------------------------
    // The window, and the escape from it
    // -----------------------------------------------------------------------

    test('a window bounds the rows to it', () async {
      await seed(at: _now.subtract(const Duration(days: 1)), itemKey: 'inside');
      await seed(
          at: _now.subtract(const Duration(days: 10)), itemKey: 'outside');

      final rows = await run(const AuditTrailFilters());

      expect(rows.map((r) => r.itemKey), ['inside']);
    });

    test('a null window applies no time predicate at all', () async {
      await seed(at: _now.subtract(const Duration(days: 400)), itemKey: 'ancient');

      final rows = await store().entries(AuditQuery(limit: 500));

      expect(rows.map((r) => r.itemKey), ['ancient']);
    });

    test('the whole-table search escape is observable in SQL, not merely in '
        'the query object', () async {
      await seed(
          at: _now.subtract(const Duration(days: 30)),
          itemKey: 'CN04.MOT01.p_cmd_Run');

      final defaulted = await run(const AuditTrailFilters());
      final searched = await run(const AuditTrailFilters(keyPrefix: 'CN04'));

      expect(defaulted, isEmpty,
          reason: 'thirty days is outside the seven-day default window.');
      expect(searched, hasLength(1),
          reason: 'searching must answer "has anyone ever written this key", '
              'not "did anyone this week".');
    });

    test('before adds at < cursor and composes with the window', () async {
      await seed(at: _now.subtract(const Duration(hours: 1)), itemKey: 'newest');
      await seed(at: _now.subtract(const Duration(hours: 5)), itemKey: 'middle');
      await seed(at: _now.subtract(const Duration(days: 30)), itemKey: 'ancient');

      final rows = await store().entries(
        const AuditTrailFilters().toQuery(
          now: _now,
          before: _now.subtract(const Duration(hours: 3)),
        ),
      );

      expect(rows.map((r) => r.itemKey), ['middle'],
          reason: 'the cursor excluded the newest row and the seven-day window '
              'still excluded the ancient one — the two compose rather than '
              'one replacing the other.');
    });

    // -----------------------------------------------------------------------
    // The key prefix
    // -----------------------------------------------------------------------

    test('a key prefix matches item_key as a prefix', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, itemKey: 'CN04.MOT01.p_cmd_Run');
      await seed(at: at, itemKey: 'CN21.MOT01.p_cmd_Run');

      final rows = await run(const AuditTrailFilters(keyPrefix: 'CN04'));

      expect(rows.map((r) => r.itemKey), ['CN04.MOT01.p_cmd_Run']);
    });

    test('a key prefix containing SQL metacharacters returns rows or no rows, '
        'and never changes the shape of the statement', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, itemKey: 'CN04.MOT01.p_cmd_Run');
      await seed(at: at, itemKey: 'CN21.MOT01.p_cmd_Run');

      final rows = await run(const AuditTrailFilters(keyPrefix: "x' OR 1=1 --"));

      expect(rows, isEmpty,
          reason: 'the prefix reaches SQLite as a bound variable. If it were '
              'interpolated, OR 1=1 would have returned both seeded rows.');
    });

    test('an underscore in the prefix acts as a LIKE wildcard — documented '
        'behaviour, not a defect', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, itemKey: 'CN04.MOT01');
      await seed(at: at, itemKey: 'CN14.MOT01');
      await seed(at: at, itemKey: 'BA01.MOT01');

      final rows = await run(const AuditTrailFilters(keyPrefix: 'CN_4'));

      expect(rows.map((r) => r.itemKey).toSet(), {'CN04.MOT01', 'CN14.MOT01'},
          reason: 'a hand-rolled ESCAPE clause diverges between SQLite and '
              'Postgres. Widening the match is the accepted cost; it never '
              'narrows it and never reaches a row the group filter excluded.');
    });

    // -----------------------------------------------------------------------
    // who and outcome
    // -----------------------------------------------------------------------

    test('who matches exactly', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, who: 'engineer');
      await seed(at: at, who: 'admin');

      final rows = await run(const AuditTrailFilters(who: 'admin'));

      expect(rows.map((r) => r.who), ['admin']);
    });

    test('allowedOnly keeps only allowed rows', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, allowed: true, itemKey: 'yes');
      await seed(at: at, allowed: false, itemKey: 'no');

      final rows = await run(
          const AuditTrailFilters(outcome: AuditOutcomeFilter.allowedOnly));

      expect(rows.map((r) => r.itemKey), ['yes']);
    });

    test('deniedOnly keeps only denials', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, allowed: true, itemKey: 'yes');
      await seed(at: at, allowed: false, itemKey: 'no');

      final rows = await run(
          const AuditTrailFilters(outcome: AuditOutcomeFilter.deniedOnly));

      expect(rows.map((r) => r.itemKey), ['no']);
    });

    test('any adds no outcome predicate', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, allowed: true, itemKey: 'yes');
      await seed(at: at, allowed: false, itemKey: 'no');

      expect(await run(const AuditTrailFilters()), hasLength(2));
    });

    test('filtering happens in SQL, not over the loaded page', () async {
      final at = _now.subtract(const Duration(hours: 1));
      for (var i = 0; i < 30; i++) {
        await seed(at: at, allowed: false, itemKey: 'denied.$i');
      }
      for (var i = 0; i < 30; i++) {
        await seed(at: at, allowed: true, itemKey: 'allowed.$i');
      }

      final rows = await store().entries(AuditQuery(
        window: AuditWindow(start: _now.subtract(const Duration(days: 7)), end: _now),
        outcome: AuditOutcomeFilter.deniedOnly,
        limit: 10,
      ));

      expect(rows, hasLength(10));
      expect(rows.every((r) => !r.allowed), isTrue,
          reason: 'filtering the already-loaded rows in memory would have '
              'shown three denials while the table held three hundred — here '
              'the newest ten rows are all allows, so an in-memory filter '
              'would have returned nothing.');
    });

    // -----------------------------------------------------------------------
    // The group predicate and its auth leg
    // -----------------------------------------------------------------------

    test('the default filters exclude operate and keep everything else',
        () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, groupRequired: 'operate', itemKey: 'jog');
      await seed(at: at, groupRequired: 'configure', itemKey: 'recipe');

      final rows = await run(const AuditTrailFilters());

      expect(rows.map((r) => r.itemKey), ['recipe'],
          reason: 'the ROADMAP names exactly one exclusion: a jog button '
              'pressed four hundred times an hour would be the whole page.');
    });

    test('an operate row comes back once operate is added to the selection',
        () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, groupRequired: 'operate', itemKey: 'jog');

      final rows = await run(AuditTrailFilters(
          groupNames: [...kAuditTrailDefaultGroupNames, 'operate']));

      expect(rows.map((r) => r.itemKey), ['jog']);
    });

    test('auth rows survive the default filter, interleaved with writes',
        () async {
      await seed(
          at: _now.subtract(const Duration(hours: 2)),
          groupRequired: 'configure',
          itemKey: 'recipe');
      await DriftAuditSink(db).record(AuditRecord.login(
        who: 'admin',
        station: 'SVN-NES-OT-CL02',
        roleName: 'Administrator',
        actionId: 'action-login',
        at: _now.subtract(const Duration(hours: 1)),
      ));

      final rows = await run(const AuditTrailFilters());

      expect(rows.map((r) => r.itemKey), ['login', 'recipe'],
          reason: 'auth rows carry an empty group_required, so a bare IN would '
              'drop every sign-in from the page. Interleaving is what '
              'preserves "who signed in right before this write".');
    });

    test('auth rows are excluded when the auth chip is cleared', () async {
      await seed(
          at: _now.subtract(const Duration(hours: 2)),
          groupRequired: 'configure',
          itemKey: 'recipe');
      await DriftAuditSink(db).record(AuditRecord.login(
        who: 'admin',
        station: 'SVN-NES-OT-CL02',
        roleName: 'Administrator',
        actionId: 'action-login',
        at: _now.subtract(const Duration(hours: 1)),
      ));

      final rows = await run(const AuditTrailFilters(includeAuth: false));

      expect(rows.map((r) => r.itemKey), ['recipe'],
          reason: 'they are excluded because the operator cleared the chip, '
              'not as collateral damage of the group filter.');
    });

    test('an empty group selection with the auth chip cleared applies no '
        'constraint at all', () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, groupRequired: 'operate', itemKey: 'jog');
      await seed(at: at, groupRequired: 'configure', itemKey: 'recipe');
      await seed(at: at, groupRequired: 'users', itemKey: 'role');
      await DriftAuditSink(db).record(AuditRecord.login(
        who: 'admin',
        station: 'SVN-NES-OT-CL02',
        roleName: 'Administrator',
        actionId: 'action-login',
        at: at,
      ));

      final rows = await run(
          const AuditTrailFilters(groupNames: [], includeAuth: false));

      expect(rows, hasLength(4),
          reason: 'CONTEXT\'s locked decision: "empty selection = no '
              'constraint. Identical to AlarmLevelFilterChips" — the '
              'semantics the operator has already learned. Deselecting '
              'everything shows everything; it reads backwards and it is not '
              'open to reversal.');
    });

    test('that rule did not quietly widen the default, which is not empty',
        () async {
      final at = _now.subtract(const Duration(hours: 1));
      await seed(at: at, groupRequired: 'operate', itemKey: 'jog');
      await seed(at: at, groupRequired: 'configure', itemKey: 'recipe');

      final rows = await run(const AuditTrailFilters());

      expect(rows.map((r) => r.itemKey), ['recipe']);
    });

    test('the auth invariant: every auth constructor writes an empty '
        'group_required and surface auth', () async {
      const station = 'SVN-NES-OT-CL02';
      final sink = DriftAuditSink(db);
      final at = _now.subtract(const Duration(hours: 1));
      await sink.record(AuditRecord.login(
          who: 'admin',
          station: station,
          roleName: 'Administrator',
          actionId: 'a1',
          at: at));
      await sink.record(AuditRecord.loginFailed(
          who: 'admin', station: station, actionId: 'a2', at: at));
      await sink.record(AuditRecord.logout(
          who: 'admin',
          station: station,
          roleName: 'Administrator',
          actionId: 'a3',
          at: at));
      await sink.record(AuditRecord.sessionTimeout(
          who: 'admin',
          station: station,
          roleName: 'Administrator',
          actionId: 'a4',
          at: at));

      final rows = await store().entries(AuditQuery(limit: 500));

      expect(rows, hasLength(4));
      expect(rows.map((r) => r.groupRequired).toSet(), {''});
      expect(rows.map((r) => r.surface).toSet(), {'auth'},
          reason: "the store's auth leg keys on surface = 'auth' and 05-02's "
              'isAuthEntry uses the same predicate. Two definitions of "auth '
              'row" that happen to agree today are a defect waiting for the '
              'first row that breaks the coincidence.');
    });

    // -----------------------------------------------------------------------
    // The limit
    // -----------------------------------------------------------------------

    test('the limit is applied after every WHERE clause', () async {
      final at = _now.subtract(const Duration(hours: 1));
      for (var i = 0; i < 12; i++) {
        await seed(at: at.add(Duration(minutes: i)), itemKey: 'row.$i');
      }

      final rows = await store().entries(AuditQuery(
        window: AuditWindow(start: _now.subtract(const Duration(days: 7)), end: _now),
        limit: 5,
      ));

      expect(rows, hasLength(5));
      expect(rows.first.itemKey, 'row.11',
          reason: 'the newest five, not an arbitrary five.');
    });
  });

  // -------------------------------------------------------------------------
  // The store reads and never writes
  // -------------------------------------------------------------------------

  group('the store is read-only and ungated by construction', () {
    // Asserted against the source text, the way drift_audit_sink_test.dart
    // asserts the sink is append-only: an enumeration of members would report
    // a write rather than stop one, and reading the file is the assertion that
    // actually bites.
    late String source;

    setUpAll(() {
      final file = File('lib/core/audit_trail_store.dart');
      expect(file.existsSync(), isTrue,
          reason: 'run this suite from the repository root. Without the file '
              'these source assertions would pass vacuously.');
      final withoutBlockComments = file
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      source = withoutBlockComments
          .split('\n')
          .map((line) {
            final idx = line.indexOf('//');
            return idx == -1 ? line : line.substring(0, idx);
          })
          .join('\n');
    });

    test('contains no into, update or delete', () {
      final offender =
          RegExp(r'\.(into|update|delete)\(').firstMatch(source);
      expect(offender?.group(0), null,
          reason: 'the trail is append-only because there is nowhere to write '
              'it from. Reading it must not become a way to edit it.');
    });

    test('holds no AuditSink and cannot record', () {
      expect(source, isNot(contains('AuditSink')),
          reason: 'reading the trail does not appear in the trail: a row per '
              'render would fill the page with people looking at it.');
    });

    test('holds no session and cannot deny', () {
      expect(source, isNot(contains('AccessDenied')));
      expect(source, isNot(contains('AccessSession')),
          reason: 'the enforcement is the route gate. A store-level guard '
              'mistaken for it would be a second, weaker boundary.');
    });

    test('issues no raw SQL', () {
      expect(source, isNot(contains('customSelect')),
          reason: r'the $1-placeholder form is Postgres-only, so a raw-SQL '
              'method here would be untestable against the in-memory SQLite '
              'handle these tests use.');
      expect(source, isNot(contains('customStatement')));
    });
  });
}
